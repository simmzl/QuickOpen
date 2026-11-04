import AppKit

/// App 图标：把系统返回的（可能懒加载的）图标预先渲染成位图并缓存，
/// 保证浮层第一次出现时就有图标，不会出现空白占位。
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(forPath path: String, size: CGFloat) -> NSImage {
        let key = "\(path)#\(Int(size))"
        if let cached = cache[key] { return cached }
        let source = NSWorkspace.shared.icon(forFile: path)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = Int((size * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return source }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        cache[key] = image
        return image
    }

    /// QuickOpen 自己的 logo。优先用 App 包内的 AppIcon.icns；
    /// 在测试等非 .app 环境下回退到源码目录中的图标。
    static var brandLogo: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/AppIcon.icns")
        return NSImage(contentsOf: source) ?? NSApp.applicationIconImage ?? NSImage()
    }

    /// App 被安装/卸载后清空缓存。
    static func invalidate() { cache.removeAll() }
}

/// 跟随外观自动更新颜色的小圆点（“运行中”标记）。
final class DotView: NSView {
    var color: NSColor = Theme.runningIndicator { didSet { needsDisplay = true } }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = color.resolved(for: effectiveAppearance)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
}
