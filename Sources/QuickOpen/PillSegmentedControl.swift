import AppKit

/// 胶囊形分段控件：浅灰轨道 + 选中段白色浮起（深色模式为亮灰），类似 iOS / 系统设置的分段样式。
/// 替代 NSSegmentedControl：后者在设置页里选中态是刺眼的整块蓝色，键盘导航时还会出现焦点框。
final class PillSegmentedControl: NSControl {
    struct Segment {
        let title: String
        let symbol: String?
        let toolTip: String?
    }

    var segments: [Segment] = [] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var selectedIndex = 0 { didSet { needsDisplay = true; setAccessibilityValue(segments.indices.contains(selectedIndex) ? segments[selectedIndex].title : nil) } }
    /// `.regular` 用于页面级切换（列表 / 键盘），`.small` 用于次级切换（排序）。
    var size: ControlSize = .regular { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    private var hoverIndex: Int? { didSet { if hoverIndex != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.radioGroup)
    }

    required init?(coder: NSCoder) { nil }

    private var height: CGFloat { size == .small ? 26 : 30 }
    private var labelFont: NSFont { .systemFont(ofSize: size == .small ? 12 : 13, weight: .medium) }
    private var padding: CGFloat { size == .small ? 12 : 14 }
    private var inset: CGFloat { 3 }

    private func segmentWidth(_ segment: Segment) -> CGFloat {
        let text = ceil(NSAttributedString(string: segment.title, attributes: [.font: labelFont]).size().width)
        let icon: CGFloat = segment.symbol == nil ? 0 : (size == .small ? 14 : 16) + 6
        return text + icon + padding * 2
    }

    override var intrinsicContentSize: NSSize {
        // 等宽分段，视觉更整齐。
        let w = (segments.map(segmentWidth).max() ?? 0) * CGFloat(segments.count) + inset * 2
        return NSSize(width: w, height: height)
    }

    private func segmentRect(_ index: Int) -> NSRect {
        let w = (bounds.width - inset * 2) / CGFloat(max(1, segments.count))
        return NSRect(x: inset + CGFloat(index) * w, y: inset, width: w, height: bounds.height - inset * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = Theme.isDark(effectiveAppearance)
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.06)).setFill()
        track.fill()

        for (index, segment) in segments.enumerated() {
            let rect = segmentRect(index)
            let selected = index == selectedIndex
            if selected {
                let pill = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.4 : 0.14)
                shadow.shadowBlurRadius = 3
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.set()
                (dark ? NSColor.white.withAlphaComponent(0.2) : NSColor.white).setFill()
                pill.fill()
                NSGraphicsContext.restoreGraphicsState()
            } else if hoverIndex == index {
                let pill = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
                (dark ? NSColor.white.withAlphaComponent(0.05) : NSColor.black.withAlphaComponent(0.04)).setFill()
                pill.fill()
            }
            let color: NSColor = selected ? .labelColor : .secondaryLabelColor
            let title = NSAttributedString(string: segment.title, attributes: [.font: labelFont, .foregroundColor: color])
            let iconSize: CGFloat = size == .small ? 14 : 16
            let image = segment.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: iconSize - 2, weight: .medium)) }
            let contentW = title.size().width + (image == nil ? 0 : iconSize + 6)
            var x = rect.midX - contentW / 2
            if let image {
                let tinted = image.tinted(color)
                let r = NSRect(x: x, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize)
                tinted.draw(in: r.insetBy(dx: (iconSize - image.size.width) / 2 > 0 ? (iconSize - image.size.width) / 2 : 0,
                                          dy: (iconSize - image.size.height) / 2 > 0 ? (iconSize - image.size.height) / 2 : 0),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                x += iconSize + 6
            }
            title.draw(at: NSPoint(x: x, y: rect.midY - title.size().height / 2))
        }
    }

    private func index(at point: NSPoint) -> Int? {
        segments.indices.first { segmentRect($0).contains(point) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)), index != selectedIndex else { return }
        selectedIndex = index
        sendAction(action, to: target)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { hoverIndex = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hoverIndex = nil }

    override func layout() {
        super.layout()
        removeAllToolTips()
        for (i, segment) in segments.enumerated() {
            if let tip = segment.toolTip { addToolTip(segmentRect(i), owner: tip as NSString, userData: nil) }
        }
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let image = copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
