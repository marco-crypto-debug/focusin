# SHARED MODULE KNOWLEDGE BASE

<!-- Scored 9: Distinct domain (Cross-target networking, wire protocol serialization, and utilities) -->

## OVERVIEW
Shared networking primitives, binary framing protocols, Ed25519 licensing, and system lifecycle utilities compiled into TeacherApp and StudentApp.

## WHERE TO LOOK
| Task | File | Description |
|---|---|---|
| WebSocket transport | `Networking/PeerConnection.swift` | NWConnection wrapper, serial send queue, backpressure single-frame buffer |
| Discovery & advertising | `Networking/PeerDiscovery.swift` | Bonjour mDNS `_classroom-ctrl._tcp.` advertiser (Student) and browser (Teacher) |
| UDP multicast & probe | `Networking/MulticastTransport.swift` | BSD socket multicast on `239.255.42.99`, packet packers for `FZHV`, `FZAU`, `FZMP` |
| Transport settings | `Networking/PeerTransport.swift` | NWParameters factory enabling TCP_NODELAY, WebSocket options, interactive QoS |
| Wire protocol models | `Protocol/CommandMessage.swift`, `CommandType.swift` | JSON message envelope and command discriminator enum |
| Cryptographic licensing | `Utility/LicenseManager.swift` | Ed25519 public-key signature verification for monthly and Pro licenses |
| Tier & device limits | `Utility/DeviceLimit.swift` | Free (5 devices, unicast) vs Pro (50 devices, multicast/audio) enforcement |
| App protection & tools | `Utility/QuitGuard.swift`, `LoginStartManager.swift` | ⌘Q password guard, LaunchAgent auto-start, update checker, menu bar manager |

## CONVENTIONS
- Multiplexing uses 4-byte ASCII magic headers: `FZFR` (unicast video), `FZHV` (H.264 multicast), `FZAU` (PCM audio), `FZMP` (AP probe). Non-magic packets are parsed as JSON `CommandMessage`.
- `PeerConnection` operations MUST use `sendQueue` to prevent multi-threaded `Network.framework` memory corruptions.
- License keys use format `FI-PRO-<base64url(payload)>.<base64url(sig)>` verified against embedded Ed25519 public key.
- Multicast group is fixed to IPv4 `239.255.42.99`: Video port 7100, Audio port 7200, Probe port 7000.

## ANTI-PATTERNS
- DO NOT send JSON envelopes for raw video or audio frames: always use binary magic-prefixed streams.
- DO NOT call Network.framework `connection.send` concurrently from multiple GCD queues.
- DO NOT allow quit without password verification when `QuitGuard` is configured.

## PROTOCOL REFERENCE
- Multicast Video Group: `239.255.42.99:7100` (`FZHV` Annex-B stream)
- Multicast Audio Group: `239.255.42.99:7200` (`FZAU` PCM stereo)
- AP Throughput Probe: `239.255.42.99:7000` (`FZMP` sequence packets)
- Unicast Command / Control: TCP `4477` (Bonjour service `_classroom-ctrl._tcp.`)

