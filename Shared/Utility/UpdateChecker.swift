import Foundation

/// 自動更新檢查：App 啟動時查詢 GitHub（marco-crypto-debug/focusin）是否有新版本。
///
/// 策略（零維護）：
/// 1. 優先查 `releases/latest`——若已發佈 Release，用 tag 與本機版本比較。
/// 2. 未發佈 Release 時退回 `main` 分支最新 commit SHA——與本機構建的
///    `CFBundleVersion`（構建時注入 git SHA）比較，任何新提交都視為更新。
///
/// 兩端共用；教師端與學生端啟動時各呼叫一次 `checkForUpdate(notify:)`。
enum UpdateChecker {
    static let repo = "marco-crypto-debug/focusin"
    static let repoPage = "https://github.com/\(repo)"

    /// 更新資訊：版本標記 + 前往下載的網址。
    struct UpdateInfo {
        let version: String      // Release tag 或 commit SHA（前 7 碼）
        let url: String          // Release 頁面或 repo 主頁
        let isRelease: Bool
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

    /// 查詢遠端最新版本。網路失敗或無更新時 completion 收到 nil。
    static func check(completion: @escaping (UpdateInfo?) -> Void) {
        let session = URLSession.shared

        // 1) 最新 Release
        let releaseURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var releaseRequest = URLRequest(url: releaseURL)
        if let token = githubToken {
            releaseRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        releaseRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        session.dataTask(with: releaseRequest) { data, response, _ in
            if let data,
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String,
               let html = json["html_url"] as? String {
                completion(UpdateInfo(version: tag, url: html, isRelease: true))
                return
            }
            // 2) 退回 main 分支最新 commit SHA
            let commitURL = URL(string: "https://api.github.com/repos/\(repo)/commits/main")!
            var commitRequest = URLRequest(url: commitURL)
            if let token = githubToken {
                commitRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            commitRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

            session.dataTask(with: commitRequest) { data2, _, _ in
                guard let data2,
                      let json = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
                      let sha = json["sha"] as? String else {
                    completion(nil)   // 離線或 API 失敗：不提示
                    return
                }
                let short = String(sha.prefix(7))
                completion(UpdateInfo(version: short,
                                      url: "\(repoPage)/releases/latest",
                                      isRelease: false))
            }.resume()
        }
        .resume()
    }

    /// 啟動時自動檢查。偵測到比本機更新 → 在主執行緒回呼通知。
    static func checkForUpdate(notify: @escaping (UpdateInfo) -> Void) {
        check { info in
            guard let info else { return }
            DispatchQueue.main.async {
                if info.isRelease {
                    // Release 路徑：tag 與本機顯示版本比較
                    if localDisplayVersion != info.version { notify(info) }
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
