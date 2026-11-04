import AppKit

/// 菜单栏图标：与 App 图标一致的“卡片跃出”造型，单色模板图，自动适配浅色/深色菜单栏。
enum StatusBarIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            draw(in: size)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "QuickOpen"
        return image
    }

    private static func card(center: CGPoint, side: CGFloat, degrees: CGFloat) -> NSBezierPath {
        let rect = NSRect(x: -side / 2, y: -side / 2, width: side, height: side)
        let path = NSBezierPath(roundedRect: rect, xRadius: side * 0.27, yRadius: side * 0.27)
        var transform = AffineTransform(translationByX: center.x, byY: center.y)
        transform.rotate(byDegrees: degrees)
        path.transform(using: transform)
        return path
    }

    private static func draw(in size: NSSize) {
        let s = size.width
        // 与 App 图标一致：后卡只露出左下一角，前卡更大、更居中。
        // 后卡只描边，前卡实心；前卡周围挖空一圈，保证 18pt 下两张卡片分得开。
        // 菜单栏尺寸很小，后卡比 App 图标里露得多一些，保证一眼看出是两张卡片。
        let back = card(center: CGPoint(x: s * 0.37, y: s * 0.39), side: s * 0.52, degrees: -10)
        let front = card(center: CGPoint(x: s * 0.60, y: s * 0.59), side: s * 0.56, degrees: 6)

        NSColor.black.setStroke()
        back.lineWidth = 1.4
        back.stroke()

        // 用透明清除前卡周围的区域（模板图中透明即“镂空”）
        NSGraphicsContext.current?.compositingOperation = .clear
        let gap = front.copy() as! NSBezierPath
        gap.lineWidth = 3
        gap.stroke()
        front.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        NSColor.black.setFill()
        front.fill()
    }
}
