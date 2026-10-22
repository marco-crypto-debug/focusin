import AppKit
import CoreVideo
import Foundation
import VideoToolbox

/// H.264 硬體解碼器（v1.5-beta：學生端接收組播 H.264 流）
/// - 收到關鍵幀（附 SPS/PPS）時重建解碼 session
/// - 解碼輸出 CVPixelBuffer → `onFrame` 回呼（背景佇列）
final class H264Decoder {
    private var session: VTDecompressionSession?
    private var formatDesc: CMVideoFormatDescription?
    private var onFrame: ((CVPixelBuffer) -> Void)?
    /// 目前 session 使用的參數集（供比較是否需重建）
    private var activeSPS: Data?
    private var activePPS: Data?
    /// 解碼輸出節流：上一幀尚未顯示時跳過（保延遲）
    private var isDecoding = false

    func start(callback: @escaping (CVPixelBuffer) -> Void) {
        stop()
        onFrame = callback
    }

    /// 解碼一幀。
    /// - Parameters:
    ///   - data: Annex-B 格式 NAL 數據
    ///   - isKeyframe: 是否關鍵幀
    ///   - sps / pps: 關鍵幀時附帶的參數集（若非 nil 則重建 session）
    func decode(_ data: Data, isKeyframe: Bool, sps: Data?, pps: Data?) {
        guard let onFrame else { return }
        if isKeyframe {
            // 自愈：帶參數集的關鍵幀若缺 SPS/PPS（教師端 VideoToolbox 偶爾提取失敗），
            // 直接從 Annex-B 數據內掃描提取，確保 session 一定能建立。
            var s = sps
            var p = pps
            if s == nil || p == nil {
                let found = MulticastTransport.extractParameterSets(fromAnnexB: data)
                if s == nil { s = found.sps }
                if p == nil { p = found.pps }
            }
            if let s, let p {
                // 參數集與目前 session 相同時不重建（教師端 GOP=1s 每幀帶 SPS/PPS，避免每幀重建）
                if s != activeSPS || p != activePPS {
                    rebuildSession(sps: s, pps: p)
                    activeSPS = s
                    activePPS = p
                }
            }
        }
        guard let session, !isDecoding else { return }
        isDecoding = true
        defer { isDecoding = false }

        // data 已是 AVCC（4 位元組長度前綴 NAL 序列）——直接拷貝建 blockBuffer，
        // 不再做 start-code 掃描（否則會被 NAL 內資料誤導，拆出假 NAL → -12909）
        guard !data.isEmpty else { return }
        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard createStatus == kCMBlockBufferNoErr, let blockBuffer else { return }
        CMBlockBufferAssureBlockMemory(blockBuffer)
        let bytes = [UInt8](data)
        let fillStatus = bytes.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: blockBuffer,
                                          offsetIntoDestination: 0, dataLength: data.count)
        }
        guard fillStatus == kCMBlockBufferNoErr else { return }
        DiagLog.log("H.264 decode AVCC: \(data.count)B")
        decodeBlockBuffer(blockBuffer, session: session)
    }

    // MARK: - 解碼

    /// 以 block buffer（NAL 數據）建立 CMSampleBuffer 並解碼。
    private func decodeBlockBuffer(_ blockBuffer: CMBlockBuffer, session: VTDecompressionSession) {
        guard let formatDesc else { return }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: .zero,
                                        decodeTimeStamp: .invalid)
        // 顯式提供 sample size：sampleSizeArray 為 nil 時 CoreMedia 需從 dataBuffer 推算，
        // 若 blockBuffer 內部記憶體未就緒會 memmove 到 NULL 崩潰
        var sampleSize = [Int(CMBlockBufferGetDataLength(blockBuffer))]
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                          dataBuffer: blockBuffer,
                                          dataReady: true,
                                          makeDataReadyCallback: nil,
                                          refcon: nil,
                                          formatDescription: formatDesc,
                                          sampleCount: 1,
                                          sampleTimingEntryCount: 1,
                                          sampleTimingArray: &timing,
                                          sampleSizeEntryCount: 1,
                                          sampleSizeArray: &sampleSize,
                                          sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer else {
            DiagLog.log("H.264 sample buffer 建立失敗: \(status)")
            return
        }
        var flagsOut = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(session,
                                                             sampleBuffer: sampleBuffer,
                                                             flags: ._EnableAsynchronousDecompression,
                                                             frameRefcon: nil,
                                                             infoFlagsOut: &flagsOut)
        if decodeStatus != noErr {
            DiagLog.log("H.264 解碼失敗: \(decodeStatus)")
        }
    }

    // MARK: - Session 重建

    /// 以 SPS/PPS 重建解碼 session。
    private func rebuildSession(sps: Data, pps: Data) {
        if let session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
            formatDesc = nil
        }
        var desc: CMVideoFormatDescription?
        // 注意：withUnsafeBytes 的指標只在閉包內有效——必須在閉包內完成 C 調用，
        // 不可把 baseAddress 逃逸出去（否則讀到已釋放記憶體 → -12712 參數集建立失敗）
        let status: OSStatus = sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                guard let spsBase = spsRaw.bindMemory(to: UInt8.self).baseAddress,
                      let ppsBase = ppsRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return -1
                }
                var pointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                var sizes = [sps.count, pps.count]
                return pointers.withUnsafeBufferPointer { ptrBuf in
                    sizes.withUnsafeBufferPointer { sizeBuf in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: ptrBuf.baseAddress!,
                            parameterSetSizes: sizeBuf.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &desc)
                    }
                }
            }
        }
        guard status == noErr, let desc else {
            DiagLog.log("H.264 參數集建立失敗: \(status)（SPS \(sps.count)B / PPS \(pps.count)B）")
            return
        }
        formatDesc = desc

        var outputCb = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: Self.outputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
        var sessionOut: VTDecompressionSession?
        let decoderSpec: [CFString: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ]
        let status2 = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: desc,
            decoderSpecification: decoderSpec as CFDictionary,
            imageBufferAttributes: nil,
            outputCallback: &outputCb,
            decompressionSessionOut: &sessionOut)
        guard status2 == noErr, let sessionOut else {
            DiagLog.log("H.264 解碼 session 建立失敗: \(status2)")
            return
        }
        session = sessionOut
        // 低延遲
        VTSessionSetProperty(sessionOut, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        DiagLog.log("H.264 解碼器重建（SPS \(sps.count)B / PPS \(pps.count)B）")
    }

    /// C 函式：解碼輸出回呼。
    private static let outputCallback: VTDecompressionOutputCallback = { refcon, _, status, flags, imageBuffer, _, _ in
        guard let refcon else { return }
        let decoder = Unmanaged<H264Decoder>.fromOpaque(refcon).takeUnretainedValue()
        guard status == noErr, flags != .frameDropped, let imageBuffer else {
            DiagLog.log("H.264 解碼輸出異常: status=\(status) flags=\(flags.rawValue)")
            return
        }
        decoder.onFrame?(imageBuffer)
    }

    // MARK: - 數據轉換

    /// 把 Annex-B 數據轉成 CMBlockBuffer（AVCC 長度前綴，與 nalUnitHeaderLength=4 一致）。
    private func makeBlockBuffer(from annexB: Data) -> CMBlockBuffer? {
        var nals = [Data]()
        let bytes = [UInt8](annexB)
        var offset = 0
        let count = bytes.count
        while offset + 4 <= count {
            if bytes[offset] == 0x00, bytes[offset + 1] == 0x00,
               bytes[offset + 2] == 0x00, bytes[offset + 3] == 0x01 {
                var start = offset + 4
                if start + 3 < count, bytes[start] == 0x00, bytes[start + 1] == 0x00,
                   bytes[start + 2] == 0x01 {
                    start += 3
                }
                var end = start
                while end + 4 <= count {
                    if bytes[end] == 0x00, bytes[end + 1] == 0x00,
                       bytes[end + 2] == 0x00, bytes[end + 3] == 0x01 {
                        break
                    }
                    end += 1
                }
                if end > start {
                    let nal = Data(bytes[start..<end])
                    // formatDesc 已含 SPS/PPS，幀內重複的參數集過濾掉；SEI（type 6）也過濾——
                    // VideoToolbox 對「SEI + IDR 同 sample」組合可能拒絕整幀（-12909），只留 VCL 幀
                    let nalType = (nal[0] & 0x1F)
                    if !MulticastTransport.isParameterSetNAL(nal), nalType != 6 {
                        nals.append(nal)
                    }
                }
                offset = end
            } else {
                offset += 1
            }
        }
        guard !nals.isEmpty else { return nil }
        let nalDesc = nals.map { "t=\($0[0] & 0x1F)@\($0.count)" }.joined(separator: " ")
        DiagLog.log("H.264 makeBlockBuffer: 輸入 \(annexB.count)B → \(nals.count) NAL: \(nalDesc)")
        var total = 0
        for nal in nals { total += 4 + nal.count }
        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: total,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: total,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard createStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }
        // 強制立即分配記憶體：否則 CoreMedia 可能拿到未初始化的 memory block，
        // CMSampleBufferCreate 內部 memmove 到 NULL → SIGSEGV
        CMBlockBufferAssureBlockMemory(blockBuffer)
        var offsetInBlock = 0
        for nal in nals {
            var length = UInt32(nal.count).bigEndian
            var fillStatus = CMBlockBufferReplaceDataBytes(with: &length, blockBuffer: blockBuffer,
                                                           offsetIntoDestination: offsetInBlock,
                                                           dataLength: 4)
            guard fillStatus == kCMBlockBufferNoErr else { return nil }
            offsetInBlock += 4
            var nalData = nal
            fillStatus = nalData.withUnsafeMutableBytes { raw in
                CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: blockBuffer,
                                              offsetIntoDestination: offsetInBlock,
                                              dataLength: nal.count)
            }
            guard fillStatus == kCMBlockBufferNoErr else { return nil }
            offsetInBlock += nal.count
        }
        return blockBuffer
    }

    func stop() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDesc = nil
        onFrame = nil
        activeSPS = nil
        activePPS = nil
    }
}
