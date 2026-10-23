# PROJECT KNOWLEDGE BASE

**Generated:** 2026-10-23T16:02:05.121Z
**Commit:** 6449545
**Branch:** main

## OVERVIEW
FocusIn is a zero-dependency native macOS LAN classroom management system (TeacherApp controller, StudentApp kiosk receiver) with a Cloudflare Workers licensing backend. Core stack: Swift 5, SwiftUI, Network.framework, ScreenCaptureKit, VideoToolbox, and CryptoKit on macOS 13+.

## STRUCTURE
```
FocusIn/
├── source/
│   ├── app/                # macOS multi-target app (TeacherApp, StudentApp, Shared)
│   ├── backend/            # Cloudflare Worker (Ed25519 license issuance & Dodo webhooks)
│   ├── tools/              # Unified swiftc build script, signing tools, and keygen CLI
│   └── web/                # Marketing and landing pages for Cloudflare Pages
└── release/                # Staging directories and generated DMG distribution bundles
```

## WHERE TO LOOK
| Task | Location | Notes |
|---|---|---|
| Teacher controller | `source/app/TeacherApp/` | Teacher UI, ScreenCaptureKit capture, H.264 encoder, peer browser |
| Student lock & kiosk | `source/app/StudentApp/` | CGEventTap input interceptor, full-screen lock windows, H.264 decoder |
| Shared networking | `source/app/Shared/Networking/` | PeerConnection (WebSocket), PeerDiscovery (mDNS), MulticastTransport |
| Wire protocol | `source/app/Shared/Protocol/` | CommandMessage envelope and CommandType discriminator |
| Cryptographic licensing | `source/app/Shared/Utility/LicenseManager.swift` | Ed25519 offline signature verification |
| Multi-variant build | `source/tools/build.sh` | Compiles stable, alpha, beta, and delta variants via swiftc |
| XcodeGen project | `source/app/project.yml` | Declarative project spec for Xcode development |
| Backend licensing worker | `source/backend/license-worker/worker.js` | Cloudflare Worker issuing signed license keys |

## CODE MAP
| Symbol | Type | Location | Refs | Role |
|---|---|---|---|---|
| `FocusInTheme` | enum | `source/app/Shared/Utility/FocusInTheme.swift` | 56 | App theming, TUTTI / MoodLab palettes, style tokens |
| `DiagLog` | enum | `source/app/Shared/Utility/DiagLog.swift` | 44 | Append-only diagnostics in `~/Library/Logs/FocusIn-diag.log` |
| `MulticastTransport` | class | `source/app/Shared/Networking/MulticastTransport.swift` | 41 | Darwin BSD UDP multicast socket engine on `239.255.42.99` |
| `CommandMessage` | struct | `source/app/Shared/Protocol/CommandMessage.swift` | 35 | Codable JSON envelope for control signaling |
| `PeerConnection` | class | `source/app/Shared/Networking/PeerConnection.swift` | 27 | NWConnection WebSocket wrapper with serial queue and frame throttle |
| `LicenseManager` | class | `source/app/Shared/Utility/LicenseManager.swift` | 25 | Ed25519 offline cryptographic license validator |
| `QuitGuard` | enum | `source/app/Shared/Utility/QuitGuard.swift` | 17 | Intercepts `applicationShouldTerminate` with admin password |
| `KioskConfig` | enum | `source/app/StudentApp/Kiosk/KioskConfig.swift` | 16 | Salted SHA-256 admin password store for emergency unlock |
| `DeviceLimit` | enum | `source/app/Shared/Utility/DeviceLimit.swift` | 16 | Delta tier limits (5 free unicast vs 50 pro multicast) |
| `TeacherViewModel` | class | `source/app/TeacherApp/TeacherViewModel.swift` | 5 | Teacher state, mDNS discovery, and WebSocket peer manager |
| `KioskModeController` | class | `source/app/StudentApp/Kiosk/KioskModeController.swift` | 6 | Lock windows at `.screenSaver` level with presentation options |
| `InputInterceptor` | class | `source/app/StudentApp/Kiosk/InputInterceptor.swift` | 5 | Low-level CGEventTap input swallower and ⌘⇧U unlock trigger |
| `H264Encoder` | class | `source/app/TeacherApp/H264Encoder.swift` | 3 | VideoToolbox hardware encoder producing Annex-B streams (1s IDR) |
| `H264Decoder` | class | `source/app/StudentApp/H264Decoder.swift` | 3 | VideoToolbox hardware decoder with SPS/PPS dynamic rebuild |

## CONVENTIONS
- Multiplexing uses 4-byte ASCII magic headers: `FZFR` (unicast video), `FZHV` (H.264 multicast), `FZAU` (PCM audio), `FZMP` (AP probe). Non-magic binary frames decode as JSON `CommandMessage`.
- Both apps run unsandboxed (`com.apple.security.app-sandbox = false`) to allow screen capture, accessibility event taps, and file management.
- Multi-variant releases are governed by conditional compilation flags: `FOCUSIN_STABLE` (video only), `FOCUSIN_ALPHA` (video + audio), `FOCUSIN_BETA` (multicast), and `FOCUSIN_DELTA` (tiered licensing).
- Zero external Swift dependencies: only native Apple SDK frameworks are linked.

## ANTI-PATTERNS (THIS PROJECT)
- DO NOT manually edit `FocusIn.xcodeproj/project.pbxproj`; edit `source/app/project.yml` and run `xcodegen generate`.
- DO NOT send raw video or audio frames through JSON/base64; always use binary magic-prefixed streams.
- DO NOT call Network.framework `NWConnection.send` concurrently from multiple threads; dispatch through serial queues.
- DO NOT bypass the all-caps `DELETE` confirmation string requirement when executing student folder wiping.
- DO NOT store plain text administrator passwords; use 16-byte random salt and SHA-256 hashing.

## UNIQUE STYLES
- UI uses `FocusInTheme` with dual palette support: TUTTI style (Stable/Alpha releases) and MoodLab dark modern style (Beta/Delta releases).
- Status bar integration uses dynamic `NSMenuDelegate` rebuilds (`MenuBarManager`) to reflect live peer counts and broadcast states.

## COMMANDS
```bash
# Direct build of all release DMGs via swiftc
bash source/tools/build.sh stable
bash source/tools/build.sh all

# Generate Xcode projects via XcodeGen
cd source/app && xcodegen generate

# Issue Ed25519 license key via CLI
node source/tools/gen-license-key.js --email teacher@school.edu --months 12
```

## NOTES
- UDP Multicast requires routers/switches with IGMP snooping enabled; Wi-Fi multicast without IGMP can saturate AP airtime.
- Student emergency unlock shortcut is `⌘⇧U` (`Command+Shift+U`), opening a 60-second unlock window before auto-relocking.
