import AppKit

/// 菜单栏菜单中带快捷键的一行：图标 + 名称 + 右侧醒目的立体键帽。
/// 系统菜单自带的快捷键文字很淡、也不能改样式；这里用与设置页相同的键帽，
/// 每次打开菜单都能把“哪个键开哪个 App”看清楚、记住。
///
/// 高亮跟随菜单本身（鼠标悬停和方向键选择都会设置 `enclosingMenuItem.isHighlighted`），
/// 回车由菜单项的 action 处理；鼠标点击在 `mouseUp` 里处理。
final class MenuShortcutItemView: NSView {
    private let onSelect: () -> Void
    private let caps = KeyCapButton()
    private let nameLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let isTemplateIcon: Bool

    static let height: CGFloat = 32
    private static let font = NSFont.menuFont(ofSize: 14)

    init(title: String, icon: NSImage?, hotKey: HotKey?, unavailable: Bool, width: CGFloat, onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        isTemplateIcon = icon?.isTemplate ?? false
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.stringValue = title
        nameLabel.font = Self.font
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        caps.hotKey = hotKey
        caps.isWarning = unavailable
        caps.isHidden = hotKey == nil

        [iconView, nameLabel, caps].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: caps.leadingAnchor, constant: -16),
            caps.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            caps.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title + " " + (hotKey?.displayString ?? ""))
    }

    required init?(coder: NSCoder) { nil }

    /// 菜单项需要的最小宽度（同一菜单内取最大值，让键帽右对齐）。
    static func preferredWidth(title: String, hotKey: HotKey?) -> CGFloat {
        let name = ceil(NSAttributedString(string: title, attributes: [.font: font]).size().width)
        let probe = KeyCapButton()
        probe.hotKey = hotKey
        return 14 + 18 + 8 + name + 16 + (hotKey == nil ? 0 : probe.intrinsicContentSize.width) + 12
    }

    private var isHighlighted: Bool { enclosingMenuItem?.isHighlighted ?? false }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = isHighlighted
        nameLabel.textColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        if isTemplateIcon { iconView.contentTintColor = highlighted ? .selectedMenuItemTextColor : .labelColor }
        guard highlighted else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSColor.selectedContentBackgroundColor.setFill()
        path.fill()
    }

    /// 整行作为一个点击目标（键帽只展示）。
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        guard let menu = enclosingMenuItem?.menu else { return }
        menu.cancelTracking()
        DispatchQueue.main.async { self.onSelect() }
    }
}
