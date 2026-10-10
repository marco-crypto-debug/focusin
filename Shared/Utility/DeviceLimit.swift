import Foundation

// ============================================================
// Delta 版裝置上限管理
//
//  免費版            → 最多 5 台
//  Pro（普通模式）   → 最多 5 台
//  Pro（高級模式）   → 最多 50 台
//
// 只有 Delta 版（FOCUSIN_DELTA）會編譯此邏輯；stable/alpha/beta
// 不受影響（beta 與 delta 共用 FOCUSIN_BETA，但上限只掛在 delta）。
// ============================================================

/// Delta 版廣播規模模式（Pro 解鎖後由教師自行選擇）。
enum BroadcastScale: String, CaseIterable, Identifiable {
    case standard = "standard"
    case advanced = "advanced"

    var id: String { rawValue }

    /// 顯示名稱
    var label: String {
        switch self {
        case .standard: return "普通（最多 5 台）"
        case .advanced: return "高級（最多 50 台）"
        }
    }

    /// 上限
    var deviceLimit: Int {
        switch self {
        case .standard: return 5
        case .advanced: return 50
        }
    }
}

/// 裝置上限查詢（僅 Delta 版可用；其他版本編譯時此類不存在）。
enum DeviceLimit {
    /// 免費版上限（固定 5 台）。
    static let freeLimit = 5

    /// 目前模式（預設普通）。
    private static let modeKey = "focusin.delta.scale"

    static var scale: BroadcastScale {
        get {
            if let raw = UserDefaults.standard.string(forKey: modeKey),
               let mode = BroadcastScale(rawValue: raw) {
                return mode
            }
            return .standard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }

    /// 目前可用的裝置上限：Pro 有效時依所選模式，否則免費 5 台。
    static var currentLimit: Int {
        if LicenseManager.shared.isProActive {
            return scale.deviceLimit
        }
        return freeLimit
    }

    /// 是否為高級模式（僅 Pro 且選了高級才為 true）。
    static var isAdvanced: Bool {
        LicenseManager.shared.isProActive && scale == .advanced
    }

    /// 檢查是否超過上限；回傳 nil 表示 OK，否則回傳提示訊息。
    static func check(count: Int) -> String? {
        let limit = currentLimit
        guard count > limit else { return nil }
        let modeDesc = LicenseManager.shared.isProActive ? scale.label : "免費版（最多 5 台）"
        return "已選 \(count) 台，超過目前上限（\(modeDesc)）。\n"
             + (LicenseManager.shared.isProActive
                ? "可在「進階設定 → Broadcast Scale」切換至高級模式（最多 50 台）。"
                : "啟用 FocusIn Pro 後可升級至最多 50 台。")
    }
}
