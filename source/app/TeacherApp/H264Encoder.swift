import AppKit
import CoreVideo
import Foundation
import VideoToolbox

/// H.264 硬體編碼器（v1.5-beta：VideoToolbox 低延遲路徑）
/// - 教師端每幀 CVPixelBuffer → H.264 Annex-B 數據
/// - 每秒強制 1 個關鍵幀（組播無重傳，學生中途加入/掉幀靠關鍵幀恢復）
/// - 輸出：`onEncoded(AnnexBData, isKeyframe, sps, pps)`，SPS/PPS 僅在關鍵幀時附帶
final class H264Encoder {
    private var session: VTCompressionSession?
    private var lastKeyframeTime: TimeInterval = 0
    private let keyframeInterval: TimeInterval = 1.0
    private var onEncoded: ((Data, Bool, Data?, Data?) -> Void)?
    /// 編碼節流：上一幀未完成時跳過本幀（保延遲優先）
    private var isEncoding = false

    /// 開始編碼。
    /// - Parameters:
    ///   - width / height: 輸入畫面尺寸
    ///   - fps: 目標幀率
    ///   - bitrate: 目標平均碼率（bps）
    ///   - callback: 編碼輸出回呼（編碼佇列）
    func start(width: Int, height: Int, fps: Int, bitrate: Int,
               callback: @escaping (Data, Bool, Data?, Data?) -> Void) {
        stop()
        onEncoded = callback

        var sessionOut: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: kCFAllocatorDefault,
            outputCallback: Self.outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &sessionOut)
        guard status == noErr, let sessionOut else {
            DiagLog.log("H.264 編碼器建立失敗: \(status)")
            return
        }
        session = sessionOut

        // 低延遲配置
        VTSessionSetProperty(sessionOut, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(sessionOut, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(sessionOut, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: bitrate as CFNumber)
        VTSessionSetProperty(sessionOut, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: fps as CFNumber)
        // 關鍵幀間隔：1 秒
        VTSessionSetProperty(sessionOut, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: fps as CFNumber)
        // 低延遲：禁 B 幀重排
        VTSessionSetProperty(sessionOut, key: kVTCompressionPropertyKey_AllowFrameReordering,
                             value: kCFBooleanFalse)

        lastKeyframeTime = 0
        DiagLog.log("H.264 編碼器啟動（\(width)x\(height) @\(fps)fps, \(bitrate / 1000)kbps）")
    }

    /// C 函式：編碼輸出回呼。
    private static let outputCallback: VTCompressionOutputCallback = { refcon, _, status, flags, sampleBuffer in
        guard let refcon else { return }
        let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.handleOutput(status: status, flags: flags, sampleBuffer: sampleBuffer)
    }

    /// 壓縮一幀（背景佇列呼叫）。
    func encode(_ pixelBuffer: CVPixelBuffer) {
        guard let session, !isEncoding else { return }
        isEncoding = true
        defer { isEncoding = false }

        let now = Date().timeIntervalSince1970
        let forceKey = now - lastKeyframeTime >= keyframeInterval
        if forceKey {
            lastKeyframeTime = now
        }
        let frameProps: CFDictionary = [kVTEncodeFrameOptionKey_ForceKeyFrame: forceKey] as CFDictionary
        VTCompressionSessionEncodeFrame(session,
                                        imageBuffer: pixelBuffer,
                                        presentationTimeStamp: CMTime(value: Int64(now * 1000), timescale: 1000),
                                        duration: .invalid,
                                        frameProperties: frameProps,
                                        sourceFrameRefcon: nil,
                                        infoFlagsOut: nil)
    }

    private func handleOutput(status: OSStatus, flags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) {
        guard status == noErr, flags != .frameDropped, let sampleBuffer,
              let onEncoded else { return }
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        let isKeyframe = sampleBuffer.isKeyFrame
        var sps: Data?
        var pps: Data?
        var avcc: Data?
        if isKeyframe {
            (sps, pps) = Self.extractParameterSets(from: formatDesc)
            avcc = Self.readAVCC(sampleBuffer)
            if let avcc {
                var nalInfo = ""
                let b = [UInt8](avcc); var i = 0
                while i + 4 <= b.count {
                    if b[i] == 0, b[i+1] == 0, b[i+2] == 0, b[i+3] == 1 {
                        var h = i + 4
                        if h < b.count { nalInfo += " type=\(b[h] & 0x1F)" }
                        var e = h
                        while e + 4 <= b.count {
                            if b[e] == 0, b[e+1] == 0, b[e+2] == 0, b[e+3] == 1 { break }
                            e += 1
                        }
                        if e > h { nalInfo += "@\(e-h)" }
                        i = e
                    } else { i += 1 }
                }
                let spsHex = sps?.map { String(format: "%02x", $0) }.joined(separator: " ") ?? "nil"
                let ppsHex = pps?.map { String(format: "%02x", $0) }.joined(separator: " ") ?? "nil"
                DiagLog.log("H.264 關鍵幀: SPS \(sps?.count ?? 0)B [\(spsHex)] PPS \(pps?.count ?? 0)B [\(ppsHex)] avcc=\(avcc.count)B NAL:\(nalInfo)")
            } else {
                DiagLog.log("H.264 關鍵幀: SPS \(sps?.count ?? 0)B / PPS \(pps?.count ?? 0)B")
            }
        }
        if avcc == nil {
            avcc = Self.readAVCC(sampleBuffer)
        }
        if let avcc {
            onEncoded(avcc, isKeyframe, sps, pps)
        }
    }

    /// 從格式描述提取 SPS/PPS。
    private static func extractParameterSets(from formatDesc: CMFormatDescription) -> (Data?, Data?) {
        var spsOut: UnsafePointer<UInt8>?
        var spsSize = 0
        var ppsOut: UnsafePointer<UInt8>?
        var ppsSize = 0
        var parameterSetCount = 0
        var nalUnitHeaderLength: Int32 = 0
        guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDesc,
            parameterSetIndex: 0,
            parameterSetPointerOut: &spsOut,
            parameterSetSizeOut: &spsSize,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength) == noErr,
            spsSize > 0, let spsOut else { return (nil, nil) }
        let spsData = Data(bytes: spsOut, count: spsSize)
        var ppsData: Data?
        if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDesc,
            parameterSetIndex: 1,
            parameterSetPointerOut: &ppsOut,
            parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength) == noErr,
            ppsSize > 0, let ppsOut {
            ppsData = Data(bytes: ppsOut, count: ppsSize)
        }
        return (spsData, ppsData)
    }

    /// 直接讀取 VideoToolbox 輸出的 AVCC（4 位元組長度前綴）原始資料，不轉 Annex-B——
    /// 學生端解碼時直接以 AVCC 建 sample，避免 start-code 掃描被 NAL 內資料誤導（-12909）。
    private static func readAVCC(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let dataPointer, length > 0 else { return nil }
        let bytes = UnsafeRawBufferPointer(start: dataPointer, count: length)
        var out = Data()
        var offset = 0
        var nalLens = [Int]()
        while offset + 4 <= length {
            let raw = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            let nalLength = Int(UInt32(bigEndian: raw))
            offset += 4
            guard nalLength > 0, offset + nalLength <= length else { break }
            let nalType = Int(bytes[offset] & 0x1F)
            nalLens.append(nalType << 20 | nalLength)
            let sliceStart = offset - 4
            out.append(contentsOf: bytes[sliceStart..<(sliceStart + 4 + nalLength)].map { $0 })
            offset += nalLength
        }
        if !nalLens.isEmpty {
            let desc = nalLens.map { String(format: "t=%d@%d", $0 >> 20, $0 & 0xFFFFF) }.joined(separator: " ")
            DiagLog.log("AVCC 幀: total=\(length)B NAL: \(desc)")
        }
        return out.isEmpty ? nil : out
    }

    func stop() {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
        onEncoded = nil
    }
}

extension CMSampleBuffer {
    /// 判斷是否為關鍵幀。
    var isKeyFrame: Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else { return false }
        if let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync
        }
        return true
    }
}
