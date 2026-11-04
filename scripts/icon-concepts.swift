// 生成 QuickOpen 新 logo 的候选方案预览（不影响正式图标）。
// 用法：xcrun swift scripts/icon-concepts.swift <输出目录>
//
// 当前方向：「卡片跃出」第一版构图 + macOS 新系统的液态玻璃（Liquid Glass）质感 + 简洁浅色背景。
import AppKit
import CoreImage
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Usage: icon-concepts.swift <output-dir>") }
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

// MARK: - 方案

struct Concept {
    let id: String
    let title: String
    let note: String
    let draw: (CGContext, CGFloat) -> Void
}

let concepts: [Concept] = [
    Concept(
        id: "L1", title: "L1 · 纯白",
        note: "近乎纯白的底，背景卡是淡蓝紫磨砂玻璃，主卡片珊瑚玻璃：最干净，接近系统自带 App。"
    ) { ctx, s in
        drawBody(ctx, s, Background(colors: [rgb(0xFFFFFF), rgb(0xF1F3F8)], rim: 0.9))
        drawCards(ctx, s, Cards(
            back: frostedGlass(0x8E9BFF, 0.38),
            middle: frostedGlass(0x6C7CF5, 0.45),
            front: coralGlass(0.88)
        ))
    },
    Concept(
        id: "L2", title: "L2 · 雾蓝",
        note: "极浅的雾蓝渐变底，玻璃卡更有层次；冷暖对比让珊瑚主卡片更突出。"
    ) { ctx, s in
        drawBody(ctx, s, Background(colors: [rgb(0xF5F8FF), rgb(0xDDE6F8)], rim: 0.9))
        drawCards(ctx, s, Cards(
            back: frostedGlass(0x9AA8FF, 0.40),
            middle: frostedGlass(0x6F86F2, 0.48),
            front: coralGlass(0.88)
        ))
    },
    Concept(
        id: "L3", title: "L3 · 暖白",
        note: "带一点暖意的奶白底，背景卡改为白色磨砂玻璃：整体统一在暖色调里，柔和不刺眼。"
    ) { ctx, s in
        drawBody(ctx, s, Background(colors: [rgb(0xFFFBF7), rgb(0xF6EAE3)], rim: 0.9))
        drawCards(ctx, s, Cards(
            back: Glass(tint: [rgb(0xFFFFFF, 0.70), rgb(0xFFF1EA, 0.55)], shadow: rgb(0x8A4B3A, 0.14)),
            middle: Glass(tint: [rgb(0xFFFFFF, 0.78), rgb(0xFFE6DC, 0.62)], shadow: rgb(0x8A4B3A, 0.16)),
            front: coralGlass(0.9)
        ))
    },
    Concept(
        id: "L4", title: "L4 · 珊瑚底 + 白玻璃",
        note: "反过来：干净的珊瑚渐变底，三张都是白色磨砂玻璃，最前一张最实。最像新系统里的官方图标。"
    ) { ctx, s in
        drawBody(ctx, s, Background(colors: [rgb(0xFF9A6B), rgb(0xF2557A)], rim: 0.75))
        drawCards(ctx, s, Cards(
            back: Glass(tint: [rgb(0xFFFFFF, 0.30), rgb(0xFFFFFF, 0.18)], shadow: rgb(0x9C1F45, 0.18)),
            middle: Glass(tint: [rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0.30)], shadow: rgb(0x9C1F45, 0.20)),
            front: Glass(tint: [rgb(0xFFFFFF, 0.95), rgb(0xFFF3F1, 0.88)],
                         shadow: rgb(0x9C1F45, 0.32), shadowBlur: 0.06, rim: 1.0, sheen: 0.5)
        ))
    },
    Concept(
        id: "L5", title: "L5 · 天蓝底 + 白玻璃",
        note: "同 L4 的手法，换成清爽的天蓝底：冷静、专业，在白色和深色 Dock 都清楚。"
    ) { ctx, s in
        drawBody(ctx, s, Background(colors: [rgb(0x6FB6FF), rgb(0x3A6FF0)], rim: 0.75))
        drawCards(ctx, s, Cards(
            back: Glass(tint: [rgb(0xFFFFFF, 0.30), rgb(0xFFFFFF, 0.18)], shadow: rgb(0x10307A, 0.20)),
            middle: Glass(tint: [rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0.30)], shadow: rgb(0x10307A, 0.22)),
            front: Glass(tint: [rgb(0xFFFFFF, 0.95), rgb(0xF2F6FF, 0.88)],
                         shadow: rgb(0x10307A, 0.32), shadowBlur: 0.06, rim: 1.0, sheen: 0.5)
        ))
    }
]

// MARK: - 渲染

func renderImage(_ concept: Concept, pixels: Int) -> CGImage {
    let ctx = makeContext(pixels)
    concept.draw(ctx, CGFloat(pixels))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ name: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent(name))
}

for concept in concepts {
    try writePNG(renderImage(concept, pixels: 1024), "concept-\(concept.id)-1024.png")
}

// 对比总览：每个方案一行，左侧大图，右侧浅色/深色背景下 128/64/32/16 的实际尺寸。
let rowHeight: CGFloat = 330, margin: CGFloat = 36, big: CGFloat = 256
let smallSizes: [CGFloat] = [128, 64, 32, 16]
let panelWidth: CGFloat = smallSizes.reduce(0, +) + CGFloat(smallSizes.count + 1) * 28
let sheetWidth = Int(margin * 2 + big + 40 + panelWidth * 2 + 20)
let sheetHeight = Int(margin * 2 + rowHeight * CGFloat(concepts.count))

let sheet = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: sheetWidth, pixelsHigh: sheetHeight, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
let ctx = NSGraphicsContext.current!.cgContext
ctx.interpolationQuality = .high
ctx.setFillColor(rgb(0xF5F5F7))
ctx.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))

for (index, concept) in concepts.enumerated() {
    let top = CGFloat(sheetHeight) - margin - CGFloat(index) * rowHeight
    let iconY = top - 50 - big

    let title = NSAttributedString(string: concept.title, attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: NSColor.black
    ])
    title.draw(at: CGPoint(x: margin, y: top - 30))
    let note = NSAttributedString(string: concept.note, attributes: [
        .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor(white: 0.35, alpha: 1)
    ])
    note.draw(at: CGPoint(x: margin + title.size().width + 16, y: top - 27))

    ctx.draw(renderImage(concept, pixels: Int(big)), in: CGRect(x: margin, y: iconY, width: big, height: big))

    for (panelIndex, dark) in [false, true].enumerated() {
        let panelX = margin + big + 40 + CGFloat(panelIndex) * (panelWidth + 20)
        let panel = CGRect(x: panelX, y: iconY + 24, width: panelWidth, height: big - 48)
        ctx.addPath(roundedRect(panel, 18))
        ctx.setFillColor(dark ? rgb(0x1C1C1E) : rgb(0xFFFFFF))
        ctx.fillPath()

        var x = panelX + 28
        for size in smallSizes {
            ctx.draw(renderImage(concept, pixels: Int(size)),
                     in: CGRect(x: x, y: panel.midY - size / 2, width: size, height: size))
            let label = NSAttributedString(string: "\(Int(size))", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: dark ? NSColor(white: 0.6, alpha: 1) : NSColor(white: 0.5, alpha: 1)
            ])
            label.draw(at: CGPoint(x: x + size / 2 - label.size().width / 2, y: panel.minY + 10))
            x += size + 28
        }
    }
}
NSGraphicsContext.restoreGraphicsState()
try writePNG(sheet.cgImage!, "concepts-sheet.png")
print(outputDirectory.path)
