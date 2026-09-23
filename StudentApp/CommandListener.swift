import AppKit
import Foundation

/// 学生端核心：广告 Bonjour 服务、接受教师连接、分发命令并触发本地系统动作。
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

    // MARK: - 服务

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
                peer.onConnectionLost = {
                    Task { @MainActor in
                        self.connections.removeAll { $0 === peer }
                        self.connectionCount = self.connections.count
                        self.appendLog("教师连接已断开")
                    }
                }
                peer.start()
                Task { @MainActor in
                    self.connections.append(peer)
                    self.connectionCount = self.connections.count
                    // 握手：学生先自我介绍
                    peer.send(CommandMessage(type: .hello,
                                             senderID: self.deviceID,
                                             senderName: self.deviceName))
                    self.appendLog("教师已连接（\(self.connectionCount) 台）")
                }
            }
            self.advertiser = advertiser
            appendLog("正在监听 \(PeerTransport.serviceType)")
        } catch {
            appendLog("广告服务启动失败: \(error)")
        }
    }

    // MARK: - 命令分发

    private func handle(_ message: CommandMessage, from peer: PeerConnection) {
        switch message.type {
        case .lock:
            appendLog("收到锁定指令")
            kiosk.enterKiosk()

        case .unlock:
            appendLog("收到解锁指令")
            kiosk.exitKiosk()

        case .shutdown:
            appendLog("收到关机指令")
            runSystemEventScript("tell application \"System Events\" to shut down")

        case .restart:
            appendLog("收到重启指令")
            runSystemEventScript("tell application \"System Events\" to restart")

        case .launchApp:
            if let bundleID = message.payload {
                launchApp(bundleID: bundleID)
            }

        case .streamStart:
            isBroadcasting = true
            kiosk.clearBroadcastImage()

        case .streamFrame:
            if let payload = message.payload,
               let data = Data(base64Encoded: payload),
               let image = NSImage(data: data) {
                kiosk.setBroadcastImage(image)
            }

        case .streamStop:
            isBroadcasting = false
            kiosk.clearBroadcastImage()

        default:
            break
        }
    }

    // MARK: - 系统动作

    private func launchApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            appendLog("未找到应用: \(bundleID)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Task { @MainActor in self.appendLog("启动失败: \(error.localizedDescription)") }
            }
        }
    }

    /// 通过 System Events 触发关机/重启（首次会弹出自动化授权；部分环境需管理员权限）。
    private func runSystemEventScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            appendLog("系统命令执行失败: \(error)")
        }
    }

    private func appendLog(_ text: String) { log.append(text) }
}
