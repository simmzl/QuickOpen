import AppKit
import CoreGraphics
import os

private let log = Logger(subsystem: "com.simmzl.quickopen", category: "input")

/// “输入监控”权限。速查面板的“按住显示”需要它来可靠地检测修饰键松开。
enum InputMonitoring {
    private static let askedKey = "inputMonitoringRequested"

    static var isGranted: Bool { grantedOverride ?? CGPreflightListenEventAccess() }

    /// 仅供截图测试：模拟已授权状态。
    static var grantedOverride: Bool?

    /// 弹出系统授权提示（同一个 App 只会弹一次；之后需要在系统设置中手动开启）。
    @discardableResult
    static func request() -> Bool {
        UserDefaults.standard.set(true, forKey: askedKey)
        return CGRequestListenEventAccess()
    }

    /// 首次需要时请求一次，不反复打扰。
    static func requestOnceIfNeeded() {
        guard !isGranted, !UserDefaults.standard.bool(forKey: askedKey) else { return }
        request()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}

/// 只读的事件监听（listen-only event tap）：在系统事件流中观察修饰键变化，
/// 一旦所需修饰键不再全部按住就回调。无论系统把按键事件送给哪个 App 都能收到。
final class ModifierReleaseTap {
    private let required: CGEventFlags
    private let onRelease: () -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var fired = false

    /// 没有“输入监控”权限时返回 nil。
    init?(required: CGEventFlags, onRelease: @escaping () -> Void) {
        self.required = required
        self.onRelease = onRelease
        guard InputMonitoring.isGranted else { return nil }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    let me = Unmanaged<ModifierReleaseTap>.fromOpaque(userInfo).takeUnretainedValue()
                    me.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("event tap creation failed")
            return nil
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit { invalidate() }

    func invalidate() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 系统因超时等原因停用了监听：重新启用。
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            guard !fired, !event.flags.contains(required) else { return }
            fired = true
            onRelease()
        default:
            break
        }
    }
}
