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

    /// 鎖屏狀態變化通知（供 CommandListener 更新 UI）。
    var onLockStateChanged: ((Bool) -> Void)?

    private var lockWindows: [NSWindow] = []
    private var relockTimer: Timer?
    private let interceptor = InputInterceptor.shared

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
            promptAccessibility()
        }

        // 3) 全屏鎖窗覆蓋所有顯示器
        showLockWindows()
        onLockStateChanged?(true)
    }

    func exitKiosk() {
        guard isLocked else { return }
        relockTimer?.invalidate()
        relockTimer = nil
        interceptor.uninstall()
        lockWindows.forEach { $0.orderOut(nil) }
        lockWindows.removeAll()
        NSApp.presentationOptions = []
        isLocked = false
        unlockRequested = false
        onLockStateChanged?(false)
    }

    // MARK: - 緊急解鎖（⌘⇧U）

    private func beginUnlockFlow() {
        guard isLocked, !unlockRequested else { return }
        unlockRequested = true
        interceptor.uninstall()          // 暫時放行輸入，允許管理員在鎖窗內輸入密碼

        guard KioskConfig.hasAdminPassword else {
            // 從未設定過密碼：無解鎖途徑，保持鎖定
            reinstallBlocking(after: 5)
            return
        }
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
            unlockRequested = false
            reinstallBlocking(after: 0)
            return false
        }
        exitKiosk()
        return true
    }

    private func abortUnlock() {
        guard isLocked else { return }
        unlockRequested = false
        reinstallBlocking(after: 0)
    }

    private func reinstallBlocking(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isLocked else { return }
            if !self.interceptor.install() {
                self.promptAccessibility()
            }
        }
    }

    private func promptAccessibility() {
        let alert = NSAlert()
        alert.messageText = "需要輔助功能權限"
        alert.informativeText = "學生端需要「輔助功能」權限才能在鎖定時屏蔽本機鍵盤與滑鼠輸入。請在系統設定中開啟後重新鎖定。"
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
            window.contentView = NSHostingView(rootView: KioskLockView(controller: self))
            window.makeKeyAndOrderFront(nil)
            window.makeKey()
            return window
        }
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
