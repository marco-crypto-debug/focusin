import AppKit

/// FocusIn Menu Bar（control bar）常駐圖示管理器。
///
/// 兩端共用：安裝一個 NSStatusItem，點擊時透過 NSMenuDelegate 動態重建選單，
/// 因此選單內容會即時反映目前狀態（廣播中／已鎖定／連線數等）。
final class MenuBarManager: NSObject, NSMenuDelegate {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var menuBuilder: (() -> NSMenu)?

    private override init() {
        super.init()
    }

    /// 安裝 Menu Bar 圖示（可重複呼叫以更換圖示/選單建構器）。
    /// - Parameters:
    ///   - icon: SF Symbol 名稱（如 "display"、"desktopcomputer"）。
    ///   - menuBuilder: 每次展開選單時呼叫，回傳當前狀態下的選單。
    func install(icon: String, menuBuilder: @escaping () -> NSMenu) {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: icon, accessibilityDescription: "FocusIn")
            item.menu = NSMenu()
            item.menu?.delegate = self
            statusItem = item
        }
        self.menuBuilder = menuBuilder
    }

    /// 更新圖示（如廣播中切換樣式）。
    func setIcon(_ icon: String) {
        statusItem?.button?.image = NSImage(systemSymbolName: icon, accessibilityDescription: "FocusIn")
    }

    // MARK: - NSMenuDelegate（每次展開時重建，反映最新狀態）

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let items = menuBuilder?().items else { return }
        for item in items {
            menu.addItem(item)
        }
    }
}
