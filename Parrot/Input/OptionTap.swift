import AppKit

/// Recognizes a tap of Option on its own: down and up, quickly, with no other key, modifier, or
/// click in between. Option-shortcuts and Option-drags still reach other apps untouched.
struct OptionTapDetector {
    /// A longer hold is someone reaching for a shortcut and changing their mind, not a tap.
    var maxHold: TimeInterval = 0.5

    private enum State {
        case idle
        case armed(since: TimeInterval)
        /// Something else happened while Option was down. Waits for every modifier to lift.
        case spoiled
    }

    private var state = State.idle

    /// Feeds a modifier change. Returns true when it completes a tap.
    mutating func modifiersChanged(option: Bool, others: Bool, at time: TimeInterval) -> Bool {
        switch state {
        case .idle:
            if option { state = others ? .spoiled : .armed(since: time) }
        case .armed(let since):
            if others {
                state = .spoiled
            } else if !option {
                state = .idle
                return time - since <= maxHold
            }
        case .spoiled:
            if !option && !others { state = .idle }
        }
        return false
    }

    /// Feeds a key press or click.
    mutating func interrupted() {
        if case .armed = state { state = .spoiled }
    }
}

/// Watches every app's key events for an Option tap. macOS only delivers them once Parrot has
/// Accessibility access; until then the monitors are installed but silent.
@MainActor
final class OptionTapMonitor {
    private var detector = OptionTapDetector()
    private var monitors: [Any] = []
    private let onTap: @MainActor () -> Void

    init(onTap: @escaping @MainActor () -> Void) {
        self.onTap = onTap
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func restart() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        detector = OptionTapDetector()
        start()
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged else {
            detector.interrupted()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function, .numericPad])
        let option = flags.contains(.option)
        let others = !flags.subtracting(.option).isEmpty
        if detector.modifiersChanged(option: option, others: others, at: event.timestamp) {
            onTap()
        }
    }
}
