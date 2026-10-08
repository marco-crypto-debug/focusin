import AppKit
import SwiftUI

@main
struct TeacherApp: App {
    @StateObject private var viewModel = TeacherViewModel()
    @NSApplicationDelegateAdaptor(TeacherAppDelegate.self) private var appDelegate

    init() {
        // Pro License：啟動時檢查到期（每月 1 號自動停用）+ 每 6 小時重查
        LicenseManager.shared.checkExpiry()
        LicenseManager.shared.startAutoCheck()
    }

    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environmentObject(viewModel)
                .frame(minWidth: 720, minHeight: 460)
                .onAppear {
                    appDelegate.attach(viewModel: viewModel, appState: FocusInAppState.shared)
                }
        }
    }
}

/// 教師端 App Delegate：Menu Bar（control bar）常駐圖示 + 退出保護（穩定版）。
@MainActor
final class TeacherAppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: TeacherViewModel?
    private var appState: FocusInAppState?

    func attach(viewModel: TeacherViewModel, appState: FocusInAppState) {
        self.viewModel = viewModel
        self.appState = appState
        installMenuBar()
    }

    private func installMenuBar() {
        MenuBarManager.shared.install(icon: "rectangle.on.rectangle") { [weak self] in
            let menu = NSMenu()
            guard let self = self, let vm = self.viewModel else { return menu }

            let header = NSMenuItem(title: "FocusIn 教師端", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())

            // 廣播
            let b = NSMenuItem(title: vm.broadcastActive ? "■ 停止廣播" : "▶ 廣播教師屏幕",
                               action: #selector(self.mbToggleBroadcast), keyEquivalent: "b")
            b.target = self
            menu.addItem(b)

            // 鎖定 / 解鎖
            let l = NSMenuItem(title: "🔒 鎖定全部學生", action: #selector(self.mbLockAll), keyEquivalent: "l")
            l.target = self
            menu.addItem(l)
            let u = NSMenuItem(title: "🔓 解鎖全部學生", action: #selector(self.mbUnlockAll), keyEquivalent: "u")
            u.target = self
            menu.addItem(u)

            menu.addItem(.separator())

            // 視窗
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

    @objc private func mbToggleBroadcast() { viewModel?.toggleBroadcast() }
    @objc private func mbLockAll() { viewModel?.sendLock() }
    @objc private func mbUnlockAll() { viewModel?.sendUnlock() }

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
        // 穩定版有退出保護（QuitGuard）；非穩定版直接退出。
        #if FOCUSIN_STABLE || FOCUSIN_BETA
        let allow = QuitGuard.shouldAllowQuit(
            appName: "FocusIn 教師端",
            hasConfigured: QuitGuard.hasPassword,
            verifier: QuitGuard.verify,
            notConfiguredHint: "尚未設定管理員密碼。\n請先在主視窗「進階設定 → 管理員密碼」設定，才能退出。"
        )
        if allow { NSApp.terminate(nil) }
        #else
        NSApp.terminate(nil)
        #endif
    }

    #if FOCUSIN_STABLE || FOCUSIN_BETA
    /// 退出保護：⌘Q / Dock / 選單一律需要管理員密碼。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let allow = QuitGuard.shouldAllowQuit(
            appName: "FocusIn 教師端",
            hasConfigured: QuitGuard.hasPassword,
            verifier: QuitGuard.verify,
            notConfiguredHint: "尚未設定管理員密碼。\n請先在主視窗「進階設定 → 管理員密碼」設定，才能退出。"
        )
        return allow ? .terminateNow : .terminateCancel
    }
    #endif
}
