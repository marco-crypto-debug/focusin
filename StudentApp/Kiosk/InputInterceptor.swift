import ApplicationServices
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// 输入拦截器：通过 CGEventTap（.cghidEventTap）在系统级拦截键盘/鼠标事件，
/// 实现「本机用户无法操作」的硬锁。需要辅助功能（Accessibility）权限。
final class InputInterceptor {
    static let shared = InputInterceptor()

    /// 检测到紧急解锁组合键（⌘⇧U）时在主线程回调。
    var onEmergencyUnlockRequested: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isActive = false

    private static let emergencyCombo: (flags: CGEventFlags, keyCode: CGKeyCode) =
        ([.maskCommand, .maskShift], CGKeyCode(kVK_ANSI_U))

    // MARK: - 公共接口

    /// 安装事件拦截。返回 false 表示缺少辅助功能权限。
    @discardableResult
    func install() -> Bool {
        guard !isActive else { return true }
        guard AXIsProcessTrusted() else { return false }

        // 覆盖所有需要的输入事件
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
            tap: .cghidEventTap,          // 用户态可用的系统级 tap（需辅助功能权限）
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

    // MARK: - Tap 回调

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<InputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
        return interceptor.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系统可能因长时间阻塞而禁用 tap，收到后立即重新启用
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        switch type {
        case .keyDown, .keyUp:
            let flags = event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
            let key = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

            // 紧急解锁组合键：⌘⇧U
            if type == .keyDown, flags == Self.emergencyCombo.flags, key == Self.emergencyCombo.keyCode {
                DispatchQueue.main.async { self.onEmergencyUnlockRequested?() }
                return nil
            }

            // 即使 presentationOptions 失效也硬拦截的经典快捷键：
            // ⌘⇥（应用切换）、⌘⌥⎋（强制退出）、⌃←/⌃→（桌面切换）
            if flags.contains(.maskCommand) && key == CGKeyCode(kVK_Tab) { return nil }
            if flags == [.maskCommand, .maskAlternate] && key == CGKeyCode(kVK_Escape) { return nil }
            if flags.contains(.maskControl)
                && (key == CGKeyCode(kVK_LeftArrow) || key == CGKeyCode(kVK_RightArrow)) { return nil }

            return nil  // 硬锁：吞掉所有键盘事件

        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged,
             .rightMouseDragged, .scrollWheel:
            return nil  // 硬锁：吞掉所有鼠标事件

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
