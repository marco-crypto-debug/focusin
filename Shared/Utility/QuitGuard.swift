#if FOCUSIN_STABLE
import AppKit
import CryptoKit
import Foundation

/// 正式版（含原 Beta 功能）：**管理員密碼**（= 退出密碼）——無密碼無法退出 FocusIn。
///
/// 統一密碼架構：
/// - 教師端：在「管理員密碼」區塊設定/變更 → 存本模組（UserDefaults：quit.adminPasswordHash/Salt，
///   只存加鹽 SHA-256 雜湊，絕不存明文），同時透過 `setAdminPassword` 命令下發所有已連線學生端。
/// - 學生端：收到的密碼存入 `KioskConfig`——同一密碼用於學生端退出保護與緊急解鎖（⌘⇧U）。
///
/// 攔截點：`applicationShouldTerminate`（覆蓋 ⌘Q、選單 Quit、Dock 右鍵 Quit、登出），
/// 驗證失敗一律 `terminateCancel`。
enum QuitGuard {
    private static let hashKey = "quit.adminPasswordHash"
    private static let saltKey = "quit.adminPasswordSalt"

    static var hasPassword: Bool {
        UserDefaults.standard.string(forKey: hashKey) != nil
    }

    /// 設定或變更退出密碼。已設定過時必須先通過舊密碼驗證。
    static func setPassword(_ password: String, oldPassword: String? = nil) throws {
        guard password.count >= 4 else { throw QuitError.weakPassword }
        if hasPassword {
            guard let old = oldPassword, verify(old) else { throw QuitError.oldPasswordMismatch }
        }
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        UserDefaults.standard.set(hex(salt), forKey: saltKey)
        UserDefaults.standard.set(hex(hash(password, salt: salt)), forKey: hashKey)
    }

    static func verify(_ password: String) -> Bool {
        guard let saltHex = UserDefaults.standard.string(forKey: saltKey),
              let storedHash = UserDefaults.standard.string(forKey: hashKey) else { return false }
        return hex(hash(password, salt: parseHex(saltHex))) == storedHash
    }

    private static func hash(_ password: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(password.utf8)))
    }

    private static func hex(_ d: Data) -> String {
        d.map { String(format: "%02x", $0) }.joined()
    }

    private static func parseHex(_ s: String) -> Data {
        var bytes: [UInt8] = []
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            if let byte = UInt8(s[index..<next], radix: 16) { bytes.append(byte) }
            index = next
        }
        return Data(bytes)
    }

    /// 統一的「是否可以退出」判斷：
    /// 1. 未設定密碼 → 彈窗說明並拒絕退出（鎖定意圖：不能無密碼退出）。
    /// 2. 彈出密碼驗證窗 → 正確才允許退出；錯誤彈窗提示並拒絕。
    static func shouldAllowQuit(appName: String,
                                hasConfigured: Bool,
                                verifier: (String) -> Bool,
                                notConfiguredHint: String) -> Bool {
        guard hasConfigured else {
            let alert = NSAlert()
            alert.messageText = "無法退出"
            alert.informativeText = notConfiguredHint
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
            return false
        }
        return verifyWithPrompt(appName: appName, verifier: verifier)
    }

    /// 彈出「輸入密碼以退出」視窗。
    static func verifyWithPrompt(appName: String, verifier: (String) -> Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = "需要密碼才能退出"
        alert.informativeText = "「\(appName)」已啟用退出保護。\n請輸入密碼以允許退出。"
        alert.alertStyle = .warning
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "退出密碼"
        alert.accessoryView = field
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let ok = verifier(field.stringValue)
        if !ok {
            let err = NSAlert()
            err.messageText = "密碼錯誤"
            err.informativeText = "無法退出。請再試一次。"
            err.alertStyle = .critical
            err.addButton(withTitle: "好")
            err.runModal()
        }
        return ok
    }

    enum QuitError: Swift.Error {
        case weakPassword
        case oldPasswordMismatch
    }
}
#endif
