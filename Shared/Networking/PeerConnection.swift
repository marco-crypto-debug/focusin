import Foundation
import Network

/// 一條 WebSocket 連線。應用程式層訊息統一為 JSON 編碼的 `CommandMessage`；
/// 屏幕幀封裝在 `streamFrame` 的 payload（base64 JPEG）中。
final class PeerConnection {
    enum Mode { case client, server }

    let connection: NWConnection
    let mode: Mode

    var onStateChange: ((NWConnection.State) -> Void)?
    var onCommand: ((CommandMessage) -> Void)?
    var onConnectionLost: (() -> Void)?
    var onError: ((Error) -> Void)?

    /// 用戶端側：主動連線被發現的教師/學生。
    init(connectTo endpoint: NWEndpoint) {
        self.mode = .client
        self.connection = NWConnection(to: endpoint, using: PeerTransport.webSocketParameters())
    }

    /// 服務端側：包裝監聽器接受的連線。
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

    // MARK: - 接收循環

    private func receiveNext() {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if error == nil {
                if let data, !data.isEmpty {
                    // 校驗該幀確為 WebSocket 訊息後解碼
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
