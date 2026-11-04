// 两张卡片版 logo 的候选预览（不影响正式图标）。
// 用法：xcrun swift scripts/design/two-card-concepts.swift <输出目录>
import AppKit
import CoreImage
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Usage: two-card-concepts.swift <output-dir>") }
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

let amberBG = Background(colors: [rgb(0xFFC24D), rgb(0xF97316)], rim: 0.75)
let shadowTone: UInt32 = 0x9A3A07
func backGlass(_ a: CGFloat, _ b: CGFloat) -> Glass {
    Glass(tint: [rgb(0xFFFFFF, a), rgb(0xFFFFFF, b)], shadow: rgb(shadowTone, 0.22))
}
let frontGlass = Glass(tint: [rgb(0xFFFFFF, 0.95), rgb(0xFFFFFF, 0.88)],
                       shadow: rgb(shadowTone, 0.32), shadowBlur: 0.06, rim: 1.0, sheen: 0.5)

struct Concept {
    let id: String
    let title: String
    let note: String
    let draw: (CGContext, CGFloat) -> Void
}

let concepts: [Concept] = [
    Concept(id: "C0", title: "C0 · 当前（三张）", note: "对照") { ctx, s in
        drawBody(ctx, s, amberBG)
        glassCard(ctx, s, tilePath(CGPoint(x: 0.385, y: 0.415), 0.31, -14, s), backGlass(0.30, 0.18))
        glassCard(ctx, s, tilePath(CGPoint(x: 0.46, y: 0.465), 0.33, -4, s), backGlass(0.45, 0.30))
        glassCard(ctx, s, tilePath(CGPoint(x: 0.585, y: 0.56), 0.37, 9, s), frontGlass)
    },
    Concept(id: "T1", title: "T1 · 经典错位", note: "后卡左下、前卡右上，角度与现在一致，只去掉中间那张；最接近原版") { ctx, s in
        drawBody(ctx, s, amberBG)
        glassCard(ctx, s, tilePath(CGPoint(x: 0.41, y: 0.43), 0.36, -12, s), backGlass(0.40, 0.24))
        glassCard(ctx, s, tilePath(CGPoint(x: 0.59, y: 0.57), 0.40, 8, s), frontGlass)
    },
    Concept(id: "T2", title: "T2 · 大卡居中", note: "前卡更大、更居中，后卡只露出左下一角；最简洁，小尺寸最清楚") { ctx, s in
        drawBody(ctx, s, amberBG)
        glassCard(ctx, s, tilePath(CGPoint(x: 0.43, y: 0.44), 0.40, -10, s), backGlass(0.40, 0.24))
        glassCard(ctx, s, tilePath(CGPoint(x: 0.555, y: 0.545), 0.44, 6, s), frontGlass)
    },
    Concept(id: "T3", title: "T3 · 扇形对称", note: "两张卡同样大小，以底部为轴向两侧展开，像手里的两张牌；构图更稳") { ctx, s in
        drawBody(ctx, s, amberBG)
        glassCard(ctx, s, tilePath(CGPoint(x: 0.43, y: 0.50), 0.39, -13, s), backGlass(0.40, 0.24))
        glassCard(ctx, s, tilePath(CGPoint(x: 0.57, y: 0.51), 0.39, 11, s), frontGlass)
    },
    Concept(id: "T4", title: "T4 · 垂直叠放", note: "后卡在正上方略缩小，前卡在下方压住，像卡片堆叠的透视；安静、克制") { ctx, s in
        drawBody(ctx, s, amberBG)
        glassCard(ctx, s, tilePath(CGPoint(x: 0.50, y: 0.60), 0.36, 0, s), backGlass(0.40, 0.24))
        glassCard(ctx, s, tilePath(CGPoint(x: 0.50, y: 0.45), 0.44, 0, s), frontGlass)
    }
]

// MARK: - 渲染

func renderImage(_ concept: Concept, pixels: Int) -> CGImage {
    let ctx = makeContext(pixels)
    concept.draw(ctx, CGFloat(pixels))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ name: String) throws {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        .write(to: outputDirectory.appendingPathComponent(name))
}

for concept in concepts {
    try writePNG(renderImage(concept, pixels: 1024), "two-card-\(concept.id)-1024.png")
}

let rowHeight: CGFloat = 300, margin: CGFloat = 36, big: CGFloat = 224
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
    let iconY = top - 46 - big
    let title = NSAttributedString(string: concept.title, attributes: [
        .font: NSFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: NSColor.black])
    title.draw(at: CGPoint(x: margin, y: top - 28))
    NSAttributedString(string: concept.note, attributes: [
        .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.38, alpha: 1)])
        .draw(at: CGPoint(x: margin + title.size().width + 14, y: top - 25))
    ctx.draw(renderImage(concept, pixels: Int(big)), in: CGRect(x: margin, y: iconY, width: big, height: big))
    for (panelIndex, dark) in [false, true].enumerated() {
        let panelX = margin + big + 40 + CGFloat(panelIndex) * (panelWidth + 20)
        let panel = CGRect(x: panelX, y: iconY + 16, width: panelWidth, height: big - 32)
        ctx.addPath(roundedRect(panel, 18))
        ctx.setFillColor(dark ? rgb(0x1C1C1E) : rgb(0xFFFFFF)); ctx.fillPath()
        var x = panelX + 28
        for size in smallSizes {
            ctx.draw(renderImage(concept, pixels: Int(size)),
                     in: CGRect(x: x, y: panel.midY - size / 2, width: size, height: size))
            x += size + 28
        }
    }
}
NSGraphicsContext.restoreGraphicsState()
try writePNG(sheet.cgImage!, "two-card-sheet.png")
print(outputDirectory.path)
