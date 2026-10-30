import AppKit
import Carbon

/// 快捷键冲突的检测结果。
enum HotKeyConflict: Equatable {
    case none
    /// 与列表中某个 App 冲突。
    case application(name: String)
    /// 与速查面板快捷键冲突。
    case overview
}

enum HotKeyConflictChecker {
    /// - Parameters:
    ///   - excludingShortcut: 正在编辑的 App（与自身相同不算冲突）。
    ///   - isOverview: 正在编辑的是速查面板快捷键。
    static func conflict(
        for hotKey: HotKey,
        shortcuts: [AppShortcut],
        overviewHotKey: HotKey?,
        excludingShortcut id: UUID? = nil,
        isOverview: Bool = false
    ) -> HotKeyConflict {
        if !isOverview, hotKey == overviewHotKey { return .overview }
        if let other = shortcuts.first(where: { $0.id != id && $0.hotKey == hotKey }) {
            return .application(name: other.appName)
        }
        return .none
    }
}

/// 一次性的按键录制会话：用本地 keyDown 监听捕获下一组快捷键。
/// 只在 QuickOpen 自己的窗口为 key 时有效，因此不需要辅助功能权限。
final class HotKeyRecorder {
    enum Result {
        case recorded(HotKey)
        case cleared
        case cancelled
    }

    /// 校验失败时的提示文字回调，例如“这个快捷键已经分配给 Safari”。
    var onRejected: ((String) -> Void)?
    /// 额外校验（例如冲突检测），返回错误文字表示拒绝。
    var validator: ((HotKey) -> String?)?

    private var monitor: Any?
    private var completion: ((Result) -> Void)?

    var isRecording: Bool { monitor != nil }

    func start(completion: @escaping (Result) -> Void) {
        stop()
        self.completion = completion
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    /// 结束录制，视为取消。
    func cancel() {
        finish(.cancelled)
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func finish(_ result: Result) {
        guard isRecording else { return }
        stop()
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    private func capture(_ event: NSEvent) {
        let modifiers = HotKey.carbonModifiers(from: event.modifierFlags)
        let keyCode = UInt32(event.keyCode)

        // 录制时单独的 Esc / Delete 保留为“取消 / 清除”，其余任何键（含单键）都可录制。
        if keyCode == 53, modifiers == 0 { // Esc
            finish(.cancelled)
            return
        }
        if (keyCode == 51 || keyCode == 117), modifiers == 0 { // Delete / Forward Delete
            finish(.cleared)
            return
        }

        let hotKey = HotKey(keyCode: keyCode, modifiers: modifiers)
        if let message = validator?(hotKey) {
            reject(message)
            return
        }
        finish(.recorded(hotKey))
    }

    private func reject(_ message: String) {
        NSSound.beep()
        onRejected?(message)
    }
}

extension HotKeyConflict {
    var message: String? {
        switch self {
        case .none: return nil
        case .application(let name): return "这个快捷键已经分配给 \(name)"
        case .overview: return "这个快捷键已用于速查面板"
        }
    }
}

extension OSStatus {
    /// 热键注册失败时给用户看的说明。
    var hotKeyFailureDescription: String {
        self == eventHotKeyExistsErr
            ? "该快捷键已被系统或其他应用占用，请换一个。"
            : "系统无法注册该快捷键（错误码 \(self)）。"
    }
}
