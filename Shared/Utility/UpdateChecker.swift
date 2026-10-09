import AppKit
import Foundation

/// 自動更新檢查：App 啟動時查詢 GitHub（marco-crypto-debug/focusin）是否有新版本。
///
/// 版本分流：
/// - 穩定版（bundle id 不含 `.alpha`/`.beta`）：查 `releases/latest`，與本機顯示版本（如 1.3）比較。
/// - Alpha（bundle id 含 `.alpha`）：查 `releases` 列表，取最新含 `alpha` 的 tag 比較。
/// - Beta（bundle id 含 `.beta`）：查 `releases` 列表，取最新含 `beta` 的 tag 比較。
///
/// 抗 rate limit：GitHub API 未認證僅 60 次/小時/IP，教室網絡極易超限；
/// API 失敗時穩定版自動退回「網頁重定向」解析最新 tag（不吃 API 配額），alpha 則靜默。
///
/// 兩端共用；教師端與學生端啟動時各呼叫一次 `checkForUpdate(notify:)`。
enum UpdateChecker {
    static let repo = "marco-crypto-debug/focusin"
    static let repoPage = "https://github.com/\(repo)"

    /// 更新資訊：版本標記 + 下載/頁面網址。
    struct UpdateInfo {
        let version: String      // Release tag（如 v1.3 / v1.3-alpha）
        let url: String          // 對應端別 DMG 資產直鏈（無匹配時回退 release 頁面）
        let pageURL: String      // release 頁面（供按鈕跳轉）
        let isRelease: Bool
    }

    /// 本機是否 alpha 測試版（bundle id 含 `.alpha`）。
    static var isAlpha: Bool {
        Bundle.main.bundleIdentifier?.contains(".alpha") == true
    }

    /// 本機是否 beta 測試版（bundle id 含 `.beta`）。
    static var isBeta: Bool {
        Bundle.main.bundleIdentifier?.contains(".beta") == true
    }

    /// 本機是否教師端（bundle id 含 `teacher`）。
    static var isTeacher: Bool {
        Bundle.main.bundleIdentifier?.contains("teacher") == true
    }

    /// 本機版本標記（構建時注入的 commit SHA 前 7 碼）。
    static var localBuildSHA: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    /// 本機顯示版本（Info.plist 的 CFBundleShortVersionString）。
    static var localDisplayVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// GitHub API token（可選，用於提高 rate limit）。從 Info.plist 的 `GitHubAPIToken` 讀取。
    static var githubToken: String? {
        Bundle.main.infoDictionary?["GitHubAPIToken"] as? String
    }

    /// 版本標記規範化：去首碼 `v`、去空白、轉小寫，供顯示/比較。
    /// 例如 "v1.3" → "1.3"，本地 "1.3" → "1.3"。
    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("v") { t = String(t.dropFirst()) }
        return t.lowercased()
    }

    /// 語義化版本比較：`lhs` 是否比 `rhs` 舊（lhs < rhs）。
    /// 只取數字段（"1.3.4-alpha" → [1,3,4]），尾綴（-alpha/-beta）忽略——
    /// 版本分流已保證 alpha 只與 alpha 比較，故尾綴不影響判斷。
    static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        func nums(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let a = nums(lhs)
        let b = nums(rhs)
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false   // 完全相同 → 不是更舊
    }

    /// 查詢遠端最新版本。網路失敗或無更新時 completion 收到 nil。
    static func check(completion: @escaping (UpdateInfo?) -> Void) {
        if isAlpha {
            checkAlphaRelease(completion: completion)
        } else if isBeta {
            checkBetaRelease(completion: completion)
        } else {
            checkLatestRelease(completion: completion)
        }
    }

    // MARK: - 穩定版：releases/latest（API）→ 網頁重定向 fallback

    private static func checkLatestRelease(completion: @escaping (UpdateInfo?) -> Void) {
        fetchJSON("releases/latest") { json in
            if let dict = json as? [String: Any],
               let tag = dict["tag_name"] as? String {
                completion(makeInfo(from: dict, tag: tag))
                return
            }
            // API 失敗（rate limit / 離線）：用 GitHub 網頁重定向解析最新 tag，不吃 API 配額
            resolveLatestTagViaWebRedirect { tag in
                guard let tag else { completion(nil); return }
                completion(UpdateInfo(version: tag,
                                      url: assetURL(forTag: tag) ?? "\(repoPage)/releases/tag/\(tag)",
                                      pageURL: "\(repoPage)/releases/tag/\(tag)",
                                      isRelease: true))
            }
        }
    }

    /// 請求 `releases/latest` 並讀取重定向後的最終 URL，從 `/releases/tag/<tag>` 提取 tag。
    private static func resolveLatestTagViaWebRedirect(completion: @escaping (String?) -> Void) {
        var req = URLRequest(url: URL(string: "\(repoPage)/releases/latest")!)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { _, response, _ in
            guard let resp = response as? HTTPURLResponse,
                  let final = resp.url,
                  final.pathComponents.contains("tag"),
                  let tag = final.pathComponents.last else {
                completion(nil)
                return
            }
            completion(tag)
        }.resume()
    }

    // MARK: - Alpha/Beta：releases 列表取最新對應 tag

    private static func checkAlphaRelease(completion: @escaping (UpdateInfo?) -> Void) {
        fetchJSON("releases?per_page=10") { json in
            guard let array = json as? [[String: Any]] else { completion(nil); return }
            for release in array {
                guard let tag = release["tag_name"] as? String,
                      tag.lowercased().contains("alpha") else { continue }
                completion(makeInfo(from: release, tag: tag))
                return
            }
            completion(nil)
        }
    }

    private static func checkBetaRelease(completion: @escaping (UpdateInfo?) -> Void) {
        fetchJSON("releases?per_page=20") { json in
            guard let array = json as? [[String: Any]] else { completion(nil); return }
            for release in array {
                guard let tag = release["tag_name"] as? String,
                      tag.lowercased().contains("beta") else { continue }
                completion(makeInfo(from: release, tag: tag))
                return
            }
            completion(nil)
        }
    }

    // MARK: - 通用

    /// 組裝 UpdateInfo：自動匹配「本端別」的 DMG 資產直鏈（teacher/student × stable/alpha）。
    private static func makeInfo(from json: [String: Any], tag: String) -> UpdateInfo {
        let page = (json["html_url"] as? String) ?? "\(repoPage)/releases/latest"
        let direct = assetURL(in: json, tag: tag) ?? page
        return UpdateInfo(version: tag, url: direct, pageURL: page, isRelease: true)
    }

    /// 從 release JSON 的 assets 中，挑選與本端別匹配的 DMG 下載直鏈。
    private static func assetURL(in json: [String: Any], tag: String) -> String? {
        guard let assets = json["assets"] as? [[String: Any]] else { return nil }
        for asset in assets {
            guard let name = asset["name"] as? String, name.lowercased().hasSuffix(".dmg") else { continue }
            let lower = name.lowercased()
            if lower.contains("alpha") == isAlpha && lower.contains("beta") == isBeta
                && lower.contains("teacher") == isTeacher,
               let url = asset["browser_download_url"] as? String {
                return url
            }
        }
        return nil
    }

    /// 無 assets 資料時（fallback 路徑），依 tag 猜測 DMG 直鏈（GitHub release 資產 URL 規則）。
    private static func assetURL(forTag tag: String) -> String? {
        let prefix: String
        if isAlpha { prefix = "FocusIn-Alpha-" }
        else if isBeta { prefix = "FocusIn-Beta-" }
        else { prefix = "FocusIn-" }
        let role = isTeacher ? "Teacher" : "Student"
        return "https://github.com/\(repo)/releases/download/\(tag)/\(prefix)\(role).dmg"
    }

    /// GET GitHub API（可帶 token；失敗回傳 nil）。
    private static func fetchJSON(_ path: String, completion: @escaping (Any?) -> Void) {
        let url = URL(string: "https://api.github.com/repos/\(repo)/\(path)")!
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = githubToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard let data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                completion(nil)
                return
            }
            completion(try? JSONSerialization.jsonObject(with: data))
        }.resume()
    }

    /// 檢查並與本機版本比較。
    /// - completion(info, isLatest)：
    ///   - `info != nil`：偵測到新版本（比本機新），info 為更新資訊。
    ///   - `info == nil && isLatest == true`：已是最新版本。
    ///   - `info == nil && isLatest == false`：檢查失敗（離線 / API 不可用 / 無 Release）。
    /// 回呼一律在主執行緒。
    static func checkForUpdate(completion: @escaping (_ info: UpdateInfo?, _ isLatest: Bool) -> Void) {
        check { info in
            guard let info else {
                DispatchQueue.main.async {
                    DiagLog.log("更新檢查失敗（無網路或 API 不可用）")
                    completion(nil, false)
                }
                return
            }
            let isNewer: Bool
            if info.isRelease {
                // Release 路徑：語義化比較——本機比遠端舊 → 有新版本
                // （1.3.3 vs v1.3.4 → 舊 → 提示；1.3.4 vs v1.3.3 → 新 → 不提示；相等 → 不提示）
                isNewer = isOlder(localDisplayVersion, than: info.version)
            } else {
                // commit 路徑：本機構建 SHA 與遠端最新 SHA 比較
                if let local = localBuildSHA, !local.isEmpty {
                    isNewer = local != info.version
                } else {
                    // 舊版構建沒有 SHA：一律視為可更新，方便升級
                    isNewer = true
                }
            }
            DiagLog.log("更新檢查：遠端 \(info.version) vs 本機 \(localDisplayVersion)（\(normalize(info.version)) vs \(normalize(localDisplayVersion))）→ \(isNewer ? "有新版本" : "已是最新")")
            DispatchQueue.main.async {
                completion(isNewer ? info : nil, true)
            }
        }
    }

    // MARK: - 直接下載 DMG

    /// 直接把最新 DMG 下載到 ~/Downloads 並掛載開啟（不再跳轉 GitHub 網頁）。
    /// - 下載期間 UI 顯示進度文字（progressHandler 回呼主執行緒）。
    /// - 完成後用 Finder 掛載 DMG，用戶拖入 Applications 即完成安裝。
    static func downloadAndOpen(_ url: URL, progressHandler: ((Float) -> Void)? = nil) {
        let task = URLSession.shared.downloadTask(with: url) { tmpURL, _, error in
            guard let tmpURL, error == nil else {
                DispatchQueue.main.async {
                    DiagLog.log("更新下載失敗：\(error?.localizedDescription ?? "未知錯誤")")
                    NSSound.beep()
                }
                return
            }
            let fm = FileManager.default
            let dest = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
                .appendingPathComponent(url.lastPathComponent)
            do {
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.moveItem(at: tmpURL, to: dest)
                DispatchQueue.main.async {
                    DiagLog.log("更新已下載：\(dest.path)")
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                    NSWorkspace.shared.open(dest)
                }
            } catch {
                // 移動失敗（跨磁碟等）：退回複製
                do {
                    try fm.copyItem(at: tmpURL, to: dest)
                    DispatchQueue.main.async {
                        DiagLog.log("更新已下載：\(dest.path)")
                        NSWorkspace.shared.activateFileViewerSelecting([dest])
                        NSWorkspace.shared.open(dest)
                    }
                } catch {
                    DispatchQueue.main.async {
                        DiagLog.log("更新儲存失敗：\(error.localizedDescription)")
                        NSSound.beep()
                    }
                }
            }
        }
        // 進度回報（downloadTask 進度透過 Progress 物件觀察）
        if let handler = progressHandler {
            let progress = task.progress
            DispatchQueue.global(qos: .utility).async {
                while !task.progress.isFinished && !task.progress.isCancelled {
                    let f = Float(progress.fractionCompleted)
                    DispatchQueue.main.async { handler(f) }
                    Thread.sleep(forTimeInterval: 0.2)
                }
                DispatchQueue.main.async { handler(1) }
            }
        }
        task.resume()
    }
}
