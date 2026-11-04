import AppKit

/// 不抢焦点、跨桌面空间（含全屏 App）显示的玻璃浮层基类。
/// 速查面板与启动提示共用。内容请添加到 `effectView`（玻璃表面的内容视图）。
class OverlayPanel: NSPanel {
    let surface: GlassSurface
    /// 内容容器（位于玻璃之上）。
    var effectView: NSView { surface.contentView }

    init(cornerRadius: CGFloat) {
        surface = GlassSurface(kind: .floating, cornerRadius: cornerRadius)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        isOpaque = false
        backgroundColor = .clear
        // 液态玻璃自带投影；旧系统使用窗口投影。
        hasShadow = !GlassSurface.usesSystemGlass
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovable = false

        // 根视图透明，玻璃四周留出投影空间。
        let root = NSView()
        root.wantsLayer = true
        surface.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            surface.topAnchor.constraint(equalTo: root.topAnchor),
            surface.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        contentView = root
    }

    /// 是否允许成为 key window。速查面板需要成为 key（不激活 App）来直接接收修饰键变化事件；
    /// 启动提示只是展示，不需要。
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// 鼠标所在的屏幕；找不到则用主屏。
    static var activeScreen: NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
