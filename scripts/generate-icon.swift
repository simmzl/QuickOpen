import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: generate-icon.swift <iconset-directory>")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let size = CGFloat(pixels)
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let inset = size * 0.035
    let backgroundRect = canvas.insetBy(dx: inset, dy: inset)
    let background = NSBezierPath(
        roundedRect: backgroundRect,
        xRadius: size * 0.22,
        yRadius: size * 0.22
    )
    guard let gradient = NSGradient(colors: [
        NSColor(red: 0.16, green: 0.42, blue: 0.98, alpha: 1),
        NSColor(red: 0.39, green: 0.18, blue: 0.88, alpha: 1)
    ]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    gradient.draw(in: background, angle: -48)

    let highlight = NSBezierPath(ovalIn: NSRect(
        x: size * 0.04,
        y: size * 0.43,
        width: size * 0.92,
        height: size * 0.72
    ))
    NSColor.white.withAlphaComponent(0.08).setFill()
    highlight.fill()

    guard let context = NSGraphicsContext.current?.cgContext else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(size * 0.105)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addEllipse(in: CGRect(
        x: size * 0.245,
        y: size * 0.285,
        width: size * 0.47,
        height: size * 0.47
    ))
    context.strokePath()
    context.move(to: CGPoint(x: size * 0.60, y: size * 0.39))
    context.addLine(to: CGPoint(x: size * 0.765, y: size * 0.225))
    context.strokePath()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(variant.name), options: .atomic)
}
