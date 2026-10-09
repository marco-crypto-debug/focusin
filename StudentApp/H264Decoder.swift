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
        if isKeyframe, let sps, let pps {
            rebuildSession(sps: sps, pps: pps)
        }
        guard let session, !isDecoding else { return }
        isDecoding = true
        defer { isDecoding = false }

        guard let blockBuffer = makeBlockBuffer(from: data) else { return }
        decodeBlockBuffer(blockBuffer, session: session)
    }

    // MARK: - 解碼

    /// 以 block buffer（NAL 數據）建立 CMSampleBuffer 並解碼。
    private func decodeBlockBuffer(_ blockBuffer: CMBlockBuffer, session: VTDecompressionSession) {
        guard let formatDesc else { return }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: .zero,
                                        decodeTimeStamp: .invalid)
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
                                          sampleSizeArray: nil,
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
        let spsPtr = sps.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! }
        let ppsPtr = pps.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! }
        var parameterSetPointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
        var parameterSetSizes = [sps.count, pps.count]
        var desc: CMVideoFormatDescription?
        let status = parameterSetPointers.withUnsafeBufferPointer { ptr in
            parameterSetSizes.withUnsafeBufferPointer { sizes in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: ptr.baseAddress!,
                    parameterSetSizes: sizes.baseAddress!,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &desc)
            }
        }
        guard status == noErr, let desc else {
            DiagLog.log("H.264 參數集建立失敗: \(status)")
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
        guard let refcon, status == noErr, flags != .frameDropped, let imageBuffer else { return }
        let decoder = Unmanaged<H264Decoder>.fromOpaque(refcon).takeUnretainedValue()
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
                    nals.append(Data(bytes[start..<end]))
                }
                offset = end
            } else {
                offset += 1
            }
        }
        guard !nals.isEmpty else { return nil }
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
    }
}
