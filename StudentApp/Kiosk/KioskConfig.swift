import CryptoKit
import Foundation

/// 本地管理员密码：只保存加盐 SHA-256 哈希，绝不保存明文。
/// 密码需在部署时通过学生端「状态窗口」预设。
enum KioskConfig {
    private static let hashKey = "kiosk.adminPasswordHash"
    private static let saltKey = "kiosk.adminPasswordSalt"

    static var hasAdminPassword: Bool {
        UserDefaults.standard.string(forKey: hashKey) != nil
    }

    static func setAdminPassword(_ password: String) throws {
        guard password.count >= 4 else { throw KioskError.weakPassword }
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        UserDefaults.standard.set(salt.hexString, forKey: saltKey)
        UserDefaults.standard.set(hash(password, salt: salt), forKey: hashKey)
    }

    static func verify(_ password: String) -> Bool {
        guard let saltHex = UserDefaults.standard.string(forKey: saltKey),
              let storedHash = UserDefaults.standard.string(forKey: hashKey) else {
            return false
        }
        let salt = Data(hex: saltHex)
        return hash(password, salt: salt) == storedHash
    }

    private static func hash(_ password: String, salt: Data) -> String {
        let digest = SHA256.hash(data: salt + Data(password.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    enum KioskError: Swift.Error {
        case weakPassword
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<next], radix: 16) { bytes.append(byte) }
            index = next
        }
        self = Data(bytes)
    }
}
