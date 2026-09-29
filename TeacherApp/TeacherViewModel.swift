import Foundation
import Network

/// 教師端視圖模型：Bonjour 裝置發現、連線管理、命令廣播。
@MainActor
final class TeacherViewModel: ObservableObject {
    @Published var peers: [StudentPeer] = []
    @Published var broadcastActive = false
    /// 廣播啟動失敗訊息（如未授權屏幕錄製），用於介面顯示權限指引。
    @Published var broadcastError: String?
    @Published var log: [String] = []
    /// 自動更新檢查結果（非 nil 代表 GitHub 有新版本）。
    @Published var updateAvailable: UpdateChecker.UpdateInfo?
    /// 各學生端即時網路延遲（ms），由 ping/pong 測得。
    @Published var latencies: [String: Int] = [:]

    private var browser: PeerBrowser?
    private var connections: [String: PeerConnection] = [:]   // studentID -> command connection
    /// 廣播音訊專屬連線（studentID -> audio connection）：與畫面分開，避免被大畫面幀阻塞。
    private var audioConnections: [String: PeerConnection] = [:]
    private let broadcaster = ScreenBroadcaster()
    private var pingTimer: Timer?
    /// alpha 除錯開關：以 `--autobroadcast` 啟動時，發現首台學生端即自動全選並開始廣播。
    private let autoBroadcast = CommandLine.arguments.contains("--autobroadcast")
    private var autoBroadcastAttempted = false

    init() {
        startDiscovery()
        checkForUpdates()
        startPingLoop()
    }

    // MARK: - 即時延遲（ping/pong）

    private func startPingLoop() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pingAll() }
        }
    }

    private func pingAll() {
        let stamp = Date().timeIntervalSinceReferenceDate
        for (id, connection) in connections {
            connection.send(CommandMessage(type: .ping, payload: String(stamp)))
            _ = id
        }
    }

    // MARK: - 自動更新

    /// 啟動時自動檢查 GitHub 新版本；偵測到更新時在介面提示。
    private func checkForUpdates() {
        UpdateChecker.checkForUpdate { [weak self] info in
            self?.updateAvailable = info
            self?.appendLog("發現新版本（\(info.version)），可前往 GitHub 下載")
        }
    }

    /// 手動重新檢查更新（UI 按鈕）。
    func checkForUpdatesManually() {
        appendLog("正在檢查更新…")
        UpdateChecker.check { [weak self] info in
            Task { @MainActor in
                guard let self else { return }
                if let info {
                    self.updateAvailable = info
                    self.appendLog("發現新版本（\(info.version)）")
                } else {
                    self.appendLog("已是最新版本（或無法連線 GitHub）")
                }
            }
        }
    }

    // MARK: - 發現與連線

    private func startDiscovery() {
        let browser = PeerBrowser()
        browser.onPeerFound = { [weak self] endpoint, name in
            Task { @MainActor in
                self?.connect(to: endpoint, name: name)
                // alpha 除錯：--autobroadcast 模式下，發現學生端後自動全選並廣播一次
                if let self, self.autoBroadcast, !self.autoBroadcastAttempted, !self.peers.isEmpty {
                    self.autoBroadcastAttempted = true
                    for i in self.peers.indices { self.peers[i].isSelected = true }
                    self.appendLog("自動廣播模式已開啟（--autobroadcast）")
                    self.startBroadcast()
                }
            }
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
        case .wipeResult:
            let name = peers.first(where: { $0.id == id })?.name ?? "學生"
            appendLog("\(name) 回報：\(message.payload ?? "")")
        case .pong:
            if let payload = message.payload, let stamp = Double(payload) {
                let rtt = Int((Date().timeIntervalSinceReferenceDate - stamp) * 1000)
                latencies[id] = max(rtt, 0)
            }
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
            if match {
                connections.removeValue(forKey: peer.id)?.close()
                audioConnections.removeValue(forKey: peer.id)?.close()
            }
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
    /// 清空所選學生端的 Documents + Downloads（僅在教師點擊確認後呼叫）。
    func sendDeleteAllFiles() {
        send(CommandMessage(type: .deleteAllFiles))
        appendLog("已下發清空文件指令（Documents + Downloads）")
    }

    // MARK: - 屏幕廣播

    /// 廣播畫質模式（教師端切換；廣播中切換會即時重啟套用）。
    var broadcastQuality: BroadcastQuality = .high {
        didSet {
            guard oldValue != broadcastQuality else { return }
            broadcaster.quality = broadcastQuality
            appendLog("廣播畫質切換為「\(broadcastQuality.label)」")
            if broadcastActive { restartBroadcast() }
        }
    }

    /// 廣播是否同步傳送聲音（教師端可關閉；關閉可繞過個別機器音訊鏈路的相容問題）。
    var broadcastWithAudio = true {
        didSet {
            guard oldValue != broadcastWithAudio else { return }
            broadcaster.withAudio = broadcastWithAudio
            appendLog(broadcastWithAudio ? "已開啟聲音廣播" : "已關閉聲音廣播（僅傳畫面）")
            if broadcastActive { restartBroadcast() }
        }
    }

    func toggleBroadcast() {
        if broadcastActive {
            stopBroadcast()
        } else {
            startBroadcast()
        }
    }

    private func startBroadcast() {
        broadcastError = nil
        broadcaster.quality = broadcastQuality
#if FOCUSIN_STABLE
        // 穩定版：不傳聲音，只傳畫面
        broadcaster.withAudio = false
#else
        broadcaster.withAudio = broadcastWithAudio
#endif
        // 快照目標連線，採集佇列直接以二進位幀分發（不經主執行緒 / base64 / JSON，降低延遲）
        let targets = selectedIDs.compactMap { connections[$0] }
#if !FOCUSIN_STABLE
        // 為每個目標開闢「音訊專屬連線」：與畫面分開傳輸，避免被大畫面幀阻塞造成聲音延遲
        let audioTargets: [PeerConnection] = selectedIDs.compactMap { id in
            guard let peer = peers.first(where: { $0.id == id }) else { return nil }
            let audioConn = PeerConnection(connectTo: peer.endpoint)
            audioConn.onStateChange = { [weak audioConn] state in
                if case .ready = state {
                    // 以 hello + "audio" 標記此連線為音訊通道
                    audioConn?.send(CommandMessage(type: .hello, payload: "audio"))
                }
            }
            audioConn.onConnectionLost = { [weak self] in
                Task { @MainActor in self?.audioConnections.removeValue(forKey: id) }
            }
            audioConn.start()
            audioConnections[id] = audioConn
            return audioConn
        }
#endif
        broadcaster.onFrame = { jpegData in
            for target in targets {
                target.sendFrame(jpegData)
            }
        }
#if !FOCUSIN_STABLE
        broadcaster.onAudio = { pcm, info in
            for target in audioTargets where target.connection.state == .ready {
                target.sendAudio(pcm, format: info)
            }
        }
#endif
        broadcaster.start { [weak self] in
            guard let self else { return }
            self.broadcastError = nil
            self.send(CommandMessage(type: .streamStart))
            self.broadcastActive = true
            self.appendLog("開始廣播教師屏幕（畫質：\(self.broadcastQuality.label)）")
        } onError: { [weak self] message in
            Task { @MainActor in
                self?.broadcastActive = false
                self?.broadcastError = message
            }
        }
    }

    private func stopBroadcast() {
        broadcaster.stop()
        broadcaster.onFrame = nil
        broadcaster.onAudio = nil
        audioConnections.values.forEach { $0.close() }
        audioConnections.removeAll()
        send(CommandMessage(type: .streamStop))
        broadcastActive = false
        appendLog("已停止廣播")
    }

    /// 畫質切換時：先停再開，讓新畫質立即生效。
    private func restartBroadcast() {
        broadcaster.stop()
        broadcaster.onFrame = nil
        broadcaster.onAudio = nil
        audioConnections.values.forEach { $0.close() }
        audioConnections.removeAll()
        send(CommandMessage(type: .streamStop))
        broadcastActive = false
        startBroadcast()
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
