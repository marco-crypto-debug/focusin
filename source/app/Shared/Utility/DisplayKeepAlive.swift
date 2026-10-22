import Foundation

/// 防熄屏：接收廣播 / 鎖定期間停用 idle display sleep 與 idle system sleep，
/// 避免學生機因「沒有操作活動」而自動熄屏，導致教師畫面被切斷。
/// 使用引用計數：多處同時需要保持（廣播 + 鎖定）時，全部釋放才真正結束。
final class DisplayKeepAlive {
    static let shared = DisplayKeepAlive()
    private var token: NSObjectProtocol?
    private var refCount = 0
    private let lock = NSLock()

    /// 開始保持（可重複呼叫，引用計數 +1）。
    func engage() {
        lock.lock()
        refCount += 1
        if token == nil {
            token = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
                reason: "FocusIn 正在接收教師屏幕廣播")
        }
        lock.unlock()
    }

    /// 釋放一次保持（引用計數歸零才真正 endActivity）。
    func release() {
        lock.lock()
        refCount = max(refCount - 1, 0)
        if refCount == 0, let t = token {
            ProcessInfo.processInfo.endActivity(t)
            token = nil
        }
        lock.unlock()
    }
}
