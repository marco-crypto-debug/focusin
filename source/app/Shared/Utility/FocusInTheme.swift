import SwiftUI

// ============================================================
// FocusIn 設計語言——兩端共用
//  stable/alpha：TUTTI 風格（暖白底、淡紅裝飾）
//  beta：MoodLab 風格（Apple 灰底、主紅 #D71920、深色 #171717）
// ============================================================
enum FocusInTheme {
    /// 畫布底色（Apple Pro Dark Studio 畫布底色）
    static let canvas: Color = studioCanvas
    /// 卡片底色（深色 Studio 卡片）
    static let card: Color = studioCard
    /// 卡片描邊
    static let line: Color = studioLine
    /// 品牌強調（FocusIn 主紅 #D71920）
    static let accent: Color = studioRed
    /// 深色主按鈕（#171717）
    static let dark: Color = Color(red: 0.09, green: 0.09, blue: 0.09)

    /// 卡片圓角（14pt 大圓角）
    static var cornerRadius: CGFloat = 14

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

    static let isDelta = true
    static let studioCanvas = Color(red: 0.067, green: 0.067, blue: 0.082)     // #111115
    static let studioSidebar = Color(red: 0.047, green: 0.047, blue: 0.059)    // #0C0C0F
    static let studioCard = Color(red: 0.094, green: 0.094, blue: 0.110)       // #18181C
    static let studioCardHover = Color(red: 0.125, green: 0.125, blue: 0.145)
    static let studioLine = Color.white.opacity(0.08)
    static let studioLineHighlight = Color.white.opacity(0.16)
    static let studioRed = Color(red: 0.843, green: 0.098, blue: 0.125)        // #D71920
    static let studioRedSoft = Color(red: 1.0, green: 0.231, blue: 0.271)      // #FF3B45
    static let studioGreen = Color(red: 0.204, green: 0.780, blue: 0.349)      // #34C759
    static let studioTextPrimary = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let studioTextSecondary = Color(red: 0.55, green: 0.55, blue: 0.60)
}

/// FocusIn 向量 Squircle 應用圖標（全端共用）
struct FocusInLogoView: View {
    var size: CGFloat = 86

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.60, blue: 0.69),
                            Color(red: 0.88, green: 0.25, blue: 0.42),
                            Color(red: 0.55, green: 0.24, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
                )
                .shadow(color: Color(red: 0.88, green: 0.25, blue: 0.42).opacity(0.35), radius: size * 0.16, x: 0, y: size * 0.08)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { p in
                    p.move(to: CGPoint(x: w * 0.35, y: h * 0.72))
                    p.addLine(to: CGPoint(x: w * 0.35, y: h * 0.32))
                    p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.32))
                    p.move(to: CGPoint(x: w * 0.35, y: h * 0.51))
                    p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.51))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: w * 0.085, lineCap: .round, lineJoin: .round))

                Circle()
                    .fill(Color.white)
                    .frame(width: w * 0.09, height: w * 0.09)
                    .position(x: w * 0.72, y: h * 0.32)
            }
        }
        .frame(width: size, height: size)
    }
}



