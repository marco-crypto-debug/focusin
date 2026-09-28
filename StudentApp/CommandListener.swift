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

    private var advertiser: PeerAdvertiser?
    private var connections: [PeerConnection] = []
    private let kiosk = KioskModeController.shared
    private let audio = BroadcastAudioPlayer()

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
        startService()
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
                peer.onAudio = { pcm, info in
                    Task { @MainActor in
                        self.audio.play(pcm: pcm, format: info)
                    }
                }
                peer.onConnectionLost = {
                    Task { @MainActor in
                        self.connections.removeAll { $0 === peer }
                        self.connectionCount = self.connections.count
                        self.appendLog("教師連線已中斷")
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

        case .streamStart:
            isBroadcasting = true
            kiosk.clearBroadcastImage()
            audio.start()

        // 廣播幀改走二進位通道（PeerConnection.onFrame），此處不再處理 JSON 幀
        case .streamFrame:
            break

        case .streamStop:
            isBroadcasting = false
            kiosk.clearBroadcastImage()
            audio.stop()

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
    private func runSystemEventScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            appendLog("系統命令執行失敗: \(error)")
        }
    }

    private func appendLog(_ text: String) { log.append(text) }
}
