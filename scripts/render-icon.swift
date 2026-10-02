// Renders Parrot's app icon into the asset catalog, plus light and dark copies for the website.
//
//     swift scripts/render-icon.swift
//
// Pacer's tile with a green bird and the red recording dot from the menu bar.

import AppKit

let output = URL(fileURLWithPath: "Parrot/Assets.xcassets/AppIcon.appiconset")
let site = URL(fileURLWithPath: "site/assets")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
}

/// The bird symbol as a mask, so a gradient can fill it.
let bird: CGImage = {
    let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .regular)
    let symbol = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    var rect = CGRect(origin: .zero, size: symbol.size)
    return symbol.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
}()

func draw(in context: CGContext, size: CGFloat, dark: Bool) {
    context.scaleBy(x: size / 1024, y: size / 1024)

    // The macOS icon grid: an 824pt rounded square centered on a 1024pt canvas, with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.3))
    context.addPath(shape)
    context.setFillColor(color(dark ? 0x161618 : 0xF7F5F3))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = dark ? gradient([color(0x2A2A2E), color(0x0E0E10)]) : gradient([color(0xFFFFFF), color(0xEEEAE5)])
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    context.saveGState()
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183, cornerHeight: 183, transform: nil))
    context.setStrokeColor(dark ? color(0xFFFFFF, 0.08) : color(0x000000, 0.06))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    // The bird, centered a little left to leave room for the dot.
    let aspect = CGFloat(bird.width) / CGFloat(bird.height)
    let height: CGFloat = 540
    let frame = CGRect(x: 512 - height * aspect / 2 - 36, y: 512 - height / 2 + 30, width: height * aspect, height: height)
    context.saveGState()
    context.clip(to: frame, mask: bird)
    context.drawLinearGradient(gradient([color(0x0E8A4A), color(0x5BE39A)]), start: CGPoint(x: frame.minX, y: frame.minY), end: CGPoint(x: frame.maxX, y: frame.maxY), options: [])
    context.restoreGState()

    // The recording dot, with a halo.
    let dot = CGRect(x: 668, y: 228, width: 124, height: 124)
    context.setFillColor(color(0xE5392B, 0.22))
    context.fillEllipse(in: dot.insetBy(dx: -34, dy: -34))
    context.setFillColor(color(0xE5392B))
    context.fillEllipse(in: dot)
}

func png(pixels: Int, dark: Bool = false) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    draw(in: context.cgContext, size: CGFloat(pixels), dark: dark)
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: points * scale).write(to: output.appending(path: name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: output.appending(path: "Contents.json"))
print("Wrote \(images.count) icons to \(output.path)")

try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
for dark in [false, true] {
    let suffix = dark ? "-dark" : ""
    try png(pixels: 512, dark: dark).write(to: site.appending(path: "icon\(suffix).png"))
    try png(pixels: 64, dark: dark).write(to: site.appending(path: "favicon\(suffix).png"))
}
print("Wrote light and dark icons to \(site.path)")
