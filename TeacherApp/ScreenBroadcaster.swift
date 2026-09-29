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
    /// 音訊 PCM 資料回呼（在採集佇列上觸發）。
    var onAudio: ((Data, PeerConnection.AudioFormatInfo) -> Void)?
    /// 啟動失敗回呼（例如未授權「屏幕錄製」），在主執行緒觸發，用於在介面顯示指引。
    var onStartError: ((String) -> Void)?

    /// 目前畫質模式（教師端切換後，廣播中會即時重啟套用）。
    var quality: BroadcastQuality = .high
    /// 目前生效的 JPEG 品質（於 start 時依畫質模式決定）。
    private var activeJpegQuality: Double = 0.92

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

    private var stream: SCStream?
    private let context = CIContext(options: [.cacheIntermediates: false])
    /// 編碼節流旗標：上一幀尚未完成編碼時，直接丟棄新幀（保延遲優先於幀率）。
    private var isEncodingFrame = false

    // —— 音訊聚合：把 ~10ms 的小緩衝區併成 ~80ms 一塊再送出，
    //    大幅減少訊息數量與學生端排程抖動（低延遲 + 更穩）——
    private var pendingAudio = Data()
    private var pendingFrames = 0
    private var pendingFormat: PeerConnection.AudioFormatInfo?
    private let audioTargetFramesMs = 80

    private func flushPendingAudio() {
        guard let format = pendingFormat, pendingFrames > 0 else {
            pendingAudio = Data()
            pendingFrames = 0
            pendingFormat = nil
            return
        }
        onAudio?(pendingAudio, format)
        pendingAudio = Data()
        pendingFrames = 0
        pendingFormat = nil
    }

    /// 啟動廣播。
    /// - Parameters:
    ///   - completion: 啟動成功後在主執行緒回呼。
    ///   - onError: 啟動失敗（含未授權屏幕錄製）時在主執行緒回呼。
    func start(completion: @escaping () -> Void, onError: ((String) -> Void)? = nil) {
        let startHandler = completion
        Task {
            // 權限預檢：未授權「屏幕錄製」時，先觸發系統授權提示，並回報明確指引
            guard CGPreflightScreenCaptureAccess() else {
                await MainActor.run {
                    onStartError?("廣播需要「屏幕錄製」權限。請開啟 系統設定 → 私隱與安全性 → 屏幕錄製，勾選 FocusIn 教師端（TeacherApp），完成後重新點擊「廣播教師屏幕」。若之前選擇過「拒絕」，請先在該頁面取消勾選再重新勾選。")
                    NSApp.activate(ignoringOtherApps: true)
                    CGRequestScreenCaptureAccess()   // 觸發系統權限彈窗（首次）
                }
                return
            }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                  onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    await MainActor.run { onStartError?("未找到可廣播的顯示器。") }
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])

                // 依畫質模式（自動/低/中/高）決定縮放、幀率與 JPEG 品質
                let params = resolutionParameters(displayWidth: display.width)
                activeJpegQuality = params.jpeg

                let config = SCStreamConfiguration()
                config.width = Int(Double(display.width) * params.scale)
                config.height = Int(Double(display.height) * params.scale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(params.fps))
                config.queueDepth = 4
                config.showsCursor = false
                // 音訊：同步採集系統聲音（44.1kHz 立體聲），隨廣播一起傳給學生端
                config.capturesAudio = true
                config.sampleRate = 44100
                config.channelCount = 2
                config.excludesCurrentProcessAudio = false
                // captureResolution 預設為 .automatic（macOS 14+ 才可明確設定，這裡保持預設）

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(self,
                                           type: .screen,
                                           sampleHandlerQueue: .global(qos: .userInitiated))
                try stream.addStreamOutput(self,
                                           type: .audio,
                                           sampleHandlerQueue: .global(qos: .userInteractive))
                try await stream.startCapture()
                self.stream = stream
                DispatchQueue.main.async { startHandler() }
            } catch {
                print("[Broadcaster] 屏幕捕獲失敗: \(error)")
                await MainActor.run {
                    onStartError?("屏幕捕獲失敗：\(error.localizedDescription)\n請確認已授權「屏幕錄製」後重試。")
                }
            }
        }
    }

    func stop() {
        // 停止前先送出剩餘的聚合音訊，避免結尾被截斷
        flushPendingAudio()
        stream?.stopCapture { _ in }
        stream = nil
    }
}

// MARK: - SCStreamOutput

extension ScreenBroadcaster: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        // —— 音訊緩衝區：累積至 ~80ms 聚合後送出（低延遲 + 減少訊息數）——
        if type == .audio {
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

            if pendingFormat == nil {
                pendingFormat = PeerConnection.AudioFormatInfo(
                    sampleRate: asbd.mSampleRate,
                    channels: asbd.mChannelsPerFrame,
                    bits: UInt8(asbd.mBitsPerChannel),
                    isFloat: isFloat,
                    interleaved: true   // 統一為交錯
                )
            }
            pendingAudio.append(chunk)
            pendingFrames += frames

            let targetFrames = Int(asbd.mSampleRate) * audioTargetFramesMs / 1000
            if pendingFrames >= targetFrames {
                flushPendingAudio()
            }
            return
        }

        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 低延遲策略：上一幀還在編碼就跳過本幀，不讓畫面延遲隨佇列堆積
        guard !isEncodingFrame else { return }
        isEncodingFrame = true
        defer { isEncodingFrame = false }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        guard let jpeg = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [.compressionFactor: activeJpegQuality]) else { return }

        onFrame?(jpeg)
    }
}
