import AppKit

/// 每次按 App 快捷键时，在屏幕上短暂显示该 App 的图标、名称与快捷键，帮助记忆。
final class LaunchHUDController {
    let panel = OverlayPanel(cornerRadius: 24)
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let keyCaps = KeyCapView(style: .overlay, fontSize: 15)
    private var hideWorkItem: DispatchWorkItem?
    /// 每次显示自增，用于丢弃过期的淡出回调。
    private var generation = 0

    private static let size = NSSize(width: 220, height: 232)

    init() {
        panel.ignoresMouseEvents = true
        buildContent()
    }

    func show(
        _ shortcut: AppShortcut,
        outcome: LaunchOutcome,
        position: HUDPosition,
        duration: TimeInterval
    ) {
        generation += 1
        let token = generation
        hideWorkItem?.cancel()

        iconView.image = AppIcons.icon(forPath: shortcut.appPath, size: 112)
        nameLabel.stringValue = shortcut.appName
        keyCaps.hotKey = shortcut.hotKey
        switch outcome {
        case .activated:
            statusLabel.stringValue = ""
        case .launched:
            statusLabel.stringValue = L("Launching…", "正在启动…")
        case .hidden:
            statusLabel.stringValue = L("Hidden", "已隐藏")
        case .missing:
            statusLabel.stringValue = L("App not found", "找不到 App")
        }
        statusLabel.isHidden = statusLabel.stringValue.isEmpty
        iconView.alphaValue = outcome == .hidden ? 0.55 : 1

        guard let screen = OverlayPanel.activeScreen else { return }
        panel.setFrame(Self.frame(on: screen, position: position), display: false)

        let layer = panel.surface.layer
        let wasVisible = panel.isVisible && panel.alphaValue > 0.01
        panel.orderFrontRegardless()

        if wasVisible {
            // 连续按多个快捷键：直接替换内容，不重新播放入场动画。
            panel.alphaValue = 1
        } else if OverlayPanel.reduceMotion {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
            if let layer {
                // AppKit 管理的 layer 锚点在左下角，不去修改它，
                // 而是用“平移-缩放-平移回”的组合变换实现以中心缩放。
                let bounds = layer.bounds
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                func scaled(_ factor: CGFloat) -> CATransform3D {
                    var t = CATransform3DMakeTranslation(center.x, center.y, 0)
                    t = CATransform3DScale(t, factor, factor, 1)
                    return CATransform3DTranslate(t, -center.x, -center.y, 0)
                }
                let pop = CASpringAnimation(keyPath: "transform")
                pop.fromValue = NSValue(caTransform3D: scaled(0.86))
                pop.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                pop.damping = 18
                pop.stiffness = 320
                pop.mass = 1
                pop.duration = pop.settlingDuration
                layer.add(pop, forKey: "pop")
            }
        }

        let workItem = DispatchWorkItem { [weak self] in self?.fadeOut(token: token) }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    /// 速查面板弹出时立刻收起提示，避免叠在一起。
    func dismiss() {
        hideWorkItem?.cancel()
        generation += 1
        panel.orderOut(nil)
    }

    private func fadeOut(token: Int) {
        guard token == generation else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, token == self.generation else { return }
            self.panel.orderOut(nil)
        })
    }

    private static func frame(on screen: NSScreen, position: HUDPosition) -> NSRect {
        let visible = screen.visibleFrame
        let x = round(visible.midX - size.width / 2)
        let y: CGFloat
        switch position {
        case .center:
            y = round(visible.midY - size.height / 2)
        case .bottom:
            // 与系统音量/亮度提示的位置接近。
            y = round(visible.minY + visible.height * 0.14)
        }
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func buildContent() {
        let content = panel.effectView
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 14
            shadow.shadowOffset = NSSize(width: 0, height: -5)
            return shadow
        }()

        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        let stack = NSStackView(views: [iconView, nameLabel, keyCaps, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(12, after: iconView)
        stack.setCustomSpacing(10, after: nameLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 112),
            iconView.heightAnchor.constraint(equalToConstant: 112),
            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -32),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
    }
}
