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
                peer.onFrame = { jpegData in
                    // JPEG 解碼較耗時：先在背景佇列解碼，再切回主執行緒更新畫面，避免卡頓
                    DispatchQueue.global(qos: .userInteractive).async {
                        guard let image = NSImage(data: jpegData) else { return }
                        Task { @MainActor in
                            self.kiosk.setBroadcastImage(image)
                        }
                    }
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

#if FOCUSIN_BETA
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
#if !FOCUSIN_STABLE
            audio.start()
#endif

        // 廣播幀改走二進位通道（PeerConnection.onFrame），此處不再處理 JSON 幀
        case .streamFrame:
            break

        case .streamStop:
            isBroadcasting = false
            kiosk.clearBroadcastImage()
#if !FOCUSIN_STABLE
            audio.stop()
#endif

        default:
            break
        }
    }

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
