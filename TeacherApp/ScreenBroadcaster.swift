import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ScreenCaptureKit

/// 教師屏幕採集：ScreenCaptureKit 捕獲主顯示器，逐幀轉 JPEG 交給回呼。
/// 需要「屏幕錄製」權限（系統設定 → 私隱與安全性 → 屏幕錄製）。
final class ScreenBroadcaster: NSObject {
    /// 每幀 JPEG 資料回呼（在採集佇列上觸發）。
    var onFrame: ((Data) -> Void)?
    /// 啟動失敗回呼（例如未授權「屏幕錄製」），在主執行緒觸發，用於在介面顯示指引。
    var onStartError: ((String) -> Void)?

    // —— 流暢度 / 清晰度參數（如網速不足或更追求流暢可在此調整）——
    /// 採集縮放比例：0.8 = 顯示器解析度的 80%（約 4K 級），兼顧清晰度與 30fps 編碼/頻寬。
    private let captureScale: Double = 0.8
    /// 目標幀率（fps）。30fps 提供流暢的即時畫面。
    private let framesPerSecond: Int = 30
    /// JPEG 壓縮品質（0~1，越高越清晰、體積越大）。
    private let jpegQuality: Double = 0.75

    private var stream: SCStream?
    private let context = CIContext(options: [.cacheIntermediates: false])

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

                let config = SCStreamConfiguration()
                // 0.8 縮放 + 30fps：流暢優先，區域網（LAN）頻寬足以支撐
                config.width = Int(Double(display.width) * captureScale)
                config.height = Int(Double(display.height) * captureScale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(framesPerSecond))
                config.queueDepth = 4
                config.showsCursor = false
                // captureResolution 預設為 .automatic（macOS 14+ 才可明確設定，這裡保持預設）

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(self,
                                           type: .screen,
                                           sampleHandlerQueue: .global(qos: .userInitiated))
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
        stream?.stopCapture { _ in }
        stream = nil
    }
}

// MARK: - SCStreamOutput

extension ScreenBroadcaster: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        guard let jpeg = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [.compressionFactor: jpegQuality]) else { return }

        onFrame?(jpeg)
    }
}
