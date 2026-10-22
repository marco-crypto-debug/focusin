import SwiftUI

// ============================================================
// FocusIn 設計語言——兩端共用
//  stable/alpha：TUTTI 風格（暖白底、淡紅裝飾）
//  beta：MoodLab 風格（Apple 灰底、主紅 #D71920、深色 #171717）
// ============================================================
enum FocusInTheme {
    /// 畫布底色
    static let canvas: Color = {
#if FOCUSIN_BETA
        return Color(red: 0.965, green: 0.965, blue: 0.969)      // #F6F6F7 MoodLab Apple 灰
#else
        return Color(red: 0.969, green: 0.961, blue: 0.949)      // 暖白
#endif
    }()
    /// 卡片白
    static let card = Color(red: 1.0, green: 1.0, blue: 1.0)
    /// 卡片描邊
    static let line: Color = {
#if FOCUSIN_BETA
        return Color.black.opacity(0.09)
#else
        return Color.black.opacity(0.07)
#endif
    }()
    /// 品牌強調（beta 用 MoodLab 主紅 #D71920）
    static let accent: Color = {
#if FOCUSIN_BETA
        return Color(red: 0.843, green: 0.098, blue: 0.125)      // #D71920
#else
        return Color(red: 0.82, green: 0.32, blue: 0.30)
#endif
    }()
    /// 深色主按鈕（beta 用 #171717）
    static let dark: Color = {
#if FOCUSIN_BETA
        return Color(red: 0.09, green: 0.09, blue: 0.09)         // #171717
#else
        return Color(red: 0.12, green: 0.12, blue: 0.12)
#endif
    }()

    /// 卡片圓角（beta 用 14pt 大圓角）
    static var cornerRadius: CGFloat = {
#if FOCUSIN_BETA
        return 14
#else
        return 12
#endif
    }()

    /// 分區標籤（小號、寬字距、全大寫感）
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
            .background(card, in: RoundedRectangle(cornerRadius: FocusInTheme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FocusInTheme.cornerRadius, style: .continuous).stroke(line, lineWidth: 1))
    }

    /// 右側淡紅裝飾線
    static var accentBar: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(accent.opacity(0.55))
            .frame(width: 3)
            .padding(.vertical, 10)
    }
}


