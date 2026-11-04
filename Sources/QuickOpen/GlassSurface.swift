import AppKit

/// 界面配色（克制方案）：界面以中性色为主，主题色只用于少数关键状态。
///
/// 主题色仅出现在：
/// 1. 录制快捷键时的输入框（`accent` 描边 + `accentFill` 底色）
/// 2. 速查面板的选中项（`accent` 描边）
/// 3. 录制时的操作提示文字（`accentText`）
/// 4. 品牌标识（App 图标、速查面板标题的小 logo）
/// 其余控件（复选框、滑块、拖入高亮等）跟随系统强调色，状态色用系统红/橙。
enum Theme {
    /// 琥珀橙，与图标一致。用于描边等非文字元素。#F97316
    static let accent = NSColor(srgbRed: 0.976, green: 0.451, blue: 0.086, alpha: 1)

    /// 用作文字的主题色：比图标深/浅一档，保证对比度。
    /// 浅色模式 #C2560C，深色模式 #FFB454。
    static let accentText = NSColor(name: "QuickOpenAccentText") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 1.0, green: 0.706, blue: 0.329, alpha: 1)
            : NSColor(srgbRed: 0.761, green: 0.337, blue: 0.047, alpha: 1)
    }

    /// 录制状态下输入框的淡底色。
    static let accentFill = NSColor(name: "QuickOpenAccentFill") { appearance in
        accent.withAlphaComponent(isDark(appearance) ? 0.16 : 0.08)
    }

    /// 中性的“运行中”标记。
    static let runningIndicator = NSColor(name: "QuickOpenRunning") { appearance in
        isDark(appearance) ? NSColor.white.withAlphaComponent(0.5) : NSColor.black.withAlphaComponent(0.38)
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension NSColor {
    /// 在指定外观下解析动态颜色，得到可用于 CALayer 的 CGColor。
    func resolved(for appearance: NSAppearance) -> CGColor {
        var result = cgColor
        appearance.performAsCurrentDrawingAppearance { result = self.cgColor }
        return result
    }
}

extension NSButton {
    /// macOS 26 使用液态玻璃按钮，旧系统保持圆角按钮。保持中性，不着主题色。
    func applyGlassStyle() {
        if #available(macOS 26.0, *), GlassSurface.usesSystemGlass {
            bezelStyle = .glass
        } else {
            bezelStyle = .rounded
        }
    }
}

/// 设置窗口的背景：整窗系统磨砂，透出桌面。
final class SettingsBackdrop: NSView {
    private let material = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material.material = .underWindowBackground
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        material.autoresizingMask = [.width, .height]
        material.frame = bounds
        addSubview(material)
        if GlassSurface.forceFallback {
            // 离屏截图：桌面磨砂无法渲染，用窗口底色代替。
            material.state = .inactive
            material.material = .windowBackground
            material.blendingMode = .withinWindow
        }
    }

    required init?(coder: NSCoder) { nil }
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
        let dark = Theme.isDark(effectiveAppearance)
        let top = NSColor.white.withAlphaComponent(dark ? 0.32 : 0.85)
        let mid = NSColor.white.withAlphaComponent(dark ? 0.08 : 0.25)
        let bottom = NSColor.white.withAlphaComponent(dark ? 0.14 : 0.45)
        rimLayer.colors = [top.cgColor, mid.cgColor, bottom.cgColor]
        rimLayer.locations = [0, 0.55, 1]
    }
}
