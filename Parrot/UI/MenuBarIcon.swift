import AppKit

/// The menu bar glyph: a bird, with a red dot while recording, a hollow dot while transcribing,
/// and a red ring while a call is being recorded. Plain template image when idle, so it matches
/// every other menu bar icon.
enum MenuBarIcon {
    static func image(for phase: ParrotStore.Phase, onCall: Bool = false) -> NSImage {
        let plain = phase == .idle && !onCall
        let size = NSSize(width: 20, height: 18)
        let symbol = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "Parrot")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))

        let image = NSImage(size: size, flipped: false) { rect in
            let glyph = NSRect(x: 0, y: 1, width: 17, height: 16)
            symbol?.draw(in: glyph)
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
        return image
    }
}
