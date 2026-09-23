import AppKit
import SwiftUI

/// Kiosk 锁屏控制器：
/// - 全屏无边框窗口覆盖所有显示器，层级高于菜单栏与 Dock
/// - 系统级禁用快捷键（presentationOptions）+ 事件级拦截（CGEventTap）
/// - 紧急解锁流程（本地管理员输密码，⌘⇧U 唤起）
@MainActor
final class KioskModeController: ObservableObject {
    static let shared = KioskModeController()

    @Published var isLocked = false
    @Published var unlockRequested = false
    @Published var broadcastImage: NSImage?

    /// 锁屏状态变化通知（供 CommandListener 更新 UI）。
    var onLockStateChanged: ((Bool) -> Void)?

    private var lockWindows: [NSWindow] = []
    private var relockTimer: Timer?
    private let interceptor = InputInterceptor.shared

    private init() {
        interceptor.onEmergencyUnlockRequested = { [weak self] in
            Task { @MainActor in self?.beginUnlockFlow() }
        }
    }

    // MARK: - 锁定 / 解锁

    func enterKiosk() {
        guard !isLocked else { return }
        isLocked = true
        unlockRequested = false
        broadcastImage = nil

        // 1) 系统级：隐藏 Dock/菜单栏，禁用快捷键与系统入口。
        //    较新的 macOS 上还可加 .disableScreenCapture/.disableSpotlight/
        //    .disableControlCenter/.disableNotificationCenter；这里保持最小
        //    兼容集合，其余快捷键由 InputInterceptor 在 HID 层兜底拦截。
        NSApp.presentationOptions = [
            .hideDock, .hideMenuBar,
            .disableProcessSwitching,      // ⌘⇥ 应用切换
            .disableForceQuit,             // ⌘⌥⎋ 强制退出
            .disableAppleMenu,             // 苹果菜单
            .disableHideApplication,       // ⌘H
            .disableSessionTermination
        ]
        NSApp.activate(ignoringOtherApps: true)

        // 2) 事件级：吞掉本机键盘/鼠标输入
        if !interceptor.install() {
            promptAccessibility()
        }

        // 3) 全屏锁窗覆盖所有显示器
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

    // MARK: - 紧急解锁（⌘⇧U）

    private func beginUnlockFlow() {
        guard isLocked, !unlockRequested else { return }
        unlockRequested = true
        interceptor.uninstall()          // 暂时放行输入，允许管理员在锁窗内输入密码

        guard KioskConfig.hasAdminPassword else {
            // 从未设置过密码：无解锁途径，保持锁定
            reinstallBlocking(after: 5)
            return
        }
        // 60 秒内未输入正确密码则自动重新锁死
        relockTimer?.invalidate()
        relockTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.abortUnlock() }
        }
    }

    /// 校验密码。正确 → 解锁；错误 → 保持锁定并立即恢复输入拦截。
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
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "学生端需要「辅助功能」权限才能在锁定时屏蔽本机键盘与鼠标输入。请在系统设置中开启后重新锁定。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    // MARK: - 全屏锁窗

    private func showLockWindows() {
        let screens = NSScreen.screens.isEmpty ? [NSScreen.main!] : NSScreen.screens
        lockWindows = screens.map { screen in
            let window = LockWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver                    // 高于菜单栏/Dock
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

    // MARK: - 广播画面

    func setBroadcastImage(_ image: NSImage?) {
        broadcastImage = image
    }

    func clearBroadcastImage() {
        broadcastImage = nil
    }
}

/// 无边框但可以成为 Key 窗口（密码输入需要）。
private final class LockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
