import Foundation
import Network

/// 一条 WebSocket 连接。应用层消息统一为 JSON 编码的 `CommandMessage`；
/// 屏幕帧封装在 `streamFrame` 的 payload（base64 JPEG）中。
final class PeerConnection {
    enum Mode { case client, server }

    let connection: NWConnection
    let mode: Mode

    var onStateChange: ((NWConnection.State) -> Void)?
    var onCommand: ((CommandMessage) -> Void)?
    var onConnectionLost: (() -> Void)?
    var onError: ((Error) -> Void)?

    /// 客户端侧：主动连接被发现的教师/学生。
    init(connectTo endpoint: NWEndpoint) {
        self.mode = .client
        self.connection = NWConnection(to: endpoint, using: PeerTransport.webSocketParameters())
    }

    /// 服务端侧：包装监听器接受的连接。
    init(accepted connection: NWConnection) {
        self.mode = .server
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async { self?.onStateChange?(state) }
            if case .failed = state {
                DispatchQueue.main.async { self?.onConnectionLost?() }
            }
            if case .cancelled = state {
                DispatchQueue.main.async { self?.onConnectionLost?() }
            }
        }
        connection.start(queue: .global(qos: .utility))
        receiveNext()
    }

    func close() {
        connection.cancel()
    }

    func send(_ message: CommandMessage) {
        guard let data = message.encoded() else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "command", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true,
                        completion: .contentProcessed { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.onError?(error) }
            }
        })
    }

    // MARK: - 接收循环

    private func receiveNext() {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if error == nil {
                if let data, !data.isEmpty {
                    // 校验该帧确为 WebSocket 消息后解码
                    let isWebSocketFrame =
                        (context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                            as? NWProtocolWebSocket.Metadata) != nil
                    if isWebSocketFrame, let message = CommandMessage.decode(data) {
                        DispatchQueue.main.async { self.onCommand?(message) }
                    }
                }
                self.receiveNext()
            } else {
                DispatchQueue.main.async { self.onConnectionLost?() }
            }
        }
    }
}
