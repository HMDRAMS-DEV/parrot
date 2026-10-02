import AppKit
import ApplicationServices
import AVFoundation

/// Puts text into whatever field has focus: copies it, presses Command-V, then puts back what was
/// on the clipboard before.
@MainActor
enum Paster {
    /// Returns false when it could only copy, because Parrot lacks Accessibility access.
    static func paste(_ text: String) async -> Bool {
        let board = NSPasteboard.general
        let saved = snapshot(board)

        board.clearContents()
        board.setString(text, forType: .string)
        // Clipboard managers skip items marked transient, so dictation doesn't flood their history.
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ours = board.changeCount

        guard Permissions.accessibility else { return false }
        pressCommandV()

        // Give the target app time to read the clipboard before restoring it.
        try? await Task.sleep(for: .milliseconds(500))
        if board.changeCount == ours, !saved.isEmpty {
            board.clearContents()
            board.writeObjects(saved)
        }
        return true
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(_ board: NSPasteboard) -> [NSPasteboardItem] {
        (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }
}

@MainActor
enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }

    static var microphone: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    /// Shows the system prompt that sends people to Privacy & Security, once per launch at most.
    static func promptForAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
