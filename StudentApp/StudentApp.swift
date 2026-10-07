import SwiftUI

@main
struct StudentApp: App {
    @StateObject private var listener = CommandListener()
#if FOCUSIN_BETA
    @NSApplicationDelegateAdaptor(QuitGuardAppDelegate.self) private var quitGuard
#endif

    var body: some Scene {
        WindowGroup {
            StatusView()
                .environmentObject(listener)
                .frame(minWidth: 460, minHeight: 360)
        }
    }
}

#if FOCUSIN_BETA
/// Beta 版專屬：退出保護——退出（⌘Q / 選單 / Dock）時必須輸入管理員密碼。
final class QuitGuardAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let allow = QuitGuard.shouldAllowQuit(
            appName: "FocusIn 學生端（Beta）",
            hasConfigured: KioskConfig.hasAdminPassword,
            verifier: KioskConfig.verify,
            notConfiguredHint: "尚未設定管理員密碼。\n請先在「狀態視窗」設定管理員密碼，才能退出。"
        )
        return allow ? .terminateNow : .terminateCancel
    }
}
#endif

