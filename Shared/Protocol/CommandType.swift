import Foundation

/// 教師端與學生端之間交換的命令類型。
/// 所有訊息均為 JSON 編碼的 `CommandMessage`，透過 WebSocket 二進位幀傳輸。
enum CommandType: String, Codable {
    // —— 握手 ——
    case hello          // 學生端 → 教師端：自我介紹（攜帶裝置名稱）
    case helloAck       // 教師端 → 學生端：確認連線

    // —— 控制 ——
    case lock           // 鎖定（進入 Kiosk）
    case unlock         // 解鎖（退出 Kiosk）
    case shutdown       // 遠端關機
    case restart        // 遠端重新啟動
    case launchApp      // 啟動應用程式，payload = Bundle Identifier（如 "com.apple.Safari"）

    // —— 屏幕廣播 ——
    case streamStart    // 教師端開始廣播
    case streamFrame    // 一幀畫面，payload = base64 JPEG
    case streamStop     // 教師端停止廣播

    // —— 保活 ——
    case ping
    case pong
}
