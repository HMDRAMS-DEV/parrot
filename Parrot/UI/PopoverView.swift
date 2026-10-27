import SwiftUI

struct MenuBarLabel: View {
    @Environment(ParrotStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: store.phase, onCall: store.callState != .off))
            .task {
                // The menu bar is always there, so it hands the store a way to open Calls when a
                // call's summary is ready, even if the popover is closed.
                store.openCallsWindow = { openWindow(id: WindowID.calls) }
                store.start()
            }
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

            if let pending = store.pendingDownload {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download \(pending.name)?").font(.system(size: 13, weight: .semibold))
                        Text("It downloads once and stays on this Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") { store.pendingDownload = nil }.buttonStyle(PillButtonStyle(prominent: false))
                        Button("Download") { store.confirmDownload() }.buttonStyle(PillButtonStyle())
                    }
                }
                .padding(12)
                .tile()
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
        SettingsTile {
            SettingRow("Model", note: status) {
                Picker("Model", selection: engine) {
                    ForEach(EngineID.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .buttonSizing(.flexible)
                .frame(width: pickerWidth)
            }
            .help(store.engineID.detail)
            SettingRow("Cleanup", note: cleanerStatus) {
                Picker("Cleanup", selection: cleaner) {
                    Text("Off").tag(CleanerID?.none)
                    ForEach(CleanerID.allCases) { Text($0.name).tag(Optional($0)) }
                }
                .labelsHidden()
                .buttonSizing(.flexible)
                .frame(width: pickerWidth)
            }
            .help("Fixes punctuation and drops um and uh. If it changes your words, Parrot keeps the original." + (store.cleanupOn ? "\n\n" + store.cleanerID.detail : ""))
        }
    }

    /// The picked model, or a question first when it isn't downloaded.
    private var engine: Binding<EngineID> {
        Binding {
            store.engineID
        } set: { id in
            if id.isDownloaded { store.engineID = id } else { store.pendingDownload = .engine(id) }
        }
    }

    /// Off, or which model cleans up. Off keeps the last model picked for next time.
    private var cleaner: Binding<CleanerID?> {
        Binding {
            store.cleanupOn ? store.cleanerID : nil
        } set: { id in
            if let id, !id.isDownloaded {
                store.pendingDownload = .cleaner(id)
                return
            }
            // Pick the model first, so turning cleanup on warms the right one.
            if let id { store.cleanerID = id }
            store.cleanupOn = id != nil
        }
    }

    /// Only problems and loading. What each model is lives in the tooltip.
    private var cleanerStatus: String? {
        guard store.cleanupOn else { return nil }
        switch store.cleanerID {
        case .apple where !AppleCleaner.isAvailable: return "Needs Apple Intelligence, which is off or unsupported on this Mac."
        case .s1Mini:
            switch store.cleanerState {
            case .loading: return loading(store.cleanerProgress) + " Dictation works meanwhile, without cleanup."
            case .failed(let message): return "Couldn't load: \(message)"
            case .ready, nil: return nil
            }
        default: return nil
        }
    }

    private var status: String? {
        switch store.engineStates[store.engineID] {
        case .loading: loading(store.engineProgress[store.engineID])
        case .failed(let message): "Couldn't load: \(message)"
        case .ready, nil: nil
        }
    }

    private func loading(_ progress: Double?) -> String {
        guard let progress, progress < 1 else { return "Loading the model…" }
        return "Loading the model, \(Int(progress * 100))%."
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
                .buttonSizing(.flexible)
                .frame(width: pickerWidth)
            }
            SettingRow("Listen for “\(store.wakeWordName)”", note: store.handsFreeOn ? status : nil) {
                Toggle("Listen for “\(store.wakeWordName)”", isOn: $store.handsFreeOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .help("Say “\(store.wakeWordName)”, then what you want typed. Stop talking for a second to finish.")
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

    /// The status line up top already says what to say, so listening needs no note.
    private var status: String? {
        switch store.handsFree {
        case .off, .loading: "Starting…"
        case .listening: nil
        case .waitingForMic: store.inputUID == nil ? "Pick a microphone above. Parrot only listens hands-free on one you choose." : "Waiting for the microphone to connect."
        case .paused: "Paused while the screen is locked."
        case .failed(let message): "Stopped: \(message)"
        }
    }
}

/// Reminders before calls on the calendar, and which calendar to watch.
struct MeetingsTile: View {
    @Environment(ParrotStore.self) private var store

    var body: some View {
        @Bindable var meetings = store.meetings
        SettingsTile {
            SettingRow("Meeting reminders", note: meetings.on ? problem : nil) {
                Toggle("Meeting reminders", isOn: $meetings.on)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .help("Two minutes before a Google Meet, Zoom, or Teams call on your calendar, Parrot offers to join it and take notes.")
            if meetings.on, meetings.calendarAccess == .fullAccess {
                SettingRow("Calendar") {
                    Picker("Calendar", selection: $meetings.calendarID) {
                        Text("All calendars").tag(String?.none)
                        ForEach(meetings.calendars) { Text($0.title).tag(Optional($0.id)) }
                        if let id = meetings.calendarID, !meetings.calendars.contains(where: { $0.id == id }) {
                            Text("Not found").tag(Optional(id))
                        }
                    }
                    .labelsHidden()
                    .buttonSizing(.flexible)
                    .frame(width: pickerWidth)
                }
            }
            if meetings.on, problem != nil {
                Button("Open System Settings") { meetings.openSettings() }.buttonStyle(PillButtonStyle())
            }
        }
    }

    private var problem: String? {
        switch store.meetings.calendarAccess {
        case .notDetermined, .fullAccess: store.meetings.notificationsAllowed ? nil : "Notifications are off for Parrot."
        default: "Parrot can't see your calendar."
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
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            switch store.callState {
            case .off:
                if let meeting = store.meetings.current {
                    Button("Take notes") { store.takeNotes(meeting) }.buttonStyle(PillButtonStyle())
                } else {
                    if let call = store.call, call.summary != nil {
                        Button("Open") { openCalls() }.buttonStyle(.borderless).font(.system(size: 13))
                    }
                    Button("Record") { store.startCall() }.buttonStyle(PillButtonStyle())
                }
            case .recording:
                Button("Open") { openCalls() }.buttonStyle(.borderless).font(.system(size: 13))
                Button("Stop") { store.stopCall() }.buttonStyle(PillButtonStyle())
            case .finishing, .summarizing:
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
        .tile()
        .help("Records you and the other side, then writes a summary. Everything stays on this Mac.")
    }

    @ViewBuilder private var title: some View {
        if case .recording(let since) = store.callState {
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text("Recording call \(Format.clock(since: since, now: context.date))").monospacedDigit()
            }
        } else if store.callState == .off, let meeting = store.meetings.current {
            Text(meeting.title).lineLimit(1)
        } else {
            Text("Call notes")
        }
    }

    private var detail: String? {
        switch store.callState {
        case .off:
            if let meeting = store.meetings.current {
                let time = meeting.start.formatted(date: .omitted, time: .shortened)
                return meeting.start > .now ? "\(meeting.service) at \(time)" : "\(meeting.service), started at \(time)"
            }
            if let call = store.call, call.summary != nil { return "Summary ready: \(call.title)" }
            return nil
        case .recording:
            // The latest line, so the call reads live from the menu.
            guard let line = store.call?.lines.last else { return "Listening to both sides." }
            return (store.callBacklog > 2 ? "Catching up. " : "") + "\(line.speaker.label): \(line.text)"
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

/// Every menu in the popover is this wide, so their edges line up. Menus hug their
/// text unless sized `.flexible`.
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
