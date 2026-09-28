import AppKit
import SwiftUI

/// Kiosk 鎖屏控制器：
/// - 全屏無邊框視窗覆蓋所有顯示器，層級高於選單列與 Dock
/// - 系統級停用快捷鍵（presentationOptions）+ 事件級攔截（CGEventTap）
/// - 緊急解鎖流程（本地管理員輸密碼，⌘⇧U 喚起）
@MainActor
final class KioskModeController: ObservableObject {
    static let shared = KioskModeController()

    @Published var isLocked = false
    @Published var unlockRequested = false
    @Published var broadcastImage: NSImage?
    /// 目前是否正由 CGEventTap 攔截輸入（決定鎖屏是否提示輔助功能授權）。
    @Published var isInputBlocked = false
    /// 鎖屏上的瞬時提示訊息（如「密碼錯誤」「未設定密碼」）。
    @Published var unlockHint: String?

    /// 鎖屏狀態變化通知（供 CommandListener 更新 UI）。
    var onLockStateChanged: ((Bool) -> Void)?

    private var lockWindows: [NSWindow] = []
    private var relockTimer: Timer?
    private let interceptor = InputInterceptor.shared
    /// 鎖定期間註冊的系統通知觀察者（螢幕參數變化 / 失去焦點），用於鎖屏自愈。
    private var observers: [NSObjectProtocol] = []

    private init() {
        interceptor.onEmergencyUnlockRequested = { [weak self] in
            Task { @MainActor in self?.beginUnlockFlow() }
        }
    }

    // MARK: - 鎖定 / 解鎖

    func enterKiosk() {
        guard !isLocked else { return }
        isLocked = true
        unlockRequested = false
        broadcastImage = nil
        unlockHint = nil

        // 1) 系統級：隱藏 Dock/選單列，停用快捷鍵與系統入口。
        //    較新的 macOS 上還可加 .disableScreenCapture/.disableSpotlight/
        //    .disableControlCenter/.disableNotificationCenter；這裡保持最小
        //    相容集合，其餘快捷鍵由 InputInterceptor 在 HID 層兜底攔截。
        NSApp.presentationOptions = [
            .hideDock, .hideMenuBar,
            .disableProcessSwitching,      // ⌘⇥ 應用程式切換
            .disableForceQuit,             // ⌘⌥⎋ 強制結束
            .disableAppleMenu,             // 蘋果選單
            .disableHideApplication,       // ⌘H
            .disableSessionTermination
        ]
        NSApp.activate(ignoringOtherApps: true)

        // 2) 事件級：吞掉本機鍵盤/滑鼠輸入
        if !interceptor.install() {
            isInputBlocked = false
            promptAccessibility()
        } else {
            isInputBlocked = true
        }

        // 3) 全屏鎖窗覆蓋所有顯示器（並註冊自愈機制）
        showLockWindows()
        registerLockObservers()
        onLockStateChanged?(true)
    }

    func exitKiosk() {
        guard isLocked else { return }
        relockTimer?.invalidate()
        relockTimer = nil
        removeLockObservers()
        interceptor.uninstall()
        lockWindows.forEach { $0.orderOut(nil) }
        lockWindows.removeAll()
        NSApp.presentationOptions = []
        isLocked = false
        unlockRequested = false
        isInputBlocked = false
        unlockHint = nil
        onLockStateChanged?(false)
    }

    // MARK: - 緊急解鎖（⌘⇧U）

    private func beginUnlockFlow() {
        guard isLocked, !unlockRequested else { return }

        // 從未設定管理員密碼：沒有可用的緊急解鎖途徑，保持鎖定並明確提示
        guard KioskConfig.hasAdminPassword else {
            flashHint("未設定本地管理員密碼，無法緊急解鎖；請由教師下發解鎖指令。")
            return
        }

        unlockRequested = true
        interceptor.uninstall()          // 暫時放行輸入，允許管理員在鎖窗內輸入密碼
        isInputBlocked = false
        flashHint("請輸入本地管理員密碼（60 秒內未輸入將自動重新鎖定）")

        // 60 秒內未輸入正確密碼則自動重新鎖死
        relockTimer?.invalidate()
        relockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.abortUnlock() }
        }
    }

    /// 校驗密碼。正確 → 解鎖；錯誤 → 保持鎖定並立即恢復輸入攔截。
    @discardableResult
    func submitUnlock(_ password: String) -> Bool {
        guard KioskConfig.verify(password) else {
            relockTimer?.invalidate()
            relockTimer = nil
            unlockRequested = false
            reinstallBlocking(after: 0)
            flashHint("密碼錯誤，已恢復鎖定（再次按 ⌘⇧U 重試）")
            return false
        }
        exitKiosk()
        return true
    }

    private func abortUnlock() {
        guard isLocked else { return }
        unlockRequested = false
        reinstallBlocking(after: 0)
        flashHint("已逾時，重新鎖定")
    }

    private func reinstallBlocking(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isLocked else { return }
            if !self.interceptor.install() {
                self.isInputBlocked = false
                self.promptAccessibility()
            } else {
                self.isInputBlocked = true
            }
        }
    }

    /// 在鎖屏顯示一條瞬時提示，5 秒後自動清除。
    private func flashHint(_ text: String) {
        unlockHint = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.unlockHint == text else { return }
            self.unlockHint = nil
        }
    }

    private func promptAccessibility() {
        let alert = NSAlert()
        alert.messageText = "需要輔助功能權限"
        alert.informativeText = "學生端需要「輔助功能」權限才能在鎖定時屏蔽本機鍵盤與滑鼠輸入，緊急解鎖（⌘⇧U）也依賴該權限。請在系統設定中開啟後重新鎖定。"
        alert.addButton(withTitle: "打開系統設定")
        alert.addButton(withTitle: "稍後")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    // MARK: - 全屏鎖窗

    private func showLockWindows() {
        let screens = NSScreen.screens.isEmpty ? [NSScreen.main!] : NSScreen.screens

        // 先移除舊鎖窗，避免「螢幕參數變化」觸發重建時重複疊加
        lockWindows.forEach { $0.orderOut(nil) }
        lockWindows.removeAll()

        lockWindows = screens.map { screen in
            let window = LockWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver                    // 高於選單列/Dock
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: KioskLockView(controller: self))
            window.makeKeyAndOrderFront(nil)
            // 關鍵：即使本 App 不是前臺應用（例如學生機正處於其他 App 的全屏模式/全屏 Space），
            // orderFrontRegardless 也會強制把鎖窗抬到最上層。
            window.orderFrontRegardless()
            return window
        }

        // 啟動後再抬升一次，確保蓋過全屏 App 與全屏 Space
        NSApp.activate(ignoringOtherApps: true)
        for window in lockWindows {
            window.makeKey()
            window.orderFrontRegardless()
        }
    }

    // MARK: - 鎖定期間的自愈機制

    private func registerLockObservers() {
        let center = NotificationCenter.default
        // 螢幕參數變化（接上/喚醒外接顯示器、解析度改變）：重建鎖窗，避免出現未覆蓋的縫隙
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isLocked, !self.unlockRequested else { return }
                self.showLockWindows()
            }
        })
        // 被其他 App 搶走焦點（例如尚未授予輔助功能權限時）：
        // 奪回焦點、把鎖窗抬回最上層，並嘗試補裝輸入攔截。
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isLocked else { return }
                NSApp.activate(ignoringOtherApps: true)
                for window in self.lockWindows { window.orderFrontRegardless() }
                guard !self.unlockRequested else { return }
                if self.interceptor.isActive {
                    self.isInputBlocked = true
                } else if self.interceptor.install() {
                    self.isInputBlocked = true
                } else {
                    self.isInputBlocked = false
                    self.promptAccessibility()
                }
            }
        })
    }

    private func removeLockObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: - 廣播畫面

    func setBroadcastImage(_ image: NSImage?) {
        broadcastImage = image
    }

    func clearBroadcastImage() {
        broadcastImage = nil
    }
}

/// 無邊框但可以成為 Key 視窗（密碼輸入需要）。
private final class LockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
