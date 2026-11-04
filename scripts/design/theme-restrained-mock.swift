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


struct Theme { let light: UInt32; let deep: UInt32; let shadow: UInt32 }
let amber = Theme(light: 0xFFC24D, deep: 0xF97316, shadow: 0x9A3A07)
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


/// 界面中使用的琥珀色：比图标深一档，保证白底对比度（≈ 4.5:1）。
let amberText: UInt32 = 0xC2560C      // 浅色模式文字
let amberTextDark: UInt32 = 0xFFB454  // 深色模式文字

enum Mode { case full, restrained }

func mock(_ ctx: CGContext, _ rect: CGRect, dark: Bool, mode: Mode) {
    let fg = dark ? NSColor.white : NSColor.black
    let secondary = dark ? NSColor(white: 1, alpha: 0.55) : NSColor(white: 0, alpha: 0.5)
    let neutralFill = dark ? rgb(0xFFFFFF, 0.07) : rgb(0x000000, 0.035)
    let neutralStroke = dark ? rgb(0xFFFFFF, 0.14) : rgb(0x000000, 0.09)
    let accentText = ns(dark ? amberTextDark : amberText)

    // 窗口
    ctx.addPath(roundedRect(rect, 16))
    ctx.setFillColor(dark ? rgb(0x232326) : rgb(0xF6F6F8)); ctx.fillPath()
    if mode == .full {
        // 角落品牌色光晕
        ctx.saveGState(); ctx.addPath(roundedRect(rect, 16)); ctx.clip()
        let c = CGPoint(x: rect.maxX - 40, y: rect.maxY - 20)
        ctx.drawRadialGradient(gradient([rgb(amber.light, 0.35), rgb(amber.light, 0)]),
                               startCenter: c, startRadius: 0, endCenter: c, endRadius: 260, options: [])
        ctx.restoreGState()
    }
    let x0 = rect.minX + 22
    text("App 快捷键", CGPoint(x: x0, y: rect.maxY - 40), size: 17, weight: .semibold, color: fg)

    // 三行卡片
    let rows: [(String, String, Bool, Bool)] = [   // 名称, 快捷键, 运行中, 录制中
        ("Safari", "⌥ ⌘ S", true, false),
        ("访达", "", false, true),
        ("音乐", "⌥ ⌘ M", false, false)
    ]
    for (i, row) in rows.enumerated() {
        let r = CGRect(x: rect.minX + 16, y: rect.maxY - 100 - CGFloat(i) * 58, width: rect.width - 32, height: 50)
        ctx.addPath(roundedRect(r, 12))
        ctx.setFillColor(dark ? rgb(0xFFFFFF, 0.05) : rgb(0xFFFFFF)); ctx.fillPath()
        ctx.addPath(roundedRect(r.insetBy(dx: 0.5, dy: 0.5), 12))
        ctx.setStrokeColor(neutralStroke); ctx.setLineWidth(1); ctx.strokePath()
        let icon = CGRect(x: r.minX + 12, y: r.midY - 15, width: 30, height: 30)
        ctx.addPath(roundedRect(icon, 7)); ctx.setFillColor(dark ? rgb(0x48484C) : rgb(0xDADADF)); ctx.fillPath()
        text(row.0, CGPoint(x: icon.maxX + 10, y: r.midY + 1), size: 13, weight: .semibold, color: fg)
        if row.2 {
            // 运行中：full 用琥珀文字；restrained 用中性小圆点
            if mode == .full {
                text("运行中", CGPoint(x: icon.maxX + 60, y: r.midY + 2), size: 10, weight: .medium, color: ns(amber.deep))
            } else {
                ctx.addEllipse(in: CGRect(x: icon.maxX + 58, y: r.midY + 6, width: 5, height: 5))
                ctx.setFillColor(dark ? rgb(0xFFFFFF, 0.45) : rgb(0x000000, 0.35)); ctx.fillPath()
            }
        }
        text("com.example.app", CGPoint(x: icon.maxX + 10, y: r.midY - 15), size: 10, color: secondary)

        // 快捷键框
        let f = CGRect(x: r.maxX - 140, y: r.midY - 13, width: 124, height: 26)
        ctx.addPath(roundedRect(f, 13))
        if row.3 {
            ctx.setFillColor(rgb(amber.deep, dark ? 0.16 : 0.08)); ctx.fillPath()
            ctx.addPath(roundedRect(f.insetBy(dx: 1, dy: 1), 12))
            ctx.setStrokeColor(rgb(amber.deep)); ctx.setLineWidth(2); ctx.strokePath()
            text("请按快捷键…", CGPoint(x: f.midX, y: f.minY + 7), size: 11, weight: .medium,
                 color: mode == .full ? ns(amber.deep) : accentText, center: true)
        } else {
            ctx.setFillColor(neutralFill); ctx.fillPath()
            ctx.addPath(roundedRect(f.insetBy(dx: 0.5, dy: 0.5), 13))
            ctx.setStrokeColor(neutralStroke); ctx.setLineWidth(1); ctx.strokePath()
            text(row.1, CGPoint(x: f.midX, y: f.minY + 7), size: 11, weight: .medium, color: fg, center: true)
        }
    }

    // 底部：添加按钮 + 提示
    let b = CGRect(x: x0, y: rect.minY + 18, width: 104, height: 28)
    ctx.addPath(roundedRect(b, 14))
    if mode == .full {
        ctx.saveGState(); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(amber.light), rgb(amber.deep)]),
                               start: CGPoint(x: b.minX, y: b.maxY), end: CGPoint(x: b.maxX, y: b.minY), options: [])
        ctx.restoreGState()
        text("＋ 添加 App…", CGPoint(x: b.midX, y: b.minY + 7), size: 12, weight: .semibold, color: .white, center: true)
    } else {
        ctx.setFillColor(dark ? rgb(0xFFFFFF, 0.10) : rgb(0xFFFFFF)); ctx.fillPath()
        ctx.addPath(roundedRect(b.insetBy(dx: 0.5, dy: 0.5), 14))
        ctx.setStrokeColor(neutralStroke); ctx.setLineWidth(1); ctx.strokePath()
        text("＋ 添加 App…", CGPoint(x: b.midX, y: b.minY + 7), size: 12, weight: .medium, color: fg, center: true)
    }
    text(row2Hint(mode), CGPoint(x: b.maxX + 12, y: b.minY + 8), size: 11,
         color: mode == .full ? ns(amber.deep) : accentText)
}
func row2Hint(_ m: Mode) -> String { "按下新快捷键 · Esc 取消" }

/// 速查面板示意
func overlayMock(_ ctx: CGContext, _ rect: CGRect, dark: Bool, mode: Mode) {
    let fg = dark ? NSColor.white : NSColor.black
    ctx.addPath(roundedRect(rect, 22))
    ctx.setFillColor(dark ? rgb(0x2C2C30, 0.96) : rgb(0xFFFFFF, 0.92)); ctx.fillPath()
    ctx.addPath(roundedRect(rect.insetBy(dx: 0.5, dy: 0.5), 22))
    ctx.setStrokeColor(dark ? rgb(0xFFFFFF, 0.16) : rgb(0x000000, 0.08)); ctx.setLineWidth(1); ctx.strokePath()
    // 标题：小 logo
    ctx.draw(iconImage(amber, 36), in: CGRect(x: rect.midX - 52, y: rect.maxY - 36, width: 18, height: 18))
    text("QuickOpen", CGPoint(x: rect.midX - 30, y: rect.maxY - 34), size: 12, weight: .semibold,
         color: dark ? NSColor(white: 1, alpha: 0.6) : NSColor(white: 0, alpha: 0.5))
    for i in 0..<4 {
        let cx = rect.minX + 56 + CGFloat(i) * 92
        let cy = rect.midY - 6
        if i == 1 {
            let hl = CGRect(x: cx - 40, y: cy - 46, width: 80, height: 94)
            ctx.addPath(roundedRect(hl, 16))
            if mode == .full {
                ctx.setFillColor(rgb(amber.deep, dark ? 0.32 : 0.20)); ctx.fillPath()
            } else {
                ctx.setFillColor(dark ? rgb(0xFFFFFF, 0.10) : rgb(0x000000, 0.05)); ctx.fillPath()
                ctx.addPath(roundedRect(hl.insetBy(dx: 1, dy: 1), 15))
                ctx.setStrokeColor(rgb(amber.deep, 0.9)); ctx.setLineWidth(2); ctx.strokePath()
            }
        }
        let icon = CGRect(x: cx - 22, y: cy - 2, width: 44, height: 44)
        ctx.addPath(roundedRect(icon, 11)); ctx.setFillColor(dark ? rgb(0x48484C) : rgb(0xDADADF)); ctx.fillPath()
        if i == 0 || i == 2 {
            ctx.addEllipse(in: CGRect(x: cx - 2.5, y: cy - 10, width: 5, height: 5))
            ctx.setFillColor(mode == .full ? rgb(amber.deep) : (dark ? rgb(0xFFFFFF, 0.5) : rgb(0x000000, 0.4)))
            ctx.fillPath()
        }
        text(["Safari", "访达", "终端", "音乐"][i], CGPoint(x: cx, y: cy - 28), size: 11, weight: .medium,
             color: fg, center: true)
        text("⌥ ⌘ " + ["S", "F", "T", "M"][i], CGPoint(x: cx, y: cy - 44), size: 10, color: fg, center: true)
    }
}

let W = 1180, H = 860
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
let ctx = NSGraphicsContext.current!.cgContext
ctx.interpolationQuality = .high
ctx.setFillColor(rgb(0xEDEDF0)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

text("❌ 全量主题色（当前做法换成琥珀色）", CGPoint(x: 36, y: CGFloat(H) - 44), size: 17, weight: .bold, color: .black)
text("✅ 克制方案：界面中性，主题色只用在 4 个关键点", CGPoint(x: 616, y: CGFloat(H) - 44), size: 17, weight: .bold, color: .black)
for (col, mode) in [(0, Mode.full), (1, Mode.restrained)] {
    let x = 36 + CGFloat(col) * 580
    mock(ctx, CGRect(x: x, y: 480, width: 264, height: 320), dark: false, mode: mode)
    mock(ctx, CGRect(x: x + 280, y: 480, width: 264, height: 320), dark: true, mode: mode)
    overlayMock(ctx, CGRect(x: x, y: 250, width: 400, height: 200), dark: false, mode: mode)
    overlayMock(ctx, CGRect(x: x + 40, y: 30, width: 400, height: 200), dark: true, mode: mode)
}
ctx.draw(iconImage(amber, 120), in: CGRect(x: 1040, y: 300, width: 120, height: 120))
text("Logo：琥珀橙", CGPoint(x: 1100, y: 280), size: 12, weight: .medium, color: .black, center: true)
NSGraphicsContext.restoreGraphicsState()
try sheet.representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent("restrained-ui.png"))
print("ok")
