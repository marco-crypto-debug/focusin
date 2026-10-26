# 🧠 Project Agent Memory: FocusIn

> **專案名稱 Project**: `FocusIn`  
> **最後更新時間 Last Updated**: `2026-10-24T17:35:55.358Z`  
> **適用 Agents**: OpenCode, Claude Desktop, Claude Code, Cursor, Windsurf, Copilot

---

> ⚠️ **MANDATORY INSTRUCTION FOR ALL AGENTS (所有 Agent 必讀指令):**
> 1. **在開始執行任何任務前**：請務必先閱讀本檔案，了解先前其他 Agent 完成了什麼、有哪些架構決定，避免重複工作或破壞現有功能。
> 2. **在完成工作或做出重要決策後**：請於下方的「🕒 1. Episodic Action Timeline」中新增記錄，註明時間、Agent 名稱、修改內容與影響檔案。

---

## 🕒 1. Episodic Action Timeline (以前的 Agent 做了些什麼)
<!-- EPISODIC_LOG_START -->
### 🔹 [2026-10-26T18:24:00.000Z] @Antigravity
- **Summary**: Overhauled StudentApp UI for Delta Edition into Apple Pro Dark Studio dashboard
- **Files Touched**: `source/app/StudentApp/Views/DeltaStudentStudioView.swift`, `source/app/StudentApp/Views/StatusView.swift`, `source/app/StudentApp/CommandListener.swift`, `source/app/StudentApp/StudentApp.swift`, `source/app/Shared/Utility/FocusInTheme.swift`, `source/app/Shared/Utility/WiFiMonitor.swift`, `source/app/TeacherApp/TeacherViewModel.swift`, `source/app/TeacherApp/Views/DeltaStudioView.swift`, `source/tools/build.sh`, `AGENT_MEMORY.md`
- **Key Decisions**:
  - Identified root cause of blank white solid slabs in student screenshot: `FocusInTheme.card` was hardcoded to pure white (`#FFFFFF`) on a `#111115` dark canvas, rendering cards blindingly bright with invisible white-on-white text, and lacking responsive container bounds.
  - Fixed `FocusInTheme.card` to resolve to `studioCard` (`#18181C`) and `line` to `studioLine` when `FOCUSIN_DELTA` is active.
  - Extracted `WiFiMonitor` into `Shared/Utility/WiFiMonitor.swift` with Darwin `getLocalIPAddress()` support, enabling shared real-time SSID and IP discovery across TeacherApp and StudentApp.
  - Made `FocusInLogoView` globally available in `FocusInTheme.swift` for unified vector branding.
  - Created `DeltaStudentStudioView.swift` implementing an Apple Pro Studio dark receiver interface:
    - **Header Bar**: Squircle FocusIn brand icon, DELTA badge, machine hostname, dynamic Wi-Fi SSID pill, Teacher connection halo capsule, and Kiosk status badge.
    - **Sub-Tabs**:
      1. `廣播接收 (Live Stream)`: 16:9 cinematic video viewport with live H.264 stream and corner telemetry tags (`🔴 LIVE`, `H.264 硬體解碼`, `48kHz PCM 音訊同步`); atmospheric ambient radar standby visualization when waiting for broadcast, and 4 telemetry cards (Teacher link, Hardware decoder, Audio engine, Kiosk shield).
      2. `安全防護 (Security & Kiosk)`: Visual `⌘⇧U` Emergency Unlock showcase card with Accessibility permission detection; salted SHA-256 local admin password management; Quit Guard protection guide.
      3. `系統診斷 (Diagnostics)`: Auto-start on login toggle (`LoginStartManager`), DisplayKeepAlive status, Accessibility permission status with one-click authorization deep link, system telemetry, and monospace terminal-style diagnostic log console with filter, copy all, and clear actions.
      4. `關於 (About)`: Identical modern Apple Pro About dashboard with squircle logo, version info, 4 info cards (Author: Marco, GitHub, Security, Platform — zero WeChat/Telegram/Donate), tech stack pills, update channel selector, and manual update checker.
    - Responsive layout with `minWidth: 860, minHeight: 580` preventing stretched horizontal bars.
  - Recompiled, signed, and generated fresh DMGs in `release/delta/FocusIn-Delta-Student.dmg` and `FocusIn-Delta-Teacher.dmg`.
### 🔹 [2026-10-25T16:38:00.000Z] @Antigravity
- **Summary**: Implemented modern About & Settings sub-navigation dashboard matching user reference UI
- **Files Touched**: `source/app/TeacherApp/Views/DeltaStudioView.swift`, `source/app/TeacherApp/TeacherViewModel.swift`, `AGENT_MEMORY.md`
- **Key Decisions**:
  - Replaced flat settings list with horizontal sub-tab navigation (`SettingsSubTab`: `通用`, `傳輸模式`, `管理密碼`, `組播探測`, `關於`) alongside a top right `💾 儲存設定` button and utility icons (`⤢`, `☀️`, `TW`).
  - Implemented modern Apple Pro About dashboard (`aboutCardView`):
    - Vector squircle brand logo (`FocusInLogoView`) with official gradient (`#FF9AAF` → `#E0416A` → `#8B3DFF`).
    - App title and subtitle: `FocusIn` / `v1.5.10-delta · Native macOS Classroom System`.
    - Information grid cards: Author (Marco), GitHub repository (direct browser link), Security Architecture (Zero-dependency / offline Ed25519), and System Environment (macOS 14+ Native).
    - **Excluded WeChat, Telegram, and Donate cards** as explicitly instructed by the user.
    - Native tech stack pills (`Swift 5`, `SwiftUI`, `ScreenCaptureKit`, `VideoToolbox`, `Network.framework`).
    - Update channel picker (`正式版 (Stable)` vs `預覽版 (Beta) ◆`).
    - Prominent blue `[ 🔄 檢查更新 ]` button with live status spinner and textual feedback.
    - Copyright footer: `Copyright © 2025-2026 FocusIn. All rights reserved.`.
  - Recompiled, code-signed, and repackaged Delta DMGs (`release/delta/FocusIn-Delta-Teacher.dmg` and `release/delta/FocusIn-Delta-Student.dmg`).
### 🔹 [2026-10-25T06:50:00.000Z] @Antigravity
- **Summary**: Implemented dynamic event-driven Wi-Fi detection to follow active network changes
  - **Files Touched**: `source/app/TeacherApp/TeacherViewModel.swift`, `source/app/TeacherApp/Info.plist`, `AGENT_MEMORY.md`
  - **Key Decisions**:
    - Discovered that previous implementation relied on `/usr/sbin/ipconfig getsummary` which returns stale cached DHCP leases from initial boot, preventing the app from updating when connecting to a different Wi-Fi.
    - Implemented `WiFiMonitor` conforming to `CWEventDelegate` with `.ssidDidChange`, `.linkDidChange`, and `.bssidDidChange` event monitoring.
    - Added CoreWLAN `lastPreferredNetworkJoined` retrieval and sanitized fallback to dynamically follow whatever Wi-Fi network the Mac is currently connected to in real time.
    - Added `NSLocationWhenInUseUsageDescription` to `Info.plist`.
    - Discarded literal `<redacted>` strings in parsing fallbacks.
    - Recompiled, signed, and generated fresh DMGs in `release/delta/`.
### 🔹 [2026-10-25T04:14:00.000Z] @Antigravity
- **Summary**: Changed sidebar header to display exclusively the current Wi-Fi name
  - **Files Touched**: `source/app/TeacherApp/Views/DeltaStudioView.swift`, `source/app/TeacherApp/TeacherViewModel.swift`, `AGENT_MEMORY.md`
  - **Key Decisions**:
    - Removed the "Local network" subtitle entirely from `sidebarView` in `DeltaStudioView.swift`.
    - Implemented `nonisolated static func detectCurrentWiFiSSID()` in `TeacherViewModel` to synchronously resolve the active Wi-Fi SSID at initialization, preventing any placeholder text flash.
    - Top-left header now cleanly shows exclusively the current Wi-Fi name directly alongside the online status capsule.
    - Recompiled, signed, and generated fresh DMGs in `release/delta/`.
### 🔹 [2026-10-25T04:03:00.000Z] @Antigravity
- **Summary**: Excluded TeacherApp from ScreenCaptureKit filter to eliminate infinite recursive preview loop
  - **Files Touched**: `source/app/TeacherApp/TeacherViewModel.swift`, `source/app/TeacherApp/ScreenBroadcaster.swift`, `AGENT_MEMORY.md`
  - **Key Decisions**:
    - Identified root cause of infinite recursive mirror tunnel in preview card: `SCContentFilter(display: targetDisplay, excludingWindows: [])` was capturing TeacherApp's own window rendering the preview.
    - Updated both `captureStandbyPreview()` in `TeacherViewModel` and `ScreenBroadcaster.start()` / `switchDisplay(to:)` to resolve the current process ID (`ProcessInfo.processInfo.processIdentifier`) and exclude the TeacherApp application via `SCContentFilter(display: targetDisplay, excludingApplications: [myApp], exceptingWindows: [])` (with window exclusion fallback).
    - TeacherApp preview now displays the teacher's clean desktop, wallpapers, slides, and background apps without capturing itself.
    - Recompiled, code-signed, and repackaged Delta DMGs (`release/delta/FocusIn-Delta-Teacher.dmg` and `release/delta/FocusIn-Delta-Student.dmg`).
### 🔹 [2026-10-25T02:56:00.000Z] @Antigravity
- **Summary**: Switched primary lab title directly to dynamic Wi-Fi SSID with Local network subtitle
  - **Files Touched**: `source/app/TeacherApp/Views/DeltaStudioView.swift`, `AGENT_MEMORY.md`
  - **Key Decisions**: Updated DeltaStudioView sidebar header to use `viewModel.currentWiFiName` directly as the main bold headline, replacing placeholder "iMac Lab" and displaying "Local network" as clean subtext. Repackaged and signed Delta DMGs.
### 🔹 [2026-10-25T02:50:00.000Z] @Antigravity
- **Summary**: Implemented real-time desktop screen preview with Screen Recording permission fallback and dynamic Wi-Fi SSID detection
  - **Files Touched**: `source/app/TeacherApp/TeacherViewModel.swift`, `source/app/TeacherApp/Views/DeltaStudioView.swift`, `AGENT_MEMORY.md`
  - **Key Decisions**:
    - Replaced static "Room 204" with dynamic Wi-Fi SSID detection using `CWWiFiClient` and `ipconfig getsummary` fallback to bypass macOS 14+ CoreLocation restriction, dynamically displaying the connected network name in sidebar and stream telemetry card.
    - Implemented real desktop screen preview in Studio: When broadcasting, live 30fps stream feeds `onPreviewImage` (8fps); when on standby, `SCScreenshotManager` captures 720p snapshots every 1.5s so the preview is always actual live desktop content.
    - Added in-viewport Screen Recording permission detection (`CGPreflightScreenCaptureAccess`): If permission is missing, displays an interactive permission request card with direct one-click button to open macOS System Settings and trigger `CGRequestScreenCaptureAccess`.
    - Repackaged and signed Delta Teacher & Student applications and generated fresh DMGs in `release/delta/`.
### 🔹 [2026-10-25T01:50:00.000Z] @Antigravity
- **Summary**: Upgraded FocusIn Delta Edition UI to Apple Pro Studio dark aesthetic & overhauled student lock screen
  - **Files Touched**: `source/app/TeacherApp/Views/DeltaStudioView.swift`, `source/app/TeacherApp/Views/DeviceListView.swift`, `source/app/TeacherApp/TeacherViewModel.swift`, `source/app/TeacherApp/ScreenBroadcaster.swift`, `source/app/StudentApp/Kiosk/KioskLockView.swift`, `source/app/StudentApp/Views/StatusView.swift`, `source/app/Shared/Utility/FocusInTheme.swift`, `source/tools/build.sh`, `AGENT_MEMORY.md`
  - **Key Decisions**:
    - Built `DeltaStudioView`: Apple-grade Pro Studio dark dashboard matching the official web interactive demo. Features live 16:9 Screen Preview with realtime downsampled capture, dynamic latency Sparkline chart, live student Mac grid cards with selection/isolation, and categorized activity log stream.
    - Integrated multi-tab navigation: Studio Console (`DeltaStudioTab.studio`), Classroom Tools (`DeltaStudioTab.tools` for brightness presets, quick app launchers, power control, safe folder wipe), and Advanced Settings (`DeltaStudioTab.settings` for UDP multicast vs WebSocket, admin password, multicast probe, auto-start, update checker).
    - Upgraded StudentApp `KioskLockView` to matching dark ambient obsidian canvas with glowing circular red lock badge, `⌘⇧U Emergency Unlock` pill, and `● Input blocked` indicator.
    - Added throttled 120ms local screen capture preview (`onPreviewImage`) in `ScreenBroadcaster` to provide real-time stream feedback in TeacherApp without overhead.
    - Successfully compiled, signed, and generated verified DMG distribution bundles (`FocusIn-Delta-Teacher.dmg` and `FocusIn-Delta-Student.dmg`) and `.app` bundles in `release/delta/`.
### 🔹 [2026-10-24T18:00:00.000Z] @OMO
- **Summary**: Aligned shared memory protocol & fully documented FocusIn architecture, Swift standards, and AVAudioEngine pitfalls
  - **Files Touched**: `AGENT_MEMORY.md`, OMO persistent memory repo
  - **Key Decisions**: Documented AVAudioEngine 6 major pitfalls (format lock crash, in-flight retention, mandatory interleaved buffers, jitter pre-roll, drop-new-keep-old, engine start error handling) and past failed approaches. Established dual-agent (OpenCode / OMO) logging protocol.
### 🔹 [2026-10-24T17:35:55.357Z] @OpenCode
- **Summary**: Configured multi-agent shared memory and FocusIn directive
  - **Files Touched**: `CLAUDE.md`, `.cursorrules`, `.windsurfrules`
  - **Key Decisions**: Injected FocusIn architecture constraints and AVAudioEngine anti-gotcha directive into all agent configs
### 🔹 [2026-10-24T17:35:41.220Z] @system
- **Summary**: Initialized project agent memory & injected cross-agent workflow rules.
- **Files Touched**: `AGENT_MEMORY.md`, `CLAUDE.md`, `.cursorrules`, `.windsurfrules`
- **Key Decisions**: Enabled multi-agent memory tracking across OpenCode, Claude, Cursor, and Windsurf.

---

## 🧠 2. Semantic Memory (專案核心事實、架構與約定)
<!-- SEMANTIC_START -->
- **專案目標**: 零外部依賴、原生 macOS 區域網路廣播與教學管理系統（TeacherApp 主控端廣播螢幕與音訊、StudentApp 全螢幕鎖屏與音畫同步播放）。
- **技術棧 (Tech Stack)**:
  - macOS 13+ 原生 SDK：Swift 5、SwiftUI、Network.framework、ScreenCaptureKit、VideoToolbox、AVFAudio、CryptoKit。
  - 無第三方 Swift 套件依賴（Zero external Swift dependencies）。
  - 後端：Cloudflare Workers (Ed25519 授權簽發) + Cloudflare Pages (靜態官網)。
- **核心架構與目錄結構**:
  - `source/app/TeacherApp/`: 教師主控端（螢幕音訊擷取、VideoToolbox H.264 編碼器、Peer 管理、UI）。
  - `source/app/StudentApp/`: 學生端（Kiosk 鎖屏視窗 `.screenSaver` 層級、CGEventTap 輸入攔截器、VideoToolbox H.264 解碼器、AVAudioEngine 播放器）。
  - `source/app/Shared/Networking/`: 網路引擎（PeerConnection WebSocket、PeerDiscovery mDNS、MulticastTransport UDP 組播 `239.255.42.99:7200`、AirPlayAudioStream 時鐘同步）。
  - `source/app/Shared/Protocol/`: 通訊協定（CommandMessage JSON 控制通道、二進位 Magic Header 封包）。
  - `source/app/Shared/Utility/`: 通用工具（FocusInTheme 主題色、DiagLog 診斷日誌、QuitGuard 防退密碼、UpdateChecker 更新檢查、DeviceLimit 統一 50 台裝置上限）。
  - `source/tools/build.sh`: 多版本統一建置腳本（支援 `stable`, `alpha`, `beta`, `delta`, `all`）。
- **關鍵架構約束 (Architectural Constraints)**:
  - **非沙盒架構**: 雙端皆為非沙盒 (`com.apple.security.app-sandbox = false`)，以支援 ScreenCaptureKit、CGEventTap、磁碟操作。
  - **二進位魔術標頭 (Binary Magic Multiplexing)**:
    - `FZAU`: PCM 音訊幀（取樣率 + 聲道 + 位深 + 浮點 + 交錯旗標 + PCM payload）。
    - `FZHV`: H.264 UDP 組播視訊幀。
    - `FZFR`: H.264 單播視訊幀。
    - `FZMP`: AP 組播探測封包。
    - `APAU`: AirPlay 時鐘同步音訊封包（4-byte magic + Mach timebase pts + clockID + PCM payload）。
    - `APVD`: 多顯示器串流封包（displayID + displayIndex + keyframe + pts + videoData）。
    - **禁止包裝**: 視訊與音訊二進位串流嚴禁包裝為 JSON 或 base64。
  - **網路執行緒安全**: Network.framework `NWConnection.send` 嚴禁跨執行緒並行呼叫，一律經由專屬 serial queue 發送。
  - **XcodeGen 管理**: 嚴禁手動修改 `FocusIn.xcodeproj/project.pbxproj`，必須修改 `source/app/project.yml` 後執行 `xcodegen generate`。
  - **版本與定價**: v1.5.10 起移除 Pro 授權硬性阻斷，全版本預設統一 50 台設備上限，傳輸與聲音功能向所有版本開放。
<!-- SEMANTIC_END -->

---

## 🛠 3. Procedural Rules (工作規範與防踩坑指南)
<!-- PROCEDURAL_START -->
- **開工前檢索約定 (Pre-task Check)**:
  - 每次開工前，必須優先檢閱 `AGENT_MEMORY.md` 與專案 shared memory，確認架構邊界、Swift 規範、AVAudioEngine 踩坑歷史與過往失敗方案。
- **重要決策自動記錄 (Post-task Logging)**:
  - 完成一輪重要決策、找出 bug 根因、確認架構方案後，自動記錄至 `AGENT_MEMORY.md` 的「Episodic Action Timeline」，標記來源 Agent：`@OpenCode` 或 `@OMO`。
  - 只記錄長期有價值之事實，不記錄瑣碎日常對話。
- **Swift 規範 (Swift Guidelines)**:
  - Swift 5/6 嚴格並發：UI 狀態綁定 `@MainActor`，異步回調使用 `[weak self]`。
  - 記憶體生命週期：在渲染執行緒（Audio/Video Render Thread）讀取期間，物件必須維持強引用保活，杜絕野指標。
  - 條件編譯：音訊與組播等高階功能需配合標誌編譯（`#if FOCUSIN_ALPHA || FOCUSIN_DELTA`），保證 `stable` 版無條件乾淨編譯。
- **建置指令 (Build & Verify Commands)**:
  - 專案建置：`bash source/tools/build.sh <variant>`（如 `delta`, `beta`, `stable`, `all`）。
  - Xcode 專案產生：`cd source/app && xcodegen generate`。
  - 官網打包與發布：`python3 source/tools/build-site-apple.py` 以及 `bunx wrangler pages deploy source/web/public --project-name focusin`。
- **Git 規範**: 每次修改代碼前確認 git checkpoint，依使用者指示提交 commit。
<!-- PROCEDURAL_END -->

---

## 🔍 4. Reflective Notes & Known Issues (反思與已知問題)
<!-- REFLECTIVE_START -->
- **AVAudioEngine 踩坑與防護心法 (Audio Engine Gotchas)**:
  1. **格式鎖死與渲染崩潰 (Format Lock Crash)**:
     - *根因*: `AVAudioPlayerNode` 啟動後即鎖定輸出格式，若排入不同格式（取樣率、聲道數、位深變更）的 buffer，渲染執行緒轉換器指針錯位產生 `EXC_BAD_ACCESS` (IOThread.client + memmove)。
     - *解法*: 廣播期間鎖定首個合法塊之格式（`lockedFormat`），後續格式不符或畸形之塊一律丟棄拒收。
  2. **在飛緩衝保活 (In-Flight Buffer Retention)**:
     - *根因*: 異步渲染執行緒讀取資料期間，若緩衝區提早釋放會造成記憶體崩潰。
     - *解法*: 維護 `inFlight: [AVAudioPCMBuffer]` 強引用陣列，待 `scheduleBuffer` 完成回調在主執行緒執行時才移除引用。
  3. **強制交錯格式 (Mandatory Interleaved Layout)**:
     - *根因*: 非交錯（Planar）緩衝在多聲道分通道指針運算與 `mDataByteSize` 假設容易出現越界。
     - *解法*: 無論線上資料是否交錯，建立 `AVAudioPCMBuffer` 時一律宣告 `interleaved: true`，以單一連續記憶體做平面拷貝或手動重排。
  4. **抖動緩衝與佇列乾涸 (Jitter Pre-roll Buffer)**:
     - *根因*: Wi-Fi 網路封包抖動，任一 80ms 塊延遲抵達即導致播放佇列乾涸與聲音卡頓。
     - *解法*: 設定預卷機制（`preRollChunks = 3`，約 240ms），累積滿才啟動播放；若佇列乾涸重設 `isPrimed = false`，重新等待預卷。
  5. **積壓上限與丟新保舊 (Drop New, Keep Old)**:
     - *根因*: 累積超過上限時若丟棄舊塊，會製造音訊波形時間斷層，聽感呈現嚴重低頻風鳴或破音（馬達聲）。
     - *解法*: 當積壓超過上限（8 塊 ≈ 640ms）時，直接丟棄「新到的」塊，保持已排程音訊的連續性。
  6. **無輸出裝置防護**:
     - *根因*: 學生端設備無耳機/揚聲器時 `engine.start()` 拋出錯誤。
     - *解法*: 用 do-catch 捕捉並寫入 `DiagLog`，防止整體應用崩潰。

- **過往失敗方案總結 (Avoid Past Mistakes)**:
  - ❌ **JSON / Base64 傳輸音畫**: 曾嘗試以 JSON/base64 包裝幀資料，造成嚴重的 CPU 負載、記憶體抖動與數百毫秒延遲。現全面採用二進位 Magic Header。
  - ❌ **無緩衝即收即播**: 網路稍有抖動即嚴重破音，必須透過 Jitter Buffer 預卷平滑化。
  - ❌ **丟舊保新調度**: 舊塊被丟棄導致的音頻斷點會產生巨大刺耳爆音與低頻哼聲，必須採「丟新保舊」。
  - ❌ **動態非交錯 AudioBufferList 指標計算**: 極易在 Apple Silicon 記憶體對齊與執行緒競爭中崩潰，改採統一交錯單塊連續記憶體。
  - ❌ **螢幕廣播後處理銳化濾鏡**: 曾嘗試後處理以增強畫質，結果反而造成畫面邊緣毛邊劣化且消耗算力，已全數移除還原原生畫面。
  - ❌ **前端儲存授權私鑰種子**: 早期在官網前端驗證/生成金鑰造成安全性隱憂，現已完全遷至 Cloudflare Worker 後端與 Ed25519 離線簽章機制。
<!-- REFLECTIVE_END -->
