import AppKit
import CoreWLAN
import Darwin
import Foundation

/// 監控並動態獲取當前連線之 Wi-Fi SSID 與本機 IP
final class WiFiMonitor: NSObject, CWEventDelegate {
    private let client = CWWiFiClient.shared()
    var onWiFiChange: ((String) -> Void)?

    override init() {
        super.init()
        client.delegate = self
        _ = try? client.startMonitoringEvent(with: .ssidDidChange)
        _ = try? client.startMonitoringEvent(with: .linkDidChange)
        _ = try? client.startMonitoringEvent(with: .bssidDidChange)
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        check()
    }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        check()
    }
    func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
        check()
    }

    private func check() {
        let ssid = WiFiMonitor.getCurrentSSID()
        DispatchQueue.main.async { [weak self] in
            self?.onWiFiChange?(ssid)
        }
    }

    static func getCurrentSSID() -> String {
        if let iface = CWWiFiClient.shared().interface() {
            if let ssid = iface.ssid(), !ssid.isEmpty, ssid != "<redacted>" {
                return ssid
            }
            if let lastProfile = iface.value(forKey: "lastPreferredNetworkJoined") as? NSObject,
               let ssid = lastProfile.value(forKey: "ssid") as? String,
               !ssid.isEmpty, ssid != "<redacted>" {
                return ssid
            }
        }
        return fetchSSIDFromIPConfig() ?? "Wi-Fi"
    }

    static func fetchSSIDFromIPConfig() -> String? {
        let ifaces = [CWWiFiClient.shared().interface()?.interfaceName ?? "en0", "en0", "en1"]
        for iface in ifaces {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
            task.arguments = ["getsummary", iface]
            let pipe = Pipe()
            task.standardOutput = pipe
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                if let output = String(data: data, encoding: .utf8) {
                    for line in output.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("SSID : ") {
                            let name = String(trimmed.dropFirst("SSID : ".count)).trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty && name != "<redacted>" {
                                return name
                            }
                        }
                    }
                }
            } catch {}
        }
        return nil
    }

    static func getLocalIPAddress() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        let ifName = String(cString: ptr.pointee.ifa_name)
                        if ifName == "en0" || ifName.starts(with: "en") {
                            return ip
                        }
                        address = ip
                    }
                }
            }
        }
        return address
    }
}
