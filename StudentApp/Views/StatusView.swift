import SwiftUI

/// 學生端狀態視窗：簡潔主頁（連線 / 鎖定 / 廣播狀態）+ 進階設定（密碼 / 自動啟動 / 更新）。
struct StatusView: View {
    @EnvironmentObject var listener: CommandListener
    @ObservedObject private var kiosk = KioskModeController.shared
    @ObservedObject private var appState = FocusInAppState.shared
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordSaved = false
    @State private var passwordError = ""
    @State private var autoStartError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 頂部品牌列
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 16))
                    .foregroundStyle(FocusInTheme.accent)
                Text("FocusIn")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(listener.deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                    ForEach(listener.log, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxHeight: 60)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FocusInTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FocusInTheme.line, lineWidth: 1))

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
        .frame(minWidth: 380, minHeight: 420)
        .background(FocusInTheme.canvas)
    }

    // MARK: - 第一頁：狀態（基礎功能）

    private var homeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 連線狀態大卡
            FocusInTheme.sectionLabel("Status")
            FocusInTheme.card {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(listener.connectionCount > 0 ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                        if listener.connectionCount > 0 {
                            Circle()
                                .stroke(Color.green.opacity(0.3), lineWidth: 5)
                                .frame(width: 22, height: 22)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(listener.connectionCount > 0
                             ? "\(listener.connectionCount) 位教師已連線"
                             : "等待教師連線…")
                            .font(.system(size: 14, weight: .semibold))
                        Text(listener.isLocked ? "屏幕已鎖定" : "屏幕未被鎖定")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: listener.isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 18))
                        .foregroundStyle(listener.isLocked ? FocusInTheme.accent : .secondary)
                }
            }

            // 廣播狀態
            if listener.isBroadcasting {
                FocusInTheme.sectionLabel("Broadcast")
                FocusInTheme.card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("正在接收教師屏幕廣播", systemImage: "rectangle.on.rectangle")
                            .font(.system(size: 13, weight: .semibold))
                        if let image = kiosk.broadcastImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text("教師鎖定學生端後將全屏顯示，聲音同步播放")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                FocusInTheme.sectionLabel("Broadcast")
                FocusInTheme.card {
                    HStack(spacing: 10) {
                        Image(systemName: "pause.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                        Text("目前沒有廣播")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 第二頁：進階設定

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 本地管理員密碼（緊急解鎖用）
            FocusInTheme.sectionLabel("Admin Password")
            FocusInTheme.card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(KioskConfig.hasAdminPassword
                         ? "變更本地管理員密碼（需先驗證目前密碼）"
                         : "設定本地管理員密碼（部署時設定，用於緊急解鎖）")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if KioskConfig.hasAdminPassword {
                        SecureField("目前密碼", text: $oldPassword)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    SecureField("新密碼（至少 4 位）", text: $newPassword)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    SecureField("確認密碼", text: $confirmPassword)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button(KioskConfig.hasAdminPassword ? "變更密碼" : "保存密碼", action: savePassword)
                        .controlSize(.small)
                    if !passwordError.isEmpty {
                        Text(passwordError)
                            .font(.system(size: 11))
                            .foregroundStyle(passwordSaved ? .green : .red)
                    }
                }
            }

            // 一般設定
            FocusInTheme.sectionLabel("General")
            FocusInTheme.card {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("登入時自動啟動學生端", isOn: Binding(
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
                        Button("檢查更新") { listener.checkForUpdatesManually() }
                            .controlSize(.small)
                    }
                    if let update = listener.updateAvailable {
                        HStack(spacing: 10) {
                            Label("發現新版本（\(update.version)）", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.blue)
                            Spacer()
                            Button("前往 GitHub 下載") {
                                if let url = URL(string: update.pageURL) { NSWorkspace.shared.open(url) }
                                listener.updateAvailable = nil
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

    // MARK: - 動作

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
            try KioskConfig.setAdminPassword(newPassword,
                                             oldPassword: KioskConfig.hasAdminPassword ? oldPassword : nil)
            passwordSaved = true
            passwordError = KioskConfig.hasAdminPassword
                ? "密碼已變更（雜湊儲存，僅用於本地緊急解鎖）"
                : "密碼已保存（雜湊儲存，僅用於本地緊急解鎖）"
            oldPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch KioskConfig.KioskError.oldPasswordMismatch {
            passwordError = "目前密碼不正確，無法變更"
            oldPassword = ""
        } catch {
            passwordError = "保存失敗: \(error)"
        }
    }
}
