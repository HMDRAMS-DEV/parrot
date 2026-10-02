import SwiftUI

struct MenuBarLabel: View {
    @Environment(ParrotStore.self) private var store

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: store.phase, onCall: store.callState != .off))
            .task { store.start() }
    }
}

/// Sits on the system menu material, like Pacer's.
struct PopoverView: View {
    @Environment(ParrotStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var copies = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Wordmark(size: 20, recording: isRecording)
                Spacer()
                StatusText()
            }

            if let version = Updater.shared.available {
                HStack {
                    Text("Parrot \(version) is ready.").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("Update") { Updater.shared.check() }.buttonStyle(PillButtonStyle())
                }
                .padding(12)
                .tile()
            }

            if !store.accessibility {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow Accessibility").font(.system(size: 13, weight: .semibold))
                        Text("Parrot needs it to hear the Option key and paste for you.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Open") { Permissions.openAccessibilitySettings() }.buttonStyle(PillButtonStyle())
                }
                .padding(12)
                .tile()
            }

            if let notice = store.notice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            EnginePicker()

            HandsFreeTile()

            CallTile()

            recent

            footer
        }
        .padding(14)
        .frame(width: 320)
        .toast("Copied", trigger: copies)
    }

    private var isRecording: Bool {
        switch store.phase {
        case .recording, .awaitingWords, .hearing: true
        default: false
        }
    }

    @ViewBuilder private var recent: some View {
        let entries = store.history.entries.prefix(3)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    Button {
                        copyToClipboard(entry.text)
                        copies += 1
                    } label: {
                        Text(entry.text)
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                }
            }
            .padding(.vertical, 4)
            .tile()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("History") { open(WindowID.history) }
            Button("Calls") { open(WindowID.calls) }
            Button("Vocabulary") { open(WindowID.vocabulary) }
            Spacer()
            Menu {
                Button("Settings…") { showSettings() }
                    .keyboardShortcut(",")
                Button("Check for Updates…") { Updater.shared.check() }
                Button("Open Eval Folder") { NSWorkspace.shared.open(History.evalSet.creatingDirectory()) }
                Button("Open Wake Log") { NSWorkspace.shared.open(WakeLog.file) }
                    .disabled(!FileManager.default.fileExists(atPath: WakeLog.file.path))
                Divider()
                Button("Quit Parrot") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.system(size: 13))
        .buttonStyle(.borderless)
    }

    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }

    private func showSettings() {
        // A menu bar app isn't active, so bring it forward or the window opens behind others.
        NSApp.activate()
        openSettings()
    }
}

private struct StatusText: View {
    @Environment(ParrotStore.self) private var store

    var body: some View {
        Group {
            switch store.phase {
            case .idle:
                Text(store.handsFree == .listening ? "Say “\(store.wakeWordName)” or tap ⌥" : "Tap ⌥ to dictate")
            case .recording(let since):
                HStack(spacing: 8) {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text("Listening \(Format.clock(since: since, now: context.date))").monospacedDigit()
                    }
                    Button("Cancel") { store.cancel() }.buttonStyle(.borderless)
                }
            case .awaitingWords, .hearing:
                HStack(spacing: 8) {
                    Text(isHearing ? "Listening…" : "Go ahead")
                    Button("Cancel") { store.cancel() }.buttonStyle(.borderless)
                }
            case .transcribing:
                Text("Writing it down…")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var isHearing: Bool {
        if case .hearing = store.phase { true } else { false }
    }
}

struct EnginePicker: View {
    @Environment(ParrotStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SettingsTile {
            SettingRow("Model", note: status) {
                Picker("Model", selection: $store.engineID) {
                    ForEach(EngineID.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .frame(width: pickerWidth)
            }
            if AppleCleaner.isAvailable {
                SettingRow("Fix punctuation, drop fillers") {
                    Toggle("Fix punctuation, drop fillers", isOn: $store.cleanupOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .help("Apple's on-device model fixes punctuation and drops um and uh. If it changes your words, Parrot keeps the original.")
            }
        }
    }

    private var status: String {
        switch store.engineStates[store.engineID] {
        case .loading: "Loading the model. The first time, this includes a download."
        case .failed(let message): "Couldn't load: \(message)"
        case .ready, nil: store.engineID.detail
        }
    }
}

/// The microphone, and whether to listen for the wake word all the time.
struct HandsFreeTile: View {
    @Environment(ParrotStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SettingsTile {
            SettingRow("Microphone") {
                Picker("Microphone", selection: $store.inputUID) {
                    Text("System default").tag(String?.none)
                    ForEach(store.inputs) { Text($0.name).tag(Optional($0.uid)) }
                    if let uid = store.inputUID, store.input == nil {
                        Text("Not connected").tag(Optional(uid))
                    }
                }
                .labelsHidden()
                .frame(width: pickerWidth)
            }
            SettingRow("Listen for “\(store.wakeWordName)”", note: store.handsFreeOn ? status : nil) {
                Toggle("Listen for “\(store.wakeWordName)”", isOn: $store.handsFreeOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if store.handsFreeOn {
                SettingRow("Wake word") {
                    TextField("Wake word", text: $store.wakeWord, prompt: Text(WakeWord.standard))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: pickerWidth)
                }
                .help("One word. A short, unusual word works best, since everyday words wake Parrot by mistake. Oy and Parrot also catch common mishearings.")
            }
        }
    }

    private var status: String {
        switch store.handsFree {
        case .off, .loading: "Starting…"
        case .listening: "Say “\(store.wakeWordName)”, then what you want typed. Stop talking for a second to finish."
        case .waitingForMic: store.inputUID == nil ? "Pick a microphone above. Parrot only listens hands-free on one you choose." : "Waiting for the microphone to connect."
        case .paused: "Paused while the screen is locked."
        case .failed(let message): "Stopped: \(message)"
        }
    }
}

/// Record a call, see how it's going, and open the summary when it's done.
private struct CallTile: View {
    @Environment(ParrotStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                title.font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            switch store.callState {
            case .off:
                if let call = store.call, call.summary != nil {
                    Button("Open") { openCalls() }.buttonStyle(.borderless).font(.system(size: 13))
                }
                Button("Record") { store.startCall() }.buttonStyle(PillButtonStyle())
            case .recording:
                Button("Stop") { store.stopCall() }.buttonStyle(PillButtonStyle())
            case .finishing, .summarizing:
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
        .tile()
    }

    @ViewBuilder private var title: some View {
        if case .recording(let since) = store.callState {
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text("Recording call \(Format.clock(since: since, now: context.date))").monospacedDigit()
            }
        } else {
            Text("Call notes")
        }
    }

    private var detail: String {
        let lines = store.call?.lines.count ?? 0
        switch store.callState {
        case .off:
            if let call = store.call, call.summary != nil { return "Summary ready: \(call.title)" }
            return "Records you and the other side, then writes a summary. Everything stays on this Mac."
        case .recording:
            return lines == 0 ? "Listening to both sides." : "\(lines) lines so far." + (store.callBacklog > 2 ? " Catching up." : "")
        case .finishing:
            return "Writing down the last words…"
        case .summarizing:
            return "Writing the summary…"
        }
    }

    private func openCalls() {
        openWindow(id: WindowID.calls)
        NSApp.activate()
    }
}

/// Every menu in the popover is this wide, so their edges line up.
private let pickerWidth: CGFloat = 160

/// A tile of setting rows, evenly spaced.
private struct SettingsTile<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(12)
            .tile()
    }
}

/// A setting: label on the left, control flush right, an optional note under both.
private struct SettingRow<Control: View>: View {
    let label: String
    let note: String?
    @ViewBuilder let control: Control

    init(_ label: String, note: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.note = note
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                control
            }
            .frame(minHeight: 22)
            if let note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum WindowID {
    static let history = "history"
    static let calls = "calls"
    static let vocabulary = "vocabulary"
}

extension URL {
    func creatingDirectory() -> URL {
        try? FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}
