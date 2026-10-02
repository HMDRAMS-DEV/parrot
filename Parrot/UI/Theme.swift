import AppKit
import SwiftUI

/// Pacer's look: native materials, warm neutrals, semibold tight display type. Parrot's color is
/// a leafy green, with red reserved for the recording dot.
enum Theme {
    static let ink = Color(light: 0x0D0D0D, dark: 0xFFFFFF)
    static let accent = Color(light: 0x14A35A, dark: 0x3DD68C)
    static let recording = Color(light: 0xE5392B, dark: 0xFF5A4E)
    static let quietWash = Color.primary.opacity(0.07)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

/// "Parrot" with a dot that turns red while recording.
struct Wordmark: View {
    var size: CGFloat = 20
    var recording = false

    var body: some View {
        let dot = size * 0.3
        let color = recording ? Theme.recording : Theme.accent
        HStack(alignment: .firstTextBaseline, spacing: size * 0.3) {
            Text("Parrot").display(size).foregroundStyle(.primary)
            Circle().fill(color)
                .frame(width: dot, height: dot)
                .background(Circle().fill(color.opacity(0.28)).frame(width: dot * 1.9, height: dot * 1.9))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Parrot")
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? .white : Theme.ink)
            .background(prominent ? Theme.accent : Theme.quietWash, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// Copies plain text to the clipboard.
@MainActor func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// A small "Copied" pill at the bottom of a view. Each change to `trigger` shows it again.
private struct Toast: ViewModifier {
    let message: String
    let trigger: Int
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if visible {
                    Label(message, systemImage: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .task(id: trigger) {
                guard trigger > 0 else { return }
                withAnimation(.snappy(duration: 0.2)) { visible = true }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.25)) { visible = false }
            }
    }
}

extension View {
    func toast(_ message: String, trigger: Int) -> some View {
        modifier(Toast(message: message, trigger: trigger))
    }

    func display(_ size: CGFloat) -> some View {
        font(Theme.display(size)).tracking(-size * 0.035)
    }

    /// A translucent tile that sits on the menu material.
    func tile() -> some View {
        background(Theme.quietWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Format {
    static func seconds(_ value: Double) -> String {
        value < 10 ? String(format: "%.1fs", value) : "\(Int(value.rounded()))s"
    }

    static func clock(since start: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "4 min" or "1 hr 12 min".
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(60, seconds)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
