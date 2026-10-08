import SwiftUI

@main
struct TeacherApp: App {
    @StateObject private var viewModel = TeacherViewModel()
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
            DeviceListView()
                .environmentObject(viewModel)
                .frame(minWidth: 760, minHeight: 480)
        }
    }
}

#if FOCUSIN_STABLE
/// 正式版（含原 Beta 功能）：退出保護——退出（⌘Q / 選單 / Dock）時必須輸入管理員密碼。
final class QuitGuardAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let allow = QuitGuard.shouldAllowQuit(
            appName: "FocusIn 教師端",
            hasConfigured: QuitGuard.hasPassword,
            verifier: QuitGuard.verify,
            notConfiguredHint: "尚未設定管理員密碼。\n請先在主視窗「管理員密碼」區塊設定，才能退出。"
        )
        return allow ? .terminateNow : .terminateCancel
    }
}
#endif

