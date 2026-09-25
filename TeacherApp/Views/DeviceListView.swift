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
