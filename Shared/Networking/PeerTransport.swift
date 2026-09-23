import Foundation
import Network

/// 网络参数工厂：两端共用一套 NWParameters，默认协议栈最上层挂 WebSocket。
enum PeerTransport {
    /// Bonjour 服务类型（两端共用，同一 Wi-Fi 子网内自动发现）。
    static let serviceType = "_classroom-ctrl._tcp."
    static let defaultPort: UInt16 = 4477

    /// 构建带 WebSocket 应用协议的 NWParameters。
    static func webSocketParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true                       // 协议层自动回 PONG
        parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        parameters.allowLocalEndpointReuse = true
        parameters.serviceClass = .interactiveVideo   // 实时画面 + 命令的低延迟优先级
        return parameters
    }

    static func endpoint(host: String, port: UInt16 = defaultPort) -> NWEndpoint {
        .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
    }
}
