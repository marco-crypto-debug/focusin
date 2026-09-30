import Foundation

/// 自動更新檢查：App 啟動時查詢 GitHub（marco-crypto-debug/focusin）是否有新版本。
///
/// 版本分流：
/// - 穩定版（bundle id 不含 `.alpha`）：查 `releases/latest`，與本機顯示版本（如 1.3）比較。
/// - Alpha（bundle id 含 `.alpha`）：查 `releases` 列表，取最新含 `alpha` 的 tag 比較。
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

    /// 版本標記規範化：去首碼 `v`、去空白、轉小寫，供比較。
    /// 例如 "v1.3" → "1.3"，本地 "1.3" → "1.3"，兩者相等 → 無更新。
    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("v") { t = String(t.dropFirst()) }
        return t.lowercased()
    }

    /// 查詢遠端最新版本。網路失敗或無更新時 completion 收到 nil。
    static func check(completion: @escaping (UpdateInfo?) -> Void) {
        if isAlpha {
            checkAlphaRelease(completion: completion)
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

    // MARK: - Alpha：releases 列表取最新 alpha tag

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
            if lower.contains("alpha") == isAlpha && lower.contains("teacher") == isTeacher,
               let url = asset["browser_download_url"] as? String {
                return url
            }
        }
        return nil
    }

    /// 無 assets 資料時（fallback 路徑），依 tag 猜測 DMG 直鏈（GitHub release 資產 URL 規則）。
    private static func assetURL(forTag tag: String) -> String? {
        let prefix = isAlpha ? "FocusIn-Alpha-" : "FocusIn-"
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

    /// 啟動時自動檢查。偵測到比本機更新 → 在主執行緒回呼通知。
    static func checkForUpdate(notify: @escaping (UpdateInfo) -> Void) {
        check { info in
            guard let info else { return }
            DispatchQueue.main.async {
                if info.isRelease {
                    // Release 路徑：規範化 tag 與本機顯示版本比較（v1.3 == 1.3）
                    if normalize(localDisplayVersion) != normalize(info.version) { notify(info) }
                } else {
                    // commit 路徑：本機構建 SHA 與遠端最新 SHA 比較
                    if let local = localBuildSHA, !local.isEmpty {
                        if local != info.version { notify(info) }
                    } else {
                        // 舊版構建沒有 SHA：一律提示一次，方便升級
                        notify(info)
                    }
                }
            }
        }
    }
}
