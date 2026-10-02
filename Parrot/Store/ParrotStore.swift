import AppKit
import Observation

/// Runs dictation: Option tap starts recording, the next tap stops it, transcribes with the
/// chosen engine, pastes the text, and adds it to history.
@MainActor @Observable
final class ParrotStore {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        /// Heard the wake word on its own, waiting for what comes next.
        case awaitingWords(since: Date)
        /// Heard the wake word while the speaker is still talking. Ends when they pause.
        case hearing(since: Date)
        case transcribing
    }

    enum HandsFree: Equatable {
        case off
        case loading
        case listening
        /// The chosen microphone isn't connected. Parrot never falls back to another one.
        case waitingForMic
        /// The screen is locked or asleep.
        case paused
        case failed(String)
    }

    enum CallState: Equatable {
        case off
        case recording(since: Date)
        /// Transcribing what's left after the call ended.
        case finishing
        case summarizing
    }

    enum EngineState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase = Phase.idle
    private(set) var engineStates: [EngineID: EngineState] = [:]
    /// The last problem worth showing, cleared by the next successful dictation.
    private(set) var notice: String?
    private(set) var accessibility = Permissions.accessibility

    let history = History()
    let vocabulary = Vocabulary()
    let calls = Calls()
    private(set) var callState = CallState.off
    /// Utterances from the current call still waiting to be transcribed.
    private(set) var callBacklog = 0
    /// The call being recorded, then the last one recorded.
    private(set) var call: Call?
    /// Calls whose summary is being written.
    private(set) var summarizing: Set<UUID> = []
    private(set) var inputs: [AudioInput] = AudioInputs.all()
    private(set) var handsFree = HandsFree.off

    /// The microphone for both modes. nil is the system default.
    var inputUID: String? {
        didSet {
            UserDefaults.standard.set(inputUID, forKey: Keys.input)
            updateListener()
        }
    }

    /// Listen all the time for the wake word.
    var handsFreeOn: Bool {
        didSet {
            UserDefaults.standard.set(handsFreeOn, forKey: Keys.handsFree)
            updateListener()
        }
    }

    /// The word that starts hands-free dictation, as the user typed it.
    var wakeWord: String {
        didSet { UserDefaults.standard.set(wakeWord, forKey: Keys.wakeWord) }
    }

    /// The wake word as Parrot hears it, for showing: "Hey jarvis!" is "Jarvis".
    var wakeWordName: String {
        (WakeWord.normalized(wakeWord) ?? WakeWord.standard).capitalized
    }

    /// Tidy punctuation and drop filler words with Apple's on-device model before pasting.
    var cleanupOn: Bool {
        didSet { UserDefaults.standard.set(cleanupOn, forKey: Keys.cleanup) }
    }

    var engineID: EngineID {
        didSet {
            UserDefaults.standard.set(engineID.rawValue, forKey: Keys.engine)
            warm(engineID)
        }
    }

    @ObservationIgnored private let recorder = Recorder()
    @ObservationIgnored private var engines: [EngineID: any TranscriptionEngine] = [:]
    @ObservationIgnored private var loads: [EngineID: Task<any TranscriptionEngine, any Error>] = [:]
    @ObservationIgnored private lazy var monitor = OptionTapMonitor { [weak self] in self?.toggle() }
    @ObservationIgnored private let listener = WakeListener()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var screenAway = false
    @ObservationIgnored private var awaitingTimeout: Task<Void, Never>?
    /// The utterance being checked for the wake word before it ends, by its start time.
    /// `settled` once it woke Parrot, clearly didn't, or ended. `heard` is what followed the wake
    /// word once it woke Parrot.
    @ObservationIgnored private var early: (start: Date, settled: Bool, checking: Bool, heard: String?)?
    /// The utterance that woke Parrot early, then was cancelled. Its ending is ignored.
    @ObservationIgnored private var cancelledStart: Date?
    @ObservationIgnored private let capture = CallCapture()
    @ObservationIgnored private var callWork: [Task<Void, Never>] = []
    @ObservationIgnored private let cleaner: any Cleaner = AppleCleaner()

    init() {
        engineID = UserDefaults.standard.string(forKey: Keys.engine).flatMap(EngineID.init) ?? .default
        inputUID = UserDefaults.standard.string(forKey: Keys.input)
        handsFreeOn = UserDefaults.standard.bool(forKey: Keys.handsFree)
        wakeWord = UserDefaults.standard.string(forKey: Keys.wakeWord) ?? WakeWord.standard
        cleanupOn = UserDefaults.standard.object(forKey: Keys.cleanup) as? Bool ?? true
    }

    /// The chosen microphone, if it's plugged in.
    var input: AudioInput? {
        inputUID.flatMap { uid in inputs.first { $0.uid == uid } }
    }

    /// Called once the menu bar item appears.
    func start() {
        // Unit tests run inside the app and shouldn't listen to the keyboard or load models.
        guard !started, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        started = true
        monitor.start()
        warm(engineID)
        AudioInputs.onChange { [weak self] in
            guard let self else { return }
            inputs = AudioInputs.all()
            updateListener()
        }
        watchScreen()
        updateListener()
        if !Permissions.accessibility { Permissions.promptForAccessibility() }
        // Accessibility is granted in System Settings with no callback, so check back now and then.
        Task {
            while true {
                let trusted = Permissions.accessibility
                // Monitors installed before the grant can stay deaf to other apps, so start over.
                if trusted && !accessibility { monitor.restart() }
                accessibility = trusted
                try? await Task.sleep(for: .seconds(accessibility ? 30 : 2))
            }
        }
    }

    func toggle() {
        switch phase {
        case .idle: startRecording()
        case .recording: Task { await finishRecording() }
        case .awaitingWords, .hearing: cancel()
        case .transcribing: break
        }
    }

    /// Stops without transcribing.
    func cancel() {
        switch phase {
        case .recording: _ = recorder.stop()
        case .awaitingWords: awaitingTimeout?.cancel()
        case .hearing: cancelledStart = early?.start
        default: return
        }
        phase = .idle
        Sound.cancel.play()
    }

    private func startRecording() {
        switch Permissions.microphone {
        case .notDetermined:
            Task {
                if await Permissions.requestMicrophone() { startRecording() }
            }
            return
        case .denied, .restricted:
            notice = "Parrot needs the microphone. Turn it on in System Settings."
            Permissions.openMicrophoneSettings()
            return
        default:
            break
        }
        do {
            try recorder.start(from: input)
            phase = .recording(since: .now)
            Sound.start.play()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func finishRecording() async {
        guard case .recording(let since) = phase else { return }
        let samples = recorder.stop()
        Sound.stop.play()
        let audio = Double(samples.count) / Recorder.sampleRate
        // Shorter than this is a double tap, not speech.
        guard audio >= 0.3 else {
            phase = .idle
            return
        }
        phase = .transcribing
        defer { phase = .idle }

        let id = engineID
        let clock = ContinuousClock.now
        do {
            let text = try await engine(id).transcribe(samples).trimmingCharacters(in: .whitespacesAndNewlines)
            await deliver(text, samples: samples, since: since, engine: id, startedWork: clock)
        } catch {
            notice = "\(id.name) failed: \(error.localizedDescription)"
        }
    }

    private func deliver(_ heard: String, samples: [Float], since: Date, engine id: EngineID, startedWork: ContinuousClock.Instant) async {
        guard !heard.isEmpty else {
            notice = "Parrot didn't hear any words."
            return
        }
        let text = await polish(heard)
        let latency = (ContinuousClock.now - startedWork) / .seconds(1)
        let audio = Double(samples.count) / Recorder.sampleRate
        history.add(Dictation(date: since, text: text, engine: id.rawValue, audio: audio, latency: latency, raw: text == heard ? nil : heard), samples: samples)
        notice = await Paster.paste(text) ? nil : "Copied. Give Parrot Accessibility access to paste for you."
    }

    /// Custom vocabulary, then cleanup if it's on.
    private func polish(_ heard: String) async -> String {
        let terms = vocabulary.terms
        let text = Vocabulary.apply(terms, to: heard)
        guard cleanupOn, AppleCleaner.isAvailable else { return text }
        return await Cleanup.guarded(text, with: cleaner, vocabulary: terms.map(\.text))
    }

    // MARK: Hands-free

    /// Starts or stops listening to match the setting, the microphone, and the screen.
    private func updateListener() {
        guard started else { return }
        // A restart loses the utterance being heard, so don't wait for its end.
        if case .hearing = phase { phase = .idle }
        early = nil
        guard handsFreeOn else {
            listener.stop()
            handsFree = .off
            return
        }
        guard !screenAway else {
            listener.stop()
            handsFree = .paused
            return
        }
        // Hands-free needs a chosen microphone. Listening on the built-in mic all day by accident
        // would be a surprise, so an unplugged mic means wait, not fall back.
        guard let input else {
            listener.stop()
            handsFree = .waitingForMic
            return
        }
        guard Permissions.microphone == .authorized else {
            Task {
                if await Permissions.requestMicrophone() { updateListener() }
            }
            return
        }
        handsFree = .loading
        listener.start(from: input) { [weak self] partial in
            self?.heardPartial(partial)
        } onUtterance: { [weak self] utterance in
            self?.heard(utterance)
        } onFailure: { [weak self] message in
            guard let self else { return }
            listener.stop()
            inputs = AudioInputs.all()
            if input.uid == inputUID, inputs.contains(input) {
                handsFree = .failed(message)
            } else {
                updateListener()
            }
        }
        // The detector loads within a second or two. It reports failure through the callback.
        Task {
            try? await Task.sleep(for: .seconds(1))
            if handsFree == .loading { handsFree = .listening }
        }
    }

    /// Checks the start of an utterance while it's still going, so the start sound plays as soon
    /// as the wake word is said instead of after the pause.
    private func heardPartial(_ partial: WakeListener.Utterance) {
        guard phase == .idle else { return }
        if early?.start != partial.startedAt { early = (partial.startedAt, false, false, nil) }
        guard let current = early, !current.settled, !current.checking else { return }
        early?.checking = true
        Task {
            let text = (try? await engine(engineID).transcribe(partial.samples)) ?? ""
            // The utterance may have ended, or another begun, while this ran.
            guard early?.start == partial.startedAt, early?.settled == false else { return }
            early?.checking = false
            if let rest = WakeWord.match(text, word: wakeWord), phase == .idle {
                early?.settled = true
                early?.heard = rest
                phase = .hearing(since: .now)
                Sound.start.play()
            } else if WordErrorRate.words(text).count >= 2 {
                // It started with other words, so it isn't for Parrot.
                early?.settled = true
            }
        }
    }

    private func heard(_ utterance: WakeListener.Utterance) {
        handsFree = .listening
        var wokeEarly = false
        if case .hearing = phase, early?.start == utterance.startedAt { wokeEarly = true }
        if early?.start == utterance.startedAt { early?.settled = true }
        if cancelledStart == utterance.startedAt {
            cancelledStart = nil
            return
        }
        switch phase {
        case .hearing:
            guard wokeEarly else { return }
            Task { await transcribeHandsFree(utterance, heardStart: early?.heard ?? "") }
        case .idle:
            Task { await checkForWakeWord(utterance) }
        case .awaitingWords(let since):
            // Skip anything that began before the wake word was confirmed, like Parrot's own coo.
            guard utterance.startedAt > since.addingTimeInterval(0.3) else { return }
            awaitingTimeout?.cancel()
            Task { await transcribeHandsFree(utterance) }
        case .recording, .transcribing:
            break
        }
    }

    /// Transcribes only the first couple of seconds, which is enough to hear the wake word. Most
    /// utterances aren't meant for Parrot, so this keeps the work small.
    private func checkForWakeWord(_ utterance: WakeListener.Utterance) async {
        let head = Array(utterance.samples.prefix(Int(2.5 * Recorder.sampleRate)))
        guard let text = try? await engine(engineID).transcribe(head) else { return }
        let match = WakeWord.match(text, word: wakeWord)
        if head.count == utterance.samples.count { WakeLog.add(text, triggered: match != nil) }
        guard let rest = match, phase == .idle else { return }
        if rest.isEmpty && head.count == utterance.samples.count {
            awaitWords(playSound: true)
        } else {
            await transcribeHandsFree(utterance, heardStart: rest)
        }
    }

    /// The wake word was said on its own. Wait a few seconds for what comes next.
    private func awaitWords(playSound: Bool) {
        phase = .awaitingWords(since: .now)
        if playSound { Sound.start.play() }
        awaitingTimeout = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, case .awaitingWords = phase else { return }
            phase = .idle
            Sound.cancel.play()
        }
    }

    /// - Parameter heardStart: what followed the wake word at the utterance's start. nil when the
    ///   wake word came in an earlier utterance, said on its own.
    private func transcribeHandsFree(_ utterance: WakeListener.Utterance, heardStart: String? = nil) async {
        phase = .transcribing
        let id = engineID
        let clock = ContinuousClock.now
        do {
            var text = try await engine(id).transcribe(utterance.samples).trimmingCharacters(in: .whitespacesAndNewlines)
            if let heardStart {
                // The start already matched, so keep the dictation even if the whole utterance
                // hears the wake word differently. Long ones often do.
                text = WakeWord.rest(of: text, heardStart: heardStart, word: wakeWord)
            }
            guard !text.isEmpty else {
                // The wake word said on its own: wait for the words. The start sound already
                // played if it woke Parrot before the pause.
                if heardStart != nil { awaitWords(playSound: early?.start != utterance.startedAt || early?.heard == nil) } else { phase = .idle }
                return
            }
            defer { phase = .idle }
            Sound.stop.play()
            await deliver(text, samples: utterance.samples, since: utterance.startedAt, engine: id, startedWork: clock)
        } catch {
            phase = .idle
            notice = "\(id.name) failed: \(error.localizedDescription)"
        }
    }

    /// Stops listening while the screen is locked or asleep, and picks back up after.
    private func watchScreen() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let away: [(NotificationCenter, Notification.Name, Bool)] = [
            (workspace, NSWorkspace.screensDidSleepNotification, true),
            (workspace, NSWorkspace.screensDidWakeNotification, false),
            (distributed, Notification.Name("com.apple.screenIsLocked"), true),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), false),
        ]
        for (center, name, isAway) in away {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.screenAway != isAway else { return }
                    self.screenAway = isAway
                    self.updateListener()
                }
            }
        }
    }

    // MARK: Calls

    /// Records both sides of a call and transcribes it as it goes. Uses the chosen microphone if
    /// it's connected, otherwise the system default.
    func startCall() {
        guard callState == .off else { return }
        guard Permissions.microphone == .authorized else {
            Task {
                if await Permissions.requestMicrophone() { startCall() } else { notice = "Parrot needs the microphone to record your side of a call." }
            }
            return
        }
        let call = Call(started: .now)
        self.call = call
        do {
            try capture.start(mic: input) { [weak self] speaker, utterance in
                self?.transcribe(utterance, from: speaker)
            } onFailure: { [weak self] message in
                self?.notice = "Call recording: \(message)"
            }
        } catch {
            self.call = nil
            notice = error.localizedDescription
            return
        }
        calls.save(call)
        callState = .recording(since: call.started)
        notice = nil
    }

    func stopCall() {
        guard case .recording = callState else { return }
        callState = .finishing
        Task {
            await capture.stop()
            for work in callWork { await work.value }
            callWork = []
            guard var call else { return }
            call.ended = .now
            call.removeEcho()
            self.call = call
            calls.save(call)
            callState = .summarizing
            await summarize(call)
            callState = .off
        }
    }

    /// Writes or rewrites a call's summary.
    func summarize(_ call: Call) async {
        summarizing.insert(call.id)
        defer { summarizing.remove(call.id) }
        do {
            var call = call
            call.summary = try await Summarizer.summarize(call)
            calls.save(call)
            if self.call?.id == call.id { self.call = call }
        } catch {
            notice = "Couldn't summarize the call: \(error.localizedDescription) The transcript is saved."
        }
    }

    private func transcribe(_ utterance: WakeListener.Utterance, from speaker: Call.Speaker) {
        callBacklog += 1
        let id = engineID
        callWork.append(Task {
            defer { callBacklog -= 1 }
            guard let heard = try? await engine(id).transcribe(utterance.samples) else { return }
            let text = Vocabulary.apply(vocabulary.terms, to: heard.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !text.isEmpty, call != nil else { return }
            call?.insert(Call.Line(speaker: speaker, at: utterance.startedAt, text: text))
            // Save now and then, so a crash doesn't lose the whole call.
            if let call, call.lines.count % 10 == 0 { calls.save(call) }
        })
    }

    // MARK: Engines

    /// The engine, loaded. Loads it on first use and shares that load with anyone else waiting.
    func engine(_ id: EngineID) async throws -> any TranscriptionEngine {
        if let ready = engines[id] {
            // Returns at once unless the vocabulary changed since the last call.
            await ready.useVocabulary(vocabulary.terms)
            return ready
        }
        let task = loads[id] ?? {
            engineStates[id] = .loading
            let task = Task<any TranscriptionEngine, any Error> {
                let engine = id.make()
                try await engine.prepare()
                return engine
            }
            loads[id] = task
            return task
        }()
        do {
            let engine = try await task.value
            engines[id] = engine
            engineStates[id] = .ready
            await engine.useVocabulary(vocabulary.terms)
            return engine
        } catch {
            loads[id] = nil
            engineStates[id] = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Unloads a model and deletes its download to free memory and disk. The model in use and one
    /// that's still loading stay, since deleting them would only start the download again.
    func deleteModel(_ id: EngineID) throws {
        guard id != engineID, engineStates[id] != .loading, let folder = id.downloadFolder else { return }
        engines[id] = nil
        loads[id] = nil
        engineStates[id] = nil
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// Loads the engine in the background, so the first dictation doesn't wait on a download.
    func warm(_ id: EngineID) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { _ = try? await engine(id) }
    }

    /// Runs one past recording through an engine, for side-by-side comparison.
    func rerun(_ entry: Dictation, with id: EngineID) async throws -> (text: String, seconds: Double) {
        let samples = try WAV.read(History.clip(for: entry))
        let engine = try await engine(id)
        let clock = ContinuousClock.now
        let text = try await engine.transcribe(samples)
        return (text, (ContinuousClock.now - clock) / .seconds(1))
    }
}

/// Short utterances heard while listening hands-free, and whether they woke Parrot. Saying "Oy"
/// and reading what the model wrote shows which spellings to add to `WakeWord`. Keeps the last
/// 300 lines, in wake-log.txt next to the history.
enum WakeLog {
    nonisolated static let file = History.folder.appending(path: "wake-log.txt")

    static func add(_ text: String, triggered: Bool) {
        let line = "\(Date.now.formatted(.iso8601))\t\(triggered ? "WOKE" : "-")\t\(text)"
        let lines = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").suffix(299).map(String.init) + [line]
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }
}

enum Keys {
    static let engine = "engine"
    static let input = "input"
    static let handsFree = "handsFree"
    static let cleanup = "cleanup"
    static let wakeWord = "wakeWord"
}

/// Short sounds for start, stop, and cancel: deep parrot calls for start and cancel, a soft
/// abstract chirp for stop. Made with ElevenLabs sound effects; see scripts/make-sounds.sh.
enum Sound: String {
    case start, stop, cancel

    @MainActor private static var loaded: [Sound: NSSound] = [:]

    @MainActor func play() {
        let sound = Self.loaded[self] ?? Bundle.main.url(forResource: rawValue, withExtension: "wav").flatMap { NSSound(contentsOf: $0, byReference: true) }
        Self.loaded[self] = sound
        sound?.stop()
        sound?.play()
    }
}
