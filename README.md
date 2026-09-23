# ClassroomManager — macOS 课堂管理（教师端 / 学生端）

面向 iMac 机房的局域网课堂管理：教师端自动发现学生端、实时广播教师屏幕、下发锁屏/解锁/关机/重启/启动应用指令；学生端提供 Kiosk 全屏锁定、输入拦截与本地紧急解锁。

技术栈：Swift / SwiftUI（macOS 13+）、Network.framework（WebSocket + Bonjour/mDNS）、ScreenCaptureKit。

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
        同一 Wi-Fi 局域网 / 同一子网
```

## 目录结构

```
ClassroomManager/
├── README.md
├── project.yml                     # XcodeGen 工程定义（一键生成两个 Xcode 工程）
├── Shared/                         # 两端共用的源码（同时编译进两个 target）
│   ├── Networking/
│   │   ├── PeerTransport.swift     # NWParameters 工厂（WebSocket 应用协议）
│   │   ├── PeerConnection.swift    # WebSocket 连接封装：收发 CommandMessage
│   │   └── PeerDiscovery.swift     # PeerAdvertiser(学生) / PeerBrowser(教师)
│   └── Protocol/
│       ├── CommandType.swift       # 命令枚举：lock/unlock/shutdown/restart/launchApp/stream*
│       └── CommandMessage.swift    # JSON 消息信封
├── TeacherApp/
│   ├── TeacherApp.swift            # @main 入口
│   ├── TeacherViewModel.swift      # 发现/连接/命令分发
│   ├── ScreenBroadcaster.swift     # ScreenCaptureKit 采集 → JPEG 帧
│   ├── Views/DeviceListView.swift  # 设备列表 + 控制面板 UI
│   ├── Info.plist
│   └── TeacherApp.entitlements
└── StudentApp/
    ├── StudentApp.swift            # @main 入口
    ├── CommandListener.swift       # 广告服务 + 命令监听 + 系统动作
    ├── Views/StatusView.swift      # 状态窗口（含管理员密码预设）
    ├── Kiosk/
    │   ├── KioskModeController.swift # 全屏锁窗 + presentationOptions + 解锁流程
    │   ├── InputInterceptor.swift    # CGEventTap 键盘/鼠标拦截
    │   ├── KioskLockView.swift       # 锁屏界面（广播画面 + 密码输入）
    │   └── KioskConfig.swift         # 管理员密码加盐哈希存储
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
2. 将 `TeacherApp`、`Shared` 文件夹拖入 TeacherApp target；`StudentApp`、`Shared` 拖入 StudentApp target。
3. Build Settings：`MACOSX_DEPLOYMENT_TARGET = 13.0`；Info.plist 分别指定对应文件；Entitlements 指向对应 `.entitlements` 文件。
4. 建议对两个 target 使用独立签名 Team（本地开发可直接 Sign to Run Locally）。

部署流程
1. 学生机先启动 StudentApp → 在状态窗口设置本地管理员密码（至少 4 位）。
2. 教师机启动 TeacherApp → 自动发现学生端（同一 Wi-Fi）。
3. 勾选「全部学生」或具体设备 → 广播 / 锁定 / 解锁 / 关机 / 重启 / 启动应用。
4. 学生端锁定时：教师可随时下发 `unlock`；若网络中断，本地管理员按 **⌘⇧U** 输入预设密码紧急解锁。

## 权限清单

### 1. 系统设置（System Settings → Privacy & Security）

| 应用 | 权限 | 用途 | 位置 |
|---|---|---|---|
| TeacherApp | 屏幕录制 (Screen Recording) | 采集教师屏幕用于广播 | 隐私与安全性 → 屏幕录制 |
| StudentApp | 辅助功能 (Accessibility) | CGEventTap 拦截键盘/鼠标 | 隐私与安全性 → 辅助功能 |
| StudentApp | 自动化 (Automation, 可选) | 关机/重启走 System Events，首次执行会弹授权框 | 隐私与安全性 → 自动化 |
| 两端 | 本地网络/防火墙 | macOS 防火墙首次运行可能弹「接受传入连接」，需允许 | 系统设置 → 网络 → 防火墙 |

### 2. Info.plist 键（已在文件内提供）

| Key | 所在应用 | 说明 |
|---|---|---|
| `NSScreenCaptureUsageDescription` | TeacherApp | 屏幕录制用途说明（TCC 提示文案） |
| `NSAppleEventsUsageDescription` | StudentApp | 向 System Events 发 Apple Events 的用途说明 |

### 3. Entitlements

工程默认**关闭 App Sandbox**（`com.apple.security.app-sandbox = false`），并预置 `com.apple.security.network.client / server` 两个网络权限。若未来开启沙箱，这两项即可覆盖 WebSocket 收发；开启沙箱还会要求其他能力（如 `com.apple.security.temporary-exception.apple-events` 才能向 System Events 发 Apple Events）。

## 协议参考（WebSocket 二进制帧，JSON 信封）

| type | 方向 | payload | 说明 |
|---|---|---|---|
| `hello` / `helloAck` | S→T / T→S | — | 握手，hello 携带设备名 |
| `lock` / `unlock` | T→S | — | 进入 / 退出 Kiosk |
| `shutdown` / `restart` | T→S | — | 远程关机 / 重启（System Events） |
| `launchApp` | T→S | Bundle ID | 启动应用（NSWorkspace） |
| `streamStart` / `streamStop` | T→S | — | 广播开始 / 结束 |
| `streamFrame` | T→S | base64 JPEG | 一帧画面（约 5fps，半分辨率） |
| `ping` / `pong` | 双向 | — | 应用层保活（协议层另有 WS Ping） |

## 锁屏机制说明（StudentApp）

Kiosk 由三层组成，任一被攻破仍有兜底：

1. **presentationOptions**：隐藏 Dock/菜单栏，禁用 ⌘⇥、⌘⌥⎋ 等系统级入口（新系统还可禁用 ⌘Space、⌘⇧3/4、控制中心/通知中心；为兼容旧 SDK，本工程使用最小集合）。
2. **CGEventTap（.cghidEventTap）**：系统级吞掉全部键盘/鼠标事件，硬拦截 ⌘⇥、⌘⌥⎋、⌃←/⌃→、⌘Space、⌘⇧3/4 等一切快捷键；需要辅助功能权限。
3. **全屏无边框锁窗（level = .screenSaver）**：覆盖所有显示器、所有 Space，遮住菜单栏与 Dock。

紧急解锁：本地按 **⌘⇧U** → 输入拦截器暂时卸载 → 锁窗显示密码框 → 校验加盐 SHA-256 哈希 → 正确则退出 Kiosk；错误或 60 秒超时则自动恢复拦截重新锁死。

## 安全与运维注意事项

- **信任模型**：本设计假设教室局域网可信。WebSocket 为明文，若要跨不可信网络部署，应在 `PeerTransport.webSocketParameters()` 中叠加 `NWProtocolTLS.Options` 并做证书校验。
- **远程关机/重启**：`System Events` 方案首次会弹自动化授权，部分网络账户环境可能要求管理员权限；也可改用 `Process` 执行 `/sbin/shutdown -h now` / `-r now`（需 root）。
- **Kiosk 的边界**：事件拦截只作用于图形会话内的输入；对 SSH、另一个管理员账户、或直接 kill 进程没有防御力。生产级机房管理应叠加 MDM（Jamf / Apple School Manager / 描述文件 + 单一 App 模式）。
- **Wi-Fi 注意**：若学校 AP 开启「客户端隔离」，Bonjour 发现与直连会被阻断；请在支持组播/二层互通的 VLAN 上运行。
- **性能**：广播为 5fps / 半分辨率 JPEG，单学生约 0.5–1.5 Mbps；如需更高帧率请改用 VideoToolbox H.264 编码或 WebRTC。

## 已知限制

- 屏幕录制权限若被撤销，教师端广播会静默失败（日志会打印 `屏幕捕获失败`）。
- 学生端首次锁定若辅助功能权限缺失，会弹提示并引导打开系统设置；未授权期间输入不会被拦截。
- `NSAppleScript` 关机/重启在部分新 macOS 上可能被 TCC 拒绝，日志会记录错误。
