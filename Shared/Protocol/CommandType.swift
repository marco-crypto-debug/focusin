import Foundation

/// 教师在教师端与学生端之间交换的命令类型。
/// 所有消息均为 JSON 编码的 `CommandMessage`，通过 WebSocket 二进制帧传输。
enum CommandType: String, Codable {
    // —— 握手 ——
    case hello          // 学生端 → 教师端：自我介绍（携带设备名）
    case helloAck       // 教师端 → 学生端：确认连接

    // —— 控制 ——
    case lock           // 锁定（进入 Kiosk）
    case unlock         // 解锁（退出 Kiosk）
    case shutdown       // 远程关机
    case restart        // 远程重启
    case launchApp      // 启动应用，payload = Bundle Identifier（如 "com.apple.Safari"）

    // —— 屏幕广播 ——
    case streamStart    // 教师端开始广播
    case streamFrame    // 一帧画面，payload = base64 JPEG
    case streamStop     // 教师端停止广播

    // —— 保活 ——
    case ping
    case pong
}
