import AppKit
import Carbon

/// 类似 ⌘Tab 的速查面板：在屏幕中央列出所有已设置快捷键的 App。
///
/// - 按住模式：按住修饰键期间显示；按住时连按触发键（如 Space）依次选择，
///   松开修饰键时若有选中项则打开它，否则直接关闭。
///   快捷键是单键时，按住该键显示，松开关闭。
/// - 切换模式：再按一次快捷键或 Esc 关闭；←→↑↓/⇥ 选择，↩ 打开。
/// - 任何模式下：按某个 App 自己的快捷键或点击图标都会打开它并关闭面板。
final class OverviewPanelController {
    /// 用户在面板里选择了一个 App。
    var onLaunch: ((AppShortcut) -> Void)?
    /// 判断 App 是否正在运行（显示小圆点）。
    var isRunning: ((AppShortcut) -> Bool)?
    /// 当前热键事件的时间戳（由 AppDelegate 提供，来自 GlobalHotKeyManager）。
    var currentEventTime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    let panel = OverlayPanel(cornerRadius: 22)
    private let overlayKeys = GlobalHotKeyManager(signature: GlobalHotKeyManager.overlaySignature)
    private var tiles: [OverviewTile] = []
    private var items: [AppShortcut] = []
    private var columns = 1
    private var state = OverviewInteraction(mode: .toggle, itemCount: 0, shownAt: 0)

    var selectedIndex: Int? { state.selection }

    /// 测试用：直接设置选中项。
    func select(index: Int?) {
        state.select(index)
        updateSelection()
    }

    private var triggerHotKey: HotKey?
    private var modifierTimer: Timer?
    private var mouseMonitor: Any?
    /// 检测到修饰键松开的时间；在宽限期内到达、且发生在此之前的触发键仍计入选择。
    private var releaseDetectedAt: TimeInterval?
    private weak var footerLabel: NSTextField?
    /// 修饰键松开后等待排队中的热键事件的宽限期。
    private static let releaseGrace: TimeInterval = 0.04

    private static let tileSize = NSSize(width: 124, height: 146)
    private static let padding: CGFloat = 22
    private static let headerHeight: CGFloat = 34
    private static let footerHeight: CGFloat = 30

    /// 面板处于显示状态（不含淡出过程）。
    private(set) var isVisible = false

    // MARK: 触发

    /// 速查面板快捷键被按下。
    func hotKeyPressed(shortcuts: [AppShortcut], hotKey: HotKey, mode: OverviewMode) {
        let eventTime = currentEventTime()
        guard isVisible else {
            show(shortcuts: shortcuts, mode: mode, triggerHotKey: hotKey, at: eventTime)
            return
        }
        // 修饰键已松开、正在宽限期：只接受松开之前发生的按键。
        if let releasedAt = releaseDetectedAt, eventTime > releasedAt { return }
        apply(state.triggerPressed())
    }

    func hotKeyReleased() {
        state.triggerReleased()
        // 单键快捷键没有可检测的修饰键：按住该键显示，松开即视为“松开”。
        if isVisible, state.mode == .hold, triggerHotKey?.modifierFlags.isEmpty == true {
            finishHold()
        }
    }

    /// 显示面板。从菜单打开时修饰键并未按住，应使用 `.toggle`。
    func show(
        shortcuts: [AppShortcut],
        mode: OverviewMode,
        triggerHotKey: HotKey?,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        items = shortcuts.filter { $0.hotKey != nil }
        self.triggerHotKey = triggerHotKey
        state = OverviewInteraction(mode: triggerHotKey == nil ? .toggle : mode, itemCount: items.count, shownAt: time)
        if triggerHotKey == nil { state.triggerReleased() }
        releaseDetectedAt = nil

        buildContent()
        guard let screen = OverlayPanel.activeScreen else { return }
        let size = contentSize(maxWidth: screen.visibleFrame.width - 80)
        let visible = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: round(visible.midX - size.width / 2),
                y: round(visible.midY - size.height / 2 + visible.height * 0.06),
                width: size.width,
                height: size.height
            ),
            display: true
        )

        isVisible = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayPanel.reduceMotion ? 0.08 : 0.12
            panel.animator().alphaValue = 1
        }

        installInteraction()
    }

    func dismiss() {
        guard isVisible else { return }
        isVisible = false
        removeInteraction()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
        })
    }

    // MARK: 交互

    private func installInteraction() {
        removeInteraction()

        if state.mode == .hold, let triggerHotKey, !triggerHotKey.modifierFlags.isEmpty {
            let required = triggerHotKey.modifierFlags
            // 读取 NSEvent.modifierFlags 不需要辅助功能权限。
            let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
                let current = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if !current.isSuperset(of: required) { self?.modifiersReleasedDetected() }
            }
            RunLoop.main.add(timer, forMode: .common)
            modifierTimer = timer
        } else if state.mode == .toggle {
            registerToggleModeKeys()
        }
        // 单键 + 按住模式：由 hotKeyReleased() 处理松开。

        // 点击面板以外的地方关闭。监听全局鼠标事件不需要辅助功能权限。
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeInteraction() {
        modifierTimer?.invalidate()
        modifierTimer = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        overlayKeys.unregisterAll()
    }

    /// 轮询发现修饰键已松开：先停止轮询，再等一个很短的宽限期，
    /// 让已经发生但还在事件队列里的触发键（Space）先被处理，避免误判为“没选中/轻按”。
    private func modifiersReleasedDetected() {
        guard releaseDetectedAt == nil else { return }
        releaseDetectedAt = ProcessInfo.processInfo.systemUptime
        modifierTimer?.invalidate()
        modifierTimer = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseGrace) { [weak self] in
            self?.finishHold()
        }
    }

    private func finishHold() {
        guard isVisible, state.mode == .hold else { return }
        let releasedAt = releaseDetectedAt ?? ProcessInfo.processInfo.systemUptime
        releaseDetectedAt = nil
        apply(state.modifiersReleased(at: releasedAt))
    }

    private func apply(_ effect: OverviewInteraction.Effect) {
        updateSelection()
        switch effect {
        case .none:
            break
        case .dismiss:
            dismiss()
        case .launch(let index):
            let item = items[index]
            dismiss()
            onLaunch?(item)
        case .becomeToggle:
            // 轻按一下：保持显示，改用切换模式的操作方式。
            installInteraction()
            footerLabel?.stringValue = footerText()
        }
    }

    /// 切换模式下临时接管 Esc、方向键、Tab 与回车；面板关闭后立即归还。
    private func registerToggleModeKeys() {
        let bindings: [(UInt32, UInt32, () -> Void)] = [
            (53, 0, { [weak self] in self?.dismiss() }),
            (123, 0, { [weak self] in self?.advanceSelection(by: -1) }),
            (124, 0, { [weak self] in self?.advanceSelection(by: 1) }),
            (126, 0, { [weak self] in self?.moveSelectionVertically(by: -1) }),
            (125, 0, { [weak self] in self?.moveSelectionVertically(by: 1) }),
            (48, 0, { [weak self] in self?.advanceSelection(by: 1) }),
            (48, UInt32(shiftKey), { [weak self] in self?.advanceSelection(by: -1) }),
            (36, 0, { [weak self] in self?.launchSelection() }),
            (76, 0, { [weak self] in self?.launchSelection() })
        ]
        for (keyCode, modifiers, action) in bindings {
            overlayKeys.register(id: UUID(), hotKey: HotKey(keyCode: keyCode, modifiers: modifiers), action: action)
        }
    }

    private func advanceSelection(by delta: Int) {
        state.advance(by: delta)
        updateSelection()
    }

    private func moveSelectionVertically(by rows: Int) {
        state.moveVertically(by: rows, columns: columns)
        updateSelection()
    }

    private func launchSelection() {
        guard let index = state.selection, items.indices.contains(index) else { return }
        let item = items[index]
        dismiss()
        onLaunch?(item)
    }

    private func updateSelection() {
        for (index, tile) in tiles.enumerated() {
            tile.isSelected = index == selectedIndex
        }
    }

    // MARK: 布局

    private func contentSize(maxWidth: CGFloat) -> NSSize {
        let tile = Self.tileSize
        guard !items.isEmpty else { return NSSize(width: 360, height: 180) }
        let preferred = items.count > 24 ? 8 : 6
        let fitting = max(1, Int((maxWidth - Self.padding * 2) / tile.width))
        columns = max(1, min(items.count, preferred, fitting))
        let rows = Int(ceil(Double(items.count) / Double(columns)))
        let width = CGFloat(columns) * tile.width + Self.padding * 2
        let height = CGFloat(rows) * tile.height + Self.padding * 2 + Self.headerHeight + Self.footerHeight
        return NSSize(width: max(width, 320), height: height)
    }

    private func buildContent() {
        let content = panel.effectView
        content.subviews.forEach { $0.removeFromSuperview() }
        tiles = []

        let titleLabel = NSTextField(labelWithString: "QuickOpen")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        let mark = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.widthAnchor.constraint(equalToConstant: 18).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let title = NSStackView(views: [mark, titleLabel])
        title.orientation = .horizontal
        title.spacing = 6
        title.alignment = .centerY

        let footer = NSTextField(labelWithString: footerText())
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.lineBreakMode = .byTruncatingTail
        footer.alignment = .center
        footerLabel = footer

        [title, footer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }

        var constraints = [
            title.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.padding - 4),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.padding),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.padding),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -(Self.padding - 6))
        ]

        if items.isEmpty {
            let empty = NSTextField(labelWithString: "还没有为任何 App 设置快捷键\n在菜单栏 QuickOpen 图标 ›「设置…」中添加")
            empty.alignment = .center
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .secondaryLabelColor
            empty.maximumNumberOfLines = 2
            empty.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(empty)
            constraints += [
                empty.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                empty.centerYAnchor.constraint(equalTo: content.centerYAnchor)
            ]
        }
        NSLayoutConstraint.activate(constraints)

        // 预先计算列数，再按网格摆放（使用 frame 布局，数量多时更快）。
        _ = contentSize(maxWidth: (OverlayPanel.activeScreen?.visibleFrame.width ?? 1440) - 80)
        let tileSize = Self.tileSize
        let rows = Int(ceil(Double(items.count) / Double(max(columns, 1))))
        let gridHeight = CGFloat(rows) * tileSize.height
        let gridTop = Self.padding + Self.footerHeight + gridHeight // 距底部
        for (index, item) in items.enumerated() {
            let row = index / columns
            let column = index % columns
            // 最后一行不满时居中。
            let itemsInRow = min(columns, items.count - row * columns)
            let rowOffset = CGFloat(columns - itemsInRow) * tileSize.width / 2
            let origin = NSPoint(
                x: Self.padding + rowOffset + CGFloat(column) * tileSize.width,
                y: gridTop - CGFloat(row + 1) * tileSize.height
            )
            let tile = OverviewTile(shortcut: item, isRunning: isRunning?(item) ?? false)
            tile.frame = NSRect(origin: origin, size: tileSize)
            tile.onClick = { [weak self] in
                self?.dismiss()
                self?.onLaunch?(item)
            }
            tile.onHover = { [weak self] in self?.select(index: index) }
            content.addSubview(tile)
            tiles.append(tile)
        }
    }

    private func footerText() -> String {
        guard !items.isEmpty else { return "按 Esc 关闭" }
        switch state.mode {
        case .hold:
            let modifiers = triggerHotKey.map { HotKeyFormatter.keyCaps(for: $0).dropLast().joined() } ?? ""
            let key = triggerHotKey.map { HotKeyFormatter.keyName(for: $0.keyCode) } ?? ""
            if modifiers.isEmpty {
                return "按住 \(key) 显示 · 松开关闭 · 轻按一下则常驻"
            }
            return "按住 \(modifiers) 连按 \(key) 选择 · 松开打开 · 轻按一下则常驻"
        case .toggle:
            return "方向键选择 · ↩ 打开 · Esc 关闭"
        }
    }
}

/// 面板中的单个 App：图标、名称、键帽、运行中圆点。
private final class OverviewTile: NSView {
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    var isSelected = false { didSet { updateSelection() } }

    /// 选中态：中性玻璃底 + 主题色描边。
    private let highlight = GlassSurface(kind: .control, cornerRadius: 18)
    private let highlightRing = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let keyCaps: KeyCapView
    private let runningDot = NSView()

    init(shortcut: AppShortcut, isRunning: Bool) {
        keyCaps = KeyCapView(hotKey: shortcut.hotKey, style: .overlay, fontSize: 11)
        super.init(frame: .zero)
        wantsLayer = true

        highlight.alphaValue = 0
        highlightRing.wantsLayer = true
        highlightRing.layer?.cornerRadius = 18
        highlightRing.layer?.cornerCurve = .continuous
        highlightRing.layer?.borderWidth = 2
        highlightRing.layer?.borderColor = Theme.accent.cgColor
        highlightRing.alphaValue = 0
        for view in [highlight, highlightRing] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                view.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
            ])
        }

        let icon = NSWorkspace.shared.icon(forFile: shortcut.appPath)
        icon.size = NSSize(width: 128, height: 128)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: -3)
            return shadow
        }()

        nameLabel.stringValue = shortcut.appName
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1

        runningDot.wantsLayer = true

        runningDot.layer?.cornerRadius = 2.5
        runningDot.isHidden = !isRunning
        runningDot.toolTip = "正在运行"

        [iconView, nameLabel, keyCaps, runningDot].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            runningDot.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 3),
            runningDot.centerXAnchor.constraint(equalTo: centerXAnchor),
            runningDot.widthAnchor.constraint(equalToConstant: 5),
            runningDot.heightAnchor.constraint(equalToConstant: 5),
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 11),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            keyCaps.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 7),
            keyCaps.centerXAnchor.constraint(equalTo: centerXAnchor),
            keyCaps.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -8)
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(shortcut.appName) \(shortcut.hotKey?.displayString ?? "")")
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        runningDot.layer?.backgroundColor = Theme.runningIndicator.resolved(for: effectiveAppearance)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        runningDot.layer?.backgroundColor = Theme.runningIndicator.resolved(for: effectiveAppearance)
    }

    private func updateSelection() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayPanel.reduceMotion ? 0 : 0.12
            highlight.animator().alphaValue = isSelected ? 1 : 0
            highlightRing.animator().alphaValue = isSelected ? 1 : 0
        }
    }

    // 面板不会成为 key window，必须接受首次点击。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
}
