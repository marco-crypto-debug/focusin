import AppKit
import ApplicationServices
import SwiftUI

#if FOCUSIN_DELTA

// ============================================================
// FocusIn Delta 學生端 Studio 介面 (Apple Pro Dark UI)
// ============================================================

enum DeltaStudentTab: String, CaseIterable, Identifiable {
    case stream = "廣播接收"
    case security = "安全防護"
    case diagnostics = "系統診斷"
    case about = "關於"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .stream: return "play.desktopcomputer"
        case .security: return "lock.shield"
        case .diagnostics: return "terminal"
        case .about: return "info.circle"
        }
    }
}

struct DeltaStudentStudioView: View {
    @EnvironmentObject var listener: CommandListener
    @ObservedObject private var kiosk = KioskModeController.shared
    @State private var selectedTab: DeltaStudentTab = .stream

    // 密碼設定狀態
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordSaved = false
    @State private var passwordError = ""
    @State private var autoStartError = ""

    // 更新通道
    @State private var updateChannel: String = "正式版 (Stable)"

    // 複製反饋
    @State private var copiedLog = false

    var body: some View {
        ZStack {
            FocusInTheme.studioCanvas.ignoresSafeArea()

            VStack(spacing: 0) {
                topBarView
                Divider().background(FocusInTheme.studioLine)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .stream:
                            streamTabContent
                        case .security:
                            securityTabContent
                        case .diagnostics:
                            diagnosticsTabContent
                        case .about:
                            aboutTabContent
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: 960)
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                Divider().background(FocusInTheme.studioLine)
                footerBarView
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 頂部導航列

    private var topBarView: some View {
        HStack(spacing: 16) {
            // 左側品牌與標題
            HStack(spacing: 12) {
                FocusInLogoView(size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("FocusIn")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(FocusInTheme.studioTextPrimary)

                        Text("DELTA")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.45, blue: 0.55),
                                        Color(red: 0.88, green: 0.25, blue: 0.42),
                                        Color(red: 0.55, green: 0.24, blue: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )

                        Text("學生端")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FocusInTheme.studioTextSecondary)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(listener.connectionCount > 0 ? FocusInTheme.studioGreen : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(listener.deviceName)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(FocusInTheme.studioTextSecondary)
                    }
                }
            }

            Spacer()

            // 中間子分頁切換膠囊
            HStack(spacing: 4) {
                ForEach(DeltaStudentTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab
                                ? Color.white.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .foregroundStyle(
                            selectedTab == tab
                                ? FocusInTheme.studioTextPrimary
                                : FocusInTheme.studioTextSecondary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(FocusInTheme.studioLine, lineWidth: 1)
            )

            Spacer()

            // 右側狀態徽章
            HStack(spacing: 10) {
                // Wi-Fi 膠囊
                HStack(spacing: 5) {
                    Image(systemName: "wifi")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.4, green: 0.75, blue: 1.0))
                    Text(listener.currentWiFiName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FocusInTheme.studioTextPrimary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05), in: Capsule())
                .overlay(Capsule().stroke(FocusInTheme.studioLine, lineWidth: 1))

                // 連線狀態膠囊
                HStack(spacing: 6) {
                    Circle()
                        .fill(listener.connectionCount > 0 ? FocusInTheme.studioGreen : Color.orange)
                        .frame(width: 7, height: 7)
                        .shadow(color: (listener.connectionCount > 0 ? FocusInTheme.studioGreen : Color.orange).opacity(0.6), radius: 3)

                    Text(listener.connectionCount > 0 ? "已連線 (\(listener.connectionCount))" : "等待連線")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(listener.connectionCount > 0 ? FocusInTheme.studioGreen : Color.orange)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background((listener.connectionCount > 0 ? FocusInTheme.studioGreen : Color.orange).opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke((listener.connectionCount > 0 ? FocusInTheme.studioGreen : Color.orange).opacity(0.25), lineWidth: 1))

                // 鎖定狀態
                HStack(spacing: 5) {
                    Image(systemName: listener.isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 10))
                        .foregroundStyle(listener.isLocked ? FocusInTheme.studioRedSoft : FocusInTheme.studioTextSecondary)
                    Text(listener.isLocked ? "鎖定中" : "自由")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(listener.isLocked ? FocusInTheme.studioRedSoft : FocusInTheme.studioTextSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(listener.isLocked ? FocusInTheme.studioRed.opacity(0.12) : Color.white.opacity(0.05), in: Capsule())
                .overlay(Capsule().stroke(listener.isLocked ? FocusInTheme.studioRed.opacity(0.3) : FocusInTheme.studioLine, lineWidth: 1))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(FocusInTheme.studioSidebar)
    }

    // MARK: - 第一頁：廣播接收 (Live Stream & Status)

    private var streamTabContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 主畫面英雄區塊 (Hero Broadcast Viewport)
            VStack(alignment: .leading, spacing: 0) {
                // 卡片標題列
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "display")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.4, green: 0.75, blue: 1.0))
                        Text("課堂實時畫面接收 (STREAM VIEWPORT)")
                            .font(.system(size: 11, weight: .bold))
                            .kerning(1.2)
                            .foregroundStyle(FocusInTheme.studioTextSecondary)
                    }

                    Spacer()

                    if listener.isBroadcasting {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(FocusInTheme.studioRedSoft)
                                .frame(width: 7, height: 7)
                                .shadow(color: FocusInTheme.studioRedSoft.opacity(0.8), radius: 4)
                            Text("LIVE 實時串流中")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(FocusInTheme.studioRedSoft)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(FocusInTheme.studioRed.opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(FocusInTheme.studioRed.opacity(0.35), lineWidth: 1))
                    } else {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.orange.opacity(0.8))
                                .frame(width: 6, height: 6)
                            Text("待命中")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(FocusInTheme.studioTextSecondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.2))

                Divider().background(FocusInTheme.studioLine)

                // 畫面主體
                ZStack {
                    Color(red: 0.05, green: 0.05, blue: 0.07)

                    if listener.isBroadcasting {
                        if let image = kiosk.broadcastImage {
                            VStack(spacing: 0) {
                                Image(nsImage: image)
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .frame(maxHeight: 360)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .padding(14)
                            }
                        } else {
                            VStack(spacing: 14) {
                                ProgressView()
                                    .controlSize(.regular)
                                Text("正在同步教師端影像訊號與關鍵幀 (SPS/PPS)…")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 260)
                        }
                    } else {
                        // 待命雷達與氛圍背景
                        standbyRadarView
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 280)
            }
            .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FocusInTheme.studioLine, lineWidth: 1)
            )

            // 4 大指標卡片 (Telemetry Metrics Grid)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                metricCard(
                    icon: "network",
                    iconColor: Color(red: 0.35, green: 0.78, blue: 0.98),
                    title: "教師端連線",
                    status: listener.connectionCount > 0 ? "已連線 (\(listener.connectionCount))" : "等待教師端…",
                    statusColor: listener.connectionCount > 0 ? FocusInTheme.studioGreen : Color.orange,
                    subtitle: "mDNS Bonjour 廣播搜尋"
                )

                metricCard(
                    icon: "cpu",
                    iconColor: Color(red: 0.55, green: 0.45, blue: 1.0),
                    title: "影像硬體解碼",
                    status: "VideoToolbox 硬解",
                    statusColor: FocusInTheme.studioTextPrimary,
                    subtitle: "Annex-B H.264 · SPS 自愈"
                )

                metricCard(
                    icon: "speaker.wave.3.fill",
                    iconColor: Color(red: 1.0, green: 0.60, blue: 0.25),
                    title: "音訊同步引擎",
                    status: "AVAudioEngine",
                    statusColor: FocusInTheme.studioTextPrimary,
                    subtitle: "240ms Jitter Buffer"
                )

                metricCard(
                    icon: "shield.lefthalf.filled",
                    iconColor: FocusInTheme.studioRedSoft,
                    title: "課堂硬鎖屏",
                    status: listener.isLocked ? "全螢幕鎖定生效" : "自由待命模式",
                    statusColor: listener.isLocked ? FocusInTheme.studioRedSoft : FocusInTheme.studioTextSecondary,
                    subtitle: "CGEventTap .screenSaver"
                )
            }
        }
    }

    /// 待命狀態之雷達氛圍圖形
    private var standbyRadarView: some View {
        VStack(spacing: 16) {
            ZStack {
                // 擴散光圈
                Circle()
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    .frame(width: 170, height: 170)
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.88, green: 0.25, blue: 0.42).opacity(0.18),
                                Color(red: 0.55, green: 0.24, blue: 1.0).opacity(0.06),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 65
                        )
                    )
                    .frame(width: 130, height: 130)

                // 核心圖標
                ZStack {
                    Circle()
                        .fill(FocusInTheme.studioCard)
                        .frame(width: 68, height: 68)
                        .overlay(Circle().stroke(FocusInTheme.studioLineHighlight, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.4), radius: 10, y: 4)

                    Image(systemName: "display.and.arrow.down")
                        .font(.system(size: 26))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.60, blue: 0.69),
                                    Color(red: 0.88, green: 0.25, blue: 0.42)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }

            VStack(spacing: 6) {
                Text("等待教師端發起廣播")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(FocusInTheme.studioTextPrimary)

                Text("當教師開始課堂螢幕廣播時，畫面與聲音將自動在此呈現並同步進入課堂防護模式。")
                    .font(.system(size: 12))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            // 快捷提示膠囊
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    keyBadge("⌘")
                    keyBadge("⇧")
                    keyBadge("U")
                    Text("緊急解鎖 (60s 臨時權限)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04), in: Capsule())
                .overlay(Capsule().stroke(FocusInTheme.studioLine, lineWidth: 1))

                HStack(spacing: 4) {
                    keyBadge("⌘")
                    keyBadge("Q")
                    Text("安全退出 (需管理密碼)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04), in: Capsule())
                .overlay(Capsule().stroke(FocusInTheme.studioLine, lineWidth: 1))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 32)
    }

    private func metricCard(icon: String, iconColor: Color, title: String, status: String, statusColor: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)

                Text(status)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(FocusInTheme.studioTextSecondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FocusInTheme.studioLine, lineWidth: 1)
        )
    }

    // MARK: - 第二頁：安全防護 (Security & Kiosk)

    private var securityTabContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 緊急解鎖專題卡片
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(FocusInTheme.studioRed.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "key.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(FocusInTheme.studioRedSoft)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("緊急解鎖快捷鍵 (EMERGENCY UNLOCK)")
                            .font(.system(size: 11, weight: .bold))
                            .kerning(1.2)
                            .foregroundStyle(FocusInTheme.studioTextSecondary)
                        Text("硬體層級課堂緊急處置機制")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FocusInTheme.studioTextPrimary)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        keyBadge("⌘", size: 26)
                        Text("+").foregroundStyle(FocusInTheme.studioTextSecondary)
                        keyBadge("⇧", size: 26)
                        Text("+").foregroundStyle(FocusInTheme.studioTextSecondary)
                        keyBadge("U", size: 26)
                    }
                }

                Divider().background(FocusInTheme.studioLine)

                Text("在全螢幕鎖屏期間，若遇學生突發狀況或教師端斷開，巡堂教師或管理人員可在學生機按下 ⌘⇧U 快捷鍵呼出緊急解鎖面板。驗證本地管理員密碼後，系統將提供 60 秒臨時解除鎖定，倒數結束後自動恢復課堂管控。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                    .lineSpacing(3)

                HStack(spacing: 8) {
                    Image(systemName: InputInterceptor.shared.isActive ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(InputInterceptor.shared.isActive ? FocusInTheme.studioGreen : Color.yellow)
                    Text(InputInterceptor.shared.isActive
                         ? "CGEventTap 全局輸入攔截器已就緒 (⌘⇧U 監聽中)"
                         : "攔截器待命中（進入鎖屏時自動掛載，需輔助功能權限）")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(FocusInTheme.studioTextPrimary)
                }
                .padding(10)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(18)
            .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FocusInTheme.studioLine, lineWidth: 1)
            )

            // 本地管理員密碼設定
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.4, green: 0.75, blue: 1.0))
                        Text("本地管理員密碼 (ADMIN PASSWORD)")
                            .font(.system(size: 11, weight: .bold))
                            .kerning(1.2)
                            .foregroundStyle(FocusInTheme.studioTextSecondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(KioskConfig.hasAdminPassword ? FocusInTheme.studioGreen : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(KioskConfig.hasAdminPassword ? "已設定密碼 (加鹽雜湊)" : "未設定密碼")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KioskConfig.hasAdminPassword ? FocusInTheme.studioGreen : Color.orange)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background((KioskConfig.hasAdminPassword ? FocusInTheme.studioGreen : Color.orange).opacity(0.12), in: Capsule())
                }

                Text(KioskConfig.hasAdminPassword
                     ? "變更本機管理員密碼。此密碼僅安全儲存於本機鑰匙圈雜湊，用於 ⌘⇧U 緊急解鎖及 ⌘Q 退出保護。"
                     : "尚未設定管理員密碼。建議在電腦教室部署時預先設定，以防止學生私自退出監管或於緊急時無法解鎖。")
                    .font(.system(size: 12))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)

                VStack(spacing: 10) {
                    if KioskConfig.hasAdminPassword {
                        SecureField("目前密碼 (Current Password)", text: $oldPassword)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(FocusInTheme.studioCardHover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))
                    }

                    SecureField("新密碼（至少 4 位）", text: $newPassword)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(FocusInTheme.studioCardHover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))

                    SecureField("確認新密碼", text: $confirmPassword)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(FocusInTheme.studioCardHover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))
                }

                HStack {
                    Button {
                        savePassword()
                    } label: {
                        Text(KioskConfig.hasAdminPassword ? "變更密碼" : "保存密碼")
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(FocusInTheme.studioRedSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    if !passwordError.isEmpty {
                        Text(passwordError)
                            .font(.system(size: 11.5))
                            .foregroundStyle(passwordSaved ? FocusInTheme.studioGreen : FocusInTheme.studioRedSoft)
                            .padding(.leading, 8)
                    }

                    Spacer()
                }
            }
            .padding(18)
            .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FocusInTheme.studioLine, lineWidth: 1)
            )

            // 退出保護說明卡片
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(FocusInTheme.studioRedSoft)
                    Text("退出保護機制 (QUIT GUARD)")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                }

                Text("FocusIn 學生端攔截了系統級終止事件（含 Dock 點擊退出、⌘Q 及關閉視窗）。若未驗證管理員密碼，程序將拒絕退出，以確保課堂全程受到防護。")
                    .font(.system(size: 12))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                    .lineSpacing(2)
            }
            .padding(16)
            .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FocusInTheme.studioLine, lineWidth: 1)
            )
        }
    }

    // MARK: - 第三頁：系統診斷 (System & Diagnostics Console)

    private var diagnosticsTabContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 系統偏好卡片
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.4, green: 0.75, blue: 1.0))
                    Text("系統設定與權限 (PREFERENCES & PERMISSIONS)")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                }

                VStack(spacing: 12) {
                    // 開機自動啟動
                    Toggle(isOn: Binding(
                        get: { LoginStartManager.isEnabled },
                        set: { on in
                            autoStartError = ""
                            do {
                                if on { try LoginStartManager.enable() }
                                else { LoginStartManager.disable() }
                            } catch {
                                autoStartError = "自動啟動設定失敗：\(error.localizedDescription)"
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("登入時自動啟動 FocusIn 學生端")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(FocusInTheme.studioTextPrimary)
                            Text("開機登入後自動在背景啟動並監聽教師端廣播指令")
                                .font(.system(size: 11))
                                .foregroundStyle(FocusInTheme.studioTextSecondary)
                        }
                    }
                    .toggleStyle(.switch)

                    if !autoStartError.isEmpty {
                        Text(autoStartError).font(.system(size: 11)).foregroundStyle(.red)
                    }

                    Divider().background(FocusInTheme.studioLine)

                    // 輔助功能權限
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("macOS 輔助功能權限 (Accessibility)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(FocusInTheme.studioTextPrimary)
                                if AXIsProcessTrusted() {
                                    Text("已授權")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(FocusInTheme.studioGreen)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(FocusInTheme.studioGreen.opacity(0.15), in: Capsule())
                                } else {
                                    Text("未授權")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.yellow)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow.opacity(0.15), in: Capsule())
                                }
                            }
                            Text("鎖屏全域鍵盤攔截與 ⌘⇧U 緊急解鎖必須依賴輔助功能權限")
                                .font(.system(size: 11))
                                .foregroundStyle(FocusInTheme.studioTextSecondary)
                        }

                        Spacer()

                        if !AXIsProcessTrusted() {
                            Button("前往授權 ↗") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(18)
            .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FocusInTheme.studioLine, lineWidth: 1)
            )

            // 網路與端點資訊卡
            HStack(spacing: 14) {
                infoBlock(title: "本機主機名稱", value: listener.deviceName, icon: "desktopcomputer")
                infoBlock(title: "目前 Wi-Fi", value: listener.currentWiFiName, icon: "wifi")
                infoBlock(title: "區域網路 IP", value: listener.localIP, icon: "network")
                infoBlock(title: "通訊協議", value: "WebSocket / H.264", icon: "bolt.fill")
            }

            // 即時診斷終端機 (Diagnostic Console)
            VStack(alignment: .leading, spacing: 0) {
                // 終端頂部工具列
                HStack {
                    HStack(spacing: 8) {
                        Circle().fill(FocusInTheme.studioGreen).frame(width: 8, height: 8)
                        Text("focusin-student-diag.log")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(FocusInTheme.studioTextPrimary)
                        Text("(\(listener.log.count) 條記錄)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(FocusInTheme.studioTextSecondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            let text = listener.log.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            copiedLog = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedLog = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedLog ? "checkmark" : "doc.on.doc")
                                Text(copiedLog ? "已複製" : "複製全部")
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)

                        Button {
                            listener.clearLog()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("清空")
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.4))

                Divider().background(FocusInTheme.studioLine)

                // 終端日誌滾動區域
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 4) {
                            if listener.log.isEmpty {
                                Text("// 尚無診斷記錄，系統正常監聽中…")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(FocusInTheme.studioTextSecondary.opacity(0.6))
                                    .padding(12)
                            } else {
                                ForEach(Array(listener.log.enumerated()), id: \.offset) { idx, line in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(String(format: "%03d", idx + 1))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Color.white.opacity(0.25))
                                            .frame(width: 28, alignment: .trailing)

                                        Text(line)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(logColor(for: line))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .id(idx)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .frame(maxHeight: 180)
                    .onChange(of: listener.log.count) { _ in
                        if let last = listener.log.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FocusInTheme.studioLine, lineWidth: 1)
            )
        }
    }

    private func infoBlock(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
            }
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(FocusInTheme.studioTextPrimary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))
    }

    private func logColor(for line: String) -> Color {
        if line.contains("失敗") || line.contains("錯誤") || line.contains("中斷") {
            return FocusInTheme.studioRedSoft
        } else if line.contains("已連線") || line.contains("握手") || line.contains("成功") {
            return FocusInTheme.studioGreen
        } else if line.contains("廣播") || line.contains("指令") || line.contains("鎖定") {
            return Color(red: 0.4, green: 0.75, blue: 1.0)
        }
        return FocusInTheme.studioTextSecondary
    }

    // MARK: - 第四頁：關於 FocusIn (About Dashboard)

    private var aboutTabContent: some View {
        VStack(spacing: 24) {
            // App Logo 與版本標題
            VStack(spacing: 14) {
                FocusInLogoView(size: 86)

                VStack(spacing: 4) {
                    Text("FocusIn 學生端")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(FocusInTheme.studioTextPrimary)

                    Text("v1.5.10-delta · Native macOS Classroom Receiver")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                }
            }
            .padding(.top, 10)

            // 4 大資訊卡片 (Author, GitHub, Security, Platform)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                aboutCard(
                    icon: "person.fill",
                    title: "作者",
                    actionText: "Marco",
                    actionURL: nil
                )

                aboutCard(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "開源地址",
                    actionText: "檢視程式碼 ↗",
                    actionURL: URL(string: "https://github.com/marco-crypto-debug/FocusIn")
                )

                aboutCard(
                    icon: "shield.checkered",
                    title: "安全架構",
                    actionText: "零依賴 / 離線 Ed25519",
                    actionURL: nil
                )

                aboutCard(
                    icon: "laptopcomputer",
                    title: "系統環境",
                    actionText: "macOS 14+ 原生",
                    actionURL: nil
                )
            }

            // 技術棧 Pills
            VStack(spacing: 8) {
                Text("底層核心架構")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(FocusInTheme.studioTextSecondary)

                HStack(spacing: 8) {
                    techPill("Swift 5")
                    techPill("SwiftUI")
                    techPill("VideoToolbox")
                    techPill("AVAudioEngine")
                    techPill("Network.framework")
                }
            }
            .padding(.vertical, 4)

            // 更新通道與手動檢查
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // 通道選擇器
                    HStack(spacing: 0) {
                        channelButton(title: "正式版 (Stable)", isSelected: updateChannel.contains("Stable")) {
                            updateChannel = "正式版 (Stable)"
                        }
                        channelButton(title: "預覽版 (Beta) ◆", isSelected: updateChannel.contains("Beta")) {
                            updateChannel = "預覽版 (Beta) ◆"
                        }
                    }
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))

                    // 檢查更新按鈕
                    Button {
                        listener.checkForUpdatesManually()
                    } label: {
                        HStack(spacing: 6) {
                            if listener.isCheckingUpdate {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text(listener.isCheckingUpdate ? "檢查中…" : "檢查更新")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.50, blue: 0.98),
                                    Color(red: 0.10, green: 0.38, blue: 0.88)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(listener.isCheckingUpdate)
                }

                // 更新檢查文字回饋
                if let status = listener.updateCheckStatusText {
                    Text(status)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(
                            status.contains("發現") ? FocusInTheme.studioGreen : FocusInTheme.studioTextSecondary
                        )
                }
            }

            // 版權宣告
            Text("Copyright © 2025-2026 FocusIn. All rights reserved.")
                .font(.system(size: 11))
                .foregroundStyle(FocusInTheme.studioTextSecondary.opacity(0.7))
                .padding(.top, 8)
        }
        .frame(maxWidth: 580)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func aboutCard(icon: String, title: String, actionText: String, actionURL: URL?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FocusInTheme.studioTextPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)

                if let url = actionURL {
                    Link(destination: url) {
                        Text(actionText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.4, green: 0.75, blue: 1.0))
                    }
                } else {
                    Text(actionText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FocusInTheme.studioTextPrimary)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(FocusInTheme.studioLine, lineWidth: 1)
        )
    }

    private func techPill(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(FocusInTheme.studioTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().stroke(FocusInTheme.studioLine, lineWidth: 1))
    }

    private func channelButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? FocusInTheme.studioTextPrimary : FocusInTheme.studioTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.white.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部狀態欄

    private var footerBarView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "shield.checkerboard")
                    .font(.system(size: 11))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                Text("FocusIn Delta Kiosk · 守護課堂專注")
                    .font(.system(size: 11))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Text("⌘⇧U: 緊急解鎖")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)

                Text("•")
                    .foregroundStyle(FocusInTheme.studioTextSecondary.opacity(0.4))

                Text("⌘Q: 退出保護")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(FocusInTheme.studioSidebar)
    }

    // MARK: - 輔助工具

    private func keyBadge(_ key: String, size: CGFloat = 20) -> some View {
        Text(key)
            .font(.system(size: size * 0.55, weight: .semibold, design: .monospaced))
            .foregroundStyle(FocusInTheme.studioTextPrimary)
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
            )
    }

    private func savePassword() {
        passwordError = ""
        passwordSaved = false
        guard newPassword.count >= 4 else {
            passwordError = "密碼至少 4 位"
            return
        }
        guard newPassword == confirmPassword else {
            passwordError = "兩次輸入的密碼不一致"
            return
        }
        do {
            try KioskConfig.setAdminPassword(
                newPassword,
                oldPassword: KioskConfig.hasAdminPassword ? oldPassword : nil
            )
            passwordSaved = true
            passwordError = KioskConfig.hasAdminPassword
                ? "✓ 密碼已變更（雜湊儲存，僅用於本地緊急解鎖）"
                : "✓ 密碼已保存（雜湊儲存，僅用於本地緊急解鎖）"
            oldPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch KioskConfig.KioskError.oldPasswordMismatch {
            passwordError = "目前密碼不正確，無法變更"
            oldPassword = ""
        } catch {
            passwordError = "保存失敗: \(error.localizedDescription)"
        }
    }
}

#endif
