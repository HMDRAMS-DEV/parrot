// Renders Parrot's app icon into the asset catalog, plus light and dark copies for the website.
//
//     swift scripts/render-icon.swift
//
// A geometric parrot in profile, built from circles and quarter circles, on a plain tile.

import AppKit

let output = URL(fileURLWithPath: "Parrot/Assets.xcassets/AppIcon.appiconset")
let site = URL(fileURLWithPath: "site/assets")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A pie slice: a disc of radius `r` around (x, y), from angle `a` to `b` in degrees.
func slice(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x, y: y))
    path.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: a * .pi / 180, endAngle: b * .pi / 180, clockwise: false)
    path.closeSubpath()
    return path
}

/// A parrot in profile, built from circles and quarter circles: banded half-disc wings, a red
/// body and head, a yellow beak, and a quarter-disc tail. Drawn on the 1024pt canvas.
func parrot(in context: CGContext) {
    func fill(_ hex: UInt32, _ path: CGPath) {
        context.addPath(path)
        context.setFillColor(color(hex))
        context.fillPath()
    }

    context.translateBy(x: 0, y: 32)
    fill(0x3B5BA9, slice(512, 540, 270, 180, 360))
    fill(0xE8B04B, slice(512, 540, 215, 180, 360))
    fill(0xC8452C, slice(512, 540, 160, 180, 360))
    fill(0xA8361F, slice(422, 400, 190, 270, 360))
    fill(0xC8452C, CGPath(rect: CGRect(x: 422, y: 400, width: 180, height: 250), transform: nil))
    fill(0xC8452C, slice(512, 650, 90, 0, 180))
    fill(0xC8452C, slice(422, 650, 90, 0, 90))
    fill(0xE8B04B, slice(602, 560, 120, 0, 90))
    fill(0xF7F1E6, slice(544, 655, 50, 0, 360))
    fill(0x1E2235, slice(552, 655, 22, 0, 360))
}

func draw(in context: CGContext, size: CGFloat, dark: Bool) {
    context.scaleBy(x: size / 1024, y: size / 1024)

    // The macOS icon grid: an 824pt rounded square centered on a 1024pt canvas, with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.3))
    context.addPath(shape)
    context.setFillColor(color(dark ? 0x22263A : 0xF5EEE2))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.setFillColor(color(dark ? 0x22263A : 0xF5EEE2))
    context.fill(tile)
    context.restoreGState()

    context.saveGState()
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183, cornerHeight: 183, transform: nil))
    context.setStrokeColor(dark ? color(0xFFFFFF, 0.08) : color(0x000000, 0.06))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    parrot(in: context)
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
