import Foundation

/// 端到端传输的统一消息信封。
struct CommandMessage: Codable, Equatable {
    let type: CommandType
    let senderID: String
    let senderName: String
    let payload: String?      // 命令附带的 JSON 字符串或 base64 数据
    let timestamp: Date

    init(type: CommandType,
         senderID: String = "",
         senderName: String = "",
         payload: String? = nil,
         timestamp: Date = Date()) {
        self.type = type
        self.senderID = senderID
        self.senderName = senderName
        self.payload = payload
        self.timestamp = timestamp
    }

    static func decode(_ data: Data) -> CommandMessage? {
        try? JSONDecoder().decode(CommandMessage.self, from: data)
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
