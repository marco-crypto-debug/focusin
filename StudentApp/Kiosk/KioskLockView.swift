import SwiftUI

/// 锁屏界面：显示教师广播画面（或锁定提示），以及紧急解锁密码输入。
struct KioskLockView: View {
    @ObservedObject var controller: KioskModeController
    @State private var password = ""
    @State private var showError = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = controller.broadcastImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.white)
                    Text("屏幕已被教师锁定")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("按 ⌘⇧U，输入本地管理员密码可紧急解锁")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if controller.unlockRequested {
                VStack(spacing: 12) {
                    SecureField("管理员密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit(submit)
                    if showError {
                        Text("密码错误").foregroundStyle(.red)
                    }
                    Button("解锁", action: submit)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private func submit() {
        guard controller.isLocked else { return }
        if controller.submitUnlock(password) {
            password = ""
            showError = false
        } else {
            showError = true
            password = ""
        }
    }
}
