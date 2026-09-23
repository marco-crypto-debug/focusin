import SwiftUI

/// 教师主界面：左侧设备列表（单选/全选），右侧控制面板。
struct DeviceListView: View {
    @EnvironmentObject var viewModel: TeacherViewModel
    @State private var launchBundleID = "com.apple.Safari"
    @State private var allSelected = false

    var body: some View {
        HSplitView {
            // —— 设备列表 ——
            VStack(alignment: .leading, spacing: 8) {
                Text("学生设备").font(.headline)
                Toggle("全部学生", isOn: $allSelected)
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
                            Text("未发现学生端")
                                .font(.subheadline)
                            Text("请确认学生端已启动且与教师机在同一 Wi-Fi 网络。")
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
                            Label("锁定屏幕", systemImage: "lock.fill")
                        }
                        Button { viewModel.sendUnlock() } label: {
                            Label("解锁屏幕", systemImage: "lock.open")
                        }
                    }
                    HStack(spacing: 12) {
                        Button { viewModel.sendShutdown() } label: {
                            Label("远程关机", systemImage: "power")
                        }
                        Button { viewModel.sendRestart() } label: {
                            Label("远程重启", systemImage: "arrow.clockwise")
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("应用 Bundle ID（如 com.apple.Safari）", text: $launchBundleID)
                            .textFieldStyle(.roundedBorder)
                        Button("启动应用") { viewModel.sendLaunchApp(bundleID: launchBundleID) }
                    }
                }
                .controlSize(.large)

                Divider()

                Button {
                    viewModel.toggleBroadcast()
                } label: {
                    Label(viewModel.broadcastActive ? "停止广播" : "广播教师屏幕",
                          systemImage: viewModel.broadcastActive ? "stop.circle.fill" : "rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.broadcastActive ? .red : .blue)
                .controlSize(.large)

                Divider()

                Text("事件日志").font(.subheadline.bold())
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
