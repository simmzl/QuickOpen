import AppKit
import Carbon

/// 设置窗口各页面共享的状态与操作。
final class SettingsContext {
    /// 速查面板热键在注册结果中使用的固定 id。
    static let overviewHotKeyID = UUID(uuidString: "0B5E7F1E-0000-4000-8000-00000000000F")!

    let store: ShortcutStore
    let preferences: Preferences
    let hotKeyManager: GlobalHotKeyManager
    /// 全窗口唯一的录制器，保证同一时刻只录制一个快捷键。
    let recorder = HotKeyRecorder()

    /// 重新注册所有热键，返回失败项（id → 错误码）。
    let reloadHotKeys: () -> [UUID: OSStatus]
    /// 预览启动提示。
    let previewHUD: (AppShortcut) -> Void
    /// 判断 App 是否正在运行。
    let isRunning: (AppShortcut) -> Bool

    private(set) var registrationFailures: [UUID: OSStatus] = [:]
    /// 正在录制的目标：某个 App 的 id，或 `overviewHotKeyID`。
    private(set) var recordingTarget: UUID?

    /// 状态变化（列表、失败项、录制状态）时通知各页面刷新。
    var onChange: [() -> Void] = []

    init(
        store: ShortcutStore,
        preferences: Preferences,
        hotKeyManager: GlobalHotKeyManager,
        reloadHotKeys: @escaping () -> [UUID: OSStatus],
        previewHUD: @escaping (AppShortcut) -> Void,
        isRunning: @escaping (AppShortcut) -> Bool
    ) {
        self.store = store
        self.preferences = preferences
        self.hotKeyManager = hotKeyManager
        self.reloadHotKeys = reloadHotKeys
        self.previewHUD = previewHUD
        self.isRunning = isRunning
    }

    func updateFailures(_ failures: [UUID: OSStatus]) {
        registrationFailures = failures
        notify()
    }

    @discardableResult
    func reload() -> [UUID: OSStatus] {
        let failures = reloadHotKeys()
        registrationFailures = failures
        notify()
        return failures
    }

    func notify() {
        onChange.forEach { $0() }
    }

    // MARK: 录制

    /// 开始为 `target` 录制快捷键。录制期间注销全部热键，以便捕获已占用的组合。
    /// - Parameters:
    ///   - onHint: 校验失败等提示文字。
    ///   - apply: 录制成功或清除后写入数据；返回 nil 表示写入成功。
    func beginRecording(
        target: UUID,
        onHint: @escaping (String) -> Void,
        apply: @escaping (HotKey?) -> Void,
        revert: @escaping () -> Void,
        window: NSWindow?
    ) {
        if recorder.isRecording { recorder.cancel() }
        recordingTarget = target
        hotKeyManager.unregisterAll()
        notify()

        let isOverview = target == Self.overviewHotKeyID
        recorder.onRejected = onHint
        recorder.validator = { [weak self] hotKey in
            guard let self else { return nil }
            return HotKeyConflictChecker.conflict(
                for: hotKey,
                shortcuts: self.store.shortcuts,
                overviewHotKey: self.preferences.overviewHotKey,
                excludingShortcut: isOverview ? nil : target,
                isOverview: isOverview
            ).message
        }
        recorder.start { [weak self] result in
            guard let self else { return }
            self.recordingTarget = nil
            switch result {
            case .cancelled:
                self.reload()
            case .cleared:
                apply(nil)
                self.reload()
            case .recorded(let hotKey):
                apply(hotKey)
                let failures = self.reload()
                if let status = failures[target] {
                    revert()
                    self.reload()
                    Self.showAlert(
                        message: "快捷键 \(hotKey.displayString) 不可用",
                        detail: status.hotKeyFailureDescription,
                        window: window
                    )
                }
            }
        }
    }

    func cancelRecording() {
        if recorder.isRecording { recorder.cancel() }
    }

    static func showAlert(message: String, detail: String, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        if let window, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

/// 可点击的快捷键显示控件：平时显示键帽，录制时显示“请按快捷键…”。
final class HotKeyControl: NSControl {
    var hotKey: HotKey? { didSet { refresh() } }
    var isRecording = false { didSet { refresh() } }
    var isWarning = false { didSet { refresh() } }
    var placeholder = "点击录制" { didSet { refresh() } }

    private let keyCaps = KeyCapView(fontSize: 12)
    private let recordingLabel = NSTextField(labelWithString: "请按快捷键…")
    private var isPressed = false { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        recordingLabel.font = .systemFont(ofSize: 12, weight: .medium)
        recordingLabel.textColor = Brand.coralDeep
        [keyCaps, recordingLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
            NSLayoutConstraint.activate([
                $0.centerXAnchor.constraint(equalTo: centerXAnchor),
                $0.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 132),
            widthAnchor.constraint(greaterThanOrEqualTo: keyCaps.widthAnchor, constant: 20)
        ])
        setAccessibilityRole(.button)
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    private func refresh() {
        keyCaps.hotKey = hotKey
        keyCaps.placeholder = placeholder
        keyCaps.style = isWarning ? .warning : .regular
        keyCaps.isHidden = isRecording
        recordingLabel.isHidden = !isRecording
        setAccessibilityLabel(isRecording ? "正在录制快捷键" : (hotKey?.displayString ?? placeholder))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        let isDark = Brand.isDark(effectiveAppearance)
        // 胶囊形玻璃：半透明底 + 顶部高光
        var alpha: CGFloat = isDark ? 0.07 : 0.45
        if isHovered { alpha += isDark ? 0.05 : 0.20 }
        if isPressed { alpha += isDark ? 0.05 : 0.15 }
        NSColor.white.withAlphaComponent(alpha).setFill()
        path.fill()
        if isRecording {
            Brand.coral.withAlphaComponent(0.12).setFill()
            path.fill()
        }
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(isDark ? 0.10 : 0.6),
            NSColor.white.withAlphaComponent(0)
        ])?.draw(in: path, angle: -90)

        if isRecording {
            Brand.coral.setStroke()
            path.lineWidth = 2
        } else {
            (isDark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.08)).setStroke()
            path.lineWidth = 1
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
