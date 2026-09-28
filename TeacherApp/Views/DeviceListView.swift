import AppKit
import SwiftUI

/// 教師主介面：左側裝置列表（單選/全選），右側控制面板。
struct DeviceListView: View {
    @EnvironmentObject var viewModel: TeacherViewModel
    @State private var launchBundleID = "com.apple.Safari"
    @State private var allSelected = false

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
                    Label(viewModel.broadcastActive ? "停止廣播" : "廣播教師屏幕",
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
            }
            .padding()
            .frame(minWidth: 420)
        }
    }
}
