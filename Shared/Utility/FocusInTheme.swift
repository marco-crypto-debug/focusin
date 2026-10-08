import SwiftUI

// ============================================================
// FocusIn 設計語言（TUTTI 風格：暖白底、圓角卡片、分區標籤、淡紅裝飾線）——兩端共用
// ============================================================
enum FocusInTheme {
    /// 畫布暖白
    static let canvas = Color(red: 0.969, green: 0.961, blue: 0.949)
    /// 卡片白
    static let card = Color(red: 1.0, green: 1.0, blue: 1.0)
    /// 卡片描邊
    static let line = Color.black.opacity(0.07)
    /// 品牌強調（淡紅裝飾）
    static let accent = Color(red: 0.82, green: 0.32, blue: 0.30)
    /// 深色主按鈕
    static let dark = Color(red: 0.12, green: 0.12, blue: 0.12)

    /// 分區標籤（TUTTI 風格：小號、寬字距、全大寫感）
    static func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.4)
            .foregroundStyle(.secondary)
    }

    /// 白底圓角卡片
    static func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(line, lineWidth: 1))
    }

    /// 右側淡紅裝飾線
    static var accentBar: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(accent.opacity(0.55))
            .frame(width: 3)
            .padding(.vertical, 10)
    }
}


