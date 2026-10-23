import Foundation

// ============================================================
// 裝置上限與傳輸方式（v1.5.10+）
//
//  Pro 功能已移除：不再區分免費 / 高級版。
//  統一上限 50 台；傳輸方式（WebSocket 單播 / UDP 組播）任何人可自選。
//  聲音廣播亦已開放（見 TeacherViewModel）。
//
//  只有 Delta 版（FOCUSIN_DELTA）會編譯此邏輯；stable/alpha/beta
//  不受影響（beta 與 delta 共用 FOCUSIN_BETA，但此檔案只掛在 delta）。
// ============================================================

/// Delta 版傳輸方式（所有用戶均可自選）。
enum TransportMode: String, CaseIterable, Identifiable {
    case websocket = "websocket"
    case udp = "udp"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .websocket: return "WebSocket 單播"
        case .udp: return "UDP 組播"
        }
    }

    /// 建議使用的學生數門檻（≤ 此值建議單播；超過建議組播）。
    static let recommendAt = 5
}

/// 裝置上限查詢（僅 Delta 版可用；其他版本編譯時此類不存在）。
enum DeviceLimit {
    /// 統一上限（50 台）。
    static let proLimit = 50

    /// 目前可用的裝置上限（固定 50 台）。
    static var currentLimit: Int {
        proLimit
    }

    /// 傳輸方式：所有用戶均可自選（不再鎖定）。
    private static let transportKey = "focusin.delta.transport"

    static var transportMode: TransportMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: transportKey),
               let mode = TransportMode(rawValue: raw) {
                return mode
            }
            return .websocket
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: transportKey)
        }
    }

    /// 依目前學生數給出傳輸方式建議（供 UI 提示）。
    static func transportRecommendation(for count: Int) -> String {
        if count <= TransportMode.recommendAt {
            return "目前 \(count) 台 ≤ \(TransportMode.recommendAt) 台，建議 WebSocket 單播：每台獨立串流、更穩定，不依賴 AP 的 multicast 支援。"
        }
        return "目前 \(count) 台 > \(TransportMode.recommendAt) 台，建議 UDP 組播：只發 1 份串流由 AP 複製，50 台也不佔滿 Wi-Fi。"
    }

    /// 檢查是否超過上限；回傳 nil 表示 OK，否則回傳提示訊息。
    static func check(count: Int) -> String? {
        let limit = currentLimit
        guard count > limit else { return nil }
        return "已選 \(count) 台，超過上限（\(proLimit) 台）。"
    }
}
