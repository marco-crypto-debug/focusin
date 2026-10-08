import AppKit
import SwiftUI

@main
struct StudentApp: App {
    @StateObject private var listener = CommandListener()
    @NSApplicationDelegateAdaptor(StudentAppDelegate.self) private var appDelegate

    init() {
        // Pro License：啟動時檢查到期（每月 1 號自動停用）+ 每 6 小時重查
        LicenseManager.shared.checkExpiry()
        LicenseManager.shared.startAutoCheck()
    }

    var body: some Scene {
        WindowGroup {
            StatusView()
                .environmentObject(listener)
                .frame(minWidth: 380, minHeight: 420)
                .onAppear {
                    appDelegate.attach(listener: listener, appState: FocusInAppState.shared)
                }
        }
    }
}

/// 學生端 App Delegate：Menu Bar（control bar）常駐圖示 + 退出保護（穩定版）。
@MainActor
final class StudentAppDelegate: NSObject, NSApplicationDelegate {
    private var listener: CommandListener?
    private var appState: FocusInAppState?

    func attach(listener: CommandListener, appState: FocusInAppState) {
        self.listener = listener
        self.appState = appState
        installMenuBar()
    }

    private func installMenuBar() {
        MenuBarManager.shared.install(icon: "desktopcomputer") { [weak self] in
            let menu = NSMenu()
            guard let self = self, let ls = self.listener else { return menu }

            let state = NSMenuItem(title: ls.connectionCount > 0
                                   ? "● \(ls.connectionCount) 位教師已連線"
                                   : "○ 等待教師連線…", action: nil, keyEquivalent: "")
            state.isEnabled = false
            menu.addItem(state)

            let lock = NSMenuItem(title: ls.isLocked ? "屏幕已鎖定" : "屏幕未鎖定", action: nil, keyEquivalent: "")
            lock.isEnabled = false
            menu.addItem(lock)
            menu.addItem(.separator())

            let w = NSMenuItem(title: "開啟主視窗", action: #selector(self.mbShowMainWindow), keyEquivalent: "o")
            w.target = self
            menu.addItem(w)
            let a = NSMenuItem(title: "進階設定", action: #selector(self.mbOpenAdvanced), keyEquivalent: ",")
            a.target = self
            menu.addItem(a)

            menu.addItem(.separator())

            let q = NSMenuItem(title: "退出 FocusIn", action: #selector(self.mbQuit), keyEquivalent: "q")
            q.target = self
            menu.addItem(q)
            return menu
        }
    }

    // MARK: - Menu Bar 動作

    @objc private func mbShowMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.canBecomeMain {
            w.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func mbOpenAdvanced() {
        appState?.tab = .advanced
        mbShowMainWindow()
    }

    @objc private func mbQuit() {
        #if FOCUSIN_STABLE
        let allow = QuitGuard.shouldAllowQuit(
            appName: "FocusIn 學生端",
            hasConfigured: KioskConfig.hasAdminPassword,
            verifier: KioskConfig.verify,
            notConfiguredHint: "尚未設定管理員密碼。\n請先在「狀態視窗 → 進階設定 → 管理員密碼」設定，才能退出。"
        )
        if allow { NSApp.terminate(nil) }
        #else
        NSApp.terminate(nil)
        #endif
    }

    #if FOCUSIN_STABLE
    /// 退出保護：⌘Q / Dock / 選單一律需要管理員密碼。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let allow = QuitGuard.shouldAllowQuit(
            appName: "FocusIn 學生端",
            hasConfigured: KioskConfig.hasAdminPassword,
            verifier: KioskConfig.verify,
            notConfiguredHint: "尚未設定管理員密碼。\n請先在「狀態視窗 → 進階設定 → 管理員密碼」設定，才能退出。"
        )
        return allow ? .terminateNow : .terminateCancel
    }
    #endif
}
