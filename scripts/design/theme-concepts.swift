// 主题色候选预览：同一个「卡片跃出」图标 + 界面强调色，换不同颜色对比。
// 用法：xcrun swift scripts/theme-concepts.swift <输出目录>
import AppKit
import CoreImage
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Usage: theme-concepts.swift <output-dir>") }
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// MARK: - 基础工具

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let ciContext = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// macOS 图标网格：1024 画布中主体 824×824，圆角约 185。
func iconBody(_ s: CGFloat) -> (rect: CGRect, radius: CGFloat) {
    let inset = s * 100 / 1024
    return (CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2), s * 185 / 1024)
}

/// 以 center 为中心、旋转 deg 度的圆角方块（单位坐标 0–1）。
func tilePath(_ c: CGPoint, _ size: CGFloat, _ deg: CGFloat, _ s: CGFloat, corner: CGFloat = 0.25) -> CGPath {
    var t = CGAffineTransform(translationX: c.x * s, y: c.y * s).rotated(by: deg * .pi / 180)
    let w = size * s
    return CGPath(roundedRect: CGRect(x: -w / 2, y: -w / 2, width: w, height: w),
                  cornerWidth: w * corner, cornerHeight: w * corner, transform: &t)
}

func linear(_ ctx: CGContext, _ colors: [CGColor], _ from: CGPoint, _ to: CGPoint, _ s: CGFloat,
            locations: [CGFloat]? = nil) {
    ctx.drawLinearGradient(
        gradient(colors, locations),
        start: CGPoint(x: from.x * s, y: from.y * s),
        end: CGPoint(x: to.x * s, y: to.y * s),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

func makeContext(_ pixels: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

/// 对当前画面做高斯模糊，模拟玻璃背后的磨砂效果。
func blurredSnapshot(_ ctx: CGContext, radius: CGFloat) -> CGImage? {
    guard let snapshot = ctx.makeImage() else { return nil }
    let input = CIImage(cgImage: snapshot)
    let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
    return ciContext.createCGImage(output, from: input.extent)
}

// MARK: - 图标主体（简洁背景）

struct Background {
    let colors: [CGColor]
    /// 主体边缘高光的强度（浅色背景用较弱的高光）。
    let rim: CGFloat
}

func drawBody(_ ctx: CGContext, _ s: CGFloat, _ bg: Background) {
    let body = iconBody(s)
    let path = roundedRect(body.rect, body.radius)

    // 系统风格的柔和投影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.010), blur: s * 0.026, color: rgb(0x000000, 0.22))
    ctx.addPath(path)
    ctx.setFillColor(bg.colors[0])
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    linear(ctx, bg.colors, CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.5, y: 0.1), s)
    ctx.restoreGState()

    // 主体边缘的玻璃高光：上亮下暗
    glassRim(ctx, path, s, width: s * 0.010, top: bg.rim, bottom: bg.rim * 0.25)
}

// MARK: - 液态玻璃卡片

/// 沿形状内侧的高光描边：左上方最亮，向右下渐隐，模拟玻璃边缘的折射光。
func glassRim(_ ctx: CGContext, _ path: CGPath, _ s: CGFloat, width: CGFloat, top: CGFloat, bottom: CGFloat) {
    let box = path.boundingBoxOfPath
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.addPath(path)
    ctx.setLineWidth(width * 2) // 只保留内侧一半
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(0xFFFFFF, top), rgb(0xFFFFFF, top * 0.25), rgb(0xFFFFFF, bottom)], [0, 0.55, 1]),
        start: CGPoint(x: box.minX, y: box.maxY),
        end: CGPoint(x: box.maxX, y: box.minY),
        options: []
    )
    ctx.restoreGState()
}

struct Glass {
    /// 玻璃本身的颜色（从左上到右下的渐变），alpha 决定通透程度。
    let tint: [CGColor]
    /// 背后模糊半径（相对尺寸）。
    var blur: CGFloat = 0.022
    /// 投影颜色与强度。
    var shadow: CGColor = rgb(0x1B2340, 0.20)
    var shadowBlur: CGFloat = 0.05
    /// 边缘高光强度。
    var rim: CGFloat = 0.95
    /// 左上角的柔光。
    var sheen: CGFloat = 0.35
}

func glassCard(_ ctx: CGContext, _ s: CGFloat, _ path: CGPath, _ glass: Glass) {
    let box = path.boundingBoxOfPath
    // 先拍下当前画面，用于磨砂
    let behind = blurredSnapshot(ctx, radius: glass.blur * s)

    // 投影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.018), blur: glass.shadowBlur * s, color: glass.shadow)
    ctx.addPath(path)
    ctx.setFillColor(rgb(0xFFFFFF, 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    // 磨砂后的背景
    if let behind { ctx.draw(behind, in: CGRect(x: 0, y: 0, width: s, height: s)) }
    // 玻璃颜色
    ctx.drawLinearGradient(
        gradient(glass.tint),
        start: CGPoint(x: box.minX, y: box.maxY),
        end: CGPoint(x: box.maxX, y: box.minY),
        options: []
    )
    // 左上角柔光
    let sheenCenter = CGPoint(x: box.minX + box.width * 0.25, y: box.maxY - box.height * 0.15)
    ctx.drawRadialGradient(
        gradient([rgb(0xFFFFFF, glass.sheen), rgb(0xFFFFFF, 0)]),
        startCenter: sheenCenter, startRadius: 0,
        endCenter: sheenCenter, endRadius: box.width * 0.75, options: []
    )
    // 底部内阴影，增加厚度
    ctx.drawLinearGradient(
        gradient([rgb(0x000000, 0), rgb(0x000000, 0.06)]),
        start: CGPoint(x: box.midX, y: box.midY),
        end: CGPoint(x: box.midX, y: box.minY), options: []
    )
    ctx.restoreGState()

    glassRim(ctx, path, s, width: s * 0.009, top: glass.rim, bottom: glass.rim * 0.45)
}

// MARK: - 「卡片跃出」第一版构图

struct Cards {
    var back: Glass
    var middle: Glass
    var front: Glass
}

func drawCards(_ ctx: CGContext, _ s: CGFloat, _ cards: Cards) {
    glassCard(ctx, s, tilePath(CGPoint(x: 0.385, y: 0.415), 0.31, -14, s), cards.back)
    glassCard(ctx, s, tilePath(CGPoint(x: 0.46, y: 0.465), 0.33, -4, s), cards.middle)
    glassCard(ctx, s, tilePath(CGPoint(x: 0.585, y: 0.56), 0.37, 9, s), cards.front)
}

/// 珊瑚色主卡片（与之前方案一致的橙→粉渐变，略带透明）。
func coralGlass(_ alpha: CGFloat) -> Glass {
    Glass(
        tint: [rgb(0xFFC062, alpha), rgb(0xFF6B6B, alpha), rgb(0xEC4899, alpha)],
        shadow: rgb(0xD9365F, 0.30), shadowBlur: 0.06, rim: 1.0, sheen: 0.40
    )
}

func frostedGlass(_ hex: UInt32, _ alpha: CGFloat, shadow: CGColor = rgb(0x1B2340, 0.16)) -> Glass {
    Glass(tint: [rgb(hex, alpha * 1.15), rgb(hex, alpha)], shadow: shadow)
}

// MARK: - 主题

struct Theme {
    let id: String
    let name: String
    let note: String
    let light: UInt32   // 渐变浅端
    let deep: UInt32    // 渐变深端
    let shadow: UInt32  // 卡片投影色
}

let themes: [Theme] = [
    Theme(id: "T0", name: "珊瑚（当前）", note: "暖橙到玫红，活泼醒目", light: 0xFF9A6B, deep: 0xF2557A, shadow: 0x9C1F45),
    Theme(id: "T1", name: "靛蓝", note: "沉稳专业，贴近系统强调色但更有个性", light: 0x8B9BFF, deep: 0x5146E5, shadow: 0x231C8A),
    Theme(id: "T2", name: "天空蓝", note: "清爽通透，和液态玻璃最搭", light: 0x6FD0FF, deep: 0x2F7BF5, shadow: 0x0F3A8A),
    Theme(id: "T3", name: "薄荷青", note: "轻快、有呼吸感，在 Dock 里少见", light: 0x5BE3C0, deep: 0x0FA39A, shadow: 0x05534F),
    Theme(id: "T4", name: "紫罗兰", note: "梦幻高级，夜间模式下很漂亮", light: 0xC79BFF, deep: 0x8B3CF0, shadow: 0x4A1491),
    Theme(id: "T5", name: "琥珀橙", note: "温暖有能量，“快”的感觉最强", light: 0xFFC24D, deep: 0xF97316, shadow: 0x9A3A07),
    Theme(id: "T6", name: "石墨", note: "低调中性，最“Apple 原生”", light: 0x9AA3B2, deep: 0x4A5261, shadow: 0x1C2129)
]

func drawIcon(_ ctx: CGContext, _ s: CGFloat, _ t: Theme) {
    drawBody(ctx, s, Background(colors: [rgb(t.light), rgb(t.deep)], rim: 0.75))
    drawCards(ctx, s, Cards(
        back: Glass(tint: [rgb(0xFFFFFF, 0.30), rgb(0xFFFFFF, 0.18)], shadow: rgb(t.shadow, 0.18)),
        middle: Glass(tint: [rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0.30)], shadow: rgb(t.shadow, 0.20)),
        front: Glass(tint: [rgb(0xFFFFFF, 0.95), rgb(0xFFFFFF, 0.88)],
                     shadow: rgb(t.shadow, 0.32), shadowBlur: 0.06, rim: 1.0, sheen: 0.5)
    ))
}

func iconImage(_ t: Theme, _ pixels: Int) -> CGImage {
    let ctx = makeContext(pixels)
    drawIcon(ctx, CGFloat(pixels), t)
    return ctx.makeImage()!
}

func ns(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor { NSColor(cgColor: rgb(hex, a))! }

func text(_ string: String, _ point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor, center: Bool = false) {
    let attr = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
    ])
    let w = attr.size().width
    attr.draw(at: CGPoint(x: center ? point.x - w / 2 : point.x, y: point.y))
}

/// 界面强调色示意：主按钮、录制中的快捷键框、速查面板选中项、运行中标记。
func drawUISwatch(_ ctx: CGContext, _ rect: CGRect, _ t: Theme, dark: Bool) {
    let fg = dark ? NSColor.white : NSColor.black
    let secondary = dark ? NSColor(white: 1, alpha: 0.55) : NSColor(white: 0, alpha: 0.5)
    ctx.addPath(roundedRect(rect, 18))
    ctx.setFillColor(dark ? rgb(0x1C1C1E) : rgb(0xFFFFFF))
    ctx.fillPath()

    let x0 = rect.minX + 24
    // 主按钮
    let button = CGRect(x: x0, y: rect.maxY - 64, width: 132, height: 34)
    ctx.saveGState()
    ctx.addPath(roundedRect(button, 17)); ctx.clip()
    linear(ctx, [rgb(t.light), rgb(t.deep)], CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0), 1)
    ctx.drawLinearGradient(gradient([rgb(t.light), rgb(t.deep)]),
                           start: CGPoint(x: button.minX, y: button.maxY),
                           end: CGPoint(x: button.maxX, y: button.minY), options: [])
    ctx.restoreGState()
    text("＋ 添加 App…", CGPoint(x: button.midX, y: button.minY + 9), size: 13, weight: .semibold,
         color: .white, center: true)

    // 录制中的快捷键框
    let field = CGRect(x: button.maxX + 18, y: button.minY, width: 150, height: 34)
    ctx.addPath(roundedRect(field, 17))
    ctx.setFillColor(rgb(t.deep, dark ? 0.16 : 0.08)); ctx.fillPath()
    ctx.addPath(roundedRect(field.insetBy(dx: 1, dy: 1), 16))
    ctx.setStrokeColor(rgb(t.deep)); ctx.setLineWidth(2); ctx.strokePath()
    text("请按快捷键…", CGPoint(x: field.midX, y: field.minY + 9), size: 13, weight: .medium,
         color: ns(t.deep), center: true)

    // 速查面板选中项（三个小 App 方块，中间选中）
    let tileY = rect.minY + 22
    for i in 0..<3 {
        let cx = x0 + 34 + CGFloat(i) * 78
        if i == 1 {
            let hl = CGRect(x: cx - 34, y: tileY - 8, width: 68, height: 78)
            ctx.addPath(roundedRect(hl, 16))
            ctx.setFillColor(rgb(t.deep, dark ? 0.30 : 0.16)); ctx.fillPath()
            ctx.addPath(roundedRect(hl.insetBy(dx: 0.5, dy: 0.5), 16))
            ctx.setStrokeColor(rgb(t.light, 0.6)); ctx.setLineWidth(1); ctx.strokePath()
        }
        let icon = CGRect(x: cx - 20, y: tileY + 22, width: 40, height: 40)
        ctx.addPath(roundedRect(icon, 10))
        ctx.setFillColor(dark ? rgb(0x3A3A3C) : rgb(0xE5E5EA)); ctx.fillPath()
        // 运行中圆点
        if i != 2 {
            ctx.addEllipse(in: CGRect(x: cx - 3, y: tileY + 12, width: 6, height: 6))
            ctx.setFillColor(rgb(t.deep)); ctx.fillPath()
        }
        text(["Safari", "访达", "音乐"][i], CGPoint(x: cx, y: tileY - 4), size: 10, color: fg, center: true)
    }

    // 运行中标签 + 强调文字
    let tx = x0 + 250
    text("Safari", CGPoint(x: tx, y: tileY + 44), size: 13, weight: .semibold, color: fg)
    text("运行中", CGPoint(x: tx + 46, y: tileY + 45), size: 11, weight: .medium, color: ns(t.deep))
    text("按下新快捷键 · Esc 取消", CGPoint(x: tx, y: tileY + 18), size: 11, color: ns(t.deep))
    text("com.apple.Safari", CGPoint(x: tx, y: tileY - 2), size: 11, color: secondary)
}

// MARK: - 输出

for t in themes {
    let rep = NSBitmapImageRep(cgImage: iconImage(t, 1024))
    try rep.representation(using: .png, properties: [:])!
        .write(to: outputDirectory.appendingPathComponent("theme-\(t.id)-icon.png"))
}

let margin: CGFloat = 36, rowH: CGFloat = 260, big: CGFloat = 200
let smalls: [CGFloat] = [64, 32, 16]
let iconPanelW: CGFloat = smalls.reduce(0, +) + CGFloat(smalls.count + 1) * 22
let swatchW: CGFloat = 470
let W = Int(margin * 2 + big + 30 + iconPanelW + 16 + swatchW * 2 + 16)
let H = Int(margin * 2 + rowH * CGFloat(themes.count))

let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
let ctx = NSGraphicsContext.current!.cgContext
ctx.interpolationQuality = .high
ctx.setFillColor(rgb(0xF2F2F5)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

for (i, t) in themes.enumerated() {
    let top = CGFloat(H) - margin - CGFloat(i) * rowH
    let y = top - 40 - big
    text("\(t.id) · \(t.name)", CGPoint(x: margin, y: top - 26), size: 20, weight: .bold, color: .black)
    let titleW = NSAttributedString(string: "\(t.id) · \(t.name)", attributes: [
        .font: NSFont.systemFont(ofSize: 20, weight: .bold)]).size().width
    text(t.note, CGPoint(x: margin + titleW + 14, y: top - 23), size: 13, color: NSColor(white: 0.4, alpha: 1))
    // 色值
    text(String(format: "#%06X → #%06X", t.light, t.deep), CGPoint(x: CGFloat(W) - margin - 170, y: top - 23),
         size: 12, color: NSColor(white: 0.5, alpha: 1))

    ctx.draw(iconImage(t, Int(big)), in: CGRect(x: margin, y: y, width: big, height: big))

    // 小尺寸：上浅下深
    let px = margin + big + 30
    for (j, dark) in [false, true].enumerated() {
        let panel = CGRect(x: px, y: y + CGFloat(1 - j) * (big / 2 + 4) + 2, width: iconPanelW, height: big / 2 - 6)
        ctx.addPath(roundedRect(panel, 14))
        ctx.setFillColor(dark ? rgb(0x1C1C1E) : rgb(0xFFFFFF)); ctx.fillPath()
        var x = panel.minX + 22
        for s in smalls {
            ctx.draw(iconImage(t, Int(s)), in: CGRect(x: x, y: panel.midY - s / 2, width: s, height: s))
            x += s + 22
        }
    }

    // 界面示意：浅色 / 深色
    let sx = px + iconPanelW + 16
    drawUISwatch(ctx, CGRect(x: sx, y: y, width: swatchW, height: big), t, dark: false)
    drawUISwatch(ctx, CGRect(x: sx + swatchW + 16, y: y, width: swatchW, height: big), t, dark: true)
}
NSGraphicsContext.restoreGraphicsState()
try sheet.representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent("themes-sheet.png"))
print(outputDirectory.path)
