**English** · [繁体中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md)

---

# FocusIn — macOS 课堂管理（教师端 / 学生端）

FocusIn 是面向 iMac 机房的局域网课堂管理方案：教师端（TeacherApp）自动发现学生端、即时广播教师屏幕（正式版为高清画面，Alpha 版另含声音）、下发锁屏/解锁/关机/重新启动/启动应用程序/清空文件指令；学生端（StudentApp）提供 Kiosk 全屏锁定、输入拦截、退出保护与本地紧急解锁，并可设定登入时自动启动。

技术栈：Swift / SwiftUI（macOS 14+）、Network.framework（WebSocket + Bonjour/mDNS）、ScreenCaptureKit。

## 版本划分

- **stable（正式版）**：`release/stable/` 下的 `FocusIn-Teacher.dmg` + `FocusIn-Student.dmg`。**仅传画面**（程式码层面不采集、不传输、不播放声音，彻底避开音讯渲染链路）；含 Kiosk 全屏锁定、输入拦截、**退出保护（管理员密码，未设密码无法退出 ⌘Q）**、**统一管理员密码（教师端设定即下发所有学生端，同时用于教师端退出、学生端退出、紧急解锁 ⌘⇧U）**、**广播画面锐化**、锁屏/解锁、关机/重启、启动应用程序、**清空文件（Documents + Downloads，需输 DELETE 二次确认）**、自动更新、登入自动启动。课堂环境请使用此版。
- **alpha（含声音测试版）**：`release/alpha/` 下的 `FocusIn-Alpha-Teacher.dmg` + `FocusIn-Alpha-Student.dmg`。教师端与学生端含**声音广播**（48kHz 立体声，专属音讯通道 + 抖动缓冲 + 双端格式锁 + 交错缓冲播放）。此版用于测试/回报音讯问题，不代表稳定交付。教师端另有“传送声音”开关可临时只传画面。
- **beta（已并入 stable，GitHub 保留历史）**：原“稳定+锁定”测试渠道已于 v1.3.9 并入正式版（退出保护、统一管理员密码、广播锐化），不再维护新版本；历史 Release 与 Tag 保留于 GitHub（`v1.3.x-beta`）。

## 架构

```
┌─────────────────────────────┐              ┌─────────────────────────────┐
│        TeacherApp           │              │        StudentApp           │
│                             │   Bonjour    │                             │
│  PeerBrowser  ──发现( mDNS )──────→  PeerAdvertiser (_classroom-ctrl._tcp.)│
│  ScreenBroadcaster          │              │  CommandListener            │
│  (ScreenCaptureKit→JPEG)    │              │   ├─ lock/unlock → Kiosk    │
│  CommandCenter              │◄─WebSocket──►│   ├─ shutdown/restart       │
│                             │  命令/帧     │   ├─ launchApp(NSWorkspace) │
│                             │              │   └─ streamFrame → 锁窗显示 │
└─────────────────────────────┘              └─────────────────────────────┘
        同一 Wi-Fi 局域网 / 同一子网络
```

## 目录结构

```
ClassroomManager/
├── README.md
├── project.yml                     # XcodeGen 工程定义（一键生成两个 Xcode 工程）
├── Shared/                         # 两端共用的源代码（同时编译进两个 target）
│   ├── Networking/
│   │   ├── PeerTransport.swift     # NWParameters 工厂（WebSocket 应用程序协定）
│   │   ├── PeerConnection.swift    # WebSocket 连线封装：收发 CommandMessage
│   │   └── PeerDiscovery.swift     # PeerAdvertiser(学生) / PeerBrowser(教师)
│   └── Protocol/
│       ├── CommandType.swift       # 命令列举：lock/unlock/shutdown/restart/launchApp/stream*
│       └── CommandMessage.swift    # JSON 讯息信封
├── Shared/Utility/
│   ├── LoginStartManager.swift     # 登入时自动启动（LaunchAgent 注册，两端共用）
│   └── UpdateChecker.swift         # 自动更新检查（GitHub API：Release tag / commit SHA）
├── TeacherApp/
│   ├── TeacherApp.swift            # @main 入口
│   ├── TeacherViewModel.swift      # 发现/连线/命令分发
│   ├── ScreenBroadcaster.swift     # ScreenCaptureKit 采集 → JPEG 帧 + 音讯 PCM
│   ├── Views/DeviceListView.swift  # 装置列表 + 控制面板 UI（含画质/自动启动）
│   ├── Info.plist
│   └── TeacherApp.entitlements
└── StudentApp/
    ├── StudentApp.swift            # @main 入口
    ├── CommandListener.swift       # 公布服务 + 命令监听 + 系统动作
    ├── AudioPlayer.swift           # 广播音讯播放（AVAudioEngine）
    ├── FileWipeManager.swift       # 清空 Documents + Downloads（教师下发）
    ├── Views/StatusView.swift      # 状态视窗（管理员密码 + 自动启动 + 更新检查）
    ├── Kiosk/
    │   ├── KioskModeController.swift # 全屏锁窗 + presentationOptions + 解锁流程
    │   ├── InputInterceptor.swift    # CGEventTap 键盘/鼠标拦截
    │   ├── KioskLockView.swift       # 锁屏界面（广播画面 + 密码输入）
    │   └── KioskConfig.swift         # 管理员密码加盐杂凑储存
    ├── Info.plist
    └── StudentApp.entitlements
```

## 构建与运行

方式 A：XcodeGen（推荐，一条命令生成两个工程）

```bash
brew install xcodegen
cd ClassroomManager
xcodegen generate        # 生成 TeacherApp.xcodeproj / StudentApp.xcodeproj
open TeacherApp.xcodeproj    # 选择 TeacherApp scheme，⌘R 运行
open StudentApp.xcodeproj    # 选择 StudentApp scheme，⌘R 运行
```

方式 B：手动建工程（不用 XcodeGen）
1. Xcode → New Project → macOS → App，语言 Swift，界面 SwiftUI。
2. 将 `TeacherApp`、`Shared` 资料夹拖入 TeacherApp target；`StudentApp`、`Shared` 拖入 StudentApp target。
3. Build Settings：`MACOSX_DEPLOYMENT_TARGET = 13.0`；Info.plist 分别指定对应档案；Entitlements 指向对应 `.entitlements` 档案。
4. 建议对两个 target 使用独立签名 Team（本地开发可直接 Sign to Run Locally）。

部署流程
1. 学生机先启动 FocusIn 学生端（StudentApp）→ 在状态视窗设定本地管理员密码（至少 4 位；之后变更密码需先输入目前密码）；建议勾选“登入时自动启动学生端”，开机登入即自动就绪。
2. 教师机启动 FocusIn 教师端（TeacherApp）→ 自动发现学生端（同一 Wi-Fi）；可勾选“登入时自动启动教师端”。
3. 勾选“全部学生”或具体装置 → 广播（含声音）/ 锁定 / 解锁 / 关机 / 重新启动 / 启动应用程序。
4. 学生端锁定时：教师可随时下发 `unlock`；若网络中断，本地管理员按 **⌘⇧U** 输入预设密码紧急解锁。

## 权限清单

### 1. 系统设定（System Settings → Privacy & Security）

| 应用程序 | 权限 | 用途 | 位置 |
|---|---|---|---|
| FocusIn 教师端（TeacherApp） | 屏幕录制 (Screen Recording) | 采集教师屏幕**与声音**用于广播（音讯采集共用同一权限） | 隐私与安全性 → 屏幕录制 |
| FocusIn 学生端（StudentApp） | 辅助功能 (Accessibility) | CGEventTap 拦截键盘/鼠标 | 隐私与安全性 → 辅助功能 |
| FocusIn 学生端（StudentApp） | 自动化 (Automation, 可选) | 关机/重新启动走 System Events，首次执行会弹授权框 | 隐私与安全性 → 自动化 |
| 两端 | 本地网络/防火墙 | macOS 防火墙首次运行可能弹“接受传入连线”，需允许 | 系统设定 → 网络 → 防火墙 |

> **屏幕录制授权指引（教师端）**：点击“广播教师屏幕”时，若未授权，教师端会先在界面显示红色提示并附“开启屏幕录制设定”按钮（一键跳到 系统设定 → 隐私与安全性 → 屏幕录制），同时触发系统授权弹窗。请在该页面勾选 **FocusIn 教师端（TeacherApp）** 后重新点击“广播教师屏幕”。若之前选过“拒绝”，需先在该页面取消勾选再重新勾选。
>
> **广播画面在哪看（学生端）**：教师锁定学生端后，广播画面在锁屏全屏显示；未锁定时，学生端状态视窗会显示广播预览，方便先确认画面与网络正常。

### 2. Info.plist 键（已在档案内提供）

| Key | 所在应用程序 | 说明 |
|---|---|---|
| `NSScreenCaptureUsageDescription` | TeacherApp | 屏幕录制用途说明（TCC 提示文案） |
| `NSAppleEventsUsageDescription` | StudentApp | 向 System Events 发 Apple Events 的用途说明 |

### 3. Entitlements

工程预设**关闭 App Sandbox**（`com.apple.security.app-sandbox = false`），并预置 `com.apple.security.network.client / server` 两个网络权限。若未来开启沙箱，这两项即可覆盖 WebSocket 收发；开启沙箱还会要求其他能力（如 `com.apple.security.temporary-exception.apple-events` 才能向 System Events 发 Apple Events）。

## 协定参考（WebSocket 二进制帧，JSON 信封）

| type | 方向 | payload | 说明 |
|---|---|---|---|
| `hello` / `helloAck` | S→T / T→S | — | 握手，hello 携带装置名称 |
| `lock` / `unlock` | T→S | — | 进入 / 退出 Kiosk |
| `shutdown` / `restart` | T→S | — | 远端关机 / 重新启动（System Events） |
| `launchApp` | T→S | Bundle ID | 启动应用程序（NSWorkspace） |
| `deleteAllFiles` | T→S | — | 清空学生端 Documents + Downloads（教师点击 + 输入 DELETE 确认） |
| `wipeResult` | S→T | 摘要文字 | 清空执行结果回执 |
| `streamStart` / `streamStop` | T→S | — | 广播开始 / 结束 |
| 广播帧（二进制） | T→S | 魔数 `FZFR` + 原始 JPEG | 低延迟路径：跳过 JSON/base64（约省 33% 体积与大量编解码） |
| 广播音讯（二进制） | T→S | 魔数 `FZAU` + 格式标头 + PCM | 48kHz 立体声；**走专属连线**（hello payload = `audio` 标记），与画面分开；教师端把 SCStream 的非交错 PCM **重排成交错格式**后以 ~80ms 聚合送出（跨块拼接永远连续，杜绝左右声道交替切片造成的低频风鸣）；学生端 AVAudioEngine 播放（一律以交错缓冲 + 整段拷贝建立缓冲，杜绝非交错分通道指标类别的渲染崩溃）+ 抖动缓冲（预卷 3 块 ≈240ms，积压超限**丢新不丢旧**，播放连续且延迟有界）；全链路锁定单一格式，格式不符的块两端一律丢弃 |
| `ping` / `pong` | 双向 | — | 应用程序层保活 + 即时延迟测量（教师端每 3 秒测一次，UI 显示每台学生端 ms） |

> 崩溃防护：教师端每次广播锁定一个规范音讯格式（首个缓冲决定），格式不符的缓冲直接丢弃；学生端同样锁定首块格式并拒收畸形/异构格式块（取样率 8k-96k、1-2 声道、16/32 位元），已排入节点的缓冲以强引用保活至播完——杜绝渲染执行绪读到异构格式或已释放内存造成的 EXC_BAD_ACCESS 崩溃。

> 延迟优化：TCP 启用 `TCP_NODELAY`；教师端编码节流（编不过来丢旧帧、不积压）；每条连线同一时间只允许一帧在途；学生端 JPEG 解码在背景伫列进行；**音讯走专属 WebSocket 连线**（与画面分流，消除大帧头部阻塞），采集端把非交错 PCM 重排成交错格式并以 ~80ms 块送出（保证跨块拼接连续、左右声道正确）；学生端以**抖动缓冲**平滑 Wi-Fi 到达抖动（预卷 ~240ms、积压超限丢新不丢旧以保持播放连续），并以正确的“声道数×每采样字节”计算帧数；教师端每 3 秒以 ping/pong 测量每台学生端的即时延迟并在装置列显示。

> 广播画质由教师端界面切换（自动/低/中/高），采集参数集中在 `TeacherApp/ScreenBroadcaster.swift` 的 `BroadcastQuality` 与 `resolutionParameters`，如需自订可在该处修改。

## 锁屏机制说明（StudentApp）

Kiosk 由三层组成，任一被攻破仍有兜底：

1. **presentationOptions**：隐藏 Dock/选单列，停用 ⌘⇥、⌘⌥⎋ 等系统级入口（新系统还可停用 ⌘Space、⌘⇧3/4、控制中心/通知中心；为相容旧 SDK，本工程使用最小集合）。
2. **CGEventTap（.cghidEventTap）**：系统级吞掉全部键盘/鼠标事件，硬拦截 ⌘⇥、⌘⌥⎋、⌃←/⌃→、⌘Space、⌘⇧3/4 等一切快捷键；需要辅助功能权限。
3. **全屏无边框锁窗（level = .screenSaver）**：覆盖所有显示器、所有 Space，遮住选单列与 Dock；以 `orderFrontRegardless()` 强制抬升，即使学生机正处于其他 App 的全屏模式也能盖住。锁定期间的自愈机制：萤幕参数变化（外接显示器接上/唤醒、分辨率改变）会自动重建锁窗避免漏缝；若被其他 App 抢走焦点（如尚未授予辅助功能权限时按 ⌘⇥），会自动夺回焦点、抬升锁窗并补装输入拦截。

紧急解锁：本地按 **⌘⇧U** → 输入拦截器暂时卸载 → 锁窗显示密码框（自动聚焦，直接输入即可）→ 校验加盐 SHA-256 杂凑 → 正确则退出 Kiosk；错误或 60 秒逾时则自动恢复拦截重新锁死，锁屏会显示对应提示。

> 紧急解锁注意事项：
> - **必须先在学生端状态视窗设定本地管理员密码**；若未设定，按 ⌘⇧U 会在锁屏显示“未设定本地管理员密码”提示并保持锁定（不会出现无法输入的死锁密码框）。
> - **⌘⇧U 依赖“辅助功能”权限**：未授权时输入拦截器不会安装，组合键无法被侦测，锁屏会显示黄色“需要辅助功能权限”提示。请在系统设定 → 隐私与安全性 → 辅助功能 中勾选 FocusIn 学生端（StudentApp）。
> - ⌘⇧U 必须在**被锁定的学生机本机**按下；在教师机上按无效。

## 安全与运维注意事项

- **信任模型**：本设计假设教室局域网可信。WebSocket 为明文，若要跨不可信网络部署，应在 `PeerTransport.webSocketParameters()` 中叠加 `NWProtocolTLS.Options` 并做凭证校验。
- **远端关机/重新启动**：`System Events` 方案首次会弹自动化授权，部分网络账户环境可能要求管理员权限；也可改用 `Process` 执行 `/sbin/shutdown -h now` / `-r now`（需 root）。
- **Kiosk 的边界**：事件拦截只作用于图形会话内的输入；对 SSH、另一个管理员账户、或直接 kill 程序没有防御力。生产级机房管理应叠加 MDM（Jamf / Apple School Manager / 描述档 + 单一 App 模式）。
- **Wi-Fi 注意**：若学校 AP 开启“用户端隔离”，Bonjour 发现与直连会被阻断；请在支援多播/二层互通的 VLAN 上运行。
- **效能**：广播画质可于教师端切换——**高**：原生全分辨率（30fps，JPEG 0.92）；**中**：0.75 缩放（30fps）；**低**：0.5 缩放（24fps）；**自动**：≤4K 用原生分辨率，5K 以上微缩至 0.85。局域网环境建议使用“高”或“自动”。声音以 48kHz 立体声 PCM 随广播同步传输，学生端即时播放。教师端另有“传送声音”开关：若个别学生机的音讯链路有相容问题，可关闭声音仅传画面（开关切换会自动重启广播套用）。
- **登入时自动启动**：两端界面均有开关，透过写入 `~/Library/LaunchAgents/<bundleID>.plist`（LaunchAgent，RunAtLoad）注册。取消勾选即移除；App 移动位置后重新勾选一次即可更新路径。
- **自动更新检查**：两端启动时自动查 GitHub（`marco-crypto-debug/focusin`）——有 Release 比对 tag，否则比对 main 分支最新 commit SHA 与本机构建 SHA（构建时写入 `CFBundleVersion`）。发现新版本即在界面提示，可一键前往 GitHub 下载；也可手动“检查更新”。首次构建于未推送提交时会提示一次，属正常现象。
- **清空学生文件（破坏性）**：教师端“清空学生文件”按钮需点击后在弹窗输入 `DELETE` 才会下发；学生端只删除目前使用者家目录下的 `Documents` 与 `Downloads` 全部内容（资料夹本身保留），逐项回报结果至教师端事件日志。此操作**不可复原**，部署前请先在单台测试机验证。

## 签名与 Gatekeeper 拦截

FocusIn 目前以 **自签证书**（`FocusIn Signing (Marco TSK)`）签名。未付费加入 Apple Developer Program 前无法做正式的 Developer ID 公证，macOS 对未公证 App 一律拦截（“无法验证开发者 / 已损坏”），属正常现象。

- **构建机**：执行 `bash tools/sign-focusin.sh`，自动创建证书（首次）→ 签名 `release/staging-rel` 下所有 App → 导出公钥 `tools/focusin-signing.cer`。
- **学生机**：把 `tools/install-cert.sh` 与 `focusin-signing.cer` 放到同一资料夹执行一次（需管理员密码），安装证书 + 移除 quarantine + 加入 Gatekeeper 白名单，之后所有版本都能直接打开。
- 快速绕过单次拦截：右键 App → 开启 → 再按“开启”；或 `xattr -dr com.apple.quarantine /Applications/FocusIn\ Teacher.app`。
- 付费加入 Apple Developer Program 后，可改用正式 **Developer ID 签名 + `notarytool` 公证**，用户下载即开、零拦截；届时替换 `tools/sign-focusin.sh` 内的签名命令即可。

## 已知限制

- 屏幕录制权限若未授权或遭撤销，教师端广播会在界面显示红色提示与“开启屏幕录制设定”按钮引导开启；权限恢复后重新点击“广播教师屏幕”即可。
- 学生端首次锁定若辅助功能权限缺失，会弹提示并引导开启系统设定；未授权期间输入不会被拦截。
- `NSAppleScript` 关机/重新启动在部分新 macOS 上可能被 TCC 拒绝，日志会记录错误。
