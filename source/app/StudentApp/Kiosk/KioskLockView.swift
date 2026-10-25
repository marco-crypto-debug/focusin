import SwiftUI

/// 鎖屏介面：顯示教師廣播畫面（或鎖定提示），以及緊急解鎖密碼輸入。
struct KioskLockView: View {
    @ObservedObject var controller: KioskModeController
    @State private var password = ""
    @State private var showError = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack {
            // 背景底色與環境光暈
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

            // 柔和暗紅氛圍光 (Ambient Glow)
            RadialGradient(
                colors: [
                    Color(red: 0.843, green: 0.098, blue: 0.125).opacity(0.18),
                    Color(red: 0.54, green: 0.24, blue: 0.99).opacity(0.06),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()

            if let image = controller.broadcastImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)   // 高品質縮放，1080p/2K 級畫面更清晰
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 鎖定提示看板（致敬官網 Focus Lock 設計）
                VStack(spacing: 20) {
                    // 發光鎖定圓形徽章
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.843, green: 0.098, blue: 0.125).opacity(0.15))
                            .frame(width: 82, height: 82)
                        Circle()
                            .stroke(Color(red: 0.843, green: 0.098, blue: 0.125).opacity(0.42), lineWidth: 1.5)
                            .frame(width: 82, height: 82)
                            .shadow(color: Color(red: 0.843, green: 0.098, blue: 0.125).opacity(0.35), radius: 8)

                        Image(systemName: "lock.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.28, blue: 0.32))
                    }

                    VStack(spacing: 8) {
                        Text("Locked by FocusIn")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Focus on the lesson.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }

                    // ⌘⇧U 緊急解鎖膠囊按鈕
                    Button {
                        controller.unlockRequested = true
                    } label: {
                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                keyBadge("⌘")
                                keyBadge("⇧")
                                keyBadge("U")
                            }
                            Text("Emergency Unlock")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // 右下角「● Input blocked」狀態膠囊
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.25, blue: 0.25))
                    .frame(width: 6, height: 6)
                    .shadow(color: Color(red: 1.0, green: 0.25, blue: 0.25).opacity(0.8), radius: 3)
                Text("Input blocked")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65), in: Capsule())
            .overlay(Capsule().stroke(Color(red: 1.0, green: 0.25, blue: 0.25).opacity(0.3), lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 24)
            .padding(.bottom, 24)

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
                Text("bug report IG:marco.tsk_smile")
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
        .onChange(of: controller.unlockRequested) {
            if controller.unlockRequested { passwordFocused = true }
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

    private func keyBadge(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}
