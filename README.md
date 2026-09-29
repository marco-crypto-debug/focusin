# FocusIn — macOS 課堂管理（教師端 / 學生端）

FocusIn 是面向 iMac 機房的區域網課堂管理方案：教師端（TeacherApp）自動發現學生端、即時廣播教師屏幕**與聲音**、下發鎖屏/解鎖/關機/重新啟動/啟動應用程式指令；學生端（StudentApp）提供 Kiosk 全屏鎖定、輸入攔截與本地緊急解鎖，並可設定登入時自動啟動。

技術棧：Swift / SwiftUI（macOS 13+）、Network.framework（WebSocket + Bonjour/mDNS）、ScreenCaptureKit。

## 架構

```
┌─────────────────────────────┐              ┌─────────────────────────────┐
│        TeacherApp           │              │        StudentApp           │
│                             │   Bonjour    │                             │
│  PeerBrowser  ──發現( mDNS )──────→  PeerAdvertiser (_classroom-ctrl._tcp.)│
│  ScreenBroadcaster          │              │  CommandListener            │
│  (ScreenCaptureKit→JPEG)    │              │   ├─ lock/unlock → Kiosk    │
│  CommandCenter              │◄─WebSocket──►│   ├─ shutdown/restart       │
│                             │  命令/幀     │   ├─ launchApp(NSWorkspace) │
│                             │              │   └─ streamFrame → 鎖窗顯示 │
└─────────────────────────────┘              └─────────────────────────────┘
        同一 Wi-Fi 區域網 / 同一子網路
```

## 目錄結構

```
ClassroomManager/
├── README.md
├── project.yml                     # XcodeGen 工程定義（一鍵生成兩個 Xcode 工程）
├── Shared/                         # 兩端共用的原始碼（同時編譯進兩個 target）
│   ├── Networking/
│   │   ├── PeerTransport.swift     # NWParameters 工廠（WebSocket 應用程式協定）
│   │   ├── PeerConnection.swift    # WebSocket 連線封裝：收發 CommandMessage
│   │   └── PeerDiscovery.swift     # PeerAdvertiser(學生) / PeerBrowser(教師)
│   └── Protocol/
│       ├── CommandType.swift       # 命令列舉：lock/unlock/shutdown/restart/launchApp/stream*
│       └── CommandMessage.swift    # JSON 訊息信封
├── Shared/Utility/
│   ├── LoginStartManager.swift     # 登入時自動啟動（LaunchAgent 註冊，兩端共用）
│   └── UpdateChecker.swift         # 自動更新檢查（GitHub API：Release tag / commit SHA）
├── TeacherApp/
│   ├── TeacherApp.swift            # @main 入口
│   ├── TeacherViewModel.swift      # 發現/連線/命令分發
│   ├── ScreenBroadcaster.swift     # ScreenCaptureKit 採集 → JPEG 幀 + 音訊 PCM
│   ├── Views/DeviceListView.swift  # 裝置列表 + 控制面板 UI（含畫質/自動啟動）
│   ├── Info.plist
│   └── TeacherApp.entitlements
└── StudentApp/
    ├── StudentApp.swift            # @main 入口
    ├── CommandListener.swift       # 公布服務 + 命令監聽 + 系統動作
    ├── AudioPlayer.swift           # 廣播音訊播放（AVAudioEngine）
    ├── FileWipeManager.swift       # 清空 Documents + Downloads（教師下發）
    ├── Views/StatusView.swift      # 狀態視窗（管理員密碼 + 自動啟動 + 更新檢查）
    ├── Kiosk/
    │   ├── KioskModeController.swift # 全屏鎖窗 + presentationOptions + 解鎖流程
    │   ├── InputInterceptor.swift    # CGEventTap 鍵盤/滑鼠攔截
    │   ├── KioskLockView.swift       # 鎖屏介面（廣播畫面 + 密碼輸入）
    │   └── KioskConfig.swift         # 管理員密碼加鹽雜湊儲存
    ├── Info.plist
    └── StudentApp.entitlements
```

## 構建與運行

方式 A：XcodeGen（推薦，一條命令生成兩個工程）

```bash
brew install xcodegen
cd ClassroomManager
xcodegen generate        # 生成 TeacherApp.xcodeproj / StudentApp.xcodeproj
open TeacherApp.xcodeproj    # 選擇 TeacherApp scheme，⌘R 運行
open StudentApp.xcodeproj    # 選擇 StudentApp scheme，⌘R 運行
```

方式 B：手動建工程（不用 XcodeGen）
1. Xcode → New Project → macOS → App，語言 Swift，介面 SwiftUI。
2. 將 `TeacherApp`、`Shared` 資料夾拖入 TeacherApp target；`StudentApp`、`Shared` 拖入 StudentApp target。
3. Build Settings：`MACOSX_DEPLOYMENT_TARGET = 13.0`；Info.plist 分別指定對應檔案；Entitlements 指向對應 `.entitlements` 檔案。
4. 建議對兩個 target 使用獨立簽名 Team（本地開發可直接 Sign to Run Locally）。

部署流程
1. 學生機先啟動 FocusIn 學生端（StudentApp）→ 在狀態視窗設定本地管理員密碼（至少 4 位；之後變更密碼需先輸入目前密碼）；建議勾選「登入時自動啟動學生端」，開機登入即自動就緒。
2. 教師機啟動 FocusIn 教師端（TeacherApp）→ 自動發現學生端（同一 Wi-Fi）；可勾選「登入時自動啟動教師端」。
3. 勾選「全部學生」或具體裝置 → 廣播（含聲音）/ 鎖定 / 解鎖 / 關機 / 重新啟動 / 啟動應用程式。
4. 學生端鎖定時：教師可隨時下發 `unlock`；若網路中斷，本地管理員按 **⌘⇧U** 輸入預設密碼緊急解鎖。

## 權限清單

### 1. 系統設定（System Settings → Privacy & Security）

| 應用程式 | 權限 | 用途 | 位置 |
|---|---|---|---|
| FocusIn 教師端（TeacherApp） | 屏幕錄製 (Screen Recording) | 採集教師屏幕**與聲音**用於廣播（音訊採集共用同一權限） | 私隱與安全性 → 屏幕錄製 |
| FocusIn 學生端（StudentApp） | 輔助功能 (Accessibility) | CGEventTap 攔截鍵盤/滑鼠 | 私隱與安全性 → 輔助功能 |
| FocusIn 學生端（StudentApp） | 自動化 (Automation, 可選) | 關機/重新啟動走 System Events，首次執行會彈授權框 | 私隱與安全性 → 自動化 |
| 兩端 | 本地網路/防火牆 | macOS 防火牆首次運行可能彈「接受傳入連線」，需允許 | 系統設定 → 網路 → 防火牆 |

> **屏幕錄製授權指引（教師端）**：點擊「廣播教師屏幕」時，若未授權，教師端會先在介面顯示紅色提示並附「開啟屏幕錄製設定」按鈕（一鍵跳到 系統設定 → 私隱與安全性 → 屏幕錄製），同時觸發系統授權彈窗。請在該頁面勾選 **FocusIn 教師端（TeacherApp）** 後重新點擊「廣播教師屏幕」。若之前選過「拒絕」，需先在該頁面取消勾選再重新勾選。
>
> **廣播畫面在哪看（學生端）**：教師鎖定學生端後，廣播畫面在鎖屏全屏顯示；未鎖定時，學生端狀態視窗會顯示廣播預覽，方便先確認畫面與網路正常。

### 2. Info.plist 鍵（已在檔案內提供）

| Key | 所在應用程式 | 說明 |
|---|---|---|
| `NSScreenCaptureUsageDescription` | TeacherApp | 屏幕錄製用途說明（TCC 提示文案） |
| `NSAppleEventsUsageDescription` | StudentApp | 向 System Events 發 Apple Events 的用途說明 |

### 3. Entitlements

工程預設**關閉 App Sandbox**（`com.apple.security.app-sandbox = false`），並預置 `com.apple.security.network.client / server` 兩個網路權限。若未來開啟沙箱，這兩項即可覆蓋 WebSocket 收發；開啟沙箱還會要求其他能力（如 `com.apple.security.temporary-exception.apple-events` 才能向 System Events 發 Apple Events）。

## 協定參考（WebSocket 二進位幀，JSON 信封）

| type | 方向 | payload | 說明 |
|---|---|---|---|
| `hello` / `helloAck` | S→T / T→S | — | 握手，hello 攜帶裝置名稱 |
| `lock` / `unlock` | T→S | — | 進入 / 退出 Kiosk |
| `shutdown` / `restart` | T→S | — | 遠端關機 / 重新啟動（System Events） |
| `launchApp` | T→S | Bundle ID | 啟動應用程式（NSWorkspace） |
| `deleteAllFiles` | T→S | — | 清空學生端 Documents + Downloads（教師點擊 + 輸入 DELETE 確認） |
| `wipeResult` | S→T | 摘要文字 | 清空執行結果回執 |
| `streamStart` / `streamStop` | T→S | — | 廣播開始 / 結束 |
| 廣播幀（二進位） | T→S | 魔數 `FZFR` + 原始 JPEG | 低延遲路徑：跳過 JSON/base64（約省 33% 體積與大量編解碼） |
| 廣播音訊（二進位） | T→S | 魔數 `FZAU` + 格式標頭 + PCM | 44.1kHz 立體聲；**走專屬連線**（hello payload = `audio` 標記），與畫面分開；教師端把 SCStream 的非交錯 PCM **重排成交錯格式**後以 ~80ms 聚合送出（跨塊拼接永遠連續，杜絕左右聲道交替切片造成的低頻風鳴）；學生端 AVAudioEngine 播放 + 抖動緩衝（預卷 3 塊 ≈240ms，積壓超限**丟新不丟舊**，播放連續且延遲有界） |
| `ping` / `pong` | 雙向 | — | 應用程式層保活 + 即時延遲測量（教師端每 3 秒測一次，UI 顯示每台學生端 ms） |

> 崩潰防護：教師端每次廣播鎖定一個規範音訊格式（首個緩衝決定），格式不符的緩衝直接丟棄；學生端同樣鎖定首塊格式並拒收畸形/異構格式塊（取樣率 8k-96k、1-2 聲道、16/32 位元），已排入節點的緩衝以強引用保活至播完——杜絕渲染執行緒讀到異構格式或已釋放記憶體造成的 EXC_BAD_ACCESS 崩潰。

> 延遲優化：TCP 啟用 `TCP_NODELAY`；教師端編碼節流（編不過來丟舊幀、不積壓）；每條連線同一時間只允許一幀在途；學生端 JPEG 解碼在背景佇列進行；**音訊走專屬 WebSocket 連線**（與畫面分流，消除大幀頭部阻塞），採集端把非交錯 PCM 重排成交錯格式並以 ~80ms 塊送出（保證跨塊拼接連續、左右聲道正確）；學生端以**抖動緩衝**平滑 Wi-Fi 到達抖動（預卷 ~240ms、積壓超限丟新不丟舊以保持播放連續），並以正確的「聲道數×每採樣位元組」計算幀數；教師端每 3 秒以 ping/pong 測量每台學生端的即時延遲並在裝置列顯示。

> 廣播畫質由教師端介面切換（自動/低/中/高），採集參數集中在 `TeacherApp/ScreenBroadcaster.swift` 的 `BroadcastQuality` 與 `resolutionParameters`，如需自訂可在該處修改。

## 鎖屏機制說明（StudentApp）

Kiosk 由三層組成，任一被攻破仍有兜底：

1. **presentationOptions**：隱藏 Dock/選單列，停用 ⌘⇥、⌘⌥⎋ 等系統級入口（新系統還可停用 ⌘Space、⌘⇧3/4、控制中心/通知中心；為相容舊 SDK，本工程使用最小集合）。
2. **CGEventTap（.cghidEventTap）**：系統級吞掉全部鍵盤/滑鼠事件，硬攔截 ⌘⇥、⌘⌥⎋、⌃←/⌃→、⌘Space、⌘⇧3/4 等一切快捷鍵；需要輔助功能權限。
3. **全屏無邊框鎖窗（level = .screenSaver）**：覆蓋所有顯示器、所有 Space，遮住選單列與 Dock；以 `orderFrontRegardless()` 強制抬升，即使學生機正處於其他 App 的全屏模式也能蓋住。鎖定期間的自愈機制：螢幕參數變化（外接顯示器接上/喚醒、解析度改變）會自動重建鎖窗避免漏縫；若被其他 App 搶走焦點（如尚未授予輔助功能權限時按 ⌘⇥），會自動奪回焦點、抬升鎖窗並補裝輸入攔截。

緊急解鎖：本地按 **⌘⇧U** → 輸入攔截器暫時卸載 → 鎖窗顯示密碼框（自動聚焦，直接輸入即可）→ 校驗加鹽 SHA-256 雜湊 → 正確則退出 Kiosk；錯誤或 60 秒逾時則自動恢復攔截重新鎖死，鎖屏會顯示對應提示。

> 緊急解鎖注意事項：
> - **必須先在學生端狀態視窗設定本地管理員密碼**；若未設定，按 ⌘⇧U 會在鎖屏顯示「未設定本地管理員密碼」提示並保持鎖定（不會出現無法輸入的死鎖密碼框）。
> - **⌘⇧U 依賴「輔助功能」權限**：未授權時輸入攔截器不會安裝，組合鍵無法被偵測，鎖屏會顯示黃色「需要輔助功能權限」提示。請在系統設定 → 私隱與安全性 → 輔助功能 中勾選 FocusIn 學生端（StudentApp）。
> - ⌘⇧U 必須在**被鎖定的學生機本機**按下；在教師機上按無效。

## 安全與運維注意事項

- **信任模型**：本設計假設教室區域網可信。WebSocket 為明文，若要跨不可信網路部署，應在 `PeerTransport.webSocketParameters()` 中疊加 `NWProtocolTLS.Options` 並做憑證校驗。
- **遠端關機/重新啟動**：`System Events` 方案首次會彈自動化授權，部分網路帳戶環境可能要求管理員權限；也可改用 `Process` 執行 `/sbin/shutdown -h now` / `-r now`（需 root）。
- **Kiosk 的邊界**：事件攔截只作用於圖形會話內的輸入；對 SSH、另一個管理員帳戶、或直接 kill 程序沒有防禦力。生產級機房管理應疊加 MDM（Jamf / Apple School Manager / 描述檔 + 單一 App 模式）。
- **Wi-Fi 注意**：若學校 AP 開啟「用戶端隔離」，Bonjour 發現與直連會被阻斷；請在支援多播/二層互通的 VLAN 上運行。
- **效能**：廣播畫質可於教師端切換——**高**：原生全分辨率（30fps，JPEG 0.92）；**中**：0.75 縮放（30fps）；**低**：0.5 縮放（24fps）；**自動**：≤4K 用原生分辨率，5K 以上微縮至 0.85。區域網環境建議使用「高」或「自動」。聲音以 44.1kHz 立體聲 PCM 隨廣播同步傳輸，學生端即時播放。
- **登入時自動啟動**：兩端介面均有開關，透過寫入 `~/Library/LaunchAgents/<bundleID>.plist`（LaunchAgent，RunAtLoad）註冊。取消勾選即移除；App 移動位置後重新勾選一次即可更新路徑。
- **自動更新檢查**：兩端啟動時自動查 GitHub（`marco-crypto-debug/focusin`）——有 Release 比對 tag，否則比對 main 分支最新 commit SHA 與本機構建 SHA（構建時寫入 `CFBundleVersion`）。發現新版本即在介面提示，可一鍵前往 GitHub 下載；也可手動「檢查更新」。首次構建於未推送提交時會提示一次，屬正常現象。
- **清空學生文件（破壞性）**：教師端「清空學生文件」按鈕需點擊後在彈窗輸入 `DELETE` 才會下發；學生端只刪除目前使用者家目錄下的 `Documents` 與 `Downloads` 全部內容（資料夾本身保留），逐項回報結果至教師端事件日誌。此操作**不可復原**，部署前請先在單台測試機驗證。

## 已知限制

- 屏幕錄製權限若未授權或遭撤銷，教師端廣播會在介面顯示紅色提示與「開啟屏幕錄製設定」按鈕引導開啟；權限恢復後重新點擊「廣播教師屏幕」即可。
- 學生端首次鎖定若輔助功能權限缺失，會彈提示並引導開啟系統設定；未授權期間輸入不會被攔截。
- `NSAppleScript` 關機/重新啟動在部分新 macOS 上可能被 TCC 拒絕，日誌會記錄錯誤。
