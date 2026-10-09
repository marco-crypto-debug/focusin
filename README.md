**English** · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md)

---

# FocusIn — macOS Classroom Management (Teacher / Student)

FocusIn is a LAN classroom management solution built for iMac labs. The **Teacher App** auto-discovers student devices, broadcasts the teacher's screen in real time (high-quality video on the stable build, plus audio on the Alpha build), and sends lock/unlock, shutdown, restart, launch-app and wipe-files commands. The **Student App** provides a kiosk full-screen lock, input interception, quit protection and a local emergency unlock, and can launch automatically at login.

Tech stack: Swift / SwiftUI (macOS 14+), Network.framework (WebSocket + Bonjour/mDNS), ScreenCaptureKit.

## Editions

- **stable (release)**: `FocusIn-Teacher.dmg` + `FocusIn-Student.dmg` under `release/stable/`. **Video only** — at the code level it never captures, transmits or plays audio, which completely avoids the audio-rendering path. Includes kiosk full-screen lock, input interception, **quit protection (admin password required to ⌘Q)**, **unified admin password (set in the Teacher App and pushed to every student; used for teacher quit, student quit and emergency unlock ⌘⇧U)**, **broadcast sharpening**, lock/unlock, shutdown/restart, launch app, **wipe student files (Documents + Downloads, requires typing DELETE to confirm)**, auto-update and login auto-start. Use this build in classrooms.
- **alpha (audio testing)**: `FocusIn-Alpha-Teacher.dmg` + `FocusIn-Alpha-Student.dmg` under `release/alpha/`. Both apps include **audio broadcasting** (48 kHz stereo, dedicated audio channel with jitter buffer, format-lock on both ends, interleaved playback). Use this build to test/report audio issues; it is not a stable deliverable. The teacher can toggle "Send Audio" off to send video only.
- **beta (merged into stable, kept on GitHub)**: the former "stable + lock" test channel was merged into the release build at v1.3.9 (quit protection, unified admin password, broadcast sharpening). No longer maintained; historical Releases and Tags stay on GitHub (`v1.3.x-beta`).

## Architecture

```
┌─────────────────────────────┐              ┌─────────────────────────────┐
│        TeacherApp           │              │        StudentApp           │
│                             │   Bonjour    │                             │
│  PeerBrowser  ──discovers(mDNS)──→  PeerAdvertiser (_classroom-ctrl._tcp.)│
│  ScreenBroadcaster          │              │  CommandListener            │
│  (ScreenCaptureKit→JPEG)    │              │   ├─ lock/unlock → Kiosk    │
│  CommandCenter              │◄─WebSocket──►│   ├─ shutdown/restart       │
│                             │  commands/frames│  ├─ launchApp(NSWorkspace)│
│                             │              │   └─ streamFrame → lock view│
└─────────────────────────────┘              └─────────────────────────────┘
        Same Wi-Fi LAN / same subnet
```

## Directory Layout

```
ClassroomManager/
├── README.md
├── project.yml                     # XcodeGen project definition (generates both Xcode projects)
├── Shared/                         # Source shared by both targets (compiled into both)
│   ├── Networking/
│   │   ├── PeerTransport.swift     # NWParameters factory (WebSocket application protocol)
│   │   ├── PeerConnection.swift    # WebSocket wrapper: send/receive CommandMessage
│   │   └── PeerDiscovery.swift     # PeerAdvertiser (student) / PeerBrowser (teacher)
│   └── Protocol/
│       ├── CommandType.swift       # Command enum: lock/unlock/shutdown/restart/launchApp/stream*
│       └── CommandMessage.swift    # JSON message envelope
├── Shared/Utility/
│   ├── LoginStartManager.swift     # Launch-at-login (LaunchAgent registration, shared)
│   └── UpdateChecker.swift         # Auto-update check (GitHub API: release tag / commit SHA)
├── TeacherApp/
│   ├── TeacherApp.swift            # @main entry
│   ├── TeacherViewModel.swift      # Discovery / connection / command dispatch
│   ├── ScreenBroadcaster.swift     # ScreenCaptureKit capture → JPEG frames + audio PCM
│   ├── Views/DeviceListView.swift  # Device list + control panel UI (quality / auto-start)
│   ├── Info.plist
│   └── TeacherApp.entitlements
└── StudentApp/
    ├── StudentApp.swift            # @main entry
    ├── CommandListener.swift       # Advertise service + command listener + system actions
    ├── AudioPlayer.swift           # Broadcast audio playback (AVAudioEngine)
    ├── FileWipeManager.swift       # Wipe Documents + Downloads (sent by teacher)
    ├── Views/StatusView.swift      # Status window (admin password + auto-start + update check)
    ├── Kiosk/
    │   ├── KioskModeController.swift # Full-screen lock window + presentationOptions + unlock flow
    │   ├── InputInterceptor.swift    # CGEventTap keyboard/mouse interception
    │   ├── KioskLockView.swift       # Lock screen UI (broadcast view + password field)
    │   └── KioskConfig.swift         # Salted-hash storage of admin password
    ├── Info.plist
    └── StudentApp.entitlements
```

## Build & Run

Option A: XcodeGen (recommended — one command generates both projects)

```bash
brew install xcodegen
cd ClassroomManager
xcodegen generate        # generates TeacherApp.xcodeproj / StudentApp.xcodeproj
open TeacherApp.xcodeproj    # select the TeacherApp scheme, ⌘R to run
open StudentApp.xcodeproj    # select the StudentApp scheme, ⌘R to run
```

Option B: manual Xcode project (without XcodeGen)
1. Xcode → New Project → macOS → App, language Swift, interface SwiftUI.
2. Drag the `TeacherApp` and `Shared` folders into the TeacherApp target; drag `StudentApp` and `Shared` into the StudentApp target.
3. Build Settings: `MACOSX_DEPLOYMENT_TARGET = 13.0`; point each Info.plist and Entitlements at the corresponding files.
4. Use a separate signing team per target (for local development, "Sign to Run Locally" is fine).

Deployment flow
1. On the student Mac, launch FocusIn Student → set a local admin password in the status window (at least 4 characters; changing it requires the current password first). We recommend enabling "Launch Student at login".
2. On the teacher Mac, launch FocusIn Teacher → it auto-discovers students (same Wi-Fi). You can enable "Launch Teacher at login" too.
3. Select "All Students" or specific devices → broadcast (with audio on Alpha) / lock / unlock / shutdown / restart / launch app.
4. While students are locked: the teacher can send `unlock` anytime; if the network is down, a local admin presses **⌘⇧U** and enters the password to unlock.

## Permissions

### 1. System Settings (System Settings → Privacy & Security)

| App | Permission | Purpose | Location |
|---|---|---|---|
| FocusIn Teacher (TeacherApp) | Screen Recording | Capture the teacher's screen **and audio** for broadcast (audio capture shares the same permission) | Privacy & Security → Screen Recording |
| FocusIn Student (StudentApp) | Accessibility | CGEventTap keyboard/mouse interception | Privacy & Security → Accessibility |
| FocusIn Student (StudentApp) | Automation (optional) | Shutdown/restart via System Events; first run shows an authorization prompt | Privacy & Security → Automation |
| Both | Local network / firewall | macOS firewall may ask "Allow incoming connections" on first run | System Settings → Network → Firewall |

> **Screen Recording guidance (Teacher)**: when you press "Broadcast Teacher Screen" without permission, the Teacher App shows a red notice with an "Open Screen Recording Settings" button (jumps straight to System Settings → Privacy & Security → Screen Recording) and triggers the system authorization prompt. Tick **FocusIn Teacher (TeacherApp)** on that page, then press "Broadcast Teacher Screen" again. If you previously chose "Deny", untick and re-tick it on that page.

> **Where the broadcast is shown (Student)**: once the teacher locks the student device, the broadcast appears full-screen on the lock screen; when unlocked, the student status window shows a broadcast preview so you can verify picture and network first.

### 2. Info.plist keys (already provided in the project)

| Key | App | Description |
|---|---|---|
| `NSScreenCaptureUsageDescription` | TeacherApp | Screen-recording purpose text (TCC prompt) |
| `NSAppleEventsUsageDescription` | StudentApp | Purpose text for sending Apple Events to System Events |

### 3. Entitlements

App Sandbox is **disabled by default** (`com.apple.security.app-sandbox = false`), with `com.apple.security.network.client` / `server` pre-provisioned. If you enable the sandbox later, these two cover WebSocket traffic; enabling the sandbox also requires other capabilities (e.g. `com.apple.security.temporary-exception.apple-events` to send Apple Events to System Events).

## Protocol Reference (WebSocket binary frames, JSON envelope)

| type | direction | payload | description |
|---|---|---|---|
| `hello` / `helloAck` | S→T / T→S | — | Handshake; hello carries the device name |
| `lock` / `unlock` | T→S | — | Enter / exit Kiosk |
| `shutdown` / `restart` | T→S | — | Remote shutdown / restart (System Events) |
| `launchApp` | T→S | Bundle ID | Launch an app (NSWorkspace) |
| `deleteAllFiles` | T→S | — | Wipe student Documents + Downloads (teacher clicks + types DELETE to confirm) |
| `wipeResult` | S→T | summary text | Wipe result acknowledgement |
| `streamStart` / `streamStop` | T→S | — | Broadcast start / stop |
| Broadcast frame (binary) | T→S | magic `FZFR` + raw JPEG | Low-latency path: skips JSON/base64 (~33% smaller, far less codec work) |
| Broadcast audio (binary) | T→S | magic `FZAU` + format header + PCM | 48 kHz stereo; **dedicated connection** (hello payload = `audio` marker), separate from video; the teacher re-interleaves non-interleaved SCStream PCM and sends ~80 ms chunks (always continuous across chunks, eliminating the low-frequency hum from alternating left/right slices); the student plays via AVAudioEngine (always builds buffers as interleaved with a whole-buffer copy, avoiding non-interleaved per-channel crashes) + jitter buffer (~240 ms pre-roll, drops newest when overloaded — continuous playback with bounded latency); the format is locked on the whole path and mismatched chunks are dropped on both ends |
| `ping` / `pong` | both | — | App-level keepalive + live latency measurement (teacher measures every 3 s, UI shows ms per student) |

> Crash protection: each broadcast locks one canonical audio format (decided by the first buffer); mismatched buffers are dropped. The student locks the first chunk's format and rejects malformed/heterogeneous chunks (8k–96k rate, 1–2 channels, 16/32-bit); queued buffers are strongly referenced until playback ends — no EXC_BAD_ACCESS from rendering threads reading heterogeneous or freed memory.

> Latency optimizations: `TCP_NODELAY` on TCP; teacher encoding throttle (drops old frames instead of queueing); one in-flight frame per connection; student JPEG decode on a background queue; **audio on its own WebSocket connection** (no head-of-line blocking from large frames), non-interleaved PCM re-interleaved and sent in ~80 ms chunks; student jitter buffer smooths Wi-Fi arrival jitter (~240 ms pre-roll, drops newest on overload) with correct frame counts per channel/bytes-per-sample; the teacher measures live latency per student every 3 s with ping/pong and shows it in the device list.

> Broadcast quality is switched in the teacher UI (Auto / Low / Medium / High). Capture parameters live in `TeacherApp/ScreenBroadcaster.swift` under `BroadcastQuality` and `resolutionParameters` — customize there.

## Lock Screen Mechanism (StudentApp)

Kiosk is built from three layers; if any is bypassed, the others still hold:

1. **presentationOptions**: hides Dock/Menu Bar, disables ⌘⇥, ⌘⌥⎋ and other system-level entries (newer systems can also disable ⌘Space, ⌘⇧3/4, Control Center/Notification Center; this project uses the minimal set for SDK compatibility).
2. **CGEventTap (`.cghidEventTap`)**: swallows all keyboard/mouse events at the system level, hard-blocking ⌘⇥, ⌘⌥⎋, ⌃←/⌃→, ⌘Space, ⌘⇧3/4 and more. Requires Accessibility permission.
3. **Full-screen borderless lock window (level = `.screenSaver`)**: covers every display and every Space, hiding the Menu Bar and Dock. It is force-raised with `orderFrontRegardless()`, so it covers the screen even when another app is in full-screen mode on the student Mac. Self-healing while locked: screen-parameter changes (external display plugged/woken, resolution change) rebuild the lock window to avoid uncovered gaps; if focus is stolen by another app (e.g. pressing ⌘⇥ before Accessibility is granted), it re-takes focus, re-raises the lock window and re-installs input interception.

Emergency unlock: press **⌘⇧U** locally → the interceptor unloads temporarily → the lock window shows a password field (auto-focused, just type) → salted SHA-256 hash check → correct password exits Kiosk; wrong password or 60 s timeout restores interception and re-locks, with a hint shown on the lock screen.

> Emergency unlock notes:
> - **Set a local admin password in the student status window first**; otherwise ⌘⇧U shows "No local admin password set" and stays locked (no dead-lock password field).
> - **⌘⇧U depends on Accessibility permission**: without it the interceptor is not installed and the shortcut cannot be detected — the lock screen shows a yellow "Accessibility permission required" hint. Enable StudentApp in System Settings → Privacy & Security → Accessibility.
> - ⌘⇧U must be pressed **on the locked student Mac itself**; pressing it on the teacher Mac does nothing.

## Security & Operations Notes

- **Trust model**: this design assumes a trusted classroom LAN. WebSocket is plaintext; to deploy across untrusted networks, layer `NWProtocolTLS.Options` in `PeerTransport.webSocketParameters()` with certificate verification.
- **Remote shutdown/restart**: the System Events route shows an Automation authorization prompt on first use and may require admin rights in some network-account environments; alternatively run `/sbin/shutdown -h now` / `-r now` via `Process` (needs root).
- **Kiosk limits**: event interception only covers input in the graphical session; it does not defend against SSH, another admin account, or killing the process. For production lab management, layer MDM (Jamf / Apple School Manager / configuration profiles + Single App Mode).
- **Wi-Fi**: if the school AP enables "client isolation", Bonjour discovery and direct connections are blocked; run on a VLAN that supports multicast / L2 interop.
- **Performance**: broadcast quality is switchable in the teacher UI — **High**: native full resolution (30 fps, JPEG 0.92); **Medium**: 0.75 scale (30 fps); **Low**: 0.5 scale (24 fps); **Auto**: native up to 4K, slightly scaled (0.85) above 5K. Use "High" or "Auto" on a LAN. Audio (48 kHz stereo PCM) travels with the broadcast and plays in real time on students. The teacher also has a "Send Audio" toggle: if a specific student's audio path has compatibility issues, turn it off to send video only (toggling restarts the broadcast automatically).
- **Launch at login**: both apps have a toggle that writes `~/Library/LaunchAgents/<bundleID>.plist` (LaunchAgent, RunAtLoad). Unticking removes it; re-tick after moving the app to refresh the path.
- **Auto-update**: both apps check GitHub (`marco-crypto-debug/focusin`) at launch — comparing release tags when a Release exists, otherwise the latest main-branch commit SHA against the build's SHA (written into `CFBundleVersion` at build time). When a new version is found the UI prompts, and you can download it directly (DMG straight to ~/Downloads and auto-opened) or check manually. A first build before any push may prompt once; that is expected.
- **Wiping student files (destructive)**: the teacher's "Wipe Student Files" button only sends the command after typing `DELETE` in the dialog; the student deletes everything under the current user's `Documents` and `Downloads` (keeping the folders themselves) and reports per-item results to the teacher's event log. **This cannot be undone** — verify on a single test machine before deploying.

## Signing & Gatekeeper

FocusIn is currently signed with a **self-signed certificate** (`FocusIn Signing (Marco TSK)`). Without a paid Apple Developer Program membership, formal Developer ID notarization is impossible, and macOS blocks unnotarized apps ("Cannot verify developer / damaged") — this is expected.

- **Build machine**: run `bash tools/sign-focusin.sh` — it creates the certificate (first time), signs every app under `release/staging-rel`, and exports the public key to `tools/focusin-signing.cer`.
- **Student machines**: put `tools/install-cert.sh` and `focusin-signing.cer` in the same folder and run it once (admin password required). It installs the certificate, removes quarantine and adds a Gatekeeper allowlist — after that, every version opens directly.
- Quick one-time bypass: right-click the app → Open → Open again; or `xattr -dr com.apple.quarantine /Applications/FocusIn\ Teacher.app`.
- After joining the paid Apple Developer Program, switch to official **Developer ID signing + `notarytool` notarization** for zero-friction downloads; replace the signing command inside `tools/sign-focusin.sh`.

## Known Limitations

- If Screen Recording permission is missing or revoked, the teacher UI shows a red notice with an "Open Screen Recording Settings" button; after granting, press "Broadcast Teacher Screen" again.
- If Accessibility permission is missing on first lock, the student shows a prompt and guides you to System Settings; input is not intercepted until granted.
- `NSAppleScript` shutdown/restart may be denied by TCC on some newer macOS versions; the error is logged.
