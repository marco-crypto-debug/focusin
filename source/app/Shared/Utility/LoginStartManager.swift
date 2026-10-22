import Foundation

/// 登入時自動啟動（LaunchAgent）：以 `~/Library/LaunchAgents/<bundleID>.plist` 註冊，
/// 使用者登入後自動啟動本 App。適用於教師端（教師登入即開）與學生端（開機即就緒）。
enum LoginStartManager {
    /// LaunchAgent plist 的路徑。
    static var plistURL: URL {
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        let label = Bundle.main.bundleIdentifier ?? "com.classroom.app"
        return directory.appendingPathComponent("\(label).plist")
    }

    /// 目前是否已註冊登入自動啟動。
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 註冊登入自動啟動。重複註冊會以目前路徑覆寫（App 移動位置後仍有效）。
    static func enable() throws {
        let directory = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 直接指向 App 內的可執行檔（不依賴 launchd 的 open，穩定性最高）
        guard let executable = Bundle.main.executablePath else {
            throw LoginStartError.noExecutable
        }

        let plist: [String: Any] = [
            "Label": Bundle.main.bundleIdentifier ?? "com.classroom.app",
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                      format: .xml,
                                                      options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    /// 取消登入自動啟動。
    static func disable() {
        try? FileManager.default.removeItem(at: plistURL)
    }

    enum LoginStartError: LocalizedError {
        case noExecutable
        var errorDescription: String? {
            switch self {
            case .noExecutable: return "無法定位 App 可執行檔"
            }
        }
    }
}
