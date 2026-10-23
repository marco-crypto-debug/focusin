# STUDENT APP KNOWLEDGE BASE

<!-- Scored 11: Distinct domain (Student receiver, kiosk lock, input interception, video/audio playback) -->

## OVERVIEW
macOS student receiver application enforcing full-screen kiosk lock, input interception, quit protection, and video/audio stream rendering.

## WHERE TO LOOK
| Task | File | Description |
|---|---|---|
| Entry & lifecycle | `StudentApp.swift` | `@main` entry, NSApplicationDelegate, QuitGuard integration, status bar item |
| Network listener | `CommandListener.swift` | Bonjour advertiser (`_classroom-ctrl._tcp.`), WebSocket listener, command dispatcher |
| Input interception | `Kiosk/InputInterceptor.swift` | Low-level `CGEventTap` (`.cghidEventTap`) swallowing keyboard and mouse events |
| Kiosk window & modes | `Kiosk/KioskModeController.swift` | Multi-screen borderless lock windows at `.screenSaver` level with presentation options |
| Lock screen UI | `Kiosk/KioskLockView.swift` | SwiftUI lock screen rendering broadcast frames, lock notice, and unlock field |
| Admin password store | `Kiosk/KioskConfig.swift` | Salted SHA-256 admin password storage in UserDefaults for local emergency unlock |
| Video decoding | `H264Decoder.swift` | Hardware VideoToolbox decompression session converting H.264 streams to `CVPixelBuffer` |
| Audio playback | `AudioPlayer.swift` | Low-latency audio playback via `AVAudioEngine` with 240ms jitter buffer and format locking |
| Display & file control | `BrightnessManager.swift`, `FileWipeManager.swift` | DisplayServices brightness API and permanent non-trash deletion of user folders |

## CONVENTIONS
- `InputInterceptor` requires macOS Accessibility permission (`AXIsProcessTrusted`). If tap disabled by timeout, auto-rearm immediately.
- Emergency unlock shortcut is `⌘⇧U` (`Command+Shift+U`), triggering a 60-second unlock prompt window before automatically re-locking.
- `H264Decoder` ignores non-keyframes until the first keyframe arrives with valid SPS/PPS to avoid VideoToolbox `-12909` errors.
- `AudioPlayer` locks onto the incoming stream format on first chunk; mismatched formats are discarded to prevent core audio crashes.
- Unsandboxed execution required for AppleScript system controls, private display framework access, and file purging.

## ANTI-PATTERNS
- DO NOT use `FileManager.trashItem` in `FileWipeManager`: wiping student files is permanent deletion per classroom spec.
- DO NOT store plain text admin passwords; always salt with 16 random bytes and hash with SHA-256.
- DO NOT retain `CVPixelBuffer` references in UI views; copy to `CGImage`/`NSImage` to avoid exhausting decoder pool buffers.

## COMMANDS & TESTING
```bash
# Direct build of StudentApp binary
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library -O \
  -target arm64-apple-macos14.0 -D FOCUSIN_BETA \
  source/app/StudentApp/*.swift source/app/StudentApp/Kiosk/*.swift source/app/StudentApp/Views/*.swift source/app/Shared/*/*.swift \
  -o StudentApp
```

