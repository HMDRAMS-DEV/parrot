import AppKit

/// The menu bar glyph: the app icon's geometric parrot in one color, with a red dot while recording, a hollow dot while transcribing,
/// and a red ring while a call is being recorded. Plain template image when idle, so it matches
/// every other menu bar icon.
enum MenuBarIcon {
    static func image(for phase: ParrotStore.Phase, onCall: Bool = false) -> NSImage {
        let plain = phase == .idle && !onCall
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let glyph = NSRect(x: 0, y: 1, width: 17, height: 16)
            drawParrot(in: glyph)
            if !plain {
                // Color the template glyph for this appearance, since the image can't be a template
                // once it carries a red dot.
                NSColor.labelColor.set()
                glyph.fill(using: .sourceAtop)
            }

            let dot = NSRect(x: rect.maxX - 8, y: 0, width: 8, height: 8)
            switch phase {
            case .idle:
                guard onCall else { break }
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 1, dy: 1))
                ring.lineWidth = 2
                NSColor.systemRed.setStroke()
                ring.stroke()
            case .recording, .awaitingWords, .hearing:
                // Cut a gap around the dot so it reads apart from the bird.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: dot).fill()
            case .transcribing:
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 1, dy: 1))
                ring.lineWidth = 1.6
                NSColor.labelColor.setStroke()
                ring.stroke()
            }
            return true
        }
        image.isTemplate = plain
        image.accessibilityDescription = "Parrot"
        return image
    }

    /// The parrot from scripts/render-icon.swift, simplified: wings, body, beak, and tail as one
    /// silhouette, with the eye and the beak seam cut out.
    private static func drawParrot(in rect: NSRect) {
        // The icon's parrot spans x 242...782 and y 220...740 on its 1024pt canvas.
        let scale = min(rect.width / 540, rect.height / 520)
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.midX + (x - 512) * scale, y: rect.midY + (y - 480) * scale)
        }
        func slice(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat, _ b: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.move(to: point(x, y))
            path.appendArc(withCenter: point(x, y), radius: r * scale, startAngle: a, endAngle: b)
            path.close()
            return path
        }

        NSColor.black.setFill()
        slice(512, 540, 270, 180, 360).fill()
        slice(422, 400, 190, 270, 360).fill()
        NSBezierPath(rect: NSRect(origin: point(422, 400), size: NSSize(width: 180 * scale, height: 250 * scale))).fill()
        slice(512, 650, 90, 0, 180).fill()
        slice(422, 650, 90, 0, 90).fill()
        slice(602, 560, 120, 0, 90).fill()

        let context = NSGraphicsContext.current
        context?.compositingOperation = .clear
        let seam = NSBezierPath()
        seam.move(to: point(602, 560))
        seam.line(to: point(602, 680))
        seam.lineWidth = 1.2
        seam.stroke()
        NSBezierPath(ovalIn: NSRect(origin: point(496, 621), size: NSSize(width: 68 * scale, height: 68 * scale))).fill()
        context?.compositingOperation = .sourceOver
    }
}
