import AppKit

/// 主操作按钮（如「添加 App」）：系统强调色胶囊，图标 + 文字按 `ControlLabel` 规范排版，
/// 保证图标与文字间距和视觉垂直居中与分段控件一致。
/// 系统 NSButton 在大尺寸下中文会明显偏下，且图标与文字的间距不可控，所以自绘。
final class PrimaryButton: NSControl {
    var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; setAccessibilityLabel(title) } }
    var symbol: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    /// 不带修饰键的字符，配合 `keyEquivalentModifierMask` 触发（如 ⌘N）。
    var keyEquivalent = ""
    var keyEquivalentModifierMask: NSEvent.ModifierFlags = [.command]

    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    private var isPressed = false { didSet { if isPressed != oldValue { needsDisplay = true } } }

    private static let height: CGFloat = 32
    private static let padding: CGFloat = 16
    private static let font = NSFont.systemFont(ofSize: 13, weight: .semibold)

    override var isFlipped: Bool { true }

    init(title: String, symbol: String? = nil, target: AnyObject?, action: Selector?) {
        self.title = title
        self.symbol = symbol
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { nil }

    override var isEnabled: Bool { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }

    private var icon: NSImage? { symbol.flatMap { ControlLabel.symbol($0, pointSize: 12, weight: .semibold) } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(ControlLabel.width(title: title, font: Self.font, icon: icon) + Self.padding * 2), height: Self.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        var fill = NSColor.controlAccentColor
        if !isEnabled {
            fill = fill.withAlphaComponent(0.4)
        } else if isPressed {
            fill = fill.blended(withFraction: 0.18, of: .black) ?? fill
        } else if isHovered {
            fill = fill.blended(withFraction: 0.1, of: .white) ?? fill
        }
        fill.setFill()
        path.fill()
        ControlLabel.draw(title: title, font: Self.font, icon: icon,
                          color: .white.withAlphaComponent(isEnabled ? 1 : 0.7), centeredIn: rect)
    }

    // MARK: 交互

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside { sendAction(action, to: target) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEnabled, !keyEquivalent.isEmpty, window?.isKeyWindow == true,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == keyEquivalentModifierMask,
              event.charactersIgnoringModifiers?.lowercased() == keyEquivalent.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        sendAction(action, to: target)
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        return sendAction(action, to: target)
    }
}
