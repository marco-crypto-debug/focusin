import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ScreenCaptureKit

/// 廣播畫質模式（教師端介面可切換，頻寬不作限制、以清晰度優先）。
enum BroadcastQuality: String, CaseIterable, Identifiable {
    case auto, low, mid, high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "自動"
        case .low:  return "低"
        case .mid:  return "中"
        case .high: return "高"
        }
    }
}

/// 教師屏幕採集：ScreenCaptureKit 捕獲主顯示器，逐幀轉 JPEG 交給回呼。
/// 需要「屏幕錄製」權限（系統設定 → 私隱與安全性 → 屏幕錄製）。
final class ScreenBroadcaster: NSObject {
    /// 每幀 JPEG 資料回呼（在採集佇列上觸發）。
    var onFrame: ((Data) -> Void)?
    var onMultiDisplayFrame: ((MultiDisplayStreamPacket) -> Void)?
    var onAudio: ((Data, PeerConnection.AudioFormatInfo) -> Void)?
    var onAirPlayAudio: ((AirPlayAudioPacket) -> Void)?
    var onStartError: ((String) -> Void)?
    /// 即時畫面縮圖預覽回呼（供教師端 Studio UI 本地預覽使用）
    var onPreviewImage: ((NSImage?) -> Void)?

    /// 目前畫質模式（教師端切換後，廣播中會即時重啟套用）。
    var quality: BroadcastQuality = .high
    /// 是否同步傳送聲音（教師端可關閉，僅傳畫面；關閉可繞過音訊鏈路的個別相容問題）。
    var withAudio = true
    /// 目前生效的 JPEG 品質（於 start 時依畫質模式決定）。
    private var activeJpegQuality: Double = 0.92

    var availableDisplays: [SCDisplay] = []
    var selectedDisplayID: CGDirectDisplayID?
    private var activeFilter: SCContentFilter?

    private var audioSequenceNumber: UInt16 = 0
    private var audioClockID: UInt32 = UInt32.random(in: 1...UInt32.max)

    /// 依畫質模式與顯示器解析度決定採集參數。
    /// - 高：原生全分辨率（1.0）× 30fps × JPEG 0.92
    /// - 中：0.75 縮放 × 30fps × JPEG 0.85
    /// - 低：0.5 縮放 × 24fps × JPEG 0.75
    /// - 自動：≤4K 用原生全分辨率；5K 以上微縮至 0.85（兼顧編碼穩定性）
    private func resolutionParameters(displayWidth: Int) -> (scale: Double, fps: Int, jpeg: Double) {
        switch quality {
        case .high: return (1.0, 30, 0.92)
        case .mid:  return (0.75, 30, 0.85)
        case .low:  return (0.5, 24, 0.75)
        case .auto: return displayWidth > 3840 ? (0.85, 30, 0.92) : (1.0, 30, 0.92)
        }
    }

#if FOCUSIN_BETA
    /// beta：依畫質決定的 H.264 目標碼率（bps）。
    /// 提高基準碼率（≈1080p/2K 觀看級），靜態文字/細線更清晰；組播單流下 1 份流量複製給所有學生。
    private func h264Bitrate(displayWidth: Int) -> Int {
        let base: Double
        switch quality {
        case .high: base = 20_000_000
        case .mid:  base = 10_000_000
        case .low:  base = 5_000_000
        case .auto: base = displayWidth > 3840 ? 12_000_000 : 20_000_000
        }
        return Int(base)
    }
#endif

    private var stream: SCStream?
    private let context = CIContext(options: [.cacheIntermediates: false])
    /// 編碼節流旗標：上一幀尚未完成編碼時，直接丟棄新幀（保延遲優先於幀率）。
    private var isEncodingFrame = false
    private var lastPreviewTimestamp: CFTimeInterval = 0

#if FOCUSIN_BETA
    // —— v1.5-beta：H.264 硬體編碼（VideoToolbox，組播單流）——
    private let h264Encoder = H264Encoder()
#endif

    // —— 音訊聚合：把 ~10ms 的小緩衝區併成 ~80ms 一塊再送出，
    //    大幅減少訊息數量與學生端排程抖動（低延遲 + 更穩）——
    private var pendingAudio = Data()
    private var pendingFrames = 0
    private let audioLock = NSLock()  // 保護 pendingAudio/pendingFrames/canonicalFormat
    /// 本次廣播的規範音訊格式（由首個音訊緩衝決定後鎖定）。
    /// 崩潰防護：後續緩衝若格式與首塊不同（取樣率/聲道數/位深等），直接丟棄，
    /// 避免學生端播放節點排入異構格式緩衝而在渲染執行緒崩潰。
    private var canonicalFormat: PeerConnection.AudioFormatInfo?
    private let audioTargetFramesMs = 80

    // —— 音訊診斷日誌（alpha 除錯用）——
    private var didLogAudioFormat = false
    private var lastAudioLogAt: TimeInterval = 0
    private var audioChunkCount = 0
    private var audioByteCount: UInt64 = 0

    private func flushPendingAudio() {
        audioLock.lock()
        guard canonicalFormat != nil, pendingFrames > 0 else {
            pendingAudio = Data()
            pendingFrames = 0
            audioLock.unlock()
            return
        }
        let dataToSend = pendingAudio
        let formatToSend = canonicalFormat!
        pendingAudio = Data()
        pendingFrames = 0
        audioLock.unlock()

        let seq = audioSequenceNumber
        audioSequenceNumber &+= 1
        let pts = AirPlayClock.nowNanoseconds
        let packet = AirPlayAudioPacket(
            version: 2,
            flags: 0,
            sequenceNumber: seq,
            ptsNanoseconds: pts,
            clockID: audioClockID,
            sampleRate: formatToSend.sampleRate,
            channels: formatToSend.channels,
            bits: formatToSend.bits,
            isFloat: formatToSend.isFloat,
            isInterleaved: formatToSend.interleaved,
            pcm: dataToSend
        )
        onAirPlayAudio?(packet)
        onAudio?(dataToSend, formatToSend)
    }

    /// 啟動廣播。
    /// - Parameters:
    ///   - completion: 啟動成功後在主執行緒回呼。
    ///   - onError: 啟動失敗（含未授權屏幕錄製）時在主執行緒回呼。
    func start(completion: @escaping () -> Void, onError: ((String) -> Void)? = nil) {
        let startHandler = completion
        Task {
            // 每次廣播重新鎖定規範音訊格式
            self.canonicalFormat = nil
            // 權限預檢：未授權「屏幕錄製」時，先觸發系統授權提示，並回報明確指引
            guard CGPreflightScreenCaptureAccess() else {
                await MainActor.run {
                    let appName = ProcessInfo.processInfo.processName   // 如 TeacherAppDelta
                    onStartError?("廣播需要「屏幕與系統音頻錄製」權限（macOS 15+ 名稱；舊系統叫「屏幕錄製」）。\n請開啟：系統設定 → 私隱與安全性 → 屏幕與系統音頻錄製 → 點「+」加入本 App（\(appName)）並開啟開關；若已在列表，請取消勾選再重新勾選。完成後重新點擊「廣播教師屏幕」。")
                    // 自動打開正確的權限設定頁（macOS 15+ 與舊版共用此 deep link）
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                    CGRequestScreenCaptureAccess()   // 觸發系統權限彈窗（首次）
                }
                return
            }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                  onScreenWindowsOnly: true)
                self.availableDisplays = content.displays
                let targetDisplay: SCDisplay
                if let selID = self.selectedDisplayID, let match = content.displays.first(where: { $0.displayID == selID }) {
                    targetDisplay = match
                } else if let first = content.displays.first {
                    targetDisplay = first
                    self.selectedDisplayID = first.displayID
                } else {
                    await MainActor.run { onStartError?("未找到可廣播的顯示器。") }
                    return
                }
                let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
                self.activeFilter = filter

                let params = self.resolutionParameters(displayWidth: targetDisplay.width)
                activeJpegQuality = params.jpeg

                let config = SCStreamConfiguration()
                config.width = Int(Double(targetDisplay.width) * params.scale)
                config.height = Int(Double(targetDisplay.height) * params.scale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(params.fps))
                config.queueDepth = 4
                config.showsCursor = false
                // 明確設定捕獲解析度為最佳品質，避免 macOS 版本差異導致不一致
                if #available(macOS 14.0, *) {
                    config.captureResolution = .best
                }
#if FOCUSIN_BETA
                // v1.5-beta：啟動 H.264 硬體編碼器（輸出 Annex-B，每秒 1 關鍵幀）
                let bitrate = h264Bitrate(displayWidth: targetDisplay.width)
                h264Encoder.start(width: config.width, height: config.height,
                                  fps: params.fps, bitrate: bitrate) { [weak self] data, key, sps, pps in
                    self?.onFrame?(MulticastTransport.packH264Frame(data, key: key, sps: sps, pps: pps))
                }
                DiagLog.log("Beta 廣播走 H.264 硬編（\(bitrate / 1000)kbps）")
#endif
                // 音訊：依教師端開關決定是否同步採集系統聲音。
                // 取樣率用 48000Hz：與 macOS 內建輸出裝置的預設取樣率一致，
                // 學生端播放時無需取樣率轉換（消除渲染執行緒 SRC 的潛在崩潰點）。
                config.capturesAudio = withAudio
                config.sampleRate = 48000
                config.channelCount = 2
                config.excludesCurrentProcessAudio = false

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(self,
                                           type: .screen,
                                           sampleHandlerQueue: .global(qos: .userInitiated))
#if !FOCUSIN_STABLE
                try stream.addStreamOutput(self,
                                           type: .audio,
                                           sampleHandlerQueue: .global(qos: .userInteractive))
#endif
                try await stream.startCapture()
                self.stream = stream
                DispatchQueue.main.async { startHandler() }
            } catch {
                DiagLog.log("屏幕捕獲失敗: \(error)")
                await MainActor.run {
                    onStartError?("屏幕捕獲失敗：\(error.localizedDescription)\n請確認已授權「屏幕錄製」後重試。")
                }
            }
        }
    }

    func stop() {
        // 停止前先送出剩餘的聚合音訊，避免結尾被截斷
        audioLock.lock()
        if canonicalFormat != nil, pendingFrames > 0 {
            let dataToSend = pendingAudio
            let formatToSend = canonicalFormat!
            pendingAudio = Data()
            pendingFrames = 0
            audioLock.unlock()

            let seq = audioSequenceNumber
            audioSequenceNumber &+= 1
            let pts = AirPlayClock.nowNanoseconds
            let packet = AirPlayAudioPacket(
                version: 2,
                flags: 0,
                sequenceNumber: seq,
                ptsNanoseconds: pts,
                clockID: audioClockID,
                sampleRate: formatToSend.sampleRate,
                channels: formatToSend.channels,
                bits: formatToSend.bits,
                isFloat: formatToSend.isFloat,
                isInterleaved: formatToSend.interleaved,
                pcm: dataToSend
            )
            onAirPlayAudio?(packet)
            onAudio?(dataToSend, formatToSend)
        } else {
            audioLock.unlock()
        }
        stream?.stopCapture { _ in }
        stream = nil
        DispatchQueue.main.async { [weak self] in
            self?.onPreviewImage?(nil)
        }
#if FOCUSIN_BETA
        h264Encoder.stop()
#endif
    }

    func refreshDisplays() async -> [DisplayDescriptor] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return []
        }
        self.availableDisplays = content.displays
        return content.displays.enumerated().map { idx, d in
            DisplayDescriptor(
                id: d.displayID,
                index: idx,
                name: "顯示器 \(idx + 1)",
                width: d.width,
                height: d.height,
                isPrimary: idx == 0,
                scaleFactor: 2.0
            )
        }
    }

    func switchDisplay(to displayID: CGDirectDisplayID) async throws {
        self.selectedDisplayID = displayID
        guard let stream = self.stream else { return }
        guard let match = availableDisplays.first(where: { $0.displayID == displayID }) else { return }
        let newFilter = SCContentFilter(display: match, excludingWindows: [])
        self.activeFilter = newFilter
        try await stream.updateContentFilter(newFilter)
    }
}

// MARK: - SCStreamOutput

extension ScreenBroadcaster: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        // —— 音訊緩衝區：累積至 ~80ms 聚合後送出（低延遲 + 減少訊息數）——
        if type == .audio {
#if !FOCUSIN_STABLE
            // 教師端關閉聲音時，不採集也不處理音訊（防呆）
            guard withAudio else { return }
            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(blockBuffer,
                                                     atOffset: 0,
                                                     lengthAtOffsetOut: nil,
                                                     totalLengthOut: &length,
                                                     dataPointerOut: &dataPointer)
            guard status == kCMBlockBufferNoErr, let dataPointer, length > 0 else { return }

            let bytesPerSample = max(Int(asbd.mBitsPerChannel) / 8, 1)
            let channelCount = max(Int(asbd.mChannelsPerFrame), 1)
            let frames = length / (channelCount * bytesPerSample)
            guard frames > 0 else { return }
            let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

            // 診斷日誌：首次輸出 SCStream 實際送出的音訊格式（確認 48k/立體聲/浮點/是否非交錯）
            if !didLogAudioFormat {
                didLogAudioFormat = true
                DiagLog.log("音訊採集格式: rate=\(asbd.mSampleRate) ch=\(asbd.mChannelsPerFrame) bits=\(asbd.mBitsPerChannel) float=\(isFloat) nonInterleaved=\(isNonInterleaved) framesPerBlock=\(frames)")
            }

            // 統一重排成交錯（interleaved）格式再送出：
            // ScreenCaptureKit 送來的是非交錯緩衝（內部排列 [L 全部][R 全部]），
            // 若直接拼接多個緩衝再整段傳送，接收端無法分辨子緩衝邊界，
            // 會把「L、R 交替切片」誤當左右聲道 → 產生低頻風鳴/哼聲。
            var chunk = Data(capacity: frames * channelCount * bytesPerSample)
            if isNonInterleaved {
                for f in 0..<frames {
                    for c in 0..<channelCount {
                        let offset = c * frames * bytesPerSample + f * bytesPerSample
                        chunk.append(contentsOf: UnsafeRawBufferPointer(start: dataPointer + offset,
                                                                        count: bytesPerSample))
                    }
                }
            } else {
                chunk.append(Data(bytes: dataPointer, count: length))
            }

            // 崩潰防護：整個廣播期間鎖定同一個格式；若個別緩衝的取樣率/聲道數/
            // 位深與首塊不一致，直接丟棄（極罕見），避免學生端播放節點排入
            // 異構格式緩衝而在渲染執行緒崩潰（EXC_BAD_ACCESS in IOThread）。
            let info = PeerConnection.AudioFormatInfo(
                sampleRate: asbd.mSampleRate,
                channels: asbd.mChannelsPerFrame,
                bits: UInt8(asbd.mBitsPerChannel),
                isFloat: isFloat,
                interleaved: true   // 統一為交錯
            )

            audioLock.lock()
            if canonicalFormat == nil {
                canonicalFormat = info
            } else if canonicalFormat!.sampleRate != info.sampleRate
                        || canonicalFormat!.channels != info.channels
                        || canonicalFormat!.bits != info.bits
                        || canonicalFormat!.isFloat != info.isFloat {
                audioLock.unlock()
                return
            }
            pendingAudio.append(chunk)
            pendingFrames += frames
            audioChunkCount += 1
            audioByteCount += UInt64(chunk.count)
            let targetFrames = Int(asbd.mSampleRate) * audioTargetFramesMs / 1000
            let shouldFlush = pendingFrames >= targetFrames
            audioLock.unlock()

            let now = Date().timeIntervalSinceReferenceDate
            if now - lastAudioLogAt > 2 {
                lastAudioLogAt = now
                DiagLog.log("音訊送出中: \(audioChunkCount) 塊 / \(audioByteCount) 位元組（\(audioByteCount / 1024) KB）")
                audioChunkCount = 0
                audioByteCount = 0
            }

            if shouldFlush {
                flushPendingAudio()
            }
#endif
            return
        }

        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if let onPreview = onPreviewImage {
            let now = CACurrentMediaTime()
            if now - lastPreviewTimestamp >= 0.12 {
                lastPreviewTimestamp = now
                let ci = CIImage(cvPixelBuffer: pixelBuffer)
                let targetW: CGFloat = 640
                let scale = targetW / max(ci.extent.width, 1)
                let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                if let cg = context.createCGImage(scaled, from: scaled.extent) {
                    let nsImg = NSImage(cgImage: cg, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
                    DispatchQueue.main.async {
                        onPreview(nsImg)
                    }
                }
            }
        }

        // 低延遲策略：上一幀還在編碼就跳過本幀，不讓畫面延遲隨佇列堆積
        guard !isEncodingFrame else { return }
        isEncodingFrame = true
        defer { isEncodingFrame = false }

#if FOCUSIN_BETA
        // —— v1.5-beta：H.264 硬體編碼（組播單流）——
        // 原始畫面直通：不做任何銳化/後處理，畫面與屏幕完全一致。
        // 若採集 buffer 已是 BGRA 直接送編碼器（零複製、零失真）；
        // 其他格式（NV12 等）才轉 BGRA。
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if fmt == kCVPixelFormatType_32BGRA {
            h264Encoder.encode(pixelBuffer)
        } else {
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            if let outBuffer = makePixelBuffer(width: image.extent.width,
                                               height: image.extent.height) {
                context.render(image, to: outBuffer)
                h264Encoder.encode(outBuffer)
            }
        }
#else
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let processed = image
        guard let cgImage = context.createCGImage(processed, from: processed.extent) else { return }
        guard let jpeg = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [.compressionFactor: activeJpegQuality]) else { return }

        onFrame?(jpeg)
#endif
    }

    // MARK: - v1.5-beta H.264 幀封裝

#if FOCUSIN_BETA
    /// 建立用於 VideoToolbox 的 CVPixelBuffer（BGRA）。
    private func makePixelBuffer(width: CGFloat, height: CGFloat) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(width), Int(height),
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary, &out)
        return status == kCVReturnSuccess ? out : nil
    }
#endif
}
