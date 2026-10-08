import SwiftUI

@main
struct StudentApp: App {
    @StateObject private var listener = CommandListener()
#if FOCUSIN_STABLE
    @NSApplicationDelegateAdaptor(QuitGuardAppDelegate.self) private var quitGuard
#endif

    init() {
        // Pro License：啟動時檢查到期（每月 1 號自動停用）+ 每 6 小時重查
        LicenseManager.shared.checkExpiry()
        LicenseManager.shared.startAutoCheck()
    }

    var body: some Scene {
        WindowGroup {
            StatusView()
                .environmentObject(listener)
                .frame(minWidth: 460, minHeight: 360)
        }
    }
}

#if FOCUSIN_STABLE
/// 正式版（含原 Beta 功能）：退出保護——退出（⌘Q / 選單 / Dock）時必須輸入管理員密碼。
final class QuitGuardAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let allow = QuitGuard.shouldAllowQuit(
            appName: "FocusIn 學生端",
            hasConfigured: KioskConfig.hasAdminPassword,
            verifier: KioskConfig.verify,
            notConfiguredHint: "尚未設定管理員密碼。\n請先在「狀態視窗」設定管理員密碼，才能退出。"
        )
        return allow ? .terminateNow : .terminateCancel
    }
}
#endif

