import SwiftUI

/// 鎖屏介面：顯示教師廣播畫面（或鎖定提示），以及緊急解鎖密碼輸入。
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
                    Text("屏幕已被教師鎖定")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("按 ⌘⇧U，輸入本地管理員密碼可緊急解鎖")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if controller.unlockRequested {
                VStack(spacing: 12) {
                    SecureField("管理員密碼", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit(submit)
                    if showError {
                        Text("密碼錯誤").foregroundStyle(.red)
                    }
                    Button("解鎖", action: submit)
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
