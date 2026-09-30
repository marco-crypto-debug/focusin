import SwiftUI

/// 鎖屏介面：顯示教師廣播畫面（或鎖定提示），以及緊急解鎖密碼輸入。
struct KioskLockView: View {
    @ObservedObject var controller: KioskModeController
    @State private var password = ""
    @State private var showError = false
    @FocusState private var passwordFocused: Bool

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

            // 輸入攔截未生效（缺少輔助功能權限）時，明確提示原因
            if !controller.isInputBlocked && !controller.unlockRequested {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.yellow)
                    Text("緊急解鎖（⌘⇧U）需要「輔助功能」權限，尚未授權")
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                    Text("請在 系統設定 → 私隱與安全性 → 輔助功能 開啟後重新鎖定")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(16)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 24)
            }

            // 瞬時提示（未設定密碼 / 密碼錯誤 / 逾時等），不在解鎖面板中時顯示於底部
            if let hint = controller.unlockHint, !controller.unlockRequested {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
            }

            if controller.unlockRequested {
                VStack(spacing: 12) {
                    SecureField("管理員密碼", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .focused($passwordFocused)
                        .onSubmit(submit)
                    if showError {
                        Text("密碼錯誤").foregroundStyle(.red)
                    }
                    if let hint = controller.unlockHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 260)
                    }
                    Button("解鎖", action: submit)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .onAppear { passwordFocused = true }
            }

            // 右下角版權標記
            VStack(alignment: .trailing, spacing: 2) {
                Text("如發現 Bug，請回報 IG：marco.tsk_smile")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                Text("© 2026 Made by Marco TSK")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(10)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onChange(of: controller.unlockRequested) { value in
            if value { passwordFocused = true }
        }
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
