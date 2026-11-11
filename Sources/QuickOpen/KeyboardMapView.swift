import AppKit
import Carbon

/// 「快捷键」页的键盘视图：一把立体 Mac 键盘，每个 App 的图标直接画在它的触发键上；
/// 下方 Dock 按修饰键组合分组平铺所有 App。
///
/// 交互：
/// - 悬停 App 图标（键帽或 Dock）：抬起触发键、按下对应修饰键，其余变暗，并显示「打开」提示。
/// - 悬停分组标签：临时只看这一组，显示系统占用的键和空闲键；点击标签则固定该组，Esc 返回全部。
/// - 按住真实键盘上的 ⌃⌥⇧⌘：实时切换到对应分组。
/// - 点击 App：录制 / 预览 / 在访达中显示 / 删除；点击空闲键：选一个 App 绑定到该组合。
final class KeyboardMapView: NSView {
    // MARK: 数据与回调

    var shortcuts: [AppShortcut] = [] { didSet { invalidate() } }
    var overviewHotKey: HotKey? { didSet { invalidate() } }
    var failures: [UUID: OSStatus] = [:] { didSet { needsDisplay = true } }
    var recordingTarget: UUID? { didSet { needsDisplay = true } }

    var onRecord: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onPreview: ((UUID) -> Void)?
    var onReveal: ((UUID) -> Void)?
    /// 把某个 App 绑定到指定快捷键。
    var onAssign: ((UUID, HotKey) -> Void)?
    /// 先添加 App，再绑定到指定快捷键。
    var onAddAndAssign: ((HotKey) -> Void)?
    /// 从访达拖入 .app。
    var onDropApplications: (([URL]) -> Void)?
    private var isDropTarget = false { didSet { needsDisplay = true } }

    // MARK: 状态

    /// nil = 全部；否则为固定显示的修饰键组合（0 表示单键）。
    private(set) var lockedGroup: UInt32?
    private var previewGroup: UInt32?
    private var heldGroup: UInt32?
    private var effectiveGroup: UInt32? { heldGroup ?? previewGroup ?? lockedGroup }

    private enum Hover: Equatable {
        case none
        case binding(UUID)
        case key(Int)
        case groupLabel(UInt32?)
        case unsetApp(UUID)
    }
    private var hover: Hover = .none { didSet { if hover != oldValue { needsDisplay = true } } }
    private var flagsMonitor: Any?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("Keyboard view of app shortcuts", "App 快捷键键盘视图"))
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ok = !ShortcutsViewController.applicationURLs(from: sender.draggingPasteboard).isEmpty
        isDropTarget = ok
        return ok ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { isDropTarget = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        let urls = ShortcutsViewController.applicationURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDropApplications?(urls)
        return true
    }

    required init?(coder: NSCoder) { nil }

    deinit { removeFlagsMonitor() }

    private func invalidate() {
        geometry = nil
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        geometry = nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// 回到「全部」：清除固定、预览和按住状态。
    func resetGroup() {
        lockedGroup = nil
        previewGroup = nil
        heldGroup = nil
        hover = .none
        needsDisplay = true
    }

    // MARK: 派生数据

    private var bound: [AppShortcut] { shortcuts.filter { $0.hotKey != nil } }
    private var unset: [AppShortcut] { shortcuts.filter { $0.hotKey == nil } }
    private var reserved: [ReservedCombo] { ReservedCombos.all(overview: overviewHotKey) }

    /// 画在某个键上的 App。
    private func bindings(onKey code: UInt32) -> [AppShortcut] {
        let group = effectiveGroup
        return bound.filter { $0.hotKey!.keyCode == code && (group == nil || $0.hotKey!.modifiers == group) }
    }

    private func reservedName(code: UInt32, group: UInt32) -> String? {
        reserved.first { $0.hotKey.keyCode == code && $0.hotKey.modifiers == group }?.name
    }

    private func shortcut(_ id: UUID) -> AppShortcut? { shortcuts.first { $0.id == id } }

    // MARK: 几何

    private struct DockLabel { let group: UInt32?; let rect: CGRect }
    private struct DockIcon { let id: UUID; let rect: CGRect; let group: UInt32? }

    private struct Geometry {
        var unit: CGFloat = 40
        var gap: CGFloat = 3
        var caseRect: CGRect = .zero
        var plateRect: CGRect = .zero
        var keyRects: [CGRect] = []
        var statusRect: CGRect = .zero
        var dockRect: CGRect = .zero
        var dockLabels: [DockLabel] = []
        var dockIcons: [DockIcon] = []
        var dockSeparators: [CGFloat] = []
        var dockIconSize: CGFloat = 32
    }

    private var geometry: Geometry?
    private var geo: Geometry {
        if let geometry { return geometry }
        let g = computeGeometry()
        geometry = g
        return g
    }

    private static let dockHeight: CGFloat = 90
    private static let statusHeight: CGFloat = 28
    /// 外壳投影向四周扩散的范围（投影向下偏移，所以底部最多）。
    private static let shadowInset = (side: CGFloat(26), top: CGFloat(14), bottom: CGFloat(34))

    private func computeGeometry() -> Geometry {
        var g = Geometry()
        let b = bounds
        let platePad: CGFloat = 4
        // 键盘外壳：四边等宽（像手机屏幕的黑边），指示灯放在顶边内。
        let padSide: (CGFloat) -> CGFloat = { $0 * 0.42 }
        let padTop = padSide
        // 给外壳投影留出空间，避免阴影被视图边缘裁掉。
        let availableW = b.width - Self.shadowInset.side * 2
        let availableH = b.height - Self.dockHeight - Self.statusHeight - Self.shadowInset.top - Self.shadowInset.bottom
        let uW = (availableW - platePad * 2) / (KeyboardLayout.width + 0.84)
        let uH = (availableH - platePad * 2) / (KeyboardLayout.height + 0.84)
        // 窗口放大时键盘跟着放大，上限避免键帽大得失真。
        let u = max(18, floor(min(uW, uH, 84)))
        g.unit = u
        g.gap = max(2, round(u * 0.08))

        let plateSize = CGSize(width: KeyboardLayout.width * u + platePad * 2,
                               height: KeyboardLayout.height * u + platePad * 2)
        let caseSize = CGSize(width: plateSize.width + padSide(u) * 2,
                              height: plateSize.height + padTop(u) + padSide(u))
        let totalH = caseSize.height + Self.shadowInset.bottom + Self.statusHeight + Self.dockHeight
        let top = max(Self.shadowInset.top, floor((b.height - totalH) / 2))
        g.caseRect = CGRect(x: round((b.width - caseSize.width) / 2), y: top,
                            width: caseSize.width, height: caseSize.height)
        g.plateRect = CGRect(x: g.caseRect.minX + padSide(u), y: g.caseRect.minY + padTop(u),
                             width: plateSize.width, height: plateSize.height)
        let origin = CGPoint(x: g.plateRect.minX + platePad, y: g.plateRect.minY + platePad)
        g.keyRects = KeyboardLayout.keys.map { key in
            CGRect(x: origin.x + key.frame.minX * u + g.gap / 2,
                   y: origin.y + key.frame.minY * u + g.gap / 2,
                   width: key.frame.width * u - g.gap,
                   height: key.frame.height * u - g.gap)
        }
        g.statusRect = CGRect(x: b.minX, y: g.caseRect.maxY + Self.shadowInset.bottom - 8, width: b.width, height: Self.statusHeight)
        layoutDock(&g, top: g.statusRect.maxY)
        return g
    }

    private func dockGroups() -> [(group: UInt32?, items: [AppShortcut])] {
        var result: [(UInt32?, [AppShortcut])] = KeymapGroups.groups(of: shortcuts).map { mods in
            (mods, bound.filter { $0.hotKey!.modifiers == mods }
                .sorted { Self.keyOrder($0.hotKey!.keyCode) < Self.keyOrder($1.hotKey!.keyCode) })
        }
        if !unset.isEmpty { result.append((nil, unset)) }
        return result
    }

    /// Dock 中同组 App 按键在键盘上的位置排序（从左到右、从上到下）。
    private static func keyOrder(_ code: UInt32) -> CGFloat {
        guard let key = KeyboardLayout.keyByCode[code] else { return 9999 }
        return key.frame.minY * 100 + key.frame.minX
    }

    private func labelWidth(_ group: UInt32?) -> CGFloat {
        guard let group else { return textWidth(L("Not set", "未设置"), font: .systemFont(ofSize: 10, weight: .semibold)) + 10 }
        if group == 0 { return textWidth(KeymapGroups.title(0), font: .systemFont(ofSize: 10, weight: .semibold)) + 10 }
        return CGFloat(KeymapGroups.glyphs(group).count) * 19 - 2
    }

    private func layoutDock(_ g: inout Geometry, top: CGFloat) {
        let groups = dockGroups()
        let count = groups.reduce(0) { $0 + $1.items.count }
        let width = min(bounds.width - 8, max(g.caseRect.width, 200))
        let groupPad: CGFloat = 8, sepGap: CGFloat = 10
        var size: CGFloat = min(44, max(32, round(g.unit * 0.72))), spacing: CGFloat = 10
        func total() -> CGFloat {
            groups.reduce(CGFloat(0)) { acc, grp in
                let icons = CGFloat(grp.items.count) * size + CGFloat(max(0, grp.items.count - 1)) * spacing
                return acc + max(icons, labelWidth(grp.group)) + groupPad * 2
            } + CGFloat(max(0, groups.count - 1)) * sepGap + 24
        }
        while total() > width, size > 20 { size -= 2; spacing = max(4, spacing - 1) }
        g.dockIconSize = size
        let dockW = min(width, total())
        g.dockRect = CGRect(x: round((bounds.width - dockW) / 2), y: top + 2, width: dockW, height: Self.dockHeight - 6)

        var x = g.dockRect.minX + 12
        let labelY = g.dockRect.minY + 8
        let iconY = labelY + 22
        for (index, grp) in groups.enumerated() {
            if index > 0 { g.dockSeparators.append(x - sepGap / 2); }
            let iconsW = CGFloat(grp.items.count) * size + CGFloat(max(0, grp.items.count - 1)) * spacing
            let lw = labelWidth(grp.group)
            let w = max(iconsW, lw) + groupPad * 2
            g.dockLabels.append(DockLabel(group: grp.group,
                                          rect: CGRect(x: x + (w - lw) / 2 - 3, y: labelY - 2, width: lw + 6, height: 19)))
            var ix = x + (w - iconsW) / 2
            for item in grp.items {
                g.dockIcons.append(DockIcon(id: item.id, rect: CGRect(x: ix, y: iconY, width: size, height: size), group: grp.group))
                ix += size + spacing
            }
            x += w + sepGap
        }
    }

    /// 键帽顶面（放图标的区域）。
    private func topFace(_ rect: CGRect, key: KeyboardKey) -> CGRect {
        let m = capMetrics(key)
        return CGRect(x: rect.minX + m.side, y: rect.minY + m.back,
                      width: rect.width - m.side * 2, height: rect.height - m.back - m.lip)
    }

    private func capMetrics(_ key: KeyboardKey) -> (side: CGFloat, back: CGFloat, lip: CGFloat, radius: CGFloat) {
        let u = geo.unit
        if key.isHalfHeight { return (u * 0.09, u * 0.03, u * 0.15, u * 0.075) }
        if key.isShort { return (u * 0.115, u * 0.045, u * 0.21, u * 0.075) }
        return (u * 0.115, u * 0.045, u * 0.25, u * 0.075)
    }

    /// 键上每个 App 图标的位置。
    private func iconRects(keyIndex: Int, count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let key = KeyboardLayout.keys[keyIndex]
        let face = topFace(geo.keyRects[keyIndex], key: key)
        let u = geo.unit
        let size = round(count > 1 ? min(u * 0.36, (face.width - 4) / CGFloat(count) - 2) : (key.isShort ? u * 0.42 : u * 0.52))
        let spacing: CGFloat = 2
        let total = CGFloat(count) * size + CGFloat(count - 1) * spacing
        var x = face.midX - total / 2
        let y = face.midY - size / 2 - (count > 1 ? 1 : 0)
        return (0..<count).map { _ in
            defer { x += size + spacing }
            return CGRect(x: round(x), y: round(y), width: size, height: size)
        }
    }

    // MARK: 焦点（悬停时高亮哪些 App）

    private struct Focus {
        var ids: Set<UUID> = []
        var tooltipFor: [AppShortcut] = []
        var tooltipKey: Int?
        var active: Bool { !ids.isEmpty }
    }

    private func currentFocus() -> Focus {
        var f = Focus()
        switch hover {
        case .binding(let id):
            guard let s = shortcut(id), let code = s.hotKey?.keyCode,
                  let index = KeyboardLayout.keys.firstIndex(where: { $0.keyCode == code }) else { return f }
            if let group = effectiveGroup, s.hotKey!.modifiers != group { return f }
            f.ids = [id]
            f.tooltipFor = [s]
            f.tooltipKey = index
        case .key(let index):
            let key = KeyboardLayout.keys[index]
            guard let code = key.keyCode else { return f }
            if let bit = key.modifier {
                guard effectiveGroup == nil else { return f }
                f.ids = Set(bound.filter { $0.hotKey!.modifiers & bit != 0 }.map(\.id))
            } else {
                let list = bindings(onKey: code)
                f.ids = Set(list.map(\.id))
                f.tooltipFor = list
                f.tooltipKey = list.isEmpty ? nil : index
            }
        default:
            break
        }
        return f
    }

    // MARK: 绘制

    private struct CapPalette {
        var top, top2, back, left, right, front, front2, ink, edge: NSColor
        var modFactor: Double
        var isDark: Bool

        static func make(dark: Bool) -> CapPalette {
            if dark {
                let h = 75.0, c = 0.004
                return CapPalette(top: oklch(0.345, c, h), top2: oklch(0.325, c, h), back: oklch(0.36, c, h),
                                  left: oklch(0.285, c, h), right: oklch(0.245, c, h),
                                  front: oklch(0.27, c, h), front2: oklch(0.225, c, h),
                                  ink: oklch(0.76, 0.006, h), edge: oklch(0.11, c, h), modFactor: 0.92, isDark: true)
            }
            let h = 95.0
            return CapPalette(top: oklch(0.975, 0.004, h), top2: oklch(0.945, 0.006, h), back: oklch(0.99, 0.003, h),
                              left: oklch(0.905, 0.006, h), right: oklch(0.86, 0.008, h),
                              front: oklch(0.885, 0.007, h), front2: oklch(0.8, 0.009, h),
                              ink: oklch(0.3, 0.01, 90), edge: oklch(0.66, 0.012, 90), modFactor: 0.965, isDark: false)
        }

        /// 修饰键键帽略深一档。
        func darker(_ f: Double) -> CapPalette {
            func d(_ c: NSColor) -> NSColor { var lab = OKLab(c); lab.l *= f; return lab.color() }
            var p = self
            p.top = d(top); p.top2 = d(top2); p.back = d(back); p.left = d(left); p.right = d(right)
            p.front = d(front); p.front2 = d(front2)
            return p
        }

        /// 按下并亮起的修饰键：用分组颜色染色。
        func lit(_ lc: NSColor) -> CapPalette {
            var p = self
            if isDark {
                p.top = lc.mix(oklch(0.3, 0.004, 75), 0.55); p.top2 = lc.mix(oklch(0.27, 0.004, 75), 0.6)
                p.front = lc.mix(oklch(0.2, 0.004, 75), 0.65); p.front2 = p.front
                p.left = lc.mix(oklch(0.22, 0.004, 75), 0.65); p.right = p.left; p.back = p.top
                p.ink = lc.mix(.white, 0.55)
            } else {
                p.top = lc.mix(.white, 0.62); p.top2 = lc.mix(.white, 0.48)
                p.front = lc.mix(.white, 0.38); p.front2 = lc.mix(.black, 0.08)
                p.left = lc.mix(.white, 0.3); p.right = p.left; p.back = p.top
                p.ink = .white
            }
            return p
        }
    }

    private struct KeyLook {
        var lifted = false
        var pressed = false
        var glow: NSColor?
        var palette: CapPalette
        var alpha: CGFloat = 1
        var stripes = false
        var plus: NSColor?
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = Theme.isDark(effectiveAppearance)
        let base = CapPalette.make(dark: dark)
        let g = geo
        let focus = currentFocus()
        let group = effectiveGroup

        drawCase(ctx, g: g, dark: dark)

        // 哪些修饰键需要“按下并亮起”。
        var litBits: [UInt32: NSColor] = [:]
        if let group {
            for (bit, _) in KeymapGroups.orderedBits where group & bit != 0 { litBits[bit] = KeymapPalette.color(for: group) }
        }
        if focus.active {
            litBits = [:]
            let lead = (focus.tooltipFor.first ?? focus.ids.first.flatMap(shortcut))
            for id in focus.ids {
                guard let mods = shortcut(id)?.hotKey?.modifiers else { continue }
                for (bit, _) in KeymapGroups.orderedBits where mods & bit != 0 {
                    litBits[bit] = KeymapPalette.color(for: lead?.hotKey?.modifiers ?? mods)
                }
            }
        }

        var overlays: [() -> Void] = []
        for (index, key) in KeyboardLayout.keys.enumerated() {
            let rect = g.keyRects[index]
            var look = KeyLook(palette: key.modifier != nil ? base.darker(base.modFactor) : base)
            let code = key.keyCode
            var onKey: [AppShortcut] = []

            if let bit = key.modifier {
                if let lc = litBits[bit] {
                    // 左右两颗同名修饰键只亮左边那颗，和 App 实际按法一致。
                    if code == KeyboardLayout.primaryKeyCode(forModifier: bit) || group != nil {
                        look.pressed = true
                        look.palette = base.lit(lc)
                    }
                } else if group != nil {
                    look.alpha = 0.45
                }
            } else if key.isInert {
                if group != nil { look.alpha = 0.45 }
            } else if let code {
                onKey = bindings(onKey: code)
                let hot = onKey.contains { focus.ids.contains($0.id) }
                if hot {
                    look.lifted = true
                    look.glow = KeymapPalette.color(for: (onKey.first { focus.ids.contains($0.id) }!).hotKey!.modifiers)
                }
                if let group, onKey.isEmpty {
                    if reservedName(code: code, group: group) != nil {
                        look.stripes = true
                    } else if hover == .key(index) {
                        look.plus = KeymapPalette.color(for: group)
                    }
                } else if group == nil, onKey.isEmpty, hover == .key(index) {
                    look.plus = KeymapPalette.color(for: 0)
                }
            }

            drawKeycap(ctx, key: key, rect: rect, look: look)
            let face = topFace(look.lifted ? rect.offsetBy(dx: 0, dy: -2) : (look.pressed ? rect.offsetBy(dx: 0, dy: 2) : rect), key: key)

            if let bit = key.modifier, group == nil, code == KeyboardLayout.primaryKeyCode(forModifier: bit) {
                drawModifierUsage(bit: bit, face: face, ink: look.palette.ink, pressed: look.pressed)
            }
            if let group, let code, onKey.isEmpty, let name = reservedName(code: code, group: group) {
                drawCentered(name, in: face.insetBy(dx: 2, dy: 1), font: .systemFont(ofSize: max(7, g.unit * 0.19), weight: .semibold),
                             color: look.palette.ink.withAlphaComponent(0.75))
            }
            if let plus = look.plus {
                drawPlus(in: face, color: plus)
            }
            if !onKey.isEmpty {
                let rects = iconRects(keyIndex: index, count: onKey.count)
                let lift: CGFloat = look.lifted ? -2 : 0
                for (s, r) in zip(onKey, rects) {
                    let r = r.offsetBy(dx: 0, dy: lift)
                    let dim = focus.active && !focus.ids.contains(s.id)
                    let on = focus.ids.contains(s.id) && focus.ids.count == 1
                    let drawRect = on ? r.insetBy(dx: -r.width * 0.06, dy: -r.height * 0.06) : r
                    drawIcon(s, in: drawRect, alpha: dim ? 0.18 : 1)
                    let lc = KeymapPalette.color(for: s.hotKey!.modifiers)
                    if onKey.count > 1 {
                        let tick = CGRect(x: r.minX + r.width * 0.2, y: r.maxY + 1.5, width: r.width * 0.6, height: 2)
                        lc.withAlphaComponent(dim ? 0.25 : 1).setFill()
                        NSBezierPath(roundedRect: tick, xRadius: 1, yRadius: 1).fill()
                    } else if group == nil, s.hotKey!.modifiers != 0 {
                        overlays.append { [weak self] in self?.drawChip(for: s.hotKey!.modifiers, near: r, dim: dim, dark: dark) }
                    }
                    if failures[s.id] != nil {
                        overlays.append {
                            NSColor.systemRed.setFill()
                            NSBezierPath(ovalIn: CGRect(x: r.maxX - 4, y: r.minY - 2, width: 6, height: 6)).fill()
                        }
                    }
                }
            }
        }
        overlays.forEach { $0() }

        if isDropTarget {
            let path = NSBezierPath(roundedRect: g.caseRect.insetBy(dx: -4, dy: -4), xRadius: g.unit * 0.5, yRadius: g.unit * 0.5)
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.lineWidth = 2
            NSColor.controlAccentColor.setStroke()
            path.stroke()
        }
        drawStatus(g: g)
        drawDock(g: g, focus: focus, dark: dark)
        if let index = focus.tooltipKey, !focus.tooltipFor.isEmpty {
            drawTooltip(focus.tooltipFor, keyIndex: index)
        }
        _ = ctx
    }

    private func drawCase(_ ctx: CGContext, g: Geometry, dark: Bool) {
        let caseRect = g.caseRect
        let radius = g.unit * 0.45
        let path = NSBezierPath(roundedRect: caseRect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.22)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        (dark ? oklch(0.275, 0.004, 75) : oklch(0.95, 0.005, 95)).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        let gradient = dark
            ? NSGradient(starting: oklch(0.285, 0.004, 75), ending: oklch(0.265, 0.004, 75))
            : NSGradient(starting: oklch(0.965, 0.004, 95), ending: oklch(0.93, 0.006, 95))
        gradient?.draw(in: path, angle: 90)
        // 外壳描边与顶部高光
        (dark ? NSColor.black.withAlphaComponent(0.35) : oklch(0.8, 0.008, 95)).setStroke()
        path.lineWidth = 1
        path.stroke()
        let highlight = NSBezierPath(roundedRect: caseRect.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1)
        NSColor.white.withAlphaComponent(dark ? 0.05 : 0.8).setStroke()
        highlight.lineWidth = 0.5
        highlight.stroke()

        // 右上角指示灯：浅色时亮绿灯，深色时熄灭成暗点，不抢眼。
        let ledSize: CGFloat = max(4, round(g.unit * 0.09))
        let led = CGRect(x: g.plateRect.maxX - ledSize - 4,
                         y: caseRect.minY + (g.plateRect.minY - caseRect.minY - ledSize) / 2,
                         width: ledSize, height: ledSize)
        if dark {
            oklch(0.2, 0.004, 75).setFill()
            NSBezierPath(ovalIn: led).fill()
        } else {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = NSColor(srgbRed: 0.2, green: 0.8, blue: 0.4, alpha: 0.7)
            glow.shadowBlurRadius = 5
            glow.shadowOffset = .zero
            glow.set()
            NSColor(srgbRed: 0.2, green: 0.78, blue: 0.4, alpha: 1).setFill()
            NSBezierPath(ovalIn: led).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // 底板：深色主题是深槽；浅色主题与外壳同色，只用很淡的内阴影和描边表现下沉。
        let plate = NSBezierPath(roundedRect: g.plateRect, xRadius: g.unit * 0.2, yRadius: g.unit * 0.2)
        if dark {
            oklch(0.14, 0.003, 75).setFill()
            plate.fill()
            oklch(0.11, 0.003, 75).setStroke()
            plate.lineWidth = 1.5
            plate.stroke()
        } else {
            if let inner = NSGradient(colors: [NSColor.black.withAlphaComponent(0.06), NSColor.black.withAlphaComponent(0)]) {
                NSGraphicsContext.saveGraphicsState()
                plate.addClip()
                inner.draw(in: NSRect(x: g.plateRect.minX, y: g.plateRect.minY, width: g.plateRect.width, height: g.unit * 0.2), angle: 90)
                NSGraphicsContext.restoreGraphicsState()
            }
            NSColor.black.withAlphaComponent(0.08).setStroke()
            plate.lineWidth = 1
            plate.stroke()
        }
    }

    private func drawKeycap(_ ctx: CGContext, key: KeyboardKey, rect baseRect: CGRect, look: KeyLook) {
        var rect = baseRect
        if look.lifted { rect = rect.offsetBy(dx: 0, dy: -2) }
        if look.pressed { rect = rect.offsetBy(dx: 0, dy: 2) }
        let m = capMetrics(key)
        let p = look.palette
        let outer = CGPath(roundedRect: rect, cornerWidth: m.radius, cornerHeight: m.radius, transform: nil)

        ctx.saveGState()
        ctx.setAlpha(look.alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        // 投在底板上的影子；悬停时换成分组色的光晕。
        ctx.saveGState()
        if let glow = look.glow {
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: glow.withAlphaComponent(0.65).cgColor)
        } else {
            ctx.setShadow(offset: CGSize(width: 0, height: look.pressed ? -1 : -geo.unit * 0.06),
                          blur: geo.unit * (look.pressed ? 0.04 : 0.08),
                          color: NSColor.black.withAlphaComponent(p.isDark ? 0.6 : 0.28).cgColor)
        }
        ctx.addPath(outer)
        ctx.setFillColor(p.back.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(outer)
        ctx.clip()
        let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        func poly(_ pts: [CGPoint], _ color: NSColor) {
            ctx.beginPath(); ctx.addLines(between: pts); ctx.closePath()
            ctx.setFillColor(color.cgColor); ctx.fillPath()
        }
        // 左右侧面：左亮右暗，模拟侧光。
        poly([CGPoint(x: x0, y: y0), CGPoint(x: x0 + m.side, y: y0 + m.back),
              CGPoint(x: x0 + m.side, y: y1 - m.lip), CGPoint(x: x0, y: y1)], p.left)
        poly([CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1),
              CGPoint(x: x1 - m.side, y: y1 - m.lip), CGPoint(x: x1 - m.side, y: y0 + m.back)], p.right)
        // 正面裙边：印字的一面
        ctx.saveGState()
        ctx.beginPath()
        ctx.addLines(between: [CGPoint(x: x0, y: y1), CGPoint(x: x0 + m.side, y: y1 - m.lip),
                               CGPoint(x: x1 - m.side, y: y1 - m.lip), CGPoint(x: x1, y: y1)])
        ctx.closePath()
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: nil, colors: [p.front.cgColor, p.front2.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: y1 - m.lip), end: CGPoint(x: 0, y: y1), options: [])
        }
        ctx.restoreGState()

        // 顶面：中间略亮，带一点内凹感。
        let topRect = CGRect(x: x0 + m.side, y: y0 + m.back, width: rect.width - m.side * 2, height: rect.height - m.back - m.lip)
        let topPath = CGPath(roundedRect: topRect, cornerWidth: m.radius * 0.9, cornerHeight: m.radius * 0.9, transform: nil)
        ctx.saveGState()
        ctx.addPath(topPath)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: nil, colors: [p.top.cgColor, p.top2.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: topRect.minY), end: CGPoint(x: 0, y: topRect.maxY), options: [])
        }
        if !p.isDark, !look.pressed,
           let radial = CGGradient(colorsSpace: nil, colors: [NSColor.white.withAlphaComponent(0.45).cgColor,
                                                              NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
            let c = CGPoint(x: topRect.midX, y: topRect.minY + topRect.height * 0.42)
            ctx.drawRadialGradient(radial, startCenter: c, startRadius: 0, endCenter: c,
                                   endRadius: max(topRect.width, topRect.height) * 0.55, options: [])
        }
        if look.stripes {
            ctx.setStrokeColor((p.isDark ? NSColor.white.withAlphaComponent(0.05) : NSColor.black.withAlphaComponent(0.07)).cgColor)
            ctx.setLineWidth(2.2)
            var sx = topRect.minX - topRect.height
            while sx < topRect.maxX {
                ctx.move(to: CGPoint(x: sx, y: topRect.maxY))
                ctx.addLine(to: CGPoint(x: sx + topRect.height, y: topRect.minY))
                sx += 5.5
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
        // 选中（悬停抬起 / 修饰键按下）的键帽不描边，只靠颜色和光晕区分。
        let selected = look.glow != nil || look.pressed
        if !selected {
            ctx.addPath(topPath)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(p.isDark ? 0.35 : 0.12).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokePath()
        }
        ctx.restoreGState() // clip outer

        if !selected {
            ctx.addPath(outer)
            ctx.setStrokeColor(p.edge.cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
        }

        // 键名印在正面
        if !key.legend.isEmpty {
            let fontSize = geo.unit * (key.isHalfHeight ? 0.115 : key.isShort ? 0.14 : (key.smallLegend ? 0.13 : 0.16))
            let lipRect = CGRect(x: x0 + m.side + 3, y: y1 - m.lip, width: rect.width - m.side * 2 - 6, height: m.lip)
            // 键帽窄时（如 “⌘ command”）缩小字号，保证键名完整显示。
            var font = Self.legendFont(ofSize: max(6, fontSize))
            let natural = textWidth(key.legend, font: font)
            if natural > lipRect.width - 2 {
                font = Self.legendFont(ofSize: max(5, font.pointSize * (lipRect.width - 2) / natural * 0.94))
            }
            let para = NSMutableParagraphStyle()
            para.alignment = key.alignment == .leading ? .left : key.alignment == .trailing ? .right : .center
            para.lineBreakMode = .byClipping
            let str = NSAttributedString(string: key.legend, attributes: [.font: font, .foregroundColor: p.ink, .paragraphStyle: para])
            let h = str.size().height
            str.draw(in: CGRect(x: lipRect.minX, y: lipRect.midY - h / 2, width: lipRect.width, height: h))
        }

        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private static func legendFont(ofSize size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private func drawIcon(_ s: AppShortcut, in rect: CGRect, alpha: CGFloat) {
        let image = AppIcons.icon(forPath: s.appPath, size: max(16, rect.width))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3 * alpha)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 键帽上 App 图标右上角的修饰键小标。
    private func drawChip(for mods: UInt32, near icon: CGRect, dim: Bool, dark: Bool) {
        let lc = KeymapPalette.color(for: mods)
        let font = NSFont.systemFont(ofSize: max(7.5, geo.unit * 0.21), weight: .bold)
        let text = KeymapGroups.glyphs(mods).joined()
        let fg = dark ? lc.mix(.white, 0.45) : lc.mix(.black, 0.35)
        let bg = dark ? lc.mix(oklch(0.2, 0, 0), 0.62) : lc.mix(.white, 0.8)
        let stroke = dark ? lc.mix(oklch(0.2, 0, 0), 0.35) : lc.mix(.white, 0.45)
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: fg.withAlphaComponent(dim ? 0.3 : 1)])
        let size = str.size()
        let chip = CGRect(x: icon.maxX - size.width * 0.45 - 3, y: icon.minY - size.height * 0.55,
                          width: size.width + 6, height: size.height + 1)
        let path = NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4)
        bg.withAlphaComponent(dim ? 0.35 : 1).setFill()
        path.fill()
        stroke.withAlphaComponent(dim ? 0.3 : 1).setStroke()
        path.lineWidth = 1
        path.stroke()
        str.draw(at: CGPoint(x: chip.minX + 3, y: chip.minY + 0.5))
    }

    /// 全部视图下，修饰键顶面用彩色圆点 + 数字表示有几个 App 在用它。
    private func drawModifierUsage(bit: UInt32, face: CGRect, ink: NSColor, pressed: Bool) {
        let users = bound.filter { $0.hotKey!.modifiers & bit != 0 }
        guard !users.isEmpty else { return }
        let groups = KeymapGroups.sorted(users.map { $0.hotKey!.modifiers })
        let dot: CGFloat = 5, spacing: CGFloat = 2
        let countStr = NSAttributedString(string: "\(users.count)", attributes: [
            .font: NSFont.systemFont(ofSize: max(8, geo.unit * 0.24), weight: .bold),
            .foregroundColor: ink.withAlphaComponent(pressed ? 1 : 0.7)
        ])
        let total = CGFloat(groups.count) * (dot + spacing) + 2 + countStr.size().width
        var x = face.midX - total / 2
        let y = face.midY
        for grp in groups {
            KeymapPalette.color(for: grp).setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: y - dot / 2, width: dot, height: dot)).fill()
            x += dot + spacing
        }
        countStr.draw(at: CGPoint(x: x + 2, y: y - countStr.size().height / 2))
    }

    private func drawStatus(g: Geometry) {
        let font = NSFont.systemFont(ofSize: 11.5)
        let bold = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let text = NSMutableAttributedString()
        func add(_ s: String, _ strong: Bool = false) {
            text.append(NSAttributedString(string: s, attributes: [
                .font: strong ? bold : font, .foregroundColor: strong ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]))
        }
        if let group = effectiveGroup {
            let n = bound.filter { $0.hotKey!.modifiers == group }.count
            let free = KeyboardLayout.keys.filter { key in
                guard let code = key.keyCode, key.modifier == nil, !key.isInert else { return false }
                return bindings(onKey: code).isEmpty && reservedName(code: code, group: group) == nil
            }.count
            let source = heldGroup != nil ? L("holding", "按住中") : previewGroup != nil ? L("preview", "预览") : L("pinned", "已固定")
            add(KeymapGroups.title(group), true)
            add(L(" (\(source)) · ", "（\(source)）· "))
            add("\(n)", true)
            add(L(" apps · ", " 个 App · "))
            add("\(free)", true)
            add(L(" free keys · click a free key to assign", " 个空闲键 · 点空闲键即可绑定"))
            if lockedGroup != nil, heldGroup == nil, previewGroup == nil { add(L(" · Esc to show all", " · Esc 返回全部")) }
        } else if shortcuts.isEmpty {
            add(L("No apps yet. Add one, then click a key to assign it.", "还没有 App。添加后点击键盘上的键即可绑定。"))
        } else {
            let groups = KeymapGroups.groups(of: shortcuts)
            add(L("All · ", "全部 · "))
            add("\(bound.count)", true)
            if groups == [0] {
                add(L(" apps, all on single keys", " 个 App，全部为单键"))
            } else {
                // 单键不算“修饰键组合”：分别说明单键个数和组合数。
                let singles = bound.filter { $0.hotKey!.modifiers == 0 }.count
                let combos = groups.filter { $0 != 0 }.count
                if singles > 0 {
                    add(L(" apps · ", " 个 App · "))
                    add("\(singles)", true)
                    add(L(" on single keys, ", " 个单键，"))
                    add("\(combos)", true)
                    add(combos == 1 ? L(" modifier combination", " 组修饰键组合") : L(" modifier combinations", " 组修饰键组合"))
                } else {
                    add(L(" apps in ", " 个 App，分属 "))
                    add("\(combos)", true)
                    add(combos == 1 ? L(" modifier combination", " 组修饰键组合") : L(" modifier combinations", " 组修饰键组合"))
                }
            }
            if !unset.isEmpty {
                add(L(" · \(unset.count) not set", " · \(unset.count) 个未设置"))
            }
        }
        let size = text.size()
        text.draw(at: CGPoint(x: round(g.statusRect.midX - size.width / 2), y: g.statusRect.midY - size.height / 2))
    }

    private func drawDock(g: Geometry, focus: Focus, dark: Bool) {
        guard !g.dockIcons.isEmpty || shortcuts.isEmpty else { return }
        let path = NSBezierPath(roundedRect: g.dockRect, xRadius: 18, yRadius: 18)
        (dark ? NSColor.white.withAlphaComponent(0.05) : NSColor.white.withAlphaComponent(0.6)).setFill()
        path.fill()
        (dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.07)).setStroke()
        path.lineWidth = 1
        path.stroke()

        for x in g.dockSeparators {
            NSColor.separatorColor.setFill()
            NSRect(x: x, y: g.dockRect.minY + 30, width: 1, height: g.dockRect.height - 40).fill()
        }

        for label in g.dockLabels {
            let selected = label.group != nil && label.group == lockedGroup
            let previewing = label.group != nil && label.group == effectiveGroup && !selected
            if let group = label.group, selected || previewing {
                let lc = KeymapPalette.color(for: group)
                let bg = label.rect.insetBy(dx: -4, dy: -3)
                lc.withAlphaComponent(selected ? 0.2 : 0.12).setFill()
                NSBezierPath(roundedRect: bg, xRadius: 7, yRadius: 7).fill()
                if selected {
                    lc.setStroke()
                    let p = NSBezierPath(roundedRect: bg.insetBy(dx: 0.75, dy: 0.75), xRadius: 6.5, yRadius: 6.5)
                    p.lineWidth = 1.5
                    p.stroke()
                }
            }
            drawGroupLabel(label, dark: dark)
        }

        for icon in g.dockIcons {
            guard let s = shortcut(icon.id) else { continue }
            let isHover = hover == .binding(icon.id) || hover == .unsetApp(icon.id)
            let on = focus.ids.contains(icon.id)
            var rect = icon.rect
            if on || isHover { rect = rect.insetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.1).offsetBy(dx: 0, dy: -3) }
            var alpha: CGFloat = 1
            if focus.active && !on { alpha = 0.35 }
            if let group = effectiveGroup, icon.group != group { alpha = min(alpha, 0.35) }
            if icon.group == nil { alpha = min(alpha, isHover ? 0.9 : 0.55) }
            drawIcon(s, in: rect, alpha: alpha)

            if recordingTarget == icon.id {
                Theme.accent.setStroke()
                let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: rect.width * 0.26, yRadius: rect.width * 0.26)
                ring.lineWidth = 2
                ring.stroke()
            }
            // 触发键小标
            let keyName = s.hotKey.map { HotKeyFormatter.keyName(for: $0.keyCode) } ?? "—"
            let str = NSAttributedString(string: keyName, attributes: [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(max(alpha, 0.5))
            ])
            let size = str.size()
            let badge = CGRect(x: rect.midX - size.width / 2 - 3, y: rect.maxY - size.height + 3, width: size.width + 6, height: size.height)
            (dark ? oklch(0.3, 0.004, 75) : NSColor.white).setFill()
            let bp = NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4)
            bp.fill()
            NSColor.separatorColor.setStroke()
            bp.lineWidth = 0.5
            bp.stroke()
            str.draw(at: CGPoint(x: badge.minX + 3, y: badge.minY))
            if failures[s.id] != nil {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: CGRect(x: rect.maxX - 6, y: rect.minY - 1, width: 7, height: 7)).fill()
            }
        }
    }

    private func drawGroupLabel(_ label: DockLabel, dark: Bool) {
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        guard let group = label.group else {
            drawCentered(L("Not set", "未设置"), in: label.rect, font: font, color: .tertiaryLabelColor)
            return
        }
        let lc = KeymapPalette.color(for: group)
        let fg = dark ? lc.mix(.white, 0.45) : lc.mix(.black, 0.35)
        let bg = dark ? lc.mix(oklch(0.2, 0, 0), 0.62) : lc.mix(.white, 0.78)
        let stroke = dark ? lc.mix(oklch(0.2, 0, 0), 0.35) : lc.mix(.white, 0.4)
        let parts = group == 0 ? [KeymapGroups.title(0)] : KeymapGroups.glyphs(group)
        var x = label.rect.minX + 3
        for part in parts {
            let str = NSAttributedString(string: part, attributes: [.font: font, .foregroundColor: fg])
            let w = max(17, str.size().width + 8)
            let r = CGRect(x: x, y: label.rect.minY + 1, width: w, height: 17)
            let p = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            bg.setFill(); p.fill()
            stroke.setStroke(); p.lineWidth = 1; p.stroke()
            drawCentered(part, in: r, font: font, color: fg)
            x += w + 2
        }
    }

    private func drawTooltip(_ list: [AppShortcut], keyIndex: Int) {
        let rowH: CGFloat = 26
        let nameFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let actionFont = NSFont.systemFont(ofSize: 11)
        let capFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let action = L("Open", "打开")
        struct Row { let s: AppShortcut; let caps: [String]; let width: CGFloat }
        let rows: [Row] = list.map { s in
            let caps = HotKeyFormatter.keyCaps(for: s.hotKey!)
            let capsW = caps.reduce(CGFloat(0)) { $0 + max(20, textWidth($1, font: capFont) + 10) + 3 }
            let w = capsW + 7 + textWidth(action, font: actionFont) + 10 + 28 + textWidth(s.appName, font: nameFont)
            return Row(s: s, caps: caps, width: w)
        }
        let width = (rows.map(\.width).max() ?? 0) + 22
        let height = CGFloat(rows.count) * rowH + CGFloat(rows.count - 1) * 4 + 16
        let keyRect = geo.keyRects[keyIndex].offsetBy(dx: 0, dy: -2)
        var box = CGRect(x: keyRect.midX - width / 2, y: keyRect.minY - 10 - height, width: width, height: height)
        var arrowUp = false
        if box.minY < bounds.minY + 2 {
            box.origin.y = keyRect.maxY + 10
            arrowUp = true
        }
        box.origin.x = min(max(box.minX, bounds.minX + 4), bounds.maxX - width - 4)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        let bg = oklch(0.22, 0.006, 75)
        bg.setFill()
        NSBezierPath(roundedRect: box, xRadius: 11, yRadius: 11).fill()
        let arrow = NSBezierPath()
        let ax = min(max(keyRect.midX, box.minX + 14), box.maxX - 14)
        if arrowUp {
            arrow.move(to: CGPoint(x: ax - 6, y: box.minY)); arrow.line(to: CGPoint(x: ax, y: box.minY - 6)); arrow.line(to: CGPoint(x: ax + 6, y: box.minY))
        } else {
            arrow.move(to: CGPoint(x: ax - 6, y: box.maxY)); arrow.line(to: CGPoint(x: ax, y: box.maxY + 6)); arrow.line(to: CGPoint(x: ax + 6, y: box.maxY))
        }
        arrow.fill()
        NSGraphicsContext.restoreGraphicsState()

        // 读法与按法一致：先按快捷键 → 打开 → 哪个 App。
        var y = box.minY + 8
        for row in rows {
            var x = box.minX + 11
            let lc = KeymapPalette.color(for: row.s.hotKey!.modifiers)
            for (i, cap) in row.caps.enumerated() {
                let w = max(20, textWidth(cap, font: capFont) + 10)
                let r = CGRect(x: x, y: y + 3, width: w, height: 20)
                let isMod = i < row.caps.count - 1
                (isMod ? lc.withAlphaComponent(0.8) : NSColor.white.withAlphaComponent(0.14)).setFill()
                NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
                drawCentered(cap, in: r, font: capFont, color: .white)
                x += w + 3
            }
            x += 7
            let act = NSAttributedString(string: action, attributes: [.font: actionFont, .foregroundColor: NSColor.white.withAlphaComponent(0.6)])
            act.draw(at: CGPoint(x: x, y: y + (rowH - act.size().height) / 2))
            x += act.size().width + 10
            drawIcon(row.s, in: CGRect(x: x, y: y + 3, width: 20, height: 20), alpha: 1)
            x += 28
            let name = NSAttributedString(string: row.s.appName, attributes: [.font: nameFont, .foregroundColor: NSColor.white])
            name.draw(at: CGPoint(x: x, y: y + (rowH - name.size().height) / 2))
            y += rowH + 4
        }
    }

    /// 用线段画加号，正好落在键帽顶面的几何中心（文字 “+” 受行高影响会偏下）。
    private func drawPlus(in face: CGRect, color: NSColor) {
        let arm = round(min(face.width, face.height) * 0.26)
        let c = CGPoint(x: face.midX, y: face.midY)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: c.x - arm, y: c.y)); path.line(to: CGPoint(x: c.x + arm, y: c.y))
        path.move(to: CGPoint(x: c.x, y: c.y - arm)); path.line(to: CGPoint(x: c.x, y: c.y + arm))
        path.lineWidth = max(1.5, geo.unit * 0.035)
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func drawCentered(_ text: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        let h = str.boundingRect(with: CGSize(width: rect.width, height: 100), options: [.usesLineFragmentOrigin]).height
        str.draw(with: CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h),
                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    // MARK: 命中检测

    private enum Hit {
        case binding(UUID, keyIndex: Int?)
        case key(Int)
        case groupLabel(UInt32?)
        case unsetApp(UUID)
        case nothing
    }

    private func hitTest(point p: CGPoint) -> Hit {
        let g = geo
        for icon in g.dockIcons where icon.rect.insetBy(dx: -3, dy: -3).contains(p) {
            return icon.group == nil ? .unsetApp(icon.id) : .binding(icon.id, keyIndex: nil)
        }
        for label in g.dockLabels where label.rect.insetBy(dx: -4, dy: -3).contains(p) {
            return .groupLabel(label.group)
        }
        for (index, rect) in g.keyRects.enumerated() where rect.contains(p) {
            let key = KeyboardLayout.keys[index]
            if let code = key.keyCode, key.modifier == nil {
                let list = bindings(onKey: code)
                let rects = iconRects(keyIndex: index, count: list.count)
                for (s, r) in zip(list, rects) where r.insetBy(dx: -2, dy: -2).contains(p) {
                    return .binding(s.id, keyIndex: index)
                }
            }
            return .key(index)
        }
        return .nothing
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        if previewGroup != nil { previewGroup = nil; needsDisplay = true }
        hover = .none
    }

    private func updateHover(at point: CGPoint) {
        let hit = hitTest(point: point)
        var newPreview: UInt32? = nil
        switch hit {
        case .binding(let id, _): hover = .binding(id)
        case .key(let index): hover = .key(index)
        case .unsetApp(let id): hover = .unsetApp(id)
        case .groupLabel(let group):
            hover = .groupLabel(group)
            newPreview = group
        case .nothing: hover = .none
        }
        if newPreview != previewGroup {
            previewGroup = newPreview
            needsDisplay = true
        }
        NSCursor.current.set()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        let g = geo
        for icon in g.dockIcons { addCursorRect(icon.rect, cursor: .pointingHand) }
        for label in g.dockLabels where label.group != nil { addCursorRect(label.rect, cursor: .pointingHand) }
    }

    // MARK: 点击

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        switch hitTest(point: point) {
        case .binding(let id, let keyIndex):
            guard let s = shortcut(id) else { return }
            if let group = effectiveGroup, keyIndex == nil, s.hotKey?.modifiers != group {
                lockedGroup = nil; previewGroup = nil
            }
            showMenu(for: [s], at: point)
        case .unsetApp(let id):
            onRecord?(id)
        case .groupLabel(let group):
            guard let group else { return }
            lockedGroup = lockedGroup == group ? nil : group
            previewGroup = nil
            needsDisplay = true
        case .key(let index):
            clickKey(index, at: point)
        case .nothing:
            if lockedGroup != nil { lockedGroup = nil; needsDisplay = true }
        }
    }

    private func clickKey(_ index: Int, at point: CGPoint) {
        let key = KeyboardLayout.keys[index]
        guard let code = key.keyCode, !key.isInert else { return }
        if let bit = key.modifier {
            // 点修饰键：把它加入 / 移出当前固定的分组，可以拼出还没有任何 App 的组合。
            var group = lockedGroup ?? 0
            group ^= bit
            lockedGroup = group == 0 ? nil : group
            previewGroup = nil
            needsDisplay = true
            return
        }
        let list = bindings(onKey: code)
        if !list.isEmpty {
            showMenu(for: list, at: point)
            return
        }
        showAssignMenu(hotKey: HotKey(keyCode: code, modifiers: effectiveGroup ?? 0), at: point)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, lockedGroup != nil { // Esc
            resetGroup()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if lockedGroup != nil { resetGroup() }
    }

    // MARK: 菜单

    private func showMenu(for list: [AppShortcut], at point: CGPoint) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, s) in list.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            let title = NSMenuItem(title: "\(s.appName)  \(s.hotKey?.displayString ?? "")", action: nil, keyEquivalent: "")
            title.image = AppIcons.icon(forPath: s.appPath, size: 16)
            title.isEnabled = false
            menu.addItem(title)
            if let failure = failures[s.id] {
                let warn = NSMenuItem(title: "⚠︎ " + failure.hotKeyFailureDescription, action: nil, keyEquivalent: "")
                warn.isEnabled = false
                menu.addItem(warn)
            }
            let id = s.id
            menu.addItem(ActionMenuItem(L("Record New Shortcut", "重新录制快捷键")) { [weak self] in self?.onRecord?(id) })
            menu.addItem(ActionMenuItem(L("Preview Launch Hint", "预览启动提示")) { [weak self] in self?.onPreview?(id) })
            menu.addItem(ActionMenuItem(L("Show in Finder", "在访达中显示")) { [weak self] in self?.onReveal?(id) })
            menu.addItem(ActionMenuItem(L("Remove", "删除")) { [weak self] in self?.onDelete?(id) })
        }
        menu.popUp(positioning: nil, at: point, in: self)
        hover = .none
    }

    private func showAssignMenu(hotKey: HotKey, at point: CGPoint) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: L("Open with \(hotKey.displayString)…", "按 \(hotKey.displayString) 打开…"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let isOverview = hotKey == overviewHotKey
        if isOverview {
            let item = NSMenuItem(title: L("Used by the QuickOpen overview", "已用于 QuickOpen 速查面板"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            if let name = reservedName(code: hotKey.keyCode, group: hotKey.modifiers) {
                let warn = NSMenuItem(title: L("⚠︎ Taken by “\(name)”; assigning overrides it", "⚠︎ 已被「\(name)」占用，绑定后将覆盖原有行为"), action: nil, keyEquivalent: "")
                warn.isEnabled = false
                menu.addItem(warn)
            }
            if let warning = hotKey.typingWarning {
                let warn = NSMenuItem(title: "⚠︎ " + warning, action: nil, keyEquivalent: "")
                warn.isEnabled = false
                menu.addItem(warn)
            }
            menu.addItem(.separator())
            // 未设置快捷键的 App 排在前面
            let ordered = unset + bound
            for s in ordered {
                let suffix = s.hotKey.map { "   " + $0.displayString } ?? ""
                let id = s.id
                let item = ActionMenuItem(s.appName + suffix) { [weak self] in self?.onAssign?(id, hotKey) }
                item.image = AppIcons.icon(forPath: s.appPath, size: 16)
                menu.addItem(item)
            }
            if !ordered.isEmpty { menu.addItem(.separator()) }
            menu.addItem(ActionMenuItem(L("Add App…", "添加 App…")) { [weak self] in self?.onAddAndAssign?(hotKey) })
        }
        menu.popUp(positioning: nil, at: point, in: self)
        hover = .none
    }

    // MARK: 按住真实修饰键切换分组

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeFlagsMonitor()
        guard window != nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.modifiersChanged(event)
            return event
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        heldGroup = nil
    }

    private func removeFlagsMonitor() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
    }

    private func modifiersChanged(_ event: NSEvent) {
        guard !isHiddenOrHasHiddenAncestor, event.window === window, recordingTarget == nil else { return }
        let mods = HotKey.carbonModifiers(from: event.modifierFlags)
        let newGroup: UInt32? = mods == 0 ? nil : mods
        if newGroup != heldGroup {
            heldGroup = newGroup
            needsDisplay = true
        }
    }

    // MARK: 测试辅助

    /// 仅供快照测试：模拟悬停某个 App / 固定某个分组。
    func simulateHover(appID: UUID?) { hover = appID.map { .binding($0) } ?? .none }
    func simulateLock(group: UInt32?) { lockedGroup = group; needsDisplay = true }
    func simulateHover(keyCode: UInt32) {
        hover = KeyboardLayout.keys.firstIndex { $0.keyCode == keyCode }.map { .key($0) } ?? .none
    }
}

/// 带闭包的菜单项。
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
