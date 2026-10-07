import SwiftUI

@main
struct TeacherApp: App {
    @StateObject private var viewModel = TeacherViewModel()
#if FOCUSIN_BETA
    @NSApplicationDelegateAdaptor(QuitGuardAppDelegate.self) private var quitGuard
#endif

    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environmentObject(viewModel)
                .frame(minWidth: 760, minHeight: 480)
        }
    }
}

#if FOCUSIN_BETA
/// Beta 版專屬：退出保護——退出（⌘Q / 選單 / Dock）時必須輸入退出密碼。
final class QuitGuardAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let allow = QuitGuard.shouldAllowQuit(
            appName: "FocusIn 教師端（Beta）",
            hasConfigured: QuitGuard.hasPassword,
            verifier: QuitGuard.verify,
            notConfiguredHint: "尚未設定退出密碼。\n請先在主視窗「退出保護」區塊設定密碼，才能退出。"
        )
        return allow ? .terminateNow : .terminateCancel
    }
}
#endif

