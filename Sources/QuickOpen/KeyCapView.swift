import AppKit

/// 把快捷键画成一排独立的键帽：⌃ ⌥ ⌘ Space。
/// 速查面板、启动提示和设置列表共用。
final class KeyCapView: NSView {
    enum Style {
        /// 设置列表等普通窗口中使用。
        case regular
        /// 毛玻璃浮层上使用，颜色更柔和。
        case overlay
        /// 快捷键冲突或注册失败。
        case warning
    }

    var hotKey: HotKey? { didSet { rebuild() } }
    /// 未设置快捷键时显示的占位文字。
    var placeholder: String = "未设置" { didSet { rebuild() } }
    var style: Style = .regular { didSet { rebuild() } }
    var fontSize: CGFloat = 12 { didSet { rebuild() } }

    private let stack = NSStackView()

    init(hotKey: HotKey? = nil, style: Style = .regular, fontSize: CGFloat = 12) {
        self.hotKey = hotKey
        self.style = style
        self.fontSize = fontSize
        super.init(frame: .zero)
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // 键帽始终在自身区域内水平居中：外层被拉宽时（如单个键）也不会靠左。
        let preferTight = stack.widthAnchor.constraint(equalTo: widthAnchor)
        preferTight.priority = .defaultLow
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            preferTight,
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        stack.setHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        rebuild()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuild()
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let hotKey else {
            let label = NSTextField(labelWithString: placeholder)
            label.font = .systemFont(ofSize: fontSize)
            label.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(label)
            return
        }
        for cap in HotKeyFormatter.keyCaps(for: hotKey) {
            stack.addArrangedSubview(KeyCap(text: cap, style: style, fontSize: fontSize))
        }
        setAccessibilityLabel(hotKey.displayString)
    }
}

/// 单颗键帽。
private final class KeyCap: NSView {
    private let label: NSTextField
    private let style: KeyCapView.Style
    private let fontSize: CGFloat

    init(text: String, style: KeyCapView.Style, fontSize: CGFloat) {
        self.style = style
        self.fontSize = fontSize
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        // 单字符用等宽数字字体居中；“Space”“Esc”等字样用常规字体。
        label.font = text.count == 1
            ? .monospacedSystemFont(ofSize: fontSize, weight: .medium)
            : .systemFont(ofSize: fontSize * 0.9, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let height = round(fontSize * 1.75)
        let padding = round(fontSize * 0.45)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: height),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        let height = round(fontSize * 1.75)
        layer.cornerRadius = max(4, height * 0.24)
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch style {
        case .regular:
            layer.backgroundColor = (isDark ? NSColor.white.withAlphaComponent(0.10)
                                            : NSColor.black.withAlphaComponent(0.05)).cgColor
            layer.borderColor = (isDark ? NSColor.white.withAlphaComponent(0.14)
                                        : NSColor.black.withAlphaComponent(0.12)).cgColor
            label.textColor = .labelColor
        case .overlay:
            layer.backgroundColor = (isDark ? NSColor.white.withAlphaComponent(0.14)
                                            : NSColor.white.withAlphaComponent(0.65)).cgColor
            layer.borderColor = (isDark ? NSColor.white.withAlphaComponent(0.18)
                                        : NSColor.black.withAlphaComponent(0.10)).cgColor
            label.textColor = .labelColor
        case .warning:
            layer.backgroundColor = NSColor.systemRed.withAlphaComponent(isDark ? 0.22 : 0.12).cgColor
            layer.borderColor = NSColor.systemRed.withAlphaComponent(0.45).cgColor
            label.textColor = .systemRed
        }
        // 底部一像素阴影，模拟实体键帽。
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = isDark ? 0.35 : 0.12
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: -1)
    }
}
