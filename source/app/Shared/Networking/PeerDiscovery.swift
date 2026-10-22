import Foundation
import Network

/// 學生端：透過 Bonjour 在本機網路公布 Kiosk 服務。
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

/// 教師端：透過 Bonjour 自動發現同網段（同一子網路）的學生端。
final class PeerBrowser {
    private var browser: NWBrowser?

    var onPeerFound: ((NWEndpoint, String) -> Void)?   // (endpoint, 服務名稱)
    var onPeerLost: ((NWEndpoint) -> Void)?

    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true            // 允許 AWDL/點對點 發現
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
                    // 服務參數變化（如改名），視作重新發現
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
