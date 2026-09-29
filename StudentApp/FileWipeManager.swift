import Foundation

/// 學生端「清空文件」執行器：僅處理目前使用者的 Documents 與 Downloads 兩個資料夾，
/// 永久刪除其中全部內容（不含資料夾本身），逐項記錄結果並回報給教師端。
/// 只作用於使用者家目錄下的這兩個資料夾，不觸碰任何系統位置。
enum FileWipeManager {
    static func wipeUserFolders() -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let targets: [(name: String, dir: URL)] = [
            ("Documents", home.appendingPathComponent("Documents", isDirectory: true)),
            ("Downloads", home.appendingPathComponent("Downloads", isDirectory: true))
        ]

        var removedCount = 0
        var errorCount = 0
        var lines: [String] = []

        for target in targets {
            let items: [URL]
            do {
                items = try fm.contentsOfDirectory(at: target.dir,
                                                   includingPropertiesForKeys: nil,
                                                   options: [])
            } catch {
                lines.append("\(target.name)：無法讀取（可能不存在或無權限）")
                continue
            }

            var removed = 0
            var failed = 0
            for item in items {
                do {
                    try fm.removeItem(at: item)
                    removed += 1
                } catch {
                    failed += 1
                    lines.append("刪除失敗：\(item.lastPathComponent)（\(error.localizedDescription)）")
                }
            }
            lines.append("\(target.name)：刪除 \(removed) 項\(failed > 0 ? "，失敗 \(failed) 項" : "")")
            removedCount += removed
            errorCount += failed
        }

        lines.append("清空完成：共刪除 \(removedCount) 項"
                     + (errorCount > 0 ? "，\(errorCount) 項失敗（詳見日誌）" : ""))
        return lines.joined(separator: " | ")
    }
}
