// 生成 QuickOpen 正式图标（.iconset）：「卡片跃出」· 珊瑚底 + 白色液态玻璃卡片。
// 用法：xcrun swift scripts/generate-icon.swift <iconset-directory>
import AppKit
import CoreImage
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: generate-icon.swift <iconset-directory>")
}
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

// MARK: - 正式图标

func drawIcon(_ ctx: CGContext, _ s: CGFloat) {
    drawBody(ctx, s, Background(colors: [rgb(0xFF9A6B), rgb(0xF2557A)], rim: 0.75))
    drawCards(ctx, s, Cards(
        back: Glass(tint: [rgb(0xFFFFFF, 0.30), rgb(0xFFFFFF, 0.18)], shadow: rgb(0x9C1F45, 0.18)),
        middle: Glass(tint: [rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0.30)], shadow: rgb(0x9C1F45, 0.20)),
        front: Glass(tint: [rgb(0xFFFFFF, 0.95), rgb(0xFFF3F1, 0.88)],
                     shadow: rgb(0x9C1F45, 0.32), shadowBlur: 0.06, rim: 1.0, sheen: 0.5)
    ))
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    let ctx = makeContext(variant.pixels)
    drawIcon(ctx, CGFloat(variant.pixels))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!
        .write(to: outputDirectory.appendingPathComponent(variant.name), options: .atomic)
}
