import Foundation
import Network

/// 一條 WebSocket 連線。應用程式層命令統一為 JSON 編碼的 `CommandMessage`；
/// 屏幕幀走獨立二進位通道（4 位元組魔數 `FZFR` + 原始 JPEG），音訊另走 `FZAU` 通道，
/// 兩者皆跳過 base64/JSON 以降低延遲。
final class PeerConnection {
    enum Mode { case client, server }

    /// 廣播幀魔數：`FZFR`（FocusIn FRame），用於區分原始幀與 JSON 命令。
    static let frameMagic: [UInt8] = [0x46, 0x5A, 0x46, 0x52]
    /// 音訊幀魔數：`FZAU`（FocusIn AUdio），後接 10 位元組格式標頭 + PCM。
    static let audioMagic: [UInt8] = [0x46, 0x5A, 0x41, 0x55]

    /// 音訊格式標頭（14 位元組）：magic(4) + sampleRate(4, UInt32 LE) + channels(1) + bits(1) + isFloat(1) + interleaved(1) + reserved(2)。
    struct AudioFormatInfo {
        var sampleRate: Double
        var channels: UInt32
        var bits: UInt8
        var isFloat: Bool
        var interleaved: Bool
    }

    let connection: NWConnection
    let mode: Mode

    var onStateChange: ((NWConnection.State) -> Void)?
    var onCommand: ((CommandMessage) -> Void)?
    /// 收到原始廣播幀（JPEG 資料），在背景佇列觸發。
    var onFrame: ((Data) -> Void)?
    /// 收到廣播音訊（PCM 資料 + 格式），在背景佇列觸發。
    var onAudio: ((Data, AudioFormatInfo) -> Void)?
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
            self?.sendLock.lock()
            self?.frameSendBusy = false
            self?.sendLock.unlock()
        })
    }

    /// 發送一段廣播音訊（PCM + 格式標頭）。
    /// 音訊不節流：聲音中斷比延遲更明顯，逐緩衝區直送。
    func sendAudio(_ pcm: Data, format: AudioFormatInfo) {
        var payload = Data(Self.audioMagic)
        var sr = UInt32(format.sampleRate.rounded()).littleEndian
        payload.append(Data(bytes: &sr, count: 4))
        payload.append(UInt8(format.channels))
        payload.append(format.bits)
        payload.append(format.isFloat ? 1 : 0)
        payload.append(format.interleaved ? 1 : 0)
        payload.append(0)   // reserved
        payload.append(0)   // reserved
        payload.append(pcm)
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "audio", metadata: [metadata])
        connection.send(content: payload, contentContext: context, isComplete: true,
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
                    // 1) 原始廣播幀（魔數 FZFR 開頭）：直接交回呼，背景佇列解碼
                    if data.count > 4 && data.prefix(4).elementsEqual(Self.frameMagic) {
                        let jpeg = data.subdata(in: 4..<data.count)
                        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                            self?.onFrame?(jpeg)
                        }
                    } else if data.count > 14 && data.prefix(4).elementsEqual(Self.audioMagic) {
                        // 2) 廣播音訊（魔數 FZAU 開頭）：解析格式標頭後交回呼
                        var sr: UInt32 = 0
                        data.subdata(in: 4..<8).withUnsafeBytes { sr = $0.loadUnaligned(as: UInt32.self) }
                        let info = AudioFormatInfo(sampleRate: Double(UInt32(littleEndian: sr)),
                                                   channels: UInt32(data[8]),
                                                   bits: data[9],
                                                   isFloat: data[10] == 1,
                                                   interleaved: data[11] == 1)
                        let pcm = data.subdata(in: 14..<data.count)
                        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                            self?.onAudio?(pcm, info)
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
