import Foundation
import Network

/// 一條 WebSocket 連線。應用程式層命令統一為 JSON 編碼的 `CommandMessage`；
/// 屏幕幀走獨立二進位通道（4 位元組魔數 `FZFR` + 原始 JPEG），跳過 base64/JSON 以降低延遲。
final class PeerConnection {
    enum Mode { case client, server }

    /// 廣播幀魔數：`FZFR`（FocusIn FRame），用於區分原始幀與 JSON 命令。
    static let frameMagic: [UInt8] = [0x46, 0x5A, 0x46, 0x52]

    let connection: NWConnection
    let mode: Mode

    var onStateChange: ((NWConnection.State) -> Void)?
    var onCommand: ((CommandMessage) -> Void)?
    /// 收到原始廣播幀（JPEG 資料），在背景佇列觸發。
    var onFrame: ((Data) -> Void)?
    var onConnectionLost: (() -> Void)?
    var onError: ((Error) -> Void)?

    /// 幀傳送忙碌旗標：同時間只允許一幀在途，其餘丟棄，避免延遲堆積。
    private var frameSendBusy = false
    private let sendLock = NSLock()

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

    /// 發送一幀原始 JPEG（低延遲路徑）。
    /// 若上一幀尚未發送完成則直接丟棄本幀，避免接收端畫面延遲不斷堆積。
    func sendFrame(_ jpegData: Data) {
        sendLock.lock()
        guard !frameSendBusy else {
            sendLock.unlock()
            return
        }
        frameSendBusy = true
        sendLock.unlock()

        var payload = Data(Self.frameMagic)
        payload.append(jpegData)
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
        connection.send(content: payload, contentContext: context, isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
            self?.frameSendBusy = false
        })
    }

    // MARK: - 接收循環

    private func receiveNext() {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if error == nil {
                if let data, !data.isEmpty {
                    // 1) 原始廣播幀（魔數 FZFR 開頭）：直接交回呼，背景佇列解碼
                    if data.count > 4 && data.prefix(4).elementsEqual(Self.frameMagic) {
                        let jpeg = data.subdata(in: 4..<data.count)
                        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                            self?.onFrame?(jpeg)
                        }
                    } else {
                        // 2) JSON 命令
                        let isWebSocketFrame =
                            (context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                                as? NWProtocolWebSocket.Metadata) != nil
                        if isWebSocketFrame, let message = CommandMessage.decode(data) {
                            DispatchQueue.main.async { self.onCommand?(message) }
                        }
                    }
                }
                self.receiveNext()
            } else {
                DispatchQueue.main.async { self.onConnectionLost?() }
            }
        }
    }
}
