import ApplicationServices
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// 輸入攔截器：透過 CGEventTap（.cghidEventTap）在系統級攔截鍵盤/滑鼠事件，
/// 實現「本機使用者無法操作」的硬鎖。需要輔助功能（Accessibility）權限。
final class InputInterceptor {
    static let shared = InputInterceptor()

    /// 偵測到緊急解鎖組合鍵（⌘⇧U）時在主執行緒回呼。
    var onEmergencyUnlockRequested: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isActive = false

    /// 緊急解鎖的按鍵：'U'（美國鍵盤佈局的實體按鍵，多數佈局相同）。
    private static let emergencyKeyCode = CGKeyCode(kVK_ANSI_U)

    // MARK: - 公共介面

    /// 安裝事件攔截。返回 false 表示缺少輔助功能權限。
    @discardableResult
    func install() -> Bool {
        guard !isActive else { return true }
        guard AXIsProcessTrusted() else { return false }

        // 覆蓋所有需要的輸入事件
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,          // 使用者態可用的系統級 tap（需輔助功能權限）
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        isActive = true
        return true
    }

    func uninstall() {
        guard isActive else { return }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
    }

    // MARK: - Tap 回呼

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
        return interceptor.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系統可能因長時間阻塞而停用 tap，收到後立即重新啟用
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        switch type {
        case .keyDown, .keyUp:
            let flags = event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
            let key = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

            // 緊急解鎖組合鍵：⌘⇧U。
            // 用「包含」而非「完全相等」判斷，容許 Caps Lock / Fn 等額外旗標同時存在。
            if type == .keyDown,
               flags.contains(.maskCommand) && flags.contains(.maskShift),
               key == Self.emergencyKeyCode {
                DispatchQueue.main.async { self.onEmergencyUnlockRequested?() }
                return nil
            }

            // 即使 presentationOptions 失效也硬攔截的經典快捷鍵：
            // ⌘⇥（應用程式切換）、⌘⌥⎋（強制結束）、⌃←/⌃→（桌面切換）
            if flags.contains(.maskCommand) && key == CGKeyCode(kVK_Tab) { return nil }
            if flags == [.maskCommand, .maskAlternate] && key == CGKeyCode(kVK_Escape) { return nil }
            // 只攔截純 Control+左右鍵，避免過度攔截 Control+Shift/Option+左右鍵
            if flags == [.maskControl] && (key == CGKeyCode(kVK_LeftArrow) || key == CGKeyCode(kVK_RightArrow)) { return nil }

            return nil  // 硬鎖：吞掉所有鍵盤事件

        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged,
             .rightMouseDragged, .scrollWheel:
            return nil  // 硬鎖：吞掉所有滑鼠事件

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
