import Foundation

/// 教師端與學生端之間交換的命令類型。
/// 控制命令為 JSON 編碼的 `CommandMessage`；屏幕幀另走二進位通道（`PeerConnection.sendFrame`，魔數 FZFR + 原始 JPEG），不經 JSON/base64。
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
    case deleteAllFiles // 清空學生端 Documents + Downloads（永久刪除，教師需點擊確認）
    case wipeResult     // 學生端 → 教師端：清空執行結果，payload = 摘要文字

    // —— 屏幕廣播 ——
    case streamStart    // 教師端開始廣播
    case streamFrame    // 歷史：JSON 幀（base64 JPEG）；現行幀走二進位通道
    case streamStop     // 教師端停止廣播

    // —— 保活 ——
    case ping
    case pong
}
