import Foundation
import Network

/// 学生端：通过 Bonjour 在本地网络广告 Kiosk 服务。
final class PeerAdvertiser {
    private var listener: NWListener?
    private let serviceName: String

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    func start(onConnection: @escaping (NWConnection) -> Void) throws {
        guard let port = NWEndpoint.Port(rawValue: PeerTransport.defaultPort) else {
            throw PeerAdvertiser.Error.invalidPort
        }
        let listener = try NWListener(using: PeerTransport.webSocketParameters(), on: port)
        listener.service = NWListener.Service(name: serviceName,
                                              type: PeerTransport.serviceType,
                                              domain: "local.")
        listener.newConnectionHandler = onConnection
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[Advertiser] failed: \(error)")
            }
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    enum Error: Swift.Error {
        case invalidPort
    }
}

/// 教师端：通过 Bonjour 自动发现同网段的学生端。
final class PeerBrowser {
    private var browser: NWBrowser?

    var onPeerFound: ((NWEndpoint, String) -> Void)?   // (endpoint, 服务名)
    var onPeerLost: ((NWEndpoint) -> Void)?

    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true            // 允许 AWDL/点对点 发现
        let browser = NWBrowser(for: .bonjour(type: PeerTransport.serviceType, domain: nil),
                                using: parameters)
        browser.browseResultsChangedHandler = { _, changes in
            for change in changes {
                switch change {
                case .added(let result):
                    if case .service(let name, _, _, _) = result.endpoint {
                        self.onPeerFound?(result.endpoint, name)
                    }
                case .removed(let result):
                    self.onPeerLost?(result.endpoint)
                case .changed(let old, let new, _):
                    // 服务参数变化（如改名），视作重新发现
                    if case .service(let name, _, _, _) = new.endpoint {
                        self.onPeerLost?(old.endpoint)
                        self.onPeerFound?(new.endpoint, name)
                    }
                case .identical:
                    break
                @unknown default:
                    break
                }
            }
        }
        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[Browser] failed: \(error)")
            }
        }
        browser.start(queue: .global(qos: .utility))
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
