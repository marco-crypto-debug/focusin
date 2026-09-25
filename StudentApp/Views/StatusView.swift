import SwiftUI

/// 學生端狀態視窗：顯示連線狀態、鎖屏狀態，並用於部署時預設本地管理員密碼。
struct StatusView: View {
    @EnvironmentObject var listener: CommandListener
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordSaved = false
    @State private var passwordError = ""

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

            HStack {
                Image(systemName: listener.isLocked ? "lock.fill" : "lock.open")
                Text(listener.isLocked ? "已鎖定" : "未鎖定")
            }

            if listener.isBroadcasting {
                Label("正在接收教師屏幕廣播", systemImage: "rectangle.on.rectangle")
            }

            Divider()

            Text("本地管理員密碼（部署時設定）")
                .font(.subheadline.bold())
            SecureField("新密碼（至少 4 位）", text: $newPassword)
            SecureField("確認密碼", text: $confirmPassword)
            Button("保存密碼", action: savePassword)
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
            try KioskConfig.setAdminPassword(newPassword)
            passwordSaved = true
            passwordError = "密碼已保存（雜湊儲存，僅用於本地緊急解鎖）"
            newPassword = ""
            confirmPassword = ""
        } catch {
            passwordError = "保存失敗: \(error)"
        }
    }
}
