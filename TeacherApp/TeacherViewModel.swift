import Foundation
import Network

/// 教師端視圖模型：Bonjour 裝置發現、連線管理、命令廣播。
@MainActor
final class TeacherViewModel: ObservableObject {
    @Published var peers: [StudentPeer] = []
    @Published var broadcastActive = false
    @Published var log: [String] = []

    private var browser: PeerBrowser?
    private var connections: [String: PeerConnection] = [:]   // studentID -> connection
    private let broadcaster = ScreenBroadcaster()

    init() {
        broadcaster.onFrame = { [weak self] jpegData in
            Task { @MainActor in
                self?.send(CommandMessage(type: .streamFrame,
                                          payload: jpegData.base64EncodedString()))
            }
        }
        startDiscovery()
    }

    // MARK: - 發現與連線

    private func startDiscovery() {
        let browser = PeerBrowser()
        browser.onPeerFound = { [weak self] endpoint, name in
            Task { @MainActor in self?.connect(to: endpoint, name: name) }
        }
        browser.onPeerLost = { [weak self] endpoint in
            Task { @MainActor in self?.dropPeer(matching: endpoint) }
        }
        browser.start()
        self.browser = browser
        appendLog("正在搜索學生端（\(PeerTransport.serviceType)）…")
    }

    private func connect(to endpoint: NWEndpoint, name: String) {
        // 防止同一學生重複入列
        let endpointKey = endpoint.debugDescription
        guard !peers.contains(where: { $0.endpoint.debugDescription == endpointKey }) else { return }

        let connection = PeerConnection(connectTo: endpoint)
        let id = UUID().uuidString
        connection.onCommand = { [weak self] message in
            Task { @MainActor in self?.handle(message, from: id) }
        }
        connection.onConnectionLost = { [weak self] in
            Task { @MainActor in self?.dropPeer(id: id) }
        }
        connection.start()
        connections[id] = connection
        peers.append(StudentPeer(id: id, name: name, endpoint: endpoint, isSelected: false))
    }

    private func handle(_ message: CommandMessage, from id: String) {
        switch message.type {
        case .hello:
            if let idx = peers.firstIndex(where: { $0.id == id }) {
                peers[idx].name = message.senderName
                appendLog("學生上線: \(message.senderName)")
            }
            send(CommandMessage(type: .helloAck), to: [id])
        default:
            break
        }
    }

    private func dropPeer(matching endpoint: NWEndpoint) {
        dropPeer(id: nil, endpointKey: endpoint.debugDescription)
    }

    private func dropPeer(id: String? = nil, endpointKey: String? = nil) {
        peers.removeAll { peer in
            let match = (id != nil && peer.id == id)
                || (endpointKey != nil && peer.endpoint.debugDescription == endpointKey)
            if match { connections.removeValue(forKey: peer.id) }
            return match
        }
        appendLog("學生已離線")
    }

    // MARK: - 命令下發

    var selectedIDs: [String] {
        peers.filter(\.isSelected).map(\.id)
    }

    func send(_ message: CommandMessage, to ids: [String]? = nil) {
        let targets = ids ?? selectedIDs
        for id in targets {
            connections[id]?.send(message)
        }
    }

    func sendLock() { send(CommandMessage(type: .lock)) }
    func sendUnlock() { send(CommandMessage(type: .unlock)) }
    func sendShutdown() { send(CommandMessage(type: .shutdown)) }
    func sendRestart() { send(CommandMessage(type: .restart)) }
    func sendLaunchApp(bundleID: String) {
        send(CommandMessage(type: .launchApp, payload: bundleID))
    }

    // MARK: - 屏幕廣播

    func toggleBroadcast() {
        if broadcastActive {
            broadcaster.stop()
            send(CommandMessage(type: .streamStop))
            broadcastActive = false
            appendLog("已停止廣播")
        } else {
            broadcaster.start { [weak self] in
                guard let self else { return }
                self.send(CommandMessage(type: .streamStart))
                self.broadcastActive = true
                self.appendLog("開始廣播教師屏幕")
            }
        }
    }

    private func appendLog(_ text: String) { log.append(text) }
}

/// 一台已發現的學生裝置。
struct StudentPeer: Identifiable {
    let id: String
    var name: String
    let endpoint: NWEndpoint
    var isSelected: Bool
}
