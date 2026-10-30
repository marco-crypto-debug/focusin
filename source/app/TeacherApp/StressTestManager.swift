import Foundation
import Combine
import AppKit

// ============================================================
// FocusIn TeacherApp — 24H / 48H 連續廣播壓力測試引擎
// 監控畫面傳輸穩定度、自動重連率、記憶體佔用與系統故障
// ============================================================

enum StressTestTarget: String, CaseIterable, Identifiable {
    case tenMinutes = "10 分鐘 (快速驗證)"
    case twentyFourHours = "24 小時連續廣播"
    case fortyEightHours = "48 小時極限壓測"

    var id: String { rawValue }

    var durationSeconds: TimeInterval {
        switch self {
        case .tenMinutes: return 600
        case .twentyFourHours: return 86400
        case .fortyEightHours: return 172800
        }
    }

    var shortLabel: String {
        switch self {
        case .tenMinutes: return "10m"
        case .twentyFourHours: return "24h"
        case .fortyEightHours: return "48h"
        }
    }
}

enum StressTestState: String {
    case idle = "待命"
    case running = "壓測運行中"
    case completed = "壓測圓滿完成"
    case stopped = "手動終止"
}

struct StressTestEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: EventLevel
    let message: String

    enum EventLevel: String {
        case info = "INFO"
        case success = "PASS"
        case warning = "WARN"
        case error = "FAIL"

        var colorName: String {
            switch self {
            case .info: return "blue"
            case .success: return "green"
            case .warning: return "orange"
            case .error: return "red"
            }
        }
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

@MainActor
final class StressTestManager: ObservableObject {
    static let shared = StressTestManager()

    // MARK: - Published 狀態
    @Published var state: StressTestState = .idle
    @Published var target: StressTestTarget = .twentyFourHours
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var totalFrames: UInt64 = 0
    @Published var totalBytes: UInt64 = 0
    @Published var currentFPS: Double = 0.0
    @Published var averageFPS: Double = 0.0
    @Published var disconnectCount: Int = 0
    @Published var reconnectCount: Int = 0
    @Published var faultCount: Int = 0
    @Published var autoRecoveryCount: Int = 0
    @Published var currentMemoryMB: Double = 0.0
    @Published var peakMemoryMB: Double = 0.0
    @Published var recentEvents: [StressTestEvent] = []

    // MARK: - 內部計時與取樣
    private var testTimer: Timer?
    private var startDate: Date?
    private var lastSecondFrames: UInt64 = 0
    private var lastSecondCheck: Date = Date()
    private var lastFrameTime: Date = Date()
    private var keepAliveEngaged = false
    private let logFileURL: URL

    private weak var viewModel: TeacherViewModel?

    init() {
        let fileManager = FileManager.default
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let logsDir = libraryURL.appendingPathComponent("Logs", isDirectory: true)
        try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFileURL = logsDir.appendingPathComponent("FocusIn-StressTest.log")
    }

    func bind(viewModel: TeacherViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - 計算屬性
    var targetSeconds: TimeInterval {
        target.durationSeconds
    }

    var progress: Double {
        guard targetSeconds > 0 else { return 0.0 }
        return min(max(elapsedSeconds / targetSeconds, 0.0), 1.0)
    }

    var remainingSeconds: TimeInterval {
        max(targetSeconds - elapsedSeconds, 0)
    }

    var elapsedFormatted: String {
        formatTimeInterval(elapsedSeconds)
    }

    var remainingFormatted: String {
        formatTimeInterval(remainingSeconds)
    }

    var throughputFormatted: String {
        if totalBytes > 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", Double(totalBytes) / (1024.0 * 1024.0 * 1024.0))
        } else {
            return String(format: "%.1f MB", Double(totalBytes) / (1024.0 * 1024.0))
        }
    }

    // MARK: - 控制接口

    func startTest(target: StressTestTarget? = nil) {
        guard state != .running else { return }
        if let target = target {
            self.target = target
        }

        self.state = .running
        self.startDate = Date()
        self.elapsedSeconds = 0
        self.totalFrames = 0
        self.totalBytes = 0
        self.currentFPS = 0.0
        self.averageFPS = 0.0
        self.disconnectCount = 0
        self.reconnectCount = 0
        self.faultCount = 0
        self.autoRecoveryCount = 0
        self.lastSecondFrames = 0
        self.lastSecondCheck = Date()
        self.lastFrameTime = Date()
        self.currentMemoryMB = fetchMemoryUsageMB()
        self.peakMemoryMB = self.currentMemoryMB
        self.recentEvents.removeAll()

        // 啟動防休眠機制
        if !keepAliveEngaged {
            DisplayKeepAlive.shared.engage()
            keepAliveEngaged = true
        }

        appendEvent(.info, "=== 啟動 FocusIn \(self.target.rawValue) 壓力測試 ===")
        appendEvent(.info, "目標時長：\(formatTimeInterval(self.targetSeconds)) | 起始記憶體：\(String(format: "%.1f", currentMemoryMB)) MB")

        // 若教師端目前尚未開啟廣播，自動嘗試為勾選學生開啟廣播
        if let vm = viewModel, !vm.broadcastActive {
            if vm.selectedIDs.isEmpty && !vm.peers.isEmpty {
                for i in vm.peers.indices {
                    vm.peers[i].isSelected = true
                }
            }
            vm.startBroadcast()
            appendEvent(.info, "自動呼叫廣播啟動（目標學生數：\(vm.selectedIDs.count) 台）")
        }

        testTimer?.invalidate()
        testTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onTimerTick()
            }
        }
    }

    func stopTest() {
        guard state == .running else { return }
        testTimer?.invalidate()
        testTimer = nil
        state = .stopped

        if keepAliveEngaged {
            DisplayKeepAlive.shared.release()
            keepAliveEngaged = false
        }

        appendEvent(.warning, "使用者手動停止壓力測試。持續運行：\(elapsedFormatted)，傳輸影格：\(totalFrames) 幀")
    }

    // MARK: - 定時巡檢
    private func onTimerTick() {
        guard state == .running else { return }
        elapsedSeconds += 1.0

        // 記憶體採樣
        let mem = fetchMemoryUsageMB()
        currentMemoryMB = mem
        if mem > peakMemoryMB {
            peakMemoryMB = mem
        }

        // FPS 計算 (每秒幀率與平均幀率)
        let now = Date()
        let dt = now.timeIntervalSince(lastSecondCheck)
        if dt >= 1.0 {
            let framesThisSec = totalFrames - lastSecondFrames
            currentFPS = Double(framesThisSec) / dt
            lastSecondFrames = totalFrames
            lastSecondCheck = now
        }
        if elapsedSeconds > 0 {
            averageFPS = Double(totalFrames) / elapsedSeconds
        }

        // 健檢：檢查廣播串流是否停滯 (超過 15 秒沒有任何新影格且正在廣播中)
        if let vm = viewModel, vm.broadcastActive {
            if now.timeIntervalSince(lastFrameTime) > 15.0 && totalFrames > 0 {
                faultCount += 1
                autoRecoveryCount += 1
                appendEvent(.error, "檢測到畫面串流停滯逾 15 秒！觸發自動恢復機制重啟廣播...")
                vm.restartBroadcast()
                lastFrameTime = Date()
            }
        } else if let vm = viewModel, !vm.broadcastActive && elapsedSeconds > 5 {
            // 教師端廣播意外中斷
            faultCount += 1
            autoRecoveryCount += 1
            appendEvent(.error, "檢測到廣播線路離線，觸發自動重新拉起廣播...")
            vm.startBroadcast()
        }

        // 檢查是否已達到測試目標
        if elapsedSeconds >= targetSeconds {
            completeTest()
        }
    }

    private func completeTest() {
        testTimer?.invalidate()
        testTimer = nil
        state = .completed

        if keepAliveEngaged {
            DisplayKeepAlive.shared.release()
            keepAliveEngaged = false
        }

        appendEvent(.success, "🎉 狂賀！\(target.rawValue) 壓力測試圓滿達成！")
        appendEvent(.success, "總耗時：\(elapsedFormatted) | 總傳輸：\(totalFrames) 幀 (\(throughputFormatted)) | 平均 FPS：\(String(format: "%.1f", averageFPS))")
        appendEvent(.success, "斷線次數：\(disconnectCount) | 重連成功：\(reconnectCount) | 故障次數：\(faultCount) | 峰值記憶體：\(String(format: "%.1f", peakMemoryMB)) MB")
    }

    // MARK: - 訊號掛鉤 (Hook from ViewModel)

    func recordFrame(size: Int) {
        guard state == .running else { return }
        totalFrames += 1
        totalBytes += UInt64(max(0, size))
        lastFrameTime = Date()
    }

    func recordDisconnect(peerName: String) {
        guard state == .running else { return }
        disconnectCount += 1
        appendEvent(.warning, "學生機「\(peerName)」暫時斷開連接 (累計斷線: \(disconnectCount))")
    }

    func recordReconnect(peerName: String) {
        guard state == .running else { return }
        reconnectCount += 1
        appendEvent(.success, "學生機「\(peerName)」重新連線成功 (累計重連: \(reconnectCount))")
    }

    func recordFault(message: String) {
        guard state == .running else { return }
        faultCount += 1
        appendEvent(.error, "異常事件：\(message) (累計故障: \(faultCount))")
    }

    // MARK: - 事件日誌與持久化
    func appendEvent(_ level: StressTestEvent.EventLevel, _ message: String) {
        let event = StressTestEvent(timestamp: Date(), level: level, message: message)
        recentEvents.insert(event, at: 0)
        if recentEvents.count > 100 {
            recentEvents.removeLast()
        }

        // 寫入本地 Log 檔案
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let logLine = "[\(formatter.string(from: event.timestamp))] [\(event.level.rawValue)] \(message)\n"
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    func generateReport() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let nowStr = formatter.string(from: Date())

        return """
        ============================================================
        FocusIn 屏幕廣播穩定性壓力測試診斷報告
        生成時間：\(nowStr)
        ============================================================
        測試目標：\(target.rawValue) (\(formatTimeInterval(targetSeconds)))
        測試狀態：\(state.rawValue)
        持續運行：\(elapsedFormatted) (\(String(format: "%.1f%%", progress * 100)))

        【數據統計】
        - 總傳輸幀數：\(totalFrames) 幀
        - 總數據吞吐：\(throughputFormatted)
        - 當前 / 平均幀率：\(String(format: "%.1f", currentFPS)) / \(String(format: "%.1f", averageFPS)) FPS
        - 當前 / 峰值記憶體：\(String(format: "%.1f", currentMemoryMB)) MB / \(String(format: "%.1f", peakMemoryMB)) MB

        【網路與容錯指標】
        - 學生機斷線次數：\(disconnectCount) 次
        - 自動重連成功數：\(reconnectCount) 次
        - 廣播異常次數：\(faultCount) 次
        - 自動故障復原：\(autoRecoveryCount) 次

        【近期事件日誌 (最新 30 筆)】
        \(recentEvents.prefix(30).map { "[\($0.timeString)] [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n"))

        ============================================================
        本報告可供學校 IT 管理人員與 FocusIn 工程團隊評估 24/48 小時長時間無人值守之可靠度。
        日誌完整存檔：\(logFileURL.path)
        ============================================================
        """
    }

    func exportReportToUser() {
        let content = generateReport()
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "FocusIn-StressTest-Report.txt"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - 工具函式
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(0, interval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func fetchMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        }
        return 0.0
    }
}
