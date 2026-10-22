import Foundation

/// 除錯診斷日誌（alpha 除錯用）：寫入 `~/Library/Logs/FocusIn-diag.log`，
/// 帶進程名前綴與時間戳。正常使用不影響效能；測試後可刪除該檔案。
enum DiagLog {
    static func log(_ text: String) {
        let path = NSString(string: "~/Library/Logs/FocusIn-diag.log").expandingTildeInPath
        let name = ProcessInfo.processInfo.processName
        let line = "[\(name)] [\(Date())] \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path),
           let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
