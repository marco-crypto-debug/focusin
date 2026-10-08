import Foundation

/// 主視窗分頁：基礎功能放第一頁，進階設置放第二頁（兩端共用）。
enum FocusInTab: String, CaseIterable, Identifiable {
    case home = "快速操作"
    case advanced = "進階設定"
    var id: String { rawValue }
}

/// 兩端共用的輕量 App 狀態：Menu Bar 與主視窗共享（如切換「進階設定」分頁）。
final class FocusInAppState: ObservableObject {
    static let shared = FocusInAppState()
    @Published var tab: FocusInTab = .home
    private init() {}
}
