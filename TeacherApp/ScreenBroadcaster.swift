import AppKit
import CoreImage
import Foundation
import ScreenCaptureKit

/// 教师屏幕采集：ScreenCaptureKit 捕获主显示器，逐帧转 JPEG 交给回调。
/// 需要「屏幕录制」权限（System Settings → Privacy & Security → Screen Recording）。
final class ScreenBroadcaster: NSObject {
    /// 每帧 JPEG 数据回调（在采集队列上触发）。
    var onFrame: ((Data) -> Void)?

    private var stream: SCStream?
    private let context = CIContext(options: [.cacheIntermediates: false])

    func start(completion: @escaping () -> Void) {
        let startHandler = completion
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                  onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    print("[Broadcaster] 未找到显示器")
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])

                let config = SCStreamConfiguration()
                // 半分辨率 + 5fps：教室局域网内带宽与流畅度折中
                config.width = Int(Double(display.width) * 0.5)
                config.height = Int(Double(display.height) * 0.5)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
                config.queueDepth = 3
                config.showsCursor = false
                // captureResolution 默认为 .automatic（macOS 14+ 才可显式设置，这里保持默认）

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(self,
                                           type: .screen,
                                           sampleHandlerQueue: .global(qos: .userInitiated))
                try await stream.startCapture()
                self.stream = stream
                DispatchQueue.main.async { startHandler() }
            } catch {
                print("[Broadcaster] 屏幕捕获失败: \(error)")
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
            .representation(using: .jpeg, properties: [.compressionFactor: 0.5]) else { return }

        onFrame?(jpeg)
    }
}
