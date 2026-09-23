import SwiftUI

/// 学生端状态窗口：显示连接状态、锁屏状态，并用于部署时预设本地管理员密码。
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
                     ? "\(listener.connectionCount) 位教师已连接"
                     : "等待教师连接…")
            }

            HStack {
                Image(systemName: listener.isLocked ? "lock.fill" : "lock.open")
                Text(listener.isLocked ? "已锁定" : "未锁定")
            }

            if listener.isBroadcasting {
                Label("正在接收教师屏幕广播", systemImage: "rectangle.on.rectangle")
            }

            Divider()

            Text("本地管理员密码（部署时设置）")
                .font(.subheadline.bold())
            SecureField("新密码（至少 4 位）", text: $newPassword)
            SecureField("确认密码", text: $confirmPassword)
            Button("保存密码", action: savePassword)
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
            passwordError = "密码至少 4 位"
            return
        }
        guard newPassword == confirmPassword else {
            passwordError = "两次输入的密码不一致"
            return
        }
        do {
            try KioskConfig.setAdminPassword(newPassword)
            passwordSaved = true
            passwordError = "密码已保存（哈希存储，仅用于本地紧急解锁）"
            newPassword = ""
            confirmPassword = ""
        } catch {
            passwordError = "保存失败: \(error)"
        }
    }
}
