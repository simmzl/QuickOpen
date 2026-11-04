import AppKit

/// 品牌色：与图标一致的珊瑚渐变。
enum Brand {
    static let coralLight = NSColor(srgbRed: 1.00, green: 0.604, blue: 0.420, alpha: 1) // #FF9A6B
    static let coral = NSColor(srgbRed: 0.976, green: 0.420, blue: 0.459, alpha: 1)      // #F96B75
    static let coralDeep = NSColor(srgbRed: 0.949, green: 0.333, blue: 0.478, alpha: 1)  // #F2557A

    static var gradient: NSGradient {
        NSGradient(colors: [coralLight, coralDeep])!
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension NSButton {
    /// macOS 26 使用液态玻璃按钮，旧系统保持圆角按钮。
    func applyGlassStyle(prominent: Bool = false) {
        if #available(macOS 26.0, *), GlassSurface.usesSystemGlass {
            bezelStyle = .glass
            if prominent {
                bezelColor = Brand.coral
                tintProminence = .primary
            }
        } else {
            bezelStyle = .rounded
            if prominent { bezelColor = Brand.coral }
        }
    }
}

/// 设置窗口的背景：整窗磨砂透出桌面，角落带一抹品牌色光晕，让上层的玻璃卡片有层次。
final class SettingsBackdrop: NSView {
    private let material = NSVisualEffectView()
    private let glow = CAGradientLayer()
    private let glowAccent = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        material.material = .underWindowBackground
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        material.wantsLayer = true
        material.autoresizingMask = [.width, .height]
        material.frame = bounds
        addSubview(material)
        if GlassSurface.forceFallback {
            // 离屏截图：桌面磨砂无法渲染，用窗口底色代替。
            material.state = .inactive
            material.material = .windowBackground
            material.blendingMode = .withinWindow
        }

        for layer in [glow, glowAccent] {
            layer.type = .radial
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            material.layer?.addSublayer(layer)
        }
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = bounds.width, h = bounds.height
        glow.frame = CGRect(x: w * 0.35, y: h * 0.45, width: w, height: h)
        glowAccent.frame = CGRect(x: -w * 0.45, y: -h * 0.55, width: w, height: h)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let dark = Brand.isDark(effectiveAppearance)
        glow.colors = [
            Brand.coralLight.withAlphaComponent(dark ? 0.16 : 0.20).cgColor,
            Brand.coralLight.withAlphaComponent(0).cgColor
        ]
        glowAccent.colors = [
            Brand.coralDeep.withAlphaComponent(0.10).cgColor,
            Brand.coralDeep.withAlphaComponent(0).cgColor
        ]
    }
}

/// 玻璃表面：macOS 26 上使用系统液态玻璃（NSGlassEffectView），
/// 更早的系统用 NSVisualEffectView 磨砂 + 手绘边缘高光近似。
///
/// 子视图请添加到 `contentView`。
final class GlassSurface: NSView {
    enum Kind {
        /// 浮在桌面上的面板（速查面板、启动提示）：透出桌面背景。
        case floating
        /// 窗口里的分组卡片：透出窗口背景。
        case card
        /// 小控件（键帽、按钮）。
        case control
    }

    let contentView = NSView()
    let kind: Kind
    var cornerRadius: CGFloat { didSet { applyCornerRadius() } }
    /// 着色（例如选中态的品牌色）；nil 为无色玻璃。
    var tintColor: NSColor? { didSet { applyTint() } }

    private var backgroundView: NSView!
    private let rimLayer = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private let tintLayer = CALayer()

    init(kind: Kind, cornerRadius: CGFloat) {
        self.kind = kind
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        buildBackground()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        // macOS 26：内容放进玻璃视图内部，系统才会为其做正确的折射与适配。
        let host: NSView
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            glass.contentView = contentView
            host = glass
        } else {
            addSubview(contentView)
            host = self
        }
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: host.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// 仅用于离屏截图测试：系统玻璃由窗口服务器合成，离屏渲染不出来。
    static var forceFallback = false

    static var usesSystemGlass: Bool {
        if forceFallback { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private func buildBackground() {
        if #available(macOS 26.0, *), Self.usesSystemGlass {
            let glass = NSGlassEffectView()
            glass.style = .regular
            backgroundView = glass
        } else {
            let effect = NSVisualEffectView()
            switch kind {
            case .floating:
                effect.material = .hudWindow
                effect.blendingMode = .behindWindow
            case .card:
                effect.material = .popover
                effect.blendingMode = .withinWindow
            case .control:
                effect.material = .selection
                effect.blendingMode = .withinWindow
            }
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.masksToBounds = true
            backgroundView = effect

            // 手绘玻璃边缘：左上亮、右下淡的渐变描边。
            rimLayer.startPoint = CGPoint(x: 0, y: 1)
            rimLayer.endPoint = CGPoint(x: 1, y: 0)
            rimMask.fillColor = nil
            rimMask.strokeColor = NSColor.black.cgColor
            rimLayer.mask = rimMask
        }
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        if !Self.usesSystemGlass {
            backgroundView.layer?.addSublayer(tintLayer)
            layer?.addSublayer(rimLayer)
        }
        applyCornerRadius()
        applyTint()
    }

    private func applyCornerRadius() {
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        } else {
            backgroundView?.layer?.cornerRadius = cornerRadius
            backgroundView?.layer?.cornerCurve = .continuous
            needsLayout = true
        }
    }

    private func applyTint() {
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            glass.tintColor = tintColor
        } else {
            tintLayer.backgroundColor = tintColor?.withAlphaComponent(0.55).cgColor
        }
    }

    override func layout() {
        super.layout()
        guard !Self.usesSystemGlass else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        tintLayer.cornerRadius = cornerRadius
        tintLayer.cornerCurve = .continuous
        rimLayer.frame = bounds
        let lineWidth: CGFloat = kind == .control ? 1 : 1.5
        rimMask.lineWidth = lineWidth
        rimMask.path = CGPath(
            roundedRect: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
            cornerWidth: max(0, cornerRadius - lineWidth / 2),
            cornerHeight: max(0, cornerRadius - lineWidth / 2),
            transform: nil
        )
        updateRimColors()
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateRimColors()
        applyTint()
    }

    private func updateRimColors() {
        let dark = Brand.isDark(effectiveAppearance)
        let top = NSColor.white.withAlphaComponent(dark ? 0.32 : 0.85)
        let mid = NSColor.white.withAlphaComponent(dark ? 0.08 : 0.25)
        let bottom = NSColor.white.withAlphaComponent(dark ? 0.14 : 0.45)
        rimLayer.colors = [top.cgColor, mid.cgColor, bottom.cgColor]
        rimLayer.locations = [0, 0.55, 1]
    }
}
