import Foundation

// ============================================================
// Delta 版裝置上限管理（v1.5.3+ 簡化版）
//
//  免費版（普通）→ 最多 5 台，WebSocket 單播，無聲音廣播
//  Pro（高級）  → 最多 50 台，UDP 組播 + 聲音廣播
//
// 只有 Delta 版（FOCUSIN_DELTA）會編譯此邏輯；stable/alpha/beta
// 不受影響（beta 與 delta 共用 FOCUSIN_BETA，但上限只掛在 delta）。
// ============================================================

/// 裝置上限查詢（僅 Delta 版可用；其他版本編譯時此類不存在）。
enum DeviceLimit {
    /// 免費版上限（固定 5 台）。
    static let freeLimit = 5

    /// Pro（高級）上限（50 台）。
    static let proLimit = 50

    /// 目前可用的裝置上限：Pro 有效時 50 台，否則免費 5 台。
    static var currentLimit: Int {
        LicenseManager.shared.isProActive ? proLimit : freeLimit
    }

    /// 是否為高級（組播）模式：Pro 解鎖即為高級。
    static var isAdvanced: Bool {
        LicenseManager.shared.isProActive
    }

    /// 檢查是否超過上限；回傳 nil 表示 OK，否則回傳提示訊息。
    static func check(count: Int) -> String? {
        let limit = currentLimit
        guard count > limit else { return nil }
        return LicenseManager.shared.isProActive
            ? "已選 \(count) 台，超過高級版上限（\(proLimit) 台）。"
            : "已選 \(count) 台，超過免費版上限（\(freeLimit) 台）。\n啟用 FocusIn Pro 後可升級至最多 \(proLimit) 台並解鎖聲音廣播。"
    }
}
