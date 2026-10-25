import AppKit
import SwiftUI

#if FOCUSIN_DELTA

// ============================================================
// FocusIn Delta Studio — 旗艦暗黑專業控制台 (Apple Pro Studio UI)
// ============================================================

enum DeltaStudioTab: String, CaseIterable, Identifiable {
    case studio = "Studio 控制台"
    case tools = "課堂工具"
    case settings = "進階設定"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .studio: return "play.desktopcomputer"
        case .tools: return "wrench.and.screwdriver.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

enum SettingsSubTab: String, CaseIterable, Identifiable {
    case general = "通用"
    case transport = "傳輸模式"
    case security = "管理密碼"
    case probe = "組播探測"
    case about = "關於"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .transport: return "network"
        case .security: return "lock.shield"
        case .probe: return "waveform.path.ecg"
        case .about: return "info.circle"
        }
    }
}

/// FocusIn 向量 Squircle 應用圖標
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

struct DeltaStudioView: View {
    @EnvironmentObject var viewModel: TeacherViewModel
    @State private var selectedTab: DeltaStudioTab = .studio
    @State private var settingsSubTab: SettingsSubTab = .about
    @State private var updateChannel: String = "正式版 (Stable)"
    @State private var showSaveSuccess: Bool = false
    @State private var allSelected: Bool = false
    @State private var brightness: Double = 1.0
    @State private var launchBundleID: String = "com.apple.Safari"
    @State private var showingWipeConfirm: Bool = false
    @State private var wipeConfirmText: String = ""
    @State private var showingShutdownAlert: Bool = false
    @State private var showingRestartAlert: Bool = false
    @State private var oldQuitPass: String = ""
    @State private var newQuitPass: String = ""
    @State private var quitPassError: String = ""
    @State private var autoStartError: String = ""
    @State private var limitMsg: String = ""

    // Multicast probe states
    @State private var probeRateText: String = "2"
    @State private var probeMaxRateText: String = "16"
    @State private var probeStageText: String = "8"

    var body: some View {
        HSplitView {
            sidebarView
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
            mainContentView
                .frame(minWidth: 700, idealWidth: 840)
        }
        .background(FocusInTheme.studioCanvas)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingWipeConfirm) {
            WipeConfirmSheet(
                confirmText: $wipeConfirmText,
                onConfirm: {
                    viewModel.sendDeleteAllFiles()
                    wipeConfirmText = ""
                    showingWipeConfirm = false
                },
                onCancel: {
                    wipeConfirmText = ""
                    showingWipeConfirm = false
                }
            )
        }
        .alert("確認遠端關機", isPresented: $showingShutdownAlert) {
            Button("取消", role: .cancel) {}
            Button("關機", role: .destructive) { viewModel.sendShutdown() }
        } message: {
            Text("確定要將所有勾選的學生機遠端關機嗎？")
        }
        .alert("確認遠端重新啟動", isPresented: $showingRestartAlert) {
            Button("取消", role: .cancel) {}
            Button("重新啟動", role: .destructive) { viewModel.sendRestart() }
        } message: {
            Text("確定要將所有勾選的學生機遠端重新啟動嗎？")
        }
    }

    // MARK: - 左側側邊欄 (Sidebar)

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // 頂部課室標題
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(viewModel.currentWiFiName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FocusInTheme.studioTextPrimary)
                        .lineLimit(1)
                    Spacer()
                    // 在線人數膠囊
                    HStack(spacing: 5) {
                        Circle()
                            .fill(FocusInTheme.studioGreen)
                            .frame(width: 6, height: 6)
                        Text("+\(viewModel.peers.count) online")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FocusInTheme.studioGreen)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FocusInTheme.studioGreen.opacity(0.12), in: Capsule())
                }

                if !limitMsg.isEmpty {
                    Text(limitMsg)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }

                // 全選控制列
                HStack {
                    Button {
                        allSelected.toggle()
                        if allSelected {
                            if let msg = DeviceLimit.check(count: viewModel.peers.count) {
                                limitMsg = msg
                                allSelected = false
                                return
                            }
                        }
                        for i in viewModel.peers.indices {
                            viewModel.peers[i].isSelected = allSelected
                        }
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(allSelected ? FocusInTheme.studioRed : Color.white.opacity(0.25), lineWidth: 1.5)
                                    .frame(width: 16, height: 16)
                                if allSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(FocusInTheme.studioRed)
                                }
                            }
                            Text("All students")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(FocusInTheme.studioTextPrimary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    Text("\(viewModel.selectedIDs.count) selected")
                        .font(.system(size: 11))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                }
                .padding(.vertical, 6)
            }
            .padding(14)
            .background(FocusInTheme.studioSidebar)

            Divider().background(FocusInTheme.studioLine)

            // 學生端列表
            ScrollView {
                LazyVStack(spacing: 4) {
                    if viewModel.peers.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 28))
                                .foregroundStyle(FocusInTheme.studioTextSecondary.opacity(0.6))
                            Text("正在搜索學生端...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(FocusInTheme.studioTextSecondary)
                            Text("請確保學生端與教師機連接同一 Wi-Fi")
                                .font(.caption)
                                .foregroundStyle(FocusInTheme.studioTextSecondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        .padding(.horizontal, 16)
                    } else {
                        ForEach($viewModel.peers) { $peer in
                            studentRow(peer: $peer)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
            .background(FocusInTheme.studioSidebar)

            Divider().background(FocusInTheme.studioLine)

            // 底部 Bonjour 狀態指示
            HStack(spacing: 6) {
                Circle()
                    .fill(FocusInTheme.studioGreen)
                    .frame(width: 7, height: 7)
                    .shadow(color: FocusInTheme.studioGreen.opacity(0.6), radius: 3)
                Text("Bonjour discovery active")
                    .font(.system(size: 10.5))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(FocusInTheme.studioSidebar)
        }
    }

    private func studentRow(peer: Binding<StudentPeer>) -> some View {
        let isSelected = peer.wrappedValue.isSelected
        let ms = viewModel.latencies[peer.wrappedValue.id]

        return HStack(spacing: 10) {
            // Checkbox
            Button {
                peer.wrappedValue.isSelected.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? FocusInTheme.studioRed : Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 15, height: 15)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(FocusInTheme.studioRed)
                    }
                }
            }
            .buttonStyle(.plain)

            // 裝置小圖示
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 28, height: 28)
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 13))
                    .foregroundStyle(FocusInTheme.studioRedSoft)
            }

            // 名稱與連線狀態
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.wrappedValue.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(FocusInTheme.studioTextPrimary)
                    .lineLimit(1)
                Text("Online")
                    .font(.system(size: 10))
                    .foregroundStyle(FocusInTheme.studioGreen.opacity(0.85))
            }

            Spacer()

            // 延遲
            if let ms = ms {
                Text("\(ms) ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ms > 60 ? .orange : FocusInTheme.studioTextSecondary)
            }

            // 鎖定狀態圖示
            if viewModel.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(FocusInTheme.studioRed)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? FocusInTheme.studioCardHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            peer.wrappedValue.isSelected.toggle()
        }
    }

    // MARK: - 主工作區 (Main Content View)

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // 頂部頂級控制列 (Top Bar)
            topBarView
            Divider().background(FocusInTheme.studioLine)

            // 依分頁切換工作區內容
            ScrollView {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .studio:
                        studioTabContent
                    case .tools:
                        toolsTabContent
                    case .settings:
                        settingsTabContent
                    }
                }
                .padding(18)
            }
            .background(FocusInTheme.studioCanvas)
        }
    }

    // MARK: - 頂部控制列 (Top Bar)

    private var topBarView: some View {
        HStack(spacing: 16) {
            // 畫質控制 (Quality)
            HStack(spacing: 8) {
                Text("QUALITY")
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                Picker("", selection: $viewModel.broadcastQuality) {
                    ForEach(BroadcastQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            // 多顯示器切換（若有兩個以上螢幕）
            if viewModel.availableDisplays.count > 1 {
                HStack(spacing: 6) {
                    Text("DISPLAY")
                        .font(.system(size: 10.5, weight: .bold))
                        .kerning(1.0)
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                    Picker("", selection: Binding(
                        get: { viewModel.selectedDisplayIndex },
                        set: { viewModel.selectDisplay(at: $0) }
                    )) {
                        ForEach(viewModel.availableDisplays.indices, id: \.self) { idx in
                            Text(viewModel.availableDisplays[idx].displayTitle).tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }
            }

            Spacer()

            // 模式分頁按鈕
            Picker("", selection: $selectedTab) {
                ForEach(DeltaStudioTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 310)

            Spacer()

            // 即時指標 (Telemetry Metrics)
            HStack(spacing: 14) {
                metricItem(label: "LATENCY", value: "\(viewModel.averageLatency) ms")
                metricItem(label: "FPS", value: "30")
                metricItem(label: "BITRATE", value: "Adaptive")
            }

            Divider()
                .frame(height: 16)
                .background(FocusInTheme.studioLine)

            // 頂部輔助工具列 (全螢幕、主題、語系)
            HStack(spacing: 8) {
                Button {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                        .padding(5)
                        .background(Color.white.opacity(0.04), in: Circle())
                }
                .buttonStyle(.plain)
                .help("切換全螢幕")

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                    .padding(5)
                    .background(Color.white.opacity(0.04), in: Circle())

                Text("TW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(FocusInTheme.studioSidebar)
    }

    private func metricItem(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(FocusInTheme.studioTextSecondary)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(FocusInTheme.studioTextPrimary)
        }
    }

    // MARK: - 分頁 1：Studio 控制台內容

    private var studioTabContent: some View {
        VStack(spacing: 16) {
            // 上半部：螢幕預覽卡片 + 右側狀態資訊卡
            HStack(alignment: .top, spacing: 16) {
                // 主預覽卡片
                screenPreviewCard
                    .frame(maxWidth: .infinity)

                // 右側三聯狀態統計卡片
                VStack(spacing: 12) {
                    statCardConnected
                    statCardLatency
                    statCardStream
                }
                .frame(width: 220)
            }

            // 中部：學生端螢幕網格 (Students Grid)
            studentGridView

            // 下半部：活動日誌 (Activity Console)
            activityLogView
        }
    }

    // MARK: - 主螢幕預覽卡片

    private var screenPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 標題與 LIVE 標記
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.broadcastActive
                              ? FocusInTheme.studioRedSoft
                              : (viewModel.hasScreenRecordingPermission ? FocusInTheme.studioGreen : .orange))
                        .frame(width: 7, height: 7)
                    Text("Screen preview")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(FocusInTheme.studioTextPrimary)
                }
                Spacer()
                if viewModel.broadcastActive {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(FocusInTheme.studioRedSoft)
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.system(size: 9.5, weight: .bold))
                            .kerning(0.8)
                            .foregroundStyle(FocusInTheme.studioRedSoft)
                        Text(formatDuration(viewModel.broadcastDuration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(FocusInTheme.studioTextPrimary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(FocusInTheme.studioRed.opacity(0.18), in: Capsule())
                } else if viewModel.hasScreenRecordingPermission {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(FocusInTheme.studioGreen)
                            .frame(width: 5, height: 5)
                        Text("Real-time preview")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FocusInTheme.studioGreen)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(FocusInTheme.studioGreen.opacity(0.12), in: Capsule())
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("Permission needed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                }
            }

            // 16:9 畫面預覽視窗
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.045, green: 0.045, blue: 0.055))
                    .aspectRatio(16/9, contentMode: .fit)

                if !viewModel.hasScreenRecordingPermission {
                    permissionRequestView
                } else if let img = viewModel.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                } else {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在載入即時桌面預覽...")
                            .font(.system(size: 11.5))
                            .foregroundStyle(FocusInTheme.studioTextSecondary)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(FocusInTheme.studioLine, lineWidth: 1)
            )

            // 快捷控制按鈕列
            HStack(spacing: 10) {
                // 廣播按鈕
                Button {
                    viewModel.toggleBroadcast()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.broadcastActive ? "stop.fill" : "play.fill")
                            .font(.system(size: 11))
                        Text(viewModel.broadcastActive ? "Stop broadcast" : "Start broadcast")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        viewModel.broadcastActive
                            ? FocusInTheme.studioRed
                            : Color.white.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // 鎖定屏幕按鈕
                Button {
                    viewModel.toggleLock()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isLocked ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: 11))
                        Text(viewModel.isLocked ? "Unlock screens" : "Lock screens")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .foregroundStyle(viewModel.isLocked ? FocusInTheme.studioRedSoft : FocusInTheme.studioTextPrimary)
                }
                .buttonStyle(.plain)

                // 聲音廣播切換按鈕
                Button {
                    viewModel.broadcastWithAudio.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.broadcastWithAudio ? "waveform" : "waveform.slash")
                            .font(.system(size: 11))
                        Text("Audio")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        viewModel.broadcastWithAudio
                            ? FocusInTheme.studioRed.opacity(0.2)
                            : Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(viewModel.broadcastWithAudio ? FocusInTheme.studioRed.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                    .foregroundStyle(viewModel.broadcastWithAudio ? FocusInTheme.studioRedSoft : FocusInTheme.studioTextSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // 狀態小提示
                Text(viewModel.broadcastActive
                     ? "Broadcasting to \(viewModel.selectedIDs.count) Macs • \(viewModel.isLocked ? viewModel.selectedIDs.count : 0) locked"
                     : "Ready to broadcast to \(viewModel.selectedIDs.count) Macs")
                    .font(.system(size: 11))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
            }
        }
        .padding(14)
        .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))
    }

    // 螢幕錄製權限請求視圖
    private var permissionRequestView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 4) {
                Text("需要「螢幕錄製」權限")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FocusInTheme.studioTextPrimary)
                Text("macOS 需要您授予螢幕錄製權限，FocusIn 才能即時預覽並廣播桌面。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.requestScreenRecordingPermission()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                        Text("前往「系統設定」開啟權限")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(FocusInTheme.studioRed, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.checkScreenRecordingPermission()
                    Task { await viewModel.captureStandbyPreview() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("重新檢測")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    // MARK: - 右側三聯狀態統計卡片

    private var statCardConnected: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONNECTED")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(FocusInTheme.studioTextSecondary)
            Text("\(viewModel.peers.count)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(FocusInTheme.studioTextPrimary)
            Text("Macs on this network")
                .font(.system(size: 10.5))
                .foregroundStyle(FocusInTheme.studioTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))
    }

    private var statCardLatency: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AVERAGE LATENCY")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(FocusInTheme.studioTextSecondary)
            Text("\(viewModel.averageLatency) ms")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(FocusInTheme.studioTextPrimary)

            // Sparkline 即時折線圖
            SparklineView(data: viewModel.latencyHistory)
                .frame(height: 36)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))
    }

    private var statCardStream: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STREAM")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(FocusInTheme.studioTextSecondary)

            VStack(spacing: 5) {
                streamRow(label: "Resolution", value: "Native (30fps)")
                streamRow(label: "Transport", value: DeviceLimit.transportMode.label)
                streamRow(label: "Network", value: viewModel.currentWiFiName)
                streamRow(label: "Clock", value: "AirPlay 2 PTS")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))
    }

    private func streamRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(FocusInTheme.studioTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FocusInTheme.studioTextPrimary)
        }
    }

    // MARK: - 學生螢幕縮圖網格 (Students Grid)

    private var studentGridView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STUDENTS")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                Spacer()
                Text("Click a screen to toggle selection")
                    .font(.system(size: 10.5))
                    .foregroundStyle(FocusInTheme.studioTextSecondary.opacity(0.8))
            }

            if viewModel.peers.isEmpty {
                HStack {
                    Spacer()
                    Text("尚未發現學生機端")
                        .font(.system(size: 12))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                        .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach($viewModel.peers) { $peer in
                            StudentCardItemView(
                                peer: $peer,
                                isLocked: viewModel.isLocked,
                                broadcastActive: viewModel.broadcastActive,
                                previewImage: viewModel.previewImage,
                                latency: viewModel.latencies[peer.id] ?? 0
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))
    }

    // MARK: - 活動日誌 (Activity Console)

    private var activityLogView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACTIVITY")
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                Spacer()
                Button("清空記錄") {
                    viewModel.log.removeAll()
                }
                .font(.system(size: 10))
                .controlSize(.mini)
                .foregroundStyle(FocusInTheme.studioTextSecondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.log.suffix(40).reversed(), id: \.self) { line in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(logDotColor(for: line))
                                .frame(width: 5, height: 5)
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(FocusInTheme.studioTextSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 100)
        }
        .padding(12)
        .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))
    }

    private func logDotColor(for line: String) -> Color {
        if line.contains("鎖定") || line.contains("Lock") {
            return FocusInTheme.studioRedSoft
        } else if line.contains("廣播") || line.contains("Broadcast") {
            return FocusInTheme.studioGreen
        } else if line.contains("聲音") || line.contains("Audio") {
            return Color.blue
        } else if line.contains("重連") || line.contains("Reconnecting") {
            return Color.orange
        } else {
            return Color.secondary
        }
    }

    // MARK: - 分頁 2：課堂工具內容 (Tools Content)

    private var toolsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 學生端亮度調節
            toolSectionCard(title: "SCREEN BRIGHTNESS", icon: "sun.max.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("調節已選學生屏幕亮度")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(FocusInTheme.studioTextPrimary)
                        Spacer()
                        Text("\(Int(brightness * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(FocusInTheme.studioRedSoft)
                    }

                    Slider(value: $brightness, in: 0.1...1.0) { editing in
                        if !editing {
                            viewModel.sendBrightness(brightness)
                        }
                    }

                    HStack(spacing: 8) {
                        presetBrightnessButton("100%", value: 1.0)
                        presetBrightnessButton("75%", value: 0.75)
                        presetBrightnessButton("50%", value: 0.50)
                        presetBrightnessButton("25%", value: 0.25)
                    }
                }
            }

            // 啟動應用
            toolSectionCard(title: "LAUNCH APPLICATION", icon: "arrow.up.circle.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("向已選學生機遠端開啟應用程式 (Bundle ID)")
                        .font(.system(size: 12))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)

                    HStack(spacing: 8) {
                        TextField("如 com.apple.Safari", text: $launchBundleID)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(FocusInTheme.studioTextPrimary)

                        Button {
                            viewModel.sendLaunchApp(bundleID: launchBundleID)
                        } label: {
                            Text("推送開啟")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(FocusInTheme.studioRed, in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    // 常用預設應用程式捷徑
                    HStack(spacing: 8) {
                        quickAppPill("Safari", bundle: "com.apple.Safari")
                        quickAppPill("Keynote", bundle: "com.apple.iWork.Keynote")
                        quickAppPill("Pages", bundle: "com.apple.iWork.Pages")
                        quickAppPill("VS Code", bundle: "com.microsoft.VSCode")
                        quickAppPill("Terminal", bundle: "com.apple.Terminal")
                    }
                }
            }

            // 遠端電源控制
            toolSectionCard(title: "REMOTE POWER", icon: "power") {
                HStack(spacing: 12) {
                    Button {
                        showingShutdownAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "power")
                            Text("遠端關機")
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3)))
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingRestartAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("遠端重新啟動")
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.3)))
                        .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 清空文件
            toolSectionCard(title: "WIPE STUDENT FILES", icon: "trash.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("清除所選學生機的「文件 (Documents)」與「下載 (Downloads)」資料夾。需二次驗證輸入 DELETE。")
                        .font(.system(size: 12))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)

                    Button {
                        showingWipeConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                            Text("清空學生端文件目錄")
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.red.opacity(0.35)))
                        .foregroundStyle(FocusInTheme.studioRedSoft)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func presetBrightnessButton(_ label: String, value: Double) -> some View {
        Button(label) {
            brightness = value
            viewModel.sendBrightness(value)
        }
        .font(.system(size: 11))
        .controlSize(.small)
    }

    private func quickAppPill(_ name: String, bundle: String) -> some View {
        Button {
            launchBundleID = bundle
            viewModel.sendLaunchApp(bundleID: bundle)
        } label: {
            Text(name)
                .font(.system(size: 10.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(FocusInTheme.studioTextSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 分頁 3：進階設定內容 (Settings Content)

    private var settingsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 次導航列 (Sub-navigation Pills + 儲存設定按鈕)
            HStack {
                HStack(spacing: 6) {
                    ForEach(SettingsSubTab.allCases) { sub in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                settingsSubTab = sub
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: sub.icon)
                                    .font(.system(size: 11))
                                Text(sub.rawValue)
                                    .font(.system(size: 12, weight: settingsSubTab == sub ? .semibold : .regular))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                settingsSubTab == sub
                                    ? Color.white.opacity(0.14)
                                    : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .foregroundStyle(
                                settingsSubTab == sub
                                    ? FocusInTheme.studioTextPrimary
                                    : FocusInTheme.studioTextSecondary
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // 儲存設定按鈕 (Matching screenshot's blue Save button)
                Button {
                    showSaveSuccess = true
                    viewModel.appendLog("設定已成功儲存")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        showSaveSuccess = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showSaveSuccess ? "checkmark" : "square.and.arrow.down.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(showSaveSuccess ? "已儲存" : "儲存設定")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        showSaveSuccess ? FocusInTheme.studioGreen : Color(red: 0.14, green: 0.44, blue: 0.98),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)

            // 依子分頁呈現不同內容
            switch settingsSubTab {
            case .about:
                aboutCardView
                    .frame(maxWidth: .infinity, alignment: .center)
            case .general:
                generalSettingsSection
            case .transport:
                transportSettingsSection
            case .security:
                securitySettingsSection
            case .probe:
                probeSettingsSection
            }
        }
    }

    // MARK: - 關於 FocusIn 卡片 (About Card - Matching User Mockup)

    private var aboutCardView: some View {
        VStack(spacing: 22) {
            // 1. App Logo & Brand Header
            VStack(spacing: 12) {
                FocusInLogoView(size: 86)
                    .padding(.top, 6)

                VStack(spacing: 6) {
                    Text("FocusIn")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(FocusInTheme.studioTextPrimary)

                    Text("v1.5.10-delta · Native macOS Classroom System")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                }
            }

            // 2. Info Cards (No WeChat, No Telegram, No Donate!)
            HStack(spacing: 14) {
                aboutInfoCard(
                    icon: "person.fill",
                    iconColor: Color.blue,
                    title: "作者",
                    subtitle: "Marco",
                    action: nil
                )

                aboutInfoCard(
                    icon: "chevron.left.forwardslash.chevron.right",
                    iconColor: Color.purple,
                    title: "開源地址",
                    subtitle: "檢視程式碼 ↗",
                    action: {
                        if let url = URL(string: "https://github.com/marco-crypto-debug/FocusIn") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )

                aboutInfoCard(
                    icon: "checkmark.shield.fill",
                    iconColor: Color.green,
                    title: "安全架構",
                    subtitle: "零依賴 / 離線 Ed25519",
                    action: nil
                )

                aboutInfoCard(
                    icon: "apple.logo",
                    iconColor: Color.orange,
                    title: "系統環境",
                    subtitle: "macOS 14+ 原生",
                    action: nil
                )
            }
            .frame(maxWidth: 720)

            // 3. Tech Stack Tags
            HStack(spacing: 8) {
                techTagPill("Swift 5")
                techTagPill("SwiftUI")
                techTagPill("ScreenCaptureKit")
                techTagPill("VideoToolbox")
                techTagPill("Network.framework")
            }

            // 4. Update Channel Segmented Control
            HStack(spacing: 12) {
                Text("更新通道:")
                    .font(.system(size: 12))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)

                HStack(spacing: 2) {
                    updateChannelButton(label: "正式版 (Stable)", isBeta: false)
                    updateChannelButton(label: "預覽版 (Beta)", isBeta: true)
                }
                .padding(3)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            // 5. Check for Updates Button
            VStack(spacing: 8) {
                Button {
                    viewModel.checkForUpdatesManually()
                } label: {
                    HStack(spacing: 7) {
                        if viewModel.isCheckingUpdate {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text("檢查更新")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 9)
                    .background(Color(red: 0.14, green: 0.44, blue: 0.98), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCheckingUpdate)

                if let update = viewModel.updateAvailable {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(FocusInTheme.studioGreen)
                        Text("發現新版本（\(update.version)）")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(FocusInTheme.studioGreen)
                        if let url = URL(string: update.url) {
                            Button("立即下載 DMG") { UpdateChecker.downloadAndOpen(url) }
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                } else if let msg = viewModel.updateCheckStatusText {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                } else {
                    Text("目前已是最新版本 (\(UpdateChecker.localDisplayVersion))")
                        .font(.system(size: 11))
                        .foregroundStyle(FocusInTheme.studioTextSecondary.opacity(0.7))
                }
            }

            // 6. Copyright Footer
            Text("Copyright © 2025-2026 FocusIn. All rights reserved.")
                .font(.system(size: 10.5))
                .foregroundStyle(FocusInTheme.studioTextSecondary.opacity(0.45))
                .padding(.top, 4)
                .padding(.bottom, 6)
        }
        .padding(32)
        .frame(maxWidth: 780)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FocusInTheme.studioCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FocusInTheme.studioLine, lineWidth: 1)
        )
    }

    private func aboutInfoCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)

                Text(subtitle)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(FocusInTheme.studioTextPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(FocusInTheme.studioLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private func techTagPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(FocusInTheme.studioTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FocusInTheme.studioLine.opacity(0.5), lineWidth: 0.5)
            )
    }

    private func updateChannelButton(label: String, isBeta: Bool) -> some View {
        let isSelected = (updateChannel == label)
        return Button {
            updateChannel = label
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                if isBeta {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                isSelected ? Color(red: 0.14, green: 0.44, blue: 0.98) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .foregroundStyle(isSelected ? .white : FocusInTheme.studioTextSecondary)
        }
        .buttonStyle(.plain)
    }

    private var transportSettingsSection: some View {
        toolSectionCard(title: "TRANSPORT MODE", icon: "network") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: Binding(
                    get: { DeviceLimit.transportMode },
                    set: { mode in
                        DeviceLimit.transportMode = mode
                        viewModel.appendLog("傳輸方式切換為「\(mode.label)」")
                    }
                )) {
                    ForEach(TransportMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                Text(DeviceLimit.transportRecommendation(for: viewModel.peers.count))
                    .font(.system(size: 11.5))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
                Text("UDP 組播模式：畫面與聲音均只發 1 份串流，由路由器/AP 複製給全體學生，最高支援 50 台擴容。")
                    .font(.system(size: 11))
                    .foregroundStyle(FocusInTheme.studioTextSecondary.opacity(0.8))
            }
        }
    }

    private var securitySettingsSection: some View {
        toolSectionCard(title: "ADMIN PASSWORD", icon: "lock.shield.fill") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(QuitGuard.hasPassword ? "已設定管理員密碼" : "尚未設定管理員密碼")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(QuitGuard.hasPassword ? FocusInTheme.studioGreen : .orange)
                    Spacer()
                }
                Text("此密碼同時用於：教師端退出 (⌘Q)、學生端退出保護與學生端緊急解鎖 (⌘⇧U)。設定後會自動下發至所有已連線學生端。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)

                if QuitGuard.hasPassword {
                    SecureField("舊密碼", text: $oldQuitPass)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }

                SecureField("新管理員密碼（至少 4 字元）", text: $newQuitPass)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

                Button(QuitGuard.hasPassword ? "變更並即時下發" : "設定並即時下發") {
                    quitPassError = ""
                    do {
                        try QuitGuard.setPassword(newQuitPass, oldPassword: QuitGuard.hasPassword ? oldQuitPass : nil)
                        viewModel.sendSetAdminPassword(newQuitPass)
                        newQuitPass = ""
                        oldQuitPass = ""
                        viewModel.appendLog("已成功更新並廣播管理員密碼")
                    } catch {
                        quitPassError = error.localizedDescription
                    }
                }
                .disabled(newQuitPass.count < 4)
                .controlSize(.small)

                if !quitPassError.isEmpty {
                    Text(quitPassError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var probeSettingsSection: some View {
        toolSectionCard(title: "MULTICAST THROUGHPUT TEST", icon: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 10) {
                Text("向組播組發送階梯速率流，學生端統計接收率，用於檢驗 AP 的 IGMP snooping 與組播吞吐性能。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(FocusInTheme.studioTextSecondary)

                HStack(spacing: 8) {
                    Text("起:").font(.system(size: 11)).foregroundStyle(FocusInTheme.studioTextSecondary)
                    TextField("2", text: $probeRateText)
                        .textFieldStyle(.plain)
                        .frame(width: 44)
                        .padding(6)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    Text("Mbps → 上限:").font(.system(size: 11)).foregroundStyle(FocusInTheme.studioTextSecondary)
                    TextField("16", text: $probeMaxRateText)
                        .textFieldStyle(.plain)
                        .frame(width: 48)
                        .padding(6)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    Text("Mbps 每檔:").font(.system(size: 11)).foregroundStyle(FocusInTheme.studioTextSecondary)
                    TextField("8", text: $probeStageText)
                        .textFieldStyle(.plain)
                        .frame(width: 38)
                        .padding(6)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    Text("秒").font(.system(size: 11)).foregroundStyle(FocusInTheme.studioTextSecondary)

                    Spacer()

                    Button(viewModel.probeRunning ? "停止測試" : "開始測試") {
                        if viewModel.probeRunning {
                            viewModel.stopMulticastProbe()
                        } else {
                            let rate = Double(probeRateText) ?? 2
                            let max = Double(probeMaxRateText) ?? 16
                            let stage = Double(probeStageText) ?? 8
                            viewModel.startMulticastProbe(rate: rate, maxRate: max, step: 2, stageSeconds: stage)
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(FocusInTheme.studioRed)
                }

                if !viewModel.probeResults.isEmpty {
                    Divider().background(FocusInTheme.studioLine)
                    ForEach(viewModel.probeResults.sorted(by: { $0.key < $1.key }), id: \.key) { name, report in
                        HStack {
                            Text(name).font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(report)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(FocusInTheme.studioTextSecondary)
                        }
                    }
                }
            }
        }
    }

    private var generalSettingsSection: some View {
        toolSectionCard(title: "GENERAL & UPDATES", icon: "gearshape") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("登入時自動啟動 FocusIn 教師端", isOn: Binding(
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
                ))
                .font(.system(size: 12.5))

                if !autoStartError.isEmpty {
                    Text(autoStartError).font(.system(size: 11)).foregroundStyle(.red)
                }

                Divider().background(FocusInTheme.studioLine)

                HStack {
                    Text("快捷鍵說明")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FocusInTheme.studioTextPrimary)
                    Spacer()
                    Text("⌘Q: 安全退出 • ⌘⇧U: 學生端緊急解鎖")
                        .font(.system(size: 11))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                }
            }
        }
    }

    private func toolSectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(FocusInTheme.studioRedSoft)
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(FocusInTheme.studioTextSecondary)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FocusInTheme.studioCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FocusInTheme.studioLine, lineWidth: 1))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// ============================================================
// Sparkline 即時折線圖 (SwiftUI Native Canvas)
// ============================================================

struct SparklineView: View {
    let data: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            if data.count >= 2 {
                let minVal = (data.min() ?? 0) * 0.8
                let maxVal = max((data.max() ?? 30) * 1.2, minVal + 1)

                let points: [CGPoint] = data.enumerated().map { idx, val in
                    let x = CGFloat(idx) / CGFloat(max(data.count - 1, 1)) * w
                    let norm = CGFloat((val - minVal) / (maxVal - minVal))
                    let y = h - (norm * (h - 4)) - 2
                    return CGPoint(x: x, y: y)
                }

                ZStack {
                    // 下方半透明漸層填色
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        path.addLine(to: points[0])
                        for pt in points.dropFirst() {
                            path.addLine(to: pt)
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [FocusInTheme.studioRed.opacity(0.35), FocusInTheme.studioRed.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // 折線
                    Path { path in
                        path.move(to: points[0])
                        for pt in points.dropFirst() {
                            path.addLine(to: pt)
                        }
                    }
                    .stroke(
                        FocusInTheme.studioRedSoft,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: FocusInTheme.studioRedSoft.opacity(0.4), radius: 3)
                }
            } else {
                Color.clear
            }
        }
    }
}

// ============================================================
// 學生螢幕縮圖卡片 (Student Card Item)
// ============================================================

struct StudentCardItemView: View {
    @Binding var peer: StudentPeer
    let isLocked: Bool
    let broadcastActive: Bool
    let previewImage: NSImage?
    let latency: Int

    var body: some View {
        Button {
            peer.isSelected.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // 頂部名稱與鎖定狀態
                HStack {
                    Text(peer.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FocusInTheme.studioTextPrimary)
                        .lineLimit(1)
                    Spacer()
                    if isLocked {
                        Text("LOCKED")
                            .font(.system(size: 8.5, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(FocusInTheme.studioRed.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(FocusInTheme.studioRedSoft)
                    } else {
                        Text("READY")
                            .font(.system(size: 8.5, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(FocusInTheme.studioGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(FocusInTheme.studioGreen)
                    }
                }

                // 迷你螢幕視窗
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(red: 0.05, green: 0.05, blue: 0.07))
                        .aspectRatio(16/10, contentMode: .fit)

                    if let img = previewImage, (broadcastActive || !isLocked) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else if isLocked {
                        VStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(FocusInTheme.studioRedSoft)
                            Text("Locked")
                                .font(.system(size: 8))
                                .foregroundStyle(FocusInTheme.studioTextSecondary)
                        }
                    } else {
                        Image(systemName: "display")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.white.opacity(0.15))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // 底部延遲與狀態
                HStack {
                    Text("\(latency) ms")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(latency > 60 ? .orange : FocusInTheme.studioTextSecondary)
                    Spacer()
                    Text("Native")
                        .font(.system(size: 9.5))
                        .foregroundStyle(FocusInTheme.studioTextSecondary)
                }
            }
            .padding(8)
            .frame(width: 140)
            .background(
                peer.isSelected
                    ? FocusInTheme.studioCardHover
                    : FocusInTheme.studioCard,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        peer.isSelected
                            ? FocusInTheme.studioRed.opacity(0.7)
                            : FocusInTheme.studioLine,
                        lineWidth: peer.isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#endif
