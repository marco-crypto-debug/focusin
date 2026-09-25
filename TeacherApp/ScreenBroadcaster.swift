import AppKit
import CoreImage
import Foundation
import ScreenCaptureKit

/// 教師屏幕採集：ScreenCaptureKit 捕獲主顯示器，逐幀轉 JPEG 交給回呼。
/// 需要「屏幕錄製」權限（系統設定 → 私隱與安全性 → 屏幕錄製）。
final class ScreenBroadcaster: NSObject {
    /// 每幀 JPEG 資料回呼（在採集佇列上觸發）。
    var onFrame: ((Data) -> Void)?

    // —— 清晰度參數（如網速不足可在此調低）——
    /// 採集縮放比例：1.0 = 顯示器原生全分辨率（最清晰）。
    private let captureScale: Double = 1.0
    /// 目標幀率（fps）。
    private let framesPerSecond: Int = 10
    /// JPEG 壓縮品質（0~1，越高越清晰、體積越大）。
    private let jpegQuality: Double = 0.8

    private var stream: SCStream?
    private let context = CIContext(options: [.cacheIntermediates: false])

    func start(completion: @escaping () -> Void) {
        let startHandler = completion
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                  onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    print("[Broadcaster] 未找到顯示器")
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])

                let config = SCStreamConfiguration()
                // 全分辨率 + 10fps：清晰度優先，區域網（LAN）頻寬足以支撐
                config.width = Int(Double(display.width) * captureScale)
                config.height = Int(Double(display.height) * captureScale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(framesPerSecond))
                config.queueDepth = 3
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
