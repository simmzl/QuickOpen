import AppKit
import Carbon

/// 「快捷键」列表视图（分组列表）的行与控件。
/// 布局：像“系统设置”一样的成组列表——同组的行合成一张圆角卡片，行间细分隔线；
/// 快捷键用与键盘视图同风格的小键帽，删除等操作收进悬停时出现的 “⋯” 菜单。

// MARK: - 数据

/// 列表中的一行：分组标题或某个 App。
enum ShortcutListItem: Equatable {
    /// `modifiers == nil` 表示“未设置”组。
    case header(modifiers: UInt32?, count: Int)
    case app(UUID)
}

enum ShortcutListBuilder {
    /// 按键位：按修饰键分组（单键在前），组内按键在键盘上的位置排序，未设置的 App 放最后。
    /// 自定义：不分组，保持用户拖动的顺序。
    static func items(for shortcuts: [AppShortcut], order: ShortcutsListOrder) -> [ShortcutListItem] {
        guard order == .byKey else { return shortcuts.map { .app($0.id) } }
        var result: [ShortcutListItem] = []
        for group in KeymapGroups.groups(of: shortcuts) {
            let members = shortcuts.filter { $0.hotKey?.modifiers == group }
                .sorted { KeyboardLayout.readingOrder(of: $0.hotKey!.keyCode) < KeyboardLayout.readingOrder(of: $1.hotKey!.keyCode) }
            result.append(.header(modifiers: group, count: members.count))
            result += members.map { .app($0.id) }
        }
        let unset = shortcuts.filter { $0.hotKey == nil }
        if !unset.isEmpty {
            result.append(.header(modifiers: nil, count: unset.count))
            result += unset.map { .app($0.id) }
        }
        return result
    }
}

// MARK: - 行背景：成组卡片

/// 同一组的行拼成一张圆角卡片：组内首行画上圆角、末行画下圆角，行间画缩进的细分隔线。
final class GroupedRowView: NSTableRowView {
    var isFirstInGroup = true { didSet { needsDisplay = true } }
    var isLastInGroup = true { didSet { needsDisplay = true } }
    /// 分隔线的左缩进（与 App 名称对齐）。
    var separatorInset: CGFloat = 58
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    private static let radius: CGFloat = 12

    override var isFlipped: Bool { true }

    override func drawBackground(in dirtyRect: NSRect) {
        let dark = Theme.isDark(effectiveAppearance)
        let rect = bounds.insetBy(dx: 1, dy: 0)
        let path = Self.cardPath(rect, top: isFirstInGroup, bottom: isLastInGroup, radius: Self.radius)
        (dark ? NSColor.white.withAlphaComponent(0.055) : NSColor.white.withAlphaComponent(0.62)).setFill()
        path.fill()
        if isHovered {
            (dark ? NSColor.white.withAlphaComponent(0.03) : NSColor.black.withAlphaComponent(0.025)).setFill()
            path.fill()
        }
        // 外描边：只描卡片外轮廓（左右 + 首行顶边 + 末行底边）。
        let stroke = dark ? NSColor.white.withAlphaComponent(0.09) : NSColor.black.withAlphaComponent(0.1)
        stroke.setStroke()
        let outline = Self.outlinePath(rect.insetBy(dx: 0.25, dy: 0), top: isFirstInGroup, bottom: isLastInGroup, radius: Self.radius)
        outline.lineWidth = 0.5
        outline.stroke()
        if !isFirstInGroup {
            (dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.1)).setFill()
            NSRect(x: rect.minX + separatorInset, y: 0, width: rect.width - separatorInset, height: 0.5).fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {}
    override var isEmphasized: Bool { get { false } set {} }

    private static func cardPath(_ r: NSRect, top: Bool, bottom: Bool, radius: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        let tr = top ? radius : 0, br = bottom ? radius : 0
        p.move(to: NSPoint(x: r.minX, y: r.minY + tr))
        if top { p.appendArc(withCenter: NSPoint(x: r.minX + tr, y: r.minY + tr), radius: tr, startAngle: 180, endAngle: 270) }
        p.line(to: NSPoint(x: r.maxX - tr, y: r.minY))
        if top { p.appendArc(withCenter: NSPoint(x: r.maxX - tr, y: r.minY + tr), radius: tr, startAngle: 270, endAngle: 360) }
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - br))
        if bottom { p.appendArc(withCenter: NSPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: 0, endAngle: 90) }
        p.line(to: NSPoint(x: r.minX + br, y: r.maxY))
        if bottom { p.appendArc(withCenter: NSPoint(x: r.minX + br, y: r.maxY - br), radius: br, startAngle: 90, endAngle: 180) }
        p.close()
        return p
    }

    private static func outlinePath(_ r: NSRect, top: Bool, bottom: Bool, radius: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        let tr = top ? radius : 0, br = bottom ? radius : 0
        // 左边
        p.move(to: NSPoint(x: r.minX + br, y: r.maxY))
        if bottom { p.appendArc(withCenter: NSPoint(x: r.minX + br, y: r.maxY - br), radius: br, startAngle: 90, endAngle: 180) }
        else { p.move(to: NSPoint(x: r.minX, y: r.maxY)) }
        p.line(to: NSPoint(x: r.minX, y: r.minY + tr))
        if top {
            p.appendArc(withCenter: NSPoint(x: r.minX + tr, y: r.minY + tr), radius: tr, startAngle: 180, endAngle: 270)
            p.line(to: NSPoint(x: r.maxX - tr, y: r.minY))
            p.appendArc(withCenter: NSPoint(x: r.maxX - tr, y: r.minY + tr), radius: tr, startAngle: 270, endAngle: 360)
        } else {
            p.move(to: NSPoint(x: r.maxX, y: r.minY))
        }
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - br))
        if bottom {
            p.appendArc(withCenter: NSPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: 0, endAngle: 90)
            p.line(to: NSPoint(x: r.minX + br, y: r.maxY))
        }
        return p
    }
}

/// 分组标题行没有卡片背景。
final class PlainRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
}

// MARK: - 分组标题

/// “单键 6”“⇧ ⌘ 2”“未设置 1”：修饰键用与键盘视图同色的小标签。
final class GroupHeaderView: NSTableCellView {
    private let chips = NSStackView()
    private let countLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        chips.orientation = .horizontal
        chips.spacing = 2
        countLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        countLabel.textColor = .secondaryLabelColor
        let row = NSStackView(views: [chips, countLabel])
        row.orientation = .horizontal
        row.spacing = 7
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(modifiers: UInt32?, count: Int) {
        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        countLabel.stringValue = "\(count)"
        guard let modifiers else {
            let label = NSTextField(labelWithString: L("Not set", "未设置"))
            label.font = .systemFont(ofSize: 11.5, weight: .semibold)
            label.textColor = .secondaryLabelColor
            chips.addArrangedSubview(label)
            return
        }
        let parts = modifiers == 0 ? [KeymapGroups.title(0)] : KeymapGroups.glyphs(modifiers)
        for part in parts { chips.addArrangedSubview(GroupChip(text: part, modifiers: modifiers)) }
        setAccessibilityLabel(KeymapGroups.title(modifiers) + " \(count)")
    }
}

/// 分组颜色的小标签。
private final class GroupChip: NSView {
    private let text: String
    private let modifiers: UInt32

    init(text: String, modifiers: UInt32) {
        self.text = text
        self.modifiers = modifiers
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let width = max(17, ceil(NSAttributedString(string: text, attributes: [.font: Self.font]).size().width) + 8)
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: width), heightAnchor.constraint(equalToConstant: 17)])
    }

    required init?(coder: NSCoder) { nil }
    private static let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)

    override func draw(_ dirtyRect: NSRect) {
        let dark = Theme.isDark(effectiveAppearance)
        let lc = KeymapPalette.color(for: modifiers)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        (dark ? lc.mix(oklch(0.2, 0, 0), 0.62) : lc.mix(.white, 0.8)).setFill()
        path.fill()
        (dark ? lc.mix(oklch(0.2, 0, 0), 0.35) : lc.mix(.white, 0.45)).setStroke()
        path.lineWidth = 1
        path.stroke()
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let str = NSAttributedString(string: text, attributes: [
            .font: Self.font, .foregroundColor: dark ? lc.mix(.white, 0.45) : lc.mix(.black, 0.35), .paragraphStyle: para
        ])
        let h = str.size().height
        str.draw(in: NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h))
    }
}

// MARK: - 键帽按钮

/// 可点击的快捷键：平时是一排立体小键帽（修饰键带分组颜色），录制时是橙色的“请按快捷键…”。
final class KeyCapButton: NSControl {
    var hotKey: HotKey? { didSet { invalidate() } }
    var isRecording = false { didSet { invalidate() } }
    var isWarning = false { didSet { invalidate() } }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    private static let capHeight: CGFloat = 24
    private static let capFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let gap: CGFloat = 4

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }

    private func invalidate() {
        invalidateIntrinsicContentSize()
        needsDisplay = true
        setAccessibilityLabel(isRecording ? L("Recording shortcut", "正在录制快捷键")
                              : hotKey?.displayString ?? L("Click to record", "点击录制"))
    }

    private var caps: [String] { hotKey.map(HotKeyFormatter.keyCaps(for:)) ?? [] }

    private func capWidth(_ text: String) -> CGFloat {
        let w = ceil(NSAttributedString(string: text, attributes: [.font: Self.capFont]).size().width)
        return max(Self.capHeight + 2, w + 14)
    }

    private var recordingText: String { L("Press shortcut…", "请按快捷键…") }
    private var unsetText: String { L("Click to record", "点击录制") }

    override var intrinsicContentSize: NSSize {
        if isRecording {
            let w = ceil(NSAttributedString(string: recordingText, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).size().width)
            return NSSize(width: w + 36, height: 30)
        }
        if hotKey == nil {
            let w = ceil(NSAttributedString(string: unsetText, attributes: [.font: NSFont.systemFont(ofSize: 12)]).size().width)
            return NSSize(width: w + 20, height: 30)
        }
        let total = caps.reduce(0) { $0 + capWidth($1) } + CGFloat(max(0, caps.count - 1)) * Self.gap
        return NSSize(width: total + 4, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = Theme.isDark(effectiveAppearance)
        if isRecording {
            let rect = bounds.insetBy(dx: 1, dy: 1.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            Theme.accentFill.setFill(); path.fill()
            Theme.accent.setStroke(); path.lineWidth = 1.5; path.stroke()
            Theme.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 12, y: rect.midY - 3.5, width: 7, height: 7)).fill()
            let str = NSAttributedString(string: recordingText, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: Theme.accentText
            ])
            str.draw(at: NSPoint(x: rect.minX + 25, y: rect.midY - str.size().height / 2))
            return
        }
        if hotKey == nil {
            let rect = bounds.insetBy(dx: 1, dy: 3)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            path.setLineDash([3, 2.5], count: 2, phase: 0)
            path.lineWidth = 1
            (isHovered ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setStroke()
            path.stroke()
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let str = NSAttributedString(string: unsetText, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: isHovered ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor,
                .paragraphStyle: para
            ])
            let h = str.size().height
            str.draw(in: NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h))
            return
        }
        let mods = hotKey!.modifiers
        let lc = KeymapPalette.color(for: mods)
        var x = bounds.maxX - intrinsicContentSize.width + 2
        let lift: CGFloat = isPressed ? 0 : (isHovered ? -1 : 0)
        for (index, cap) in caps.enumerated() {
            let isMod = index < caps.count - 1
            let w = capWidth(cap)
            let rect = NSRect(x: x, y: (bounds.height - Self.capHeight) / 2 - 1 + lift, width: w, height: Self.capHeight)
            drawCap(cap, in: rect, modColor: isMod ? lc : nil, dark: dark)
            x += w + Self.gap
        }
    }

    /// 与键盘视图一致的小键帽：上浅下深的顶面 + 底部“裙边”。
    private func drawCap(_ text: String, in rect: NSRect, modColor: NSColor?, dark: Bool) {
        let radius: CGFloat = 6
        var top: NSColor, top2: NSColor, lip: NSColor, edge: NSColor, ink: NSColor
        if isWarning, modColor == nil {
            top = NSColor(srgbRed: 1, green: 0.95, blue: 0.95, alpha: 1); top2 = NSColor(srgbRed: 1, green: 0.89, blue: 0.88, alpha: 1)
            lip = NSColor(srgbRed: 0.94, green: 0.73, blue: 0.71, alpha: 1); edge = NSColor.systemRed.withAlphaComponent(0.45); ink = .systemRed
            if dark { top = NSColor.systemRed.withAlphaComponent(0.28); top2 = NSColor.systemRed.withAlphaComponent(0.22); lip = NSColor.systemRed.withAlphaComponent(0.35) }
        } else if let lc = modColor {
            if dark {
                top = lc.mix(oklch(0.27, 0, 0), 0.55); top2 = lc.mix(oklch(0.27, 0, 0), 0.65)
                lip = lc.mix(oklch(0.12, 0, 0), 0.55); edge = NSColor.black.withAlphaComponent(0.6); ink = lc.mix(.white, 0.45)
            } else {
                top = lc.mix(.white, 0.82); top2 = lc.mix(.white, 0.72)
                lip = lc.mix(.white, 0.5); edge = lc.mix(.white, 0.45); ink = lc.mix(.black, 0.35)
            }
        } else if dark {
            top = oklch(0.42, 0.004, 75); top2 = oklch(0.37, 0.004, 75); lip = oklch(0.24, 0.004, 75)
            edge = NSColor.black.withAlphaComponent(0.6); ink = oklch(0.92, 0.004, 75)
        } else {
            top = .white; top2 = oklch(0.955, 0.005, 95); lip = oklch(0.83, 0.008, 95)
            edge = NSColor.black.withAlphaComponent(0.2); ink = oklch(0.27, 0.01, 90)
        }
        let lipDepth: CGFloat = isPressed ? 1 : 2
        // 裙边与投影
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.35 : 0.12)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -(lipDepth + 0.5))
        shadow.set()
        lip.setFill()
        NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: lipDepth), xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
        // 顶面
        let face = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGradient(starting: top, ending: top2)?.draw(in: face, angle: 90)
        edge.setStroke()
        face.lineWidth = 0.5
        face.stroke()
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let font = text.count == 1 ? NSFont.systemFont(ofSize: 12, weight: .semibold)
                                   : NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: para])
        let h = str.size().height
        str.draw(in: NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h))
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { sendAction(action, to: target) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// MARK: - App 行

final class ShortcutListRowView: NSTableCellView {
    var onRecord: (() -> Void)?
    var onDelete: (() -> Void)?
    var onPreview: (() -> Void)?
    var onReveal: (() -> Void)?
    /// 悬停状态变化（用于行背景高亮）。
    var onHoverChange: ((Bool) -> Void)?

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusDot = DotView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let grip = NSImageView()
    private let keyButton = KeyCapButton()
    private let moreButton = NSButton()
    private var hoverArea: NSTrackingArea?
    private var leadingToEdge: NSLayoutConstraint!
    private var leadingToGrip: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.wantsLayer = true
        NSLayoutConstraint.activate([statusDot.widthAnchor.constraint(equalToConstant: 6), statusDot.heightAnchor.constraint(equalToConstant: 6)])

        let status = NSStackView(views: [statusDot, statusLabel])
        status.orientation = .horizontal
        status.spacing = 5
        status.alignment = .centerY
        let texts = NSStackView(views: [nameLabel, status])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2

        grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: L("Drag to reorder", "拖动排序"))
        grip.contentTintColor = .tertiaryLabelColor
        grip.toolTip = L("Drag to reorder", "拖动排序")

        keyButton.target = self
        keyButton.action = #selector(record)

        moreButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L("More", "更多"))
        moreButton.bezelStyle = .inline
        moreButton.isBordered = false
        moreButton.contentTintColor = .secondaryLabelColor
        moreButton.target = self
        moreButton.action = #selector(showMenu)
        moreButton.toolTip = L("More", "更多")
        moreButton.alphaValue = 0

        [grip, iconView, texts, keyButton, moreButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        keyButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        leadingToEdge = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14)
        leadingToGrip = iconView.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 8)
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            grip.centerYAnchor.constraint(equalTo: centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 14),
            leadingToEdge,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            texts.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: keyButton.leadingAnchor, constant: -12),
            moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            moreButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 26),
            moreButton.heightAnchor.constraint(equalToConstant: 26),
            keyButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            keyButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        menu = makeMenu()
    }

    required init?(coder: NSCoder) { nil }

    func configure(shortcut: AppShortcut, isRunning: Bool, isRecording: Bool, failure: OSStatus?, showsGrip: Bool) {
        iconView.image = AppIcons.icon(forPath: shortcut.appPath, size: 32)
        nameLabel.stringValue = shortcut.appName
        toolTip = shortcut.bundleIdentifier ?? shortcut.appPath
        moreButton.toolTip = L("More actions for \(shortcut.appName)", "\(shortcut.appName) 的更多操作")
        grip.isHidden = !showsGrip
        leadingToEdge.isActive = !showsGrip
        leadingToGrip.isActive = showsGrip

        keyButton.hotKey = shortcut.hotKey
        keyButton.isRecording = isRecording
        keyButton.isWarning = failure != nil
        keyButton.toolTip = shortcut.hotKey == nil ? L("Click to record a shortcut", "点击录制快捷键") : L("Click to change the shortcut", "点击修改快捷键")

        let missing = !FileManager.default.fileExists(atPath: shortcut.appPath)
            && shortcut.bundleIdentifier.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) == nil
        iconView.alphaValue = missing ? 0.45 : 1
        statusDot.isHidden = false
        if missing {
            setStatus(L("⚠︎ App not found — it may have been moved or uninstalled", "⚠︎ 找不到此 App，可能已被移动或卸载"), color: .systemOrange, dot: nil)
        } else if let failure {
            setStatus("⚠︎ " + failure.hotKeyFailureDescription, color: .systemRed, dot: nil)
        } else if let warning = shortcut.hotKey?.typingWarning {
            setStatus("⚠︎ " + warning, color: .systemOrange, dot: nil)
        } else if shortcut.hotKey == nil {
            setStatus(L("No shortcut yet", "还没有设置快捷键"), color: .secondaryLabelColor, dot: nil)
        } else if isRunning {
            setStatus(L("Running", "运行中"), color: .secondaryLabelColor, dot: .systemGreen)
        } else {
            setStatus(L("Not running", "未运行"), color: .secondaryLabelColor, dot: Theme.runningIndicator)
        }
    }

    private func setStatus(_ text: String, color: NSColor, dot: NSColor?) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
        statusDot.isHidden = dot == nil
        if let dot { statusDot.color = dot }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Record Shortcut", "录制快捷键"), action: #selector(record), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Preview Launch Hint", "预览启动提示"), action: #selector(preview), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Show in Finder", "在访达中显示"), action: #selector(reveal), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let remove = NSMenuItem(title: L("Remove", "删除"), action: #selector(delete), keyEquivalent: "")
        remove.target = self
        remove.attributedTitle = NSAttributedString(string: remove.title, attributes: [.foregroundColor: NSColor.systemRed])
        menu.addItem(remove)
        return menu
    }

    @objc private func showMenu() {
        menu?.popUp(positioning: nil, at: NSPoint(x: moreButton.frame.minX, y: moreButton.frame.minY - 4), in: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        moreButton.animator().alphaValue = 1
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        moreButton.animator().alphaValue = 0
        onHoverChange?(false)
    }

    /// 仅供截图测试：让 “⋯” 常显。
    func showActionsForSnapshot() { moreButton.alphaValue = 1 }

    @objc private func record() { onRecord?() }
    @objc private func delete() { onDelete?() }
    @objc private func preview() { onPreview?() }
    @objc private func reveal() { onReveal?() }
}
