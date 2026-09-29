import SwiftUI

/// 學生端狀態視窗：顯示連線狀態、鎖屏狀態、廣播預覽，並用於部署時預設本地管理員密碼。
struct StatusView: View {
    @EnvironmentObject var listener: CommandListener
    @ObservedObject private var kiosk = KioskModeController.shared
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordSaved = false
    @State private var passwordError = ""
    @State private var autoStartError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(listener.deviceName, systemImage: "desktopcomputer")
                .font(.headline)

            HStack {
                Circle()
                    .fill(listener.connectionCount > 0 ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(listener.connectionCount > 0
                     ? "\(listener.connectionCount) 位教師已連線"
                     : "等待教師連線…")
            }

            Toggle("登入時自動啟動學生端", isOn: Binding(
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

            HStack {
                Image(systemName: listener.isLocked ? "lock.fill" : "lock.open")
                Text(listener.isLocked ? "已鎖定" : "未鎖定")
            }

            // 自動更新：啟動時檢查 GitHub，發現新版本提示下載
            HStack {
                Text("版本 \(UpdateChecker.localDisplayVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("檢查更新") { listener.checkForUpdatesManually() }
                    .controlSize(.small)
            }
            if let update = listener.updateAvailable {
                HStack(spacing: 10) {
                    Label("發現新版本（\(update.version)）", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.blue)
                    Spacer()
                    Button("前往 GitHub 下載") {
                        if let url = URL(string: update.url) { NSWorkspace.shared.open(url) }
                        listener.updateAvailable = nil
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if listener.isBroadcasting {
                Label("正在接收教師屏幕廣播", systemImage: "rectangle.on.rectangle")
                if let image = kiosk.broadcastImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 220)
                    Text("廣播預覽 — 教師鎖定學生端後將全屏顯示，聲音同步播放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text(KioskConfig.hasAdminPassword
                 ? "變更本地管理員密碼（需先驗證目前密碼）"
                 : "設定本地管理員密碼（部署時設定）")
                .font(.subheadline.bold())
            if KioskConfig.hasAdminPassword {
                SecureField("目前密碼", text: $oldPassword)
            }
            SecureField("新密碼（至少 4 位）", text: $newPassword)
            SecureField("確認密碼", text: $confirmPassword)
            Button(KioskConfig.hasAdminPassword ? "變更密碼" : "保存密碼", action: savePassword)
            if !passwordError.isEmpty {
                Text(passwordError)
                    .font(.caption)
                    .foregroundStyle(passwordSaved ? .green : .red)
            }

            Divider()

            ScrollView {
                ForEach(listener.log, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 120)
        }
        .padding()
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
            // 已設定過密碼時，必須先通過目前密碼驗證
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
