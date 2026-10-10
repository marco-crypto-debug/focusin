import Foundation
import CryptoKit

/// FocusIn Pro 授權狀態。
enum LicenseStatus: Equatable {
    /// 免費版（未輸入 Key / 未解鎖）。
    case free
    /// Pro 有效中（到期日為某月 1 號，當天未到）。
    case pro(expiry: Date)
    /// 曾解鎖過，但已過期（今天已 >= 到期日），Pro 自動停用。
    case expired(expiry: Date)
    /// Key 格式或簽名無效。
    case invalid(reason: String)

    var isProActive: Bool {
        if case .pro = self { return true }
        return false
    }
}

/// FocusIn Pro License 管理器（離線驗證）。
///
/// Key 格式：`FI-PRO-<b64url(payloadJSON)>.<b64url(ed25519簽名)>`
/// payload：`{"e":"<email>","p":"pro","x":"YYYY-MM-01"}`
///
/// - 驗證：內嵌 Ed25519 公鑰驗簽，簽名不匹配即無效。
/// - 到期模型：expiry 恒為「某月 1 號」；今天 >= expiry 即自動停用 Pro（每月 1 號繳費制）。
/// - 續費：輸入新 Key（新的 expiry）即重新啟用。
/// - 檢查時機：App 啟動時、每 6 小時、以及每次嘗試使用 Pro 功能（如開啟聲音廣播）前。
final class LicenseManager {
    static let shared = LicenseManager()

    /// FocusIn License 簽發公鑰（raw 32 bytes，base64）。
    /// 由 tools/gen-license-key.js --init 生成，請勿隨意更換（會使所有已發 Key 失效）。
    private let pubKeyB64 = "+kWy/MC8XKsOOh2zMJMMChjz4mmFfCD4QC7oDY0RNcY="

    /// 開發者專用永久 KEY（解鎖測試版本；expiry 2099-01-01，永不過期）。
    /// 僅供開發者 / 測試者輸入，正式用戶請透過官網付款頁取得月度 Key。
    static let developerKey = "FI-PRO-eyJlIjoiZGV2QGZvY3VzaW4uYXBwIiwicCI6InBybyIsIngiOiIyMDk5LTAxLTAxIn0.6RDTha8QFPoxAsqJbnUL66XqZG_h06PFhTbV8vLcGmxTLW3rl_n4CyZEFAHSTHnKz2SpbR1UGbDtDQ810k9fAg"

    /// 儲存 Key 的 UserDefaults 鍵。
    private let storageKey = "focusin.license.key"

    /// 目前授權狀態（啟動時從持久化 Key 還原）。
    private(set) var status: LicenseStatus = .free

    /// Pro 是否有效（供 UI / 功能開關查詢）。
    var isProActive: Bool { status.isProActive }

    /// 到期日（格式化 YYYY-MM-01），無效或免費時為 nil。
    var expiryString: String? {
        switch status {
        case .pro(let d), .expired(let d): return Self.formatMonthFirst(d)
        default: return nil
        }
    }

    /// 已存 Key（供 UI 顯示遮罩）。
    var storedKey: String {
        UserDefaults.standard.string(forKey: storageKey) ?? ""
    }

    private init() {
        if let key = UserDefaults.standard.string(forKey: storageKey), !key.isEmpty {
            status = Self.validate(key: key, pubKeyB64: pubKeyB64)
        }
    }

    // MARK: - 公開 API

    /// 輸入 / 更換 License Key；成功則持久化。
    @discardableResult
    func activate(key: String) -> LicenseStatus {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = Self.validate(key: trimmed, pubKeyB64: pubKeyB64)
        if case .pro = result {
            UserDefaults.standard.set(trimmed, forKey: storageKey)
        } else if case .expired = result {
            // 過期的 Key 仍記住（方便顯示「已過期」狀態），但不算啟用
            UserDefaults.standard.set(trimmed, forKey: storageKey)
        }
        status = result
        DiagLog.log("License：\(Self.describe(result))")
        return result
    }

    /// 清除本地 License（登出 / 換機）。
    func deactivate() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        status = .free
        DiagLog.log("License：已清除本機授權")
    }

    /// 重新評估到期狀態（App 啟動、定時、使用 Pro 功能前呼叫）。
    func checkExpiry() {
        guard let key = UserDefaults.standard.string(forKey: storageKey), !key.isEmpty else { return }
        let fresh = Self.validate(key: key, pubKeyB64: pubKeyB64)
        // 只有到期狀態可能變化（免費/無效不變）
        if case .expired = fresh, case .pro = status {
            DiagLog.log("License：已到期（\(Self.formatMonthFirst(freshExpiry(fresh)))），Pro 已自動停用")
        }
        status = fresh
    }

    /// 到期日（Date）取得，用於 checkExpiry 日誌。
    private func freshExpiry(_ s: LicenseStatus) -> Date {
        if case .expired(let d) = s { return d }
        if case .pro(let d) = s { return d }
        return Date()
    }

    /// 每 6 小時自動重查到期（由 App 啟動時呼叫一次，內部持 Timer）。
    func startAutoCheck() {
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.checkExpiry()
        }
    }

    // MARK: - 靜態驗證核心

    /// 解析並驗證 Key；回傳授權狀態。
    static func validate(key: String, pubKeyB64: String) -> LicenseStatus {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // 開發者專用永久 KEY：直接視為 Pro（2099 到期，永不自動停用）
        if trimmed == developerKey {
            if let d = parseMonthFirst("2099-01-01") {
                return .pro(expiry: d)
            }
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payloadPart = parts.first, !payloadPart.isEmpty,
              let sigB64 = parts.last, !sigB64.isEmpty else {
            return .invalid(reason: "格式不正確")
        }
        // 去掉「FI-PRO-」前綴：格式為 FI-PRO-<payload>.<signature>
        let payloadB64 = payloadPart.hasPrefix("FI-PRO-")
            ? String(payloadPart.dropFirst("FI-PRO-".count))
            : String(payloadPart)
        guard !payloadB64.isEmpty,
              let payload = b64urlDecode(payloadB64),
              let sig = b64urlDecode(String(sigB64)) else {
            return .invalid(reason: "編碼錯誤")
        }
        // 簽名驗證
        guard let pubRaw = Data(base64Encoded: pubKeyB64),
              let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubRaw),
              pubKey.isValidSignature(sig, for: payload) else {
            return .invalid(reason: "簽名驗證失敗")
        }
        // 解析 payload JSON
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let email = obj["e"] as? String, !email.isEmpty,
              obj["p"] as? String == "pro",
              let expiryStr = obj["x"] as? String,
              let expiry = parseMonthFirst(expiryStr) else {
            return .invalid(reason: "內容無效")
        }
        // 到期檢查：今天 >= 到期日（某月 1 號）→ 停用
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        if startOfToday >= expiry {
            return .expired(expiry: expiry)
        }
        return .pro(expiry: expiry)
    }

    /// base64url → Data（補 padding）。
    static func b64urlDecode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+")
                  .replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        return Data(base64Encoded: b)
    }

    /// 解析 "YYYY-MM-01" → Date（本地時區當天 00:00）。
    static func parseMonthFirst(_ s: String) -> Date? {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), Int(parts[2]) == 1,
              (1...12).contains(m) else { return nil }
        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = .current
        comps.year = y; comps.month = m; comps.day = 1
        comps.hour = 0; comps.minute = 0; comps.second = 0
        return comps.date
    }

    /// Date → "YYYY-MM-01"。
    static func formatMonthFirst(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        let s = f.string(from: d)
        let parts = s.split(separator: "-")
        guard parts.count == 3 else { return s }
        return "\(parts[0])-\(parts[1])-01"
    }

    static func describe(_ s: LicenseStatus) -> String {
        switch s {
        case .free: return "免費版"
        case .pro(let d): return "Pro 有效至 \(formatMonthFirst(d))"
        case .expired(let d): return "已過期（\(formatMonthFirst(d))），Pro 已停用"
        case .invalid(let r): return "Key 無效（\(r)）"
        }
    }
}
