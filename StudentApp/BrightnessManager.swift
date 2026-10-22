import CoreGraphics
import Darwin
import Foundation

/// 學生端屏幕亮度控制器（教師端一鍵調節）。
/// 使用 DisplayServices 私有 API 動態載入（自簽名分發可用；App Store 審核不可用）。
/// 對內建顯示器與支援 DDC 的顯示器即時生效。
/// 驗證：CoreDisplay_DisplaySetBrightness 在 arm64 已不可見；IODisplaySetFloatParameter
/// 在較新 macOS 對內建屏返回無效 service；DisplayServicesSetBrightness 實測可用。
final class BrightnessManager {
    static let shared = BrightnessManager()
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private var setFn: SetBrightnessFn?
    private var getFn: GetBrightnessFn?

    private init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
                setFn = unsafeBitCast(sym, to: SetBrightnessFn.self)
            }
            if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
                getFn = unsafeBitCast(sym, to: GetBrightnessFn.self)
            }
        }
        DiagLog.log(setFn != nil ? "亮度控制已就緒（DisplayServices）" : "亮度控制不可用（DisplayServices 符號載入失敗）")
    }

    /// 設定主顯示器亮度（0.0 – 1.0）。
    func set(_ value: Float) {
        guard let setFn else { return }
        let clamped = min(max(value, 0.02), 1.0)
        let result = setFn(CGMainDisplayID(), clamped)
        DiagLog.log("亮度調整為 \(Int(clamped * 100))%（result=\(result)）")
    }

    /// 讀取目前主顯示器亮度（0.0 – 1.0）。
    func current() -> Float {
        guard let getFn else { return 1.0 }
        var v: Float = 1.0
        _ = getFn(CGMainDisplayID(), &v)
        return v
    }

    func reset() { set(1.0) }
}
