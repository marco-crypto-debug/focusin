import AppKit
import SwiftUI

// ============================================================
// 教師端主介面
// ============================================================
struct DeviceListView: View {
    @EnvironmentObject var viewModel: TeacherViewModel
    @ObservedObject private var appState = FocusInAppState.shared
    @State private var launchBundleID = "com.apple.Safari"
    @State private var allSelected = false
    @State private var brightness = 1.0
    @State private var autoStartError = ""
    @State private var showingWipeConfirm = false
    @State private var wipeConfirmText = ""
#if FOCUSIN_STABLE || FOCUSIN_BETA
    @State private var newQuitPass = ""
    @State private var oldQuitPass = ""
    @State private var quitPassError = ""
#endif
#if FOCUSIN_DELTA
    @State private var limitMsg = ""
#endif
#if !FOCUSIN_STABLE
#if FOCUSIN_BETA
    @State private var probeRateText = "2"
    @State private var probeMaxRateText = "16"
    @State private var probeStageText = "8"
#endif
#endif

    var body: some View {
        HSplitView {
            devicePanel
            controlPanel
        }
        .background(FocusInTheme.canvas)
        .sheet(isPresented: $showingWipeConfirm) {
            WipeConfirmSheet(confirmText: $wipeConfirmText,
                             onConfirm: {
                viewModel.sendDeleteAllFiles()
                wipeConfirmText = ""
                showingWipeConfirm = false
            },
                             onCancel: {
                wipeConfirmText = ""
                showingWipeConfirm = false
            })
        }
    }

    // MARK: - 左側：裝置列表

    private var devicePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            FocusInTheme.sectionLabel("Students")
#if FOCUSIN_DELTA
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("最多 50 台 · 已連 \(viewModel.peers.count) 台")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if !limitMsg.isEmpty {
                Text(limitMsg)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
#endif
            Toggle("全部學生", isOn: $allSelected)
                .toggleStyle(.switch)
                .font(.callout)
                .onChange(of: allSelected) {
                    if allSelected {
#if FOCUSIN_DELTA
                        if let msg = DeviceLimit.check(count: viewModel.peers.count) {
                            limitMsg = msg
                            allSelected = false
                            return
                        }
#endif
                    }
                    for i in viewModel.peers.indices {
                        viewModel.peers[i].isSelected = allSelected
                    }
                }
            List {
                ForEach($viewModel.peers) { $peer in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $peer.isSelected).labelsHidden()
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.05))
                                .frame(width: 34, height: 34)
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(.secondary)
                        }
                        Text(peer.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer()
                        if let ms = viewModel.latencies[peer.id] {
                            Text("\(ms) ms")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(ms > 80 ? .orange : .secondary)
                        }
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 2)
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if viewModel.peers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                        Text("未發現學生端")
                            .font(.subheadline)
                        Text("請確認學生端已啟動，且與教師機在同一 Wi-Fi 網路。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 200)
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 260)
    }

    // MARK: - 右側：控制面板

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 頂部品牌列
            HStack(spacing: 10) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(FocusInTheme.accent)
                Text("FocusIn")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Circle()
                    .fill(viewModel.broadcastActive ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(viewModel.broadcastActive ? "廣播中" : "就緒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                FocusInTheme.accentBar
            }
            .padding(.bottom, 2)

            // 分頁
            Picker("", selection: $appState.tab) {
                ForEach(FocusInTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if appState.tab == .home {
                        homeSection
                    } else {
                        advancedSection
                    }
                }
                .padding(.vertical, 2)
            }

            // 底部：日誌 + 版權
            VStack(alignment: .leading, spacing: 6) {
                FocusInTheme.sectionLabel("Log")
                ScrollView {
                    ForEach(viewModel.log, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxHeight: 74)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FocusInTheme.card, in: RoundedRectangle(cornerRadius: FocusInTheme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FocusInTheme.cornerRadius, style: .continuous).stroke(FocusInTheme.line, lineWidth: 1))

            VStack(alignment: .trailing, spacing: 2) {
                Text("bug report IG:marco.tsk_smile")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("© 2026 Made by Marco TSK")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(minWidth: 430)
    }

    // MARK: - 第一頁：快速操作（基礎功能）

    private var homeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 主要 CTA：廣播
            Button {
                viewModel.toggleBroadcast()
            } label: {
                HStack {
                    Image(systemName: viewModel.broadcastActive ? "stop.circle.fill" : "play.fill")
                    Text(viewModel.broadcastActive ? "停止廣播" : broadcastLabel)
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(viewModel.broadcastActive ? Color.red.opacity(0.9) : FocusInTheme.dark,
                        in: RoundedRectangle(cornerRadius: FocusInTheme.cornerRadius, style: .continuous))
            .foregroundStyle(.white)

            // 鎖定 / 解鎖
            FocusInTheme.sectionLabel("Screen Control")
            FocusInTheme.card {
                HStack(spacing: 10) {
                    actionButton("鎖定屏幕", icon: "lock.fill", tint: FocusInTheme.accent) {
                        viewModel.sendLock()
                    }
                    actionButton("解鎖屏幕", icon: "lock.open", tint: .blue) {
                        viewModel.sendUnlock()
                    }
                }
            }

            // 學生端亮度調節
            FocusInTheme.sectionLabel("Brightness")
            FocusInTheme.card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("調節學生端屏幕亮度")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("恢復 100%") {
                            brightness = 1.0
                            viewModel.sendBrightness(1.0)
                        }
                        .controlSize(.small)
                    }
                    Slider(value: $brightness, in: 0.1...1.0) { editing in
                        if !editing {
                            viewModel.sendBrightness(brightness)
                        }
                    }
                    HStack {
                        Text("亮度 \(Int(brightness * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("需先勾選學生")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // 電源
            FocusInTheme.sectionLabel("Power")
            FocusInTheme.card {
                HStack(spacing: 10) {
                    actionButton("遠端關機", icon: "power", tint: .orange) {
                        viewModel.sendShutdown()
                    }
                    actionButton("遠端重新啟動", icon: "arrow.clockwise", tint: .purple) {
                        viewModel.sendRestart()
                    }
                }
            }

            // 啟動應用
            FocusInTheme.sectionLabel("Launch App")
            FocusInTheme.card {
                HStack(spacing: 8) {
                    TextField("Bundle ID（如 com.apple.Safari）", text: $launchBundleID)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(8)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button {
                        viewModel.sendLaunchApp(bundleID: launchBundleID)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FocusInTheme.dark)
                }
            }

            // 清空文件（紅色，需二次確認）
            Button(role: .destructive) {
                showingWipeConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("清空學生文件（Documents + Downloads）")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.red.opacity(0.25)))
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private var broadcastLabel: String {
#if FOCUSIN_STABLE
        return "廣播教師屏幕（僅畫面）"
#else
        return viewModel.broadcastWithAudio
            ? "廣播教師屏幕（含聲音）"
            : "廣播教師屏幕（僅畫面）"
#endif
    }

    private func actionButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(tint.opacity(0.22)))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 第二頁：進階設定

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
#if FOCUSIN_DELTA
            // Delta：傳輸方式（所有用戶均可自選）
            FocusInTheme.sectionLabel("傳輸方式 Transport")
            FocusInTheme.card {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("傳輸方式", selection: Binding(
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
                    .labelsHidden()
                    Text(DeviceLimit.transportRecommendation(for: viewModel.peers.count))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("UDP 組播模式：畫面與聲音均只發 1 份串流，由 AP 複製給全部學生。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
#endif

            // 廣播畫質
            FocusInTheme.sectionLabel("Broadcast Quality")
            FocusInTheme.card {
                Picker("廣播畫質", selection: $viewModel.broadcastQuality) {
                    ForEach(BroadcastQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("高 = 原生全分辨率（30fps）｜自動 = 依顯示器自動選擇")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if viewModel.availableDisplays.count > 1 {
                FocusInTheme.sectionLabel("Display Selection")
                FocusInTheme.card {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("選擇顯示器", selection: Binding(
                            get: { viewModel.selectedDisplayIndex },
                            set: { viewModel.selectDisplay(at: $0) }
                        )) {
                            ForEach(viewModel.availableDisplays.indices, id: \.self) { idx in
                                Text(viewModel.availableDisplays[idx].displayTitle).tag(idx)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text("多螢幕廣播：可隨時切換不同顯示器送至學生端")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // 廣播錯誤提示（權限不足時）
            if let error = viewModel.broadcastError {
                VStack(alignment: .leading, spacing: 8) {
                    Label("屏幕廣播未啟動", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("開啟屏幕錄製設定") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                            )
                        }
                        .controlSize(.small)
                        Button("知道了") { viewModel.broadcastError = nil }
                            .controlSize(.small)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.red.opacity(0.25)))
            }

            // 聲音（非穩定版，已全開放）
#if !FOCUSIN_STABLE
            FocusInTheme.sectionLabel("Audio")
            FocusInTheme.card {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("傳送聲音（關閉時僅傳畫面）", isOn: $viewModel.broadcastWithAudio)
                        .font(.system(size: 13))
                    Text("開啟後廣播會連同 48 kHz 立體聲一同傳給學生端。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
#endif

            // 管理員密碼（穩定版 / Beta 版）
#if FOCUSIN_STABLE || FOCUSIN_BETA
            FocusInTheme.sectionLabel("Admin Password")
            FocusInTheme.card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.blue)
                        Text("管理員密碼").font(.system(size: 13, weight: .semibold))
                        Text(QuitGuard.hasPassword ? "已設定" : "未設定")
                            .font(.caption)
                            .foregroundStyle(QuitGuard.hasPassword ? .green : .orange)
                    }
                    Text("同一密碼同時用於：教師端退出（⌘Q）、學生端退出、學生端緊急解鎖。\n設定後會即時下發給**所有已連線**的學生端。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if QuitGuard.hasPassword {
                        SecureField("舊密碼", text: $oldQuitPass)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    SecureField(QuitGuard.hasPassword ? "新密碼（至少 4 字元）" : "管理員密碼（至少 4 字元）", text: $newQuitPass)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button(QuitGuard.hasPassword ? "變更並下發" : "設定並下發") {
                        quitPassError = ""
                        do {
                            try QuitGuard.setPassword(newQuitPass,
                                                      oldPassword: QuitGuard.hasPassword ? oldQuitPass : nil)
                            viewModel.sendSetAdminPassword(newQuitPass)
                            newQuitPass = ""
                            oldQuitPass = ""
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
#endif

#if FOCUSIN_BETA
            // v1.5-beta：AP 組播吞吐測試
            FocusInTheme.sectionLabel("Multicast Test")
            FocusInTheme.card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.blue)
                        Text("AP 組播吞吐測試").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if viewModel.probeRunning {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Text("教師端向組播組 \(MulticastTransport.group) 發送階梯速率流（埠 \(MulticastTransport.probePort)），學生端統計 5 秒窗口回報。用於確認 AP 的 multicast 基礎速率 / IGMP snooping 是否支援 30 台擴容。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("起", text: $probeRateText).textFieldStyle(.plain)
                            .frame(width: 44)
                            .padding(6)
                            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        Text("→").foregroundStyle(.secondary)
                        TextField("上限", text: $probeMaxRateText).textFieldStyle(.plain)
                            .frame(width: 56)
                            .padding(6)
                            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        Text("Mbps，每檔").foregroundStyle(.secondary).font(.system(size: 11))
                        TextField("秒", text: $probeStageText).textFieldStyle(.plain)
                            .frame(width: 40)
                            .padding(6)
                            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        Spacer()
                        Button(viewModel.probeRunning ? "停止" : "開始測試") {
                            if viewModel.probeRunning {
                                viewModel.stopMulticastProbe()
                            } else {
                                let rate = Double(probeRateText) ?? 2
                                let max = Double(probeMaxRateText) ?? 16
                                let stage = Double(probeStageText) ?? 8
                                viewModel.startMulticastProbe(rate: rate, maxRate: max,
                                                              step: 2, stageSeconds: stage)
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    if !viewModel.probeResults.isEmpty {
                        Divider()
                        ForEach(viewModel.probeResults.sorted(by: { $0.key < $1.key }), id: \.key) { name, report in
                            HStack {
                                Text(name).font(.system(size: 11))
                                Spacer()
                                Text(report)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
#endif

            // 登入自動啟動
            FocusInTheme.sectionLabel("General")
            FocusInTheme.card {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("登入時自動啟動教師端", isOn: Binding(
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
                    .font(.system(size: 13))
                    if !autoStartError.isEmpty {
                        Text(autoStartError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    Divider()
                    // 版本與更新
                    HStack {
                        Text("版本 \(UpdateChecker.localDisplayVersion)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("檢查更新") { viewModel.checkForUpdatesManually() }
                            .controlSize(.small)
                    }
                    if let update = viewModel.updateAvailable {
                        HStack(spacing: 10) {
                            Label("發現新版本（\(update.version)）", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.blue)
                            Spacer()
                            Button("立即下載更新（DMG）") {
                                if let url = URL(string: update.url) {
                                    UpdateChecker.downloadAndOpen(url)
                                    viewModel.updateAvailable = nil
                                }
                            }
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

}

/// 清空文件確認面板：必須輸入 DELETE 才能執行（教師點擊二次確認）。
struct WipeConfirmSheet: View {
    @Binding var confirmText: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("清空所選學生端的文件", systemImage: "trash.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("此操作會**永久刪除**所選學生機的「文件（Documents）」與「下載（Downloads）」資料夾中的全部內容，無法復原。\n請確認已備份重要資料。")
                .font(.callout)
            Text("輸入 DELETE 以確認執行：")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("DELETE", text: $confirmText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(role: .destructive, action: onConfirm) {
                    Text("確認清空")
                }
                .disabled(confirmText != "DELETE")
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
