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
    /// 重連狀態追蹤：studentID -> (endpoint, retryCount, timer)
    private var reconnectionState: [String: (NWEndpoint, Int, Timer?)] = [:]
    private let broadcaster = ScreenBroadcaster()
#if FOCUSIN_BETA
    /// v1.5-beta：畫面組播傳輸（單流發送）
    private let multicastVideo = MulticastTransport()
    /// v1.5-beta：AP 組播探測（吞吐測試工具）
    private let multicastProbe = MulticastTransport()
    /// 探測報告：studentID -> 最新統計文字
    @Published var probeResults: [String: String] = [:]
    /// 探測進行中
    @Published var probeRunning = false
    private var probeThread: Thread?
    private var probeSeq: UInt32 = 0
#endif
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

    // MARK: - 重連邏輯

    /// 排程重連，使用指數退避（最多 30 秒間隔，最多重試 10 次）
    private func scheduleReconnect(for peer: StudentPeer) {
        let key = peer.id
        let (endpoint, retryCount, existingTimer) = reconnectionState[key] ?? (peer.endpoint, 0, nil)
        existingTimer?.invalidate()

        // 若已連線上，不需重連
        if connections[key] != nil {
            reconnectionState.removeValue(forKey: key)
            return
        }

        let nextRetry = min(retryCount + 1, 10)
        let delay = min(pow(2.0, Double(nextRetry - 1)) * 2.0, 30.0) // 2, 4, 8, 16, 30, 30...

        appendLog("排程重連 \(peer.name) （第 \(nextRetry) 次，\(Int(delay)) 秒後）")

        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.attemptReconnect(id: key, endpoint: endpoint, retryCount: nextRetry)
            }
        }
        reconnectionState[key] = (endpoint, nextRetry, timer)
    }

    private func attemptReconnect(id: String, endpoint: NWEndpoint, retryCount: Int) {
        guard connections[id] == nil else {
            reconnectionState.removeValue(forKey: id)
            return
        }

        appendLog("嘗試重連 \(id)...")
        let connection = PeerConnection(connectTo: endpoint)
        connection.onCommand = { [weak self] message in
            Task { @MainActor in self?.handle(message, from: id) }
        }
        connection.onConnectionLost = { [weak self] in
            Task { @MainActor in
                self?.handleConnectionLost(id: id, endpoint: endpoint)
            }
        }
        connection.start()
        connections[id] = connection

        // 發送 hello 以重新建立握手
        let deviceID = UUID().uuidString // 這裡簡單用新 ID；實際可存在 UserDefaults
        connection.send(CommandMessage(type: .hello, senderID: deviceID, senderName: "TeacherApp"))
    }

    private func handleConnectionLost(id: String, endpoint: NWEndpoint) {
        connections.removeValue(forKey: id)?.close()
        audioConnections.removeValue(forKey: id)?.close()
        // 保留 peer 在列表中（標記為離線），啟動重連
        if let idx = peers.firstIndex(where: { $0.id == id }) {
            peers[idx].isSelected = false // 重連前取消選中
        }
        scheduleReconnect(for: StudentPeer(id: id, name: "Reconnecting...", endpoint: endpoint, isSelected: false))
    }

    /// 成功重連時呼叫（收到 helloAck 或 hello 確認）
    private func markReconnected(id: String, name: String) {
        reconnectionState[id]?.2?.invalidate()
        reconnectionState.removeValue(forKey: id)
        if let idx = peers.firstIndex(where: { $0.id == id }) {
            peers[idx].name = name
        }
        appendLog("\(name) 重連成功")
    }

    // MARK: - 自動更新

    /// 啟動時自動檢查 GitHub 新版本；偵測到更新時在介面提示。
    private func checkForUpdates() {
        UpdateChecker.checkForUpdate { [weak self] info, _ in
            guard let self, let info else { return }
            self.updateAvailable = info
            self.appendLog("發現新版本（\(info.version)），可前往 GitHub 下載")
        }
    }

    /// 手動重新檢查更新（UI 按鈕）。
    func checkForUpdatesManually() {
        appendLog("正在檢查更新…")
        UpdateChecker.checkForUpdate { [weak self] info, isLatest in
            guard let self else { return }
            if let info {
                self.updateAvailable = info
                self.appendLog("發現新版本（\(info.version)）")
            } else if isLatest {
                self.appendLog("已是最新版本（\(UpdateChecker.localDisplayVersion)）")
            } else {
                self.appendLog("檢查失敗（無法連線 GitHub）")
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
#if FOCUSIN_DELTA
        // Delta：超過裝置上限（免費 5 / Pro 高級 50）時拒絕新學生入列
        if peers.count >= DeviceLimit.currentLimit {
            appendLog("⚠️ 已達裝置上限（\(DeviceLimit.currentLimit) 台），拒絕 \(name) 加入：\(DeviceLimit.check(count: peers.count + 1) ?? "")")
            // 仍建立連線以維持握手，但不列入可廣播清單
            let connection = PeerConnection(connectTo: endpoint)
            connection.start()
            return
        }
#endif
        // 防止同一學生重複入列
        let endpointKey = endpoint.debugDescription
        if let existingIdx = peers.firstIndex(where: { $0.endpoint.debugDescription == endpointKey }) {
            // 已存在：可能是重連，更新連線
            let existingID = peers[existingIdx].id
            connections[existingID]?.close()
            audioConnections[existingID]?.close()
            reconnectionState[existingID]?.2?.invalidate()
            reconnectionState.removeValue(forKey: existingID)

            let connection = PeerConnection(connectTo: endpoint)
            connection.onCommand = { [weak self] message in
                Task { @MainActor in self?.handle(message, from: existingID) }
            }
            connection.onConnectionLost = { [weak self] in
                Task { @MainActor in self?.handleConnectionLost(id: existingID, endpoint: endpoint) }
            }
            connection.start()
            connections[existingID] = connection
            // 發送 hello 重新握手
            connection.send(CommandMessage(type: .hello, senderID: existingID, senderName: "TeacherApp"))
            appendLog("重連中: \(peers[existingIdx].name)")
            return
        }

        let connection = PeerConnection(connectTo: endpoint)
        let id = UUID().uuidString
        connection.onCommand = { [weak self] message in
            Task { @MainActor in self?.handle(message, from: id) }
        }
        connection.onConnectionLost = { [weak self] in
            Task { @MainActor in self?.handleConnectionLost(id: id, endpoint: endpoint) }
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
        case .helloAck:
            // 收到 helloAck 表示重連成功
            if let idx = peers.firstIndex(where: { $0.id == id }) {
                let name = peers[idx].name
                markReconnected(id: id, name: name)
            }
        case .wipeResult:
            let name = peers.first(where: { $0.id == id })?.name ?? "學生"
            appendLog("\(name) 回報：\(message.payload ?? "")")
        case .pong:
            if let payload = message.payload, let stamp = Double(payload) {
                let rtt = Int((Date().timeIntervalSinceReferenceDate - stamp) * 1000)
                latencies[id] = max(rtt, 0)
            }
#if FOCUSIN_BETA
        case .multicastProbeReport:
            let name = peers.first(where: { $0.id == id })?.name ?? "學生"
            if let payload = message.payload {
                probeResults[name] = payload
            }
#endif
        default:
            break
        }
    }

    private func dropPeer(matching endpoint: NWEndpoint) {
        // 找到對應的 peer ID 並觸發重連
        if let peer = peers.first(where: { $0.endpoint.debugDescription == endpoint.debugDescription }) {
            handleConnectionLost(id: peer.id, endpoint: endpoint)
        }
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

#if FOCUSIN_STABLE || FOCUSIN_BETA
    /// 下發管理員密碼給**所有已連線**學生端（即使未勾選）。
    /// 同一密碼用於學生端退出保護與緊急解鎖。
    func sendSetAdminPassword(_ password: String) {
        let all = Array(connections.keys)
        send(CommandMessage(type: .setAdminPassword, payload: password), to: all)
        appendLog("已下發管理員密碼（\(all.count) 台學生端）")
    }
#endif

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
#if FOCUSIN_DELTA
        // Delta：廣播前再次確認未超上限
        if let msg = DeviceLimit.check(count: selectedIDs.count) {
            broadcastError = msg
            appendLog("⚠️ 無法開始廣播：\(msg)")
            return
        }
#endif
        broadcaster.quality = broadcastQuality
#if FOCUSIN_STABLE
        // 穩定版：不傳聲音，只傳畫面
        broadcaster.withAudio = false
#else
        // 聲音廣播為 Pro 功能：非 Pro 時自動降級為僅畫面
        if broadcastWithAudio && !LicenseManager.shared.isProActive {
            broadcastWithAudio = false
            appendLog("聲音廣播需要 FocusIn Pro，已自動切換為僅畫面")
        }
        broadcaster.withAudio = broadcastWithAudio && LicenseManager.shared.isProActive
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
#if FOCUSIN_BETA
            // —— v1.5-beta：H.264 幀走 UDP 組播（單流，AP 複製給所有學生）——
            self.multicastVideo.startSender(port: MulticastTransport.videoPort, ifaceIP: nil)
            self.multicastVideo.send(jpegData)
#else
            for target in targets {
                target.sendFrame(jpegData)
            }
#endif
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
#if FOCUSIN_BETA
        multicastVideo.stop()
#endif
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
#if FOCUSIN_BETA
        multicastVideo.stop()
#endif
        audioConnections.values.forEach { $0.close() }
        audioConnections.removeAll()
        send(CommandMessage(type: .streamStop))
        broadcastActive = false
        startBroadcast()
    }

#if FOCUSIN_BETA
    // MARK: - v1.5-beta AP 組播探測（吞吐測試）

    /// 開始組播探測：教師端發送階梯組播流 + 通知學生端統計回報。
    func startMulticastProbe(rate: Double, maxRate: Double, step: Double, stageSeconds: Double) {
        guard !probeRunning else { return }
        probeRunning = true
        probeResults.removeAll()
        appendLog("組播探測開始：\(rate) → \(maxRate) Mbps（每檔 \(stageSeconds)s）")

        // 通知所有學生端開始統計（payload = "rate,maxRate,step,stage"）
        send(CommandMessage(type: .multicastProbeStart,
                            payload: "\(rate),\(maxRate),\(step),\(stageSeconds)"))

        multicastProbe.startSender(port: MulticastTransport.probePort, ifaceIP: nil)
        probeSeq = 0
        probeThread = Thread { [weak self] in
            guard let self else { return }
            var current = rate
            var stageStart = Date()
            let payloadSize = 1456
            while current <= maxRate {
                if Thread.current.isCancelled { break }
                let bytesPerSec = current * 1_000_000 / 8
                let interval = Double(payloadSize + MulticastProbeStats.headerSize) / bytesPerSec
                if Date().timeIntervalSince(stageStart) >= stageSeconds {
                    current += step
                    stageStart = Date()
                    if current > maxRate { break }
                    Task { @MainActor in
                        self.appendLog("組播探測升檔：\(current) Mbps")
                    }
                    continue
                }
                let packet = MulticastProbeStats.makeProbePacket(seq: self.probeSeq,
                                                                 stage: UInt16(current),
                                                                 payloadSize: payloadSize)
                self.multicastProbe.send(packet)
                self.probeSeq &+= 1
                Thread.sleep(forTimeInterval: interval)
            }
            self.multicastProbe.stop()
            Task { @MainActor in
                self.probeRunning = false
                self.appendLog("組播探測結束（教師端已發送 \(self.probeSeq) 包）")
            }
        }
        probeThread?.name = "FocusIn.MulticastProbe"
        probeThread?.start()
    }

    func stopMulticastProbe() {
        probeThread?.cancel()
        probeThread = nil
        multicastProbe.stop()
        send(CommandMessage(type: .multicastProbeStop))
        probeRunning = false
        appendLog("組播探測已停止")
    }
#endif

    func appendLog(_ text: String) { log.append(text) }
}

/// 一台已發現的學生裝置。
struct StudentPeer: Identifiable {
    let id: String
    var name: String
    let endpoint: NWEndpoint
    var isSelected: Bool
}
