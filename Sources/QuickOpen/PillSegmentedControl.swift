import AppKit

/// 胶囊形分段控件：浅灰轨道 + 选中段白色浮起（深色模式为亮灰），类似 iOS / 系统设置的分段样式。
/// 替代 NSSegmentedControl：后者在设置页里选中态是刺眼的整块蓝色，键盘导航时还会出现焦点框。
final class PillSegmentedControl: NSControl {
    struct Segment {
        let title: String
        let symbol: String?
        let toolTip: String?
    }

    var segments: [Segment] = [] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; needsLayout = true } }
    var selectedIndex = 0 { didSet { needsDisplay = true; setAccessibilityValue(segments.indices.contains(selectedIndex) ? segments[selectedIndex].title : nil) } }
    /// `.regular` 用于页面级切换（列表 / 键盘、外观），`.small` 用于次级切换（排序）。
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
    private var iconPointSize: CGFloat { size == .small ? 11 : 12 }
    private var padding: CGFloat { size == .small ? 12 : 14 }
    private var inset: CGFloat { 3 }

    private func icon(_ segment: Segment) -> NSImage? {
        segment.symbol.flatMap { ControlLabel.symbol($0, pointSize: iconPointSize) }
    }

    private func segmentWidth(_ segment: Segment) -> CGFloat {
        ControlLabel.width(title: segment.title, font: labelFont, icon: icon(segment)) + padding * 2
    }

    override var intrinsicContentSize: NSSize {
        // 等宽分段，视觉更整齐。
        let w = (segments.map(segmentWidth).max() ?? 0) * CGFloat(segments.count) + inset * 2
        return NSSize(width: ceil(w), height: height)
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
            ControlLabel.draw(title: segment.title, font: labelFont, icon: icon(segment), color: color, centeredIn: rect)
        }
    }

    private func index(at point: NSPoint) -> Int? {
        segments.indices.first { segmentRect($0).contains(point) }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let index = index(at: convert(event.locationInWindow, from: nil)), index != selectedIndex else { return }
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
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func layout() {
        super.layout()
        removeAllToolTips()
        for (i, segment) in segments.enumerated() {
            if let tip = segment.toolTip { addToolTip(segmentRect(i), owner: tip as NSString, userData: nil) }
        }
    }
}

/// 自绘控件里「图标 + 文字」的统一排版规范（分段控件、主按钮共用）：
/// - 图标与文字间距固定 5pt，按图标实际宽度排版，不留空白占位；
/// - 视觉垂直居中：以大写字母高度（cap height）的中线对齐控件中线，
///   中文字形、英文字母和 SF Symbol 都落在同一条中线上（行框居中会让中文明显偏下）。
enum ControlLabel {
    static let gap: CGFloat = 5

    static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .medium) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }

    static func width(title: String, font: NSFont, icon: NSImage?) -> CGFloat {
        let text = ceil(NSAttributedString(string: title, attributes: [.font: font]).size().width)
        return text + (icon.map { ceil($0.size.width) + gap } ?? 0)
    }

    /// 在（翻转坐标系的）`rect` 内水平、视觉垂直居中绘制图标和文字。
    static func draw(title: String, font: NSFont, icon: NSImage?, color: NSColor, centeredIn rect: NSRect) {
        let string = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: color])
        let textWidth = string.size().width
        let contentWidth = textWidth + (icon.map { $0.size.width + gap } ?? 0)
        var x = (rect.midX - contentWidth / 2).rounded()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        func pixelAligned(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        if let icon {
            let iconRect = NSRect(x: x, y: pixelAligned(rect.midY - icon.size.height / 2),
                                  width: icon.size.width, height: icon.size.height)
            icon.tinted(color).draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1,
                                    respectFlipped: true, hints: nil)
            x += icon.size.width + gap
        }
        // 不带 .usesLineFragmentOrigin 时，矩形原点就是基线位置。
        let baseline = pixelAligned(rect.midY + font.capHeight / 2)
        string.draw(with: NSRect(x: x, y: baseline, width: ceil(textWidth) + 1, height: 0), options: [], context: nil)
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
