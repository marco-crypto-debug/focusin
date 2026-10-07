import AppKit
import SwiftUI

/// 教師主介面：左側裝置列表（單選/全選），右側控制面板。
struct DeviceListView: View {
    @EnvironmentObject var viewModel: TeacherViewModel
    @State private var launchBundleID = "com.apple.Safari"
    @State private var allSelected = false
    @State private var autoStartError = ""
    @State private var showingWipeConfirm = false
    @State private var wipeConfirmText = ""
#if FOCUSIN_BETA
    @State private var newQuitPass = ""
    @State private var oldQuitPass = ""
    @State private var quitPassError = ""
#endif

    var body: some View {
        HSplitView {
            // —— 裝置列表 ——
            VStack(alignment: .leading, spacing: 8) {
                Text("學生裝置").font(.headline)
                Toggle("全部學生", isOn: $allSelected)
                    .onChange(of: allSelected) { value in
                        for i in viewModel.peers.indices {
                            viewModel.peers[i].isSelected = value
                        }
                    }
                List {
                    ForEach($viewModel.peers) { $peer in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $peer.isSelected).labelsHidden()
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(.secondary)
                            Text(peer.name)
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
                    }
                }
                .overlay {
                    if viewModel.peers.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 28))
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
            .padding()
            .frame(minWidth: 280)

            // —— 控制面板 ——
            VStack(alignment: .leading, spacing: 14) {
                Text("控制面板").font(.headline)

                Group {
                    HStack(spacing: 12) {
                        Button { viewModel.sendLock() } label: {
                            Label("鎖定屏幕", systemImage: "lock.fill")
                        }
                        Button { viewModel.sendUnlock() } label: {
                            Label("解鎖屏幕", systemImage: "lock.open")
                        }
                    }
                    HStack(spacing: 12) {
                        Button { viewModel.sendShutdown() } label: {
                            Label("遠端關機", systemImage: "power")
                        }
                        Button { viewModel.sendRestart() } label: {
                            Label("遠端重新啟動", systemImage: "arrow.clockwise")
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("應用程式 Bundle ID（如 com.apple.Safari）", text: $launchBundleID)
                            .textFieldStyle(.roundedBorder)
                        Button("啟動應用程式") { viewModel.sendLaunchApp(bundleID: launchBundleID) }
                    }
                    Button(role: .destructive) { showingWipeConfirm = true } label: {
                        Label("清空學生文件（Documents + Downloads）", systemImage: "trash.fill")
                    }
                }
                .controlSize(.large)

                Divider()

                // 廣播失敗 / 權限不足時顯示明確指引，可一鍵開啟「屏幕錄製」設定頁
                if let error = viewModel.broadcastError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("屏幕廣播未啟動", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
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
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.35)))
                }

                Button {
                    viewModel.toggleBroadcast()
                } label: {
                    Label(viewModel.broadcastActive ? "停止廣播" : (viewModel.broadcastWithAudio ? "廣播教師屏幕（含聲音）" : "廣播教師屏幕（僅畫面）"),
                          systemImage: viewModel.broadcastActive ? "stop.circle.fill" : "rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.broadcastActive ? .red : .blue)
                .controlSize(.large)

                Divider()

                // 廣播畫質：教師可自行調整分辨率/清晰度（自動 / 低 / 中 / 高）
                VStack(alignment: .leading, spacing: 6) {
                    Text("廣播畫質").font(.subheadline.bold())
                    Picker("廣播畫質", selection: $viewModel.broadcastQuality) {
                        ForEach(BroadcastQuality.allCases) { q in
                            Text(q.label).tag(q)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("高 = 原生全分辨率（30fps）｜自動 = 依顯示器自動選擇")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 聲音廣播開關：若個別學生機音訊鏈路有相容問題，可關閉聲音僅傳畫面
#if !FOCUSIN_STABLE
                Toggle("傳送聲音（關閉時僅傳畫面）", isOn: $viewModel.broadcastWithAudio)
                    .font(.subheadline)
#endif

                Divider()

                // 登入時自動啟動（LaunchAgent 註冊）
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("登入時自動啟動教師端", isOn: Binding(
                        get: { LoginStartManager.isEnabled },
                        set: { on in
                            autoStartError = ""
                            do {
                                if on {
                                    try LoginStartManager.enable()
                                } else {
                                    LoginStartManager.disable()
                                }
                            } catch {
                                autoStartError = "自動啟動設定失敗：\(error.localizedDescription)"
                            }
                        }
                    ))
                    if !autoStartError.isEmpty {
                        Text(autoStartError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

#if FOCUSIN_BETA
                Divider()

                // 退出保護（Beta 專屬）：無密碼無法退出 FocusIn
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.blue)
                        Text("退出保護（Beta）").font(.subheadline.bold())
                        Text(QuitGuard.hasPassword ? "已啟用" : "未設定密碼")
                            .font(.caption)
                            .foregroundStyle(QuitGuard.hasPassword ? .green : .orange)
                    }
                    Text("無密碼無法退出 FocusIn（⌘Q / 選單 Quit 皆需驗證）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if QuitGuard.hasPassword {
                        SecureField("舊密碼", text: $oldQuitPass)
                            .textFieldStyle(.roundedBorder)
                    }
                    SecureField(QuitGuard.hasPassword ? "新密碼（至少 4 字元）" : "退出密碼（至少 4 字元）", text: $newQuitPass)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 10) {
                        Button(QuitGuard.hasPassword ? "變更退出密碼" : "設定退出密碼") {
                            quitPassError = ""
                            do {
                                try QuitGuard.setPassword(newQuitPass,
                                                          oldPassword: QuitGuard.hasPassword ? oldQuitPass : nil)
                                newQuitPass = ""
                                oldQuitPass = ""
                            } catch {
                                quitPassError = error.localizedDescription
                            }
                        }
                        .disabled(newQuitPass.count < 4)
                        .controlSize(.small)
                    }
                    if !quitPassError.isEmpty {
                        Text(quitPassError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
#endif

                Divider()

                // 版本與更新（啟動時自動檢查 GitHub；也可手動檢查）
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("版本 \(UpdateChecker.localDisplayVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("檢查更新") { viewModel.checkForUpdatesManually() }
                            .controlSize(.small)
                    }
                    if let update = viewModel.updateAvailable {
                        HStack(spacing: 10) {
                            Label("發現新版本（\(update.version)）", systemImage: "arrow.down.circle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)
                            Spacer()
                            Button("前往 GitHub 下載") {
                                if let url = URL(string: update.pageURL) { NSWorkspace.shared.open(url) }
                                viewModel.updateAvailable = nil
                            }
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                Divider()

                Text("事件日誌").font(.subheadline.bold())
                ScrollView {
                    ForEach(viewModel.log, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxHeight: 150)

                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("bug report IG:marco.tsk_smile")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("© 2026 Made by Marco TSK")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
            .frame(minWidth: 420)
        }
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
