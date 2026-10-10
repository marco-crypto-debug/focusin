import AppKit
import Foundation

/// 學生端核心：公布 Bonjour 服務、接受教師連線、分發命令並觸發本機系統動作。
@MainActor
final class CommandListener: ObservableObject {
    @Published var deviceName: String
    @Published var isLocked = false
    @Published var isBroadcasting = false
    @Published var connectionCount = 0
    @Published var log: [String] = []
    /// 自動更新檢查結果（非 nil 代表 GitHub 有新版本）。
    @Published var updateAvailable: UpdateChecker.UpdateInfo?

    private var advertiser: PeerAdvertiser?
    private var connections: [PeerConnection] = []
#if !FOCUSIN_STABLE
    /// 教師為廣播開闢的「音訊專屬通道」（hello payload = "audio"），不計入教師連線數。
    private var audioPeers: [PeerConnection] = []
    private let kiosk = KioskModeController.shared
    private let audio = BroadcastAudioPlayer()
#else
    private let kiosk = KioskModeController.shared
#endif

    private var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "student.deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "student.deviceID")
        return id
    }

    init() {
        deviceName = Host.current().localizedName ?? "Mac"
        kiosk.onLockStateChanged = { [weak self] locked in
            Task { @MainActor in self?.isLocked = locked }
        }
        kiosk.onLog = { [weak self] msg in
            Task { @MainActor in self?.appendLog(msg) }
        }
        startService()
        checkForUpdates()
    }

    /// 啟動時自動檢查 GitHub 新版本；偵測到更新時在狀態視窗提示。
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

    // MARK: - 服務

    private func startService() {
        do {
            let advertiser = PeerAdvertiser(serviceName: deviceName)
            try advertiser.start { [weak self] rawConnection in
                guard let self else {
                    rawConnection.cancel()
                    return
                }
                let peer = PeerConnection(accepted: rawConnection)
                peer.onCommand = { message in
                    Task { @MainActor in self.handle(message, from: peer) }
                }
                peer.onFrame = { [weak self] frameData in
#if FOCUSIN_DELTA
                    // Delta：單播（普通模式）也走 H.264 硬解，與組播共用解碼器
                    DispatchQueue.global(qos: .userInteractive).async {
                        guard let self,
                              let frame = MulticastTransport.unpackH264Frame(frameData) else { return }
                        self.decodeH264(frame)
                    }
#else
                    // JPEG 解碼較耗時：先在背景佇列解碼，再切回主執行緒更新畫面，避免卡頓
                    DispatchQueue.global(qos: .userInteractive).async {
                        guard let image = NSImage(data: frameData) else { return }
                        Task { @MainActor in
                            self.kiosk.setBroadcastImage(image)
                        }
                    }
#endif
                }
#if !FOCUSIN_STABLE
                peer.onAudio = { pcm, info in
                    Task { @MainActor in
                        self.audio.play(pcm: pcm, format: info)
                    }
                }
#endif
                peer.onConnectionLost = {
                    Task { @MainActor in
#if !FOCUSIN_STABLE
                        if self.audioPeers.contains(where: { $0 === peer }) {
                            self.audioPeers.removeAll { $0 === peer }
                        } else {
                            self.connections.removeAll { $0 === peer }
                            self.connectionCount = self.connections.count
                            self.appendLog("教師連線已中斷")
                        }
#else
                        self.connections.removeAll { $0 === peer }
                        self.connectionCount = self.connections.count
                        self.appendLog("教師連線已中斷")
#endif
                    }
                }
                peer.start()
                Task { @MainActor in
                    self.connections.append(peer)
                    self.connectionCount = self.connections.count
                    // 握手：學生先自我介紹
                    peer.send(CommandMessage(type: .hello,
                                             senderID: self.deviceID,
                                             senderName: self.deviceName))
                    self.appendLog("教師已連線（\(self.connectionCount) 台）")
                }
            }
            self.advertiser = advertiser
            appendLog("正在監聽 \(PeerTransport.serviceType)")
        } catch {
            appendLog("公布服務啟動失敗: \(error)")
        }
    }

    // MARK: - 命令分發

    private func handle(_ message: CommandMessage, from peer: PeerConnection) {
        switch message.type {
        case .hello:
            // 教師端開闢音訊專屬通道：hello + "audio"，移出常規連線計數，僅用於廣播音訊
            if message.payload == "audio" {
#if !FOCUSIN_STABLE
                connections.removeAll { $0 === peer }
                connectionCount = connections.count
                if !audioPeers.contains(where: { $0 === peer }) {
                    audioPeers.append(peer)
                }
                appendLog("音訊通道已建立")
#endif
            } else {
                appendLog("收到握手（教師）")
                peer.send(CommandMessage(type: .helloAck))
            }

        case .helloAck:
            break

        case .ping:
            // 即時延遲測量：原樣回傳時間戳
            peer.send(CommandMessage(type: .pong, payload: message.payload))

        case .lock:
            appendLog("收到鎖定指令")
            kiosk.enterKiosk()

        case .unlock:
            appendLog("收到解鎖指令")
            kiosk.exitKiosk()

        case .shutdown:
            appendLog("收到關機指令")
            runSystemEventScript("tell application \"System Events\" to shut down")

        case .restart:
            appendLog("收到重新啟動指令")
            runSystemEventScript("tell application \"System Events\" to restart")

        case .launchApp:
            if let bundleID = message.payload {
                launchApp(bundleID: bundleID)
            }

        case .deleteAllFiles:
            appendLog("收到清空文件指令（Documents + Downloads）")
            let result = FileWipeManager.wipeUserFolders()
            appendLog(result)
            peer.send(CommandMessage(type: .wipeResult, senderID: deviceID, senderName: deviceName, payload: result))

#if FOCUSIN_STABLE || FOCUSIN_BETA
        case .setAdminPassword:
            if let password = message.payload {
                do {
                    try KioskConfig.setAdminPasswordFromTeacher(password)
                    appendLog("已接收教師端下發的管理員密碼")
                } catch {
                    appendLog("管理員密碼設定失敗：密碼需至少 4 字元")
                }
            }
#endif

        case .wipeResult:
            break   // 教師端使用

        case .streamStart:
            isBroadcasting = true
            kiosk.clearBroadcastImage()
#if FOCUSIN_DELTA
            // Delta：教師端 payload 標記通道——"multicast" 高級(組播) / "unicast" 普通(單播)
            if message.payload == "multicast" {
                startMulticastVideo()
            } else {
                startUnicastVideo()
            }
#elseif FOCUSIN_BETA
            startMulticastVideo()
#else
            audio.start()
#endif

        // 廣播幀改走二進位通道（PeerConnection.onFrame），此處不再處理 JSON 幀
        case .streamFrame:
            break

        case .streamStop:
            isBroadcasting = false
            kiosk.clearBroadcastImage()
#if FOCUSIN_DELTA
            stopUnicastVideo()
            stopMulticastVideo()
#elseif FOCUSIN_BETA
            stopMulticastVideo()
#else
            audio.stop()
#endif

#if FOCUSIN_BETA
        // —— v1.5-beta：AP 組播探測 ——
        case .multicastProbeStart:
            startMulticastProbe(params: message.payload)
        case .multicastProbeReport:
            break   // 教師端使用
        case .multicastProbeStop:
            stopMulticastProbe()
#endif

        default:
            break
        }
    }

#if FOCUSIN_BETA
    // MARK: - v1.5-beta 組播畫面接收

    private let multicastVideo = MulticastTransport()
    private let h264Decoder = H264Decoder()
    private var hasDecodedFrame = false

    private func startMulticastVideo() {
        multicastVideo.stop()
        hasDecodedFrame = false
        h264Decoder.start { [weak self] pixelBuffer in
            // 背景佇列：pixel buffer → NSImage → 主執行緒更新畫面
            let image = Self.image(from: pixelBuffer)
            guard let image else { return }
            Task { @MainActor in
                self?.kiosk.setBroadcastImage(image)
            }
        }
        multicastVideo.startReceiver(port: MulticastTransport.videoPort, ifaceIP: nil) { [weak self] data in
            guard let self,
                  let frame = MulticastTransport.unpackH264Frame(data) else { return }
            // 過濾：尚未解出第一幀前只接受關鍵幀（快速同步）
            if !self.hasDecodedFrame && !frame.key { return }
            self.hasDecodedFrame = true
            self.h264Decoder.decode(frame.annexB, isKeyframe: frame.key,
                                    sps: frame.sps, pps: frame.pps)
        }
        appendLog("Beta 組播畫面接收已啟動（\(MulticastTransport.group):\(MulticastTransport.videoPort)）")
    }

    private func stopMulticastVideo() {
        multicastVideo.stop()
        h264Decoder.stop()
        hasDecodedFrame = false
    }

#if FOCUSIN_DELTA
    // MARK: - Delta 單播畫面接收（普通模式：H.264 幀走 WebSocket）

    /// 啟動單播解碼（與組播共用 h264Decoder；由 onFrame 送入幀）。
    private func startUnicastVideo() {
        multicastVideo.stop()
        hasDecodedFrame = false
        h264Decoder.start { [weak self] pixelBuffer in
            let image = Self.image(from: pixelBuffer)
            guard let image else { return }
            Task { @MainActor in
                self?.kiosk.setBroadcastImage(image)
            }
        }
        appendLog("Delta 單播畫面接收已啟動（H.264 over WebSocket）")
    }

    private func stopUnicastVideo() {
        h264Decoder.stop()
        hasDecodedFrame = false
    }

    /// 解一幀 H.264（供 onFrame 背景佇列呼叫；未解出首幀前只接受關鍵幀）。
    private func decodeH264(_ frame: (annexB: Data, key: Bool, sps: Data?, pps: Data?)) {
        if !hasDecodedFrame && !frame.key { return }
        hasDecodedFrame = true
        h264Decoder.decode(frame.annexB, isKeyframe: frame.key,
                           sps: frame.sps, pps: frame.pps)
    }
#endif

    /// CVPixelBuffer → NSImage（BGRA）。
    static func image(from pixelBuffer: CVPixelBuffer) -> NSImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rep = NSCIImageRep(ciImage: ciImage)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - v1.5-beta AP 組播探測

    private let probeReceiver = MulticastTransport()
    private let probeStats = MulticastProbeStats()
    private var probeReportTimer: Timer?
    private var probeSendingPeer: PeerConnection?

    private func startMulticastProbe(params: String?) {
        probeStats.resetForProbe()
        probeSendingPeer = connections.first
        probeReceiver.startReceiver(port: MulticastTransport.probePort, ifaceIP: nil) { [weak self] data in
            self?.probeStats.record(packet: data)
        }
        appendLog("組播探測統計已啟動（\(MulticastTransport.group):\(MulticastTransport.probePort)）")
        probeReportTimer?.invalidate()
        probeReportTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reportProbeStats() }
        }
        _ = params
    }

    private func reportProbeStats() {
        let (mbps, loss, packets) = probeStats.windowStats()
        let report = "\(packets),\(String(format: "%.2f", mbps)),\(String(format: "%.1f", loss))"
        if let peer = probeSendingPeer {
            peer.send(CommandMessage(type: .multicastProbeReport, senderID: deviceID,
                                     senderName: deviceName, payload: report))
        }
    }

    private func stopMulticastProbe() {
        probeReportTimer?.invalidate()
        probeReportTimer = nil
        probeReceiver.stop()
        appendLog("組播探測統計已停止")
    }
#endif

    // MARK: - 系統動作

    private func launchApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            appendLog("未找到應用程式: \(bundleID)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Task { @MainActor in self.appendLog("啟動失敗: \(error.localizedDescription)") }
            }
        }
    }

    /// 透過 System Events 觸發關機/重新啟動（首次會彈出自動化授權；部分環境需管理員權限）。
    /// 若 System Events 失敗，嘗試用 `shutdown` 指令（需 sudo，通常失敗），最後回報錯誤。
    private func runSystemEventScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            appendLog("系統命令執行失敗 (AppleScript): \(error)")
            // Fallback: 嘗試用 shutdown 指令（通常需要 sudo，這裡僅作最佳努力）
            let fallbackScript: String
            if source.contains("shut down") {
                fallbackScript = "do shell script \"shutdown -h now\" with administrator privileges"
            } else {
                fallbackScript = "do shell script \"shutdown -r now\" with administrator privileges"
            }
            var fbError: NSDictionary?
            NSAppleScript(source: fallbackScript)?.executeAndReturnError(&fbError)
            if let fbError {
                appendLog("系統命令執行失敗 (fallback): \(fbError)")
            }
        }
    }

    private func appendLog(_ text: String) { log.append(text) }
}
