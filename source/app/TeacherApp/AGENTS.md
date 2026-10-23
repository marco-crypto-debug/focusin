# TEACHER APP KNOWLEDGE BASE

<!-- Scored 9: Distinct domain (Teacher controller, screen/audio broadcasting, device orchestration) -->

## OVERVIEW
macOS teacher controller application for discovering student devices, managing classroom controls, and broadcasting screen and audio streams.

## WHERE TO LOOK
| Task | File | Description |
|---|---|---|
| Entry & lifecycle | `TeacherApp.swift` | `@main` entry, NSApplicationDelegate, QuitGuard integration, menu bar status item |
| Device orchestration | `TeacherViewModel.swift` | Bonjour peer discovery (`PeerBrowser`), WebSocket management, ping RTT latency tracking |
| Screen capture & audio | `ScreenBroadcaster.swift` | ScreenCaptureKit `SCStream` capture, frame downscaling, audio channel re-interleaving |
| Hardware video encoding | `H264Encoder.swift` | VideoToolbox hardware-accelerated H.264 compression session with 1s forced keyframes |
| UI & controls | `Views/DeviceListView.swift` | Split view student grid, remote action cards, wipe confirmation sheet, probe runner |

## CONVENTIONS
- Hardware video compression forces 1 keyframe per second (IDR) because UDP multicast provides no packet retransmission.
- VideoToolbox compression outputs AVCC NAL units with 4-byte length prefixes; SPS/PPS are extracted from `CMVideoFormatDescription`.
- ScreenCaptureKit audio is planar; it must be manually re-interleaved into `[L0, R0, L1, R1...]` and batched into ~80ms chunks.
- Remote file wipe requires double-confirmation: teacher must explicitly type `DELETE` in all-caps in `WipeConfirmSheet`.
- App runs unsandboxed (`com.apple.security.app-sandbox = false`) to allow screen capture and ad-hoc socket connections.

## ANTI-PATTERNS
- DO NOT send video frames concurrently over `PeerConnection`: use `sendLock` and single-slot pending buffer with keyframe priority.
- DO NOT drop keyframes during network congestion; non-keyframes may be dropped, but keyframes must reach decoders.
- DO NOT bypass the `DELETE` confirmation check when dispatching `.deleteAllFiles` commands.

## COMMANDS & TESTING
```bash
# Direct build of TeacherApp binary
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library -O \
  -target arm64-apple-macos14.0 -D FOCUSIN_BETA \
  source/app/TeacherApp/*.swift source/app/TeacherApp/Views/*.swift source/app/Shared/*/*.swift \
  -o TeacherApp
```

