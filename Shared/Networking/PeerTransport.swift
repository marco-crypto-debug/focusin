import Foundation
import Network

/// 網路參數工廠：兩端共用同一套 NWParameters，預設協定棧最上層掛載 WebSocket。
enum PeerTransport {
    /// Bonjour 服務類型（兩端共用，同一 Wi-Fi 子網路內自動發現）。
    static let serviceType = "_classroom-ctrl._tcp."
    static let defaultPort: UInt16 = 4477

    /// 構建帶 WebSocket 應用程式協定的 NWParameters。
    static func webSocketParameters() -> NWParameters {
        // 自訂 TCP：關閉 Nagle 演算法（TCP_NODELAY），降低小包與命令的傳輸延遲
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true                       // 協定層自動回覆 PONG
        parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        parameters.allowLocalEndpointReuse = true
        parameters.serviceClass = .interactiveVideo   // 即時畫面 + 命令的低延遲優先級
        return parameters
    }

    static func endpoint(host: String, port: UInt16 = defaultPort) -> NWEndpoint {
        .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
    }
}
