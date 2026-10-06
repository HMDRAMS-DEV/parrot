import AVFoundation
import Synchronization

/// Records a microphone as 16 kHz mono Float samples, the format every engine takes.
@MainActor
final class Recorder {
    nonisolated static let sampleRate: Double = 16_000

    private var session: MicSession?
    /// A fresh buffer per recording, so audio that arrives while the last session winds down
    /// can't leak into the next one.
    private var samples = Samples()

    /// Records from `input`, or the system default when it's nil or unplugged.
    func start(from input: AudioInput?) async throws {
        let collected = Samples()
        samples = collected
        session = try await MicSession.open(from: input) { chunk in collected.append(chunk) }
    }

    /// Stops recording and returns everything captured since `start()`.
    func stop() -> [Float] {
        session?.stop()
        session = nil
        return samples.take()
    }

    private final class Samples: Sendable {
        private let buffer = Mutex<[Float]>([])

        func append(_ chunk: [Float]) {
            buffer.withLock { $0.append(contentsOf: chunk) }
        }

        func take() -> [Float] {
            buffer.withLock { taken in
                defer { taken = [] }
                return taken
            }
        }
    }
}

/// An audio engine on a microphone, handing 16 kHz mono chunks to `deliver` on the audio
/// thread. Each session gets a fresh engine, so switching microphones is clean.
///
/// Core Audio can spin for minutes while a new engine reads the microphone's format, holding
/// whatever thread asked. So a session opens, restarts, and stops on its own queue, never the
/// main thread, and `open` gives up after `timeout`. A stalled session can't be cancelled, but
/// it no longer freezes Parrot, and the next one gets a fresh engine on a fresh queue.
final class MicSession: @unchecked Sendable {
    static let timeout: TimeInterval = 5

    private let engine = AVAudioEngine()
    private let queue: DispatchQueue
    /// Only touched on `queue`.
    private var observer: (any NSObjectProtocol)?

    /// Opens a session off the main thread. Throws `RecorderError.stalled` if it takes longer
    /// than `timeout`; a session that opens after that is stopped.
    static func open(from input: AudioInput?, onLost: (@MainActor @Sendable (String) -> Void)? = nil, deliver: @escaping @Sendable ([Float]) -> Void) async throws -> MicSession {
        let queue = DispatchQueue(label: "dev.parrot.mic", qos: .userInitiated)
        return try await withTimeout(timeout, on: queue) {
            try MicSession(from: input, queue: queue, onLost: onLost, deliver: deliver)
        } abandon: { late in
            late.stop()
        }
    }

    /// Opens a session on the calling thread. Prefer `open`.
    /// - Parameter onLost: called when the engine stopped and couldn't start again, usually
    ///   because the microphone was unplugged.
    init(from input: AudioInput?, queue: DispatchQueue = DispatchQueue(label: "dev.parrot.mic", qos: .userInitiated), onLost: (@MainActor @Sendable (String) -> Void)? = nil, deliver: @escaping @Sendable ([Float]) -> Void) throws {
        self.queue = queue
        if let input { AudioInputs.use(input, on: engine) }
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        let sink = try Converter(from: format, deliver: deliver)
        sink.install(on: node, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            node.removeTap(onBus: 0)
            throw error
        }
        // Choosing a device fires a configuration change right after start, and so do routine
        // route changes. Those are harmless while the engine keeps running. When one stops it,
        // start it again; only give up if that fails.
        let operations = OperationQueue()
        operations.underlyingQueue = queue
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: operations) { [weak self] _ in
            guard let engine = self?.engine, !engine.isRunning else { return }
            do {
                try engine.start()
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in onLost?(message) }
            }
        }
    }

    /// Stops on the session's queue and returns at once. `deliver` may get a last chunk or two.
    func stop() {
        queue.async { [self] in
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }
}

/// Runs `work` on `queue` and returns its result, or throws `RecorderError.stalled` after
/// `seconds`. The work can't be interrupted, so a result that arrives late goes to `abandon`.
func withTimeout<T: Sendable>(_ seconds: TimeInterval, on queue: DispatchQueue, _ work: @escaping @Sendable () throws -> T, abandon: @escaping @Sendable (T) -> Void) async throws -> T {
    // Whoever settles first resumes the continuation.
    let once = Once()
    return try await withCheckedThrowingContinuation { continuation in
        queue.async {
            let result = Result { try work() }
            if once.claim() {
                continuation.resume(with: result)
            } else if case .success(let late) = result {
                abandon(late)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if once.claim() { continuation.resume(throwing: RecorderError.stalled) }
        }
    }
}

/// Turns any audio into 16 kHz mono and hands it on. Lives on the audio thread. It is a plain
/// class, not main-actor isolated, so the tap closure it installs doesn't inherit the main actor
/// and trap when Core Audio calls it.
final class Converter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat
    private let deliver: @Sendable ([Float]) -> Void

    init(from input: AVAudioFormat, deliver: @escaping @Sendable ([Float]) -> Void) throws {
        guard input.sampleRate > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Recorder.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output)
        else { throw RecorderError.noMicrophone }
        self.output = output
        self.converter = converter
        self.deliver = deliver
    }

    func install(on node: AVAudioInputNode, format: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [self] buffer, _ in
            convert(buffer)
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) {
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = converted.floatChannelData?[0] else { return }
        deliver(Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))))
    }
}

/// True for the first caller of `claim()` only.
private final class Once: Sendable {
    private let done = Mutex(false)

    func claim() -> Bool {
        done.withLock { done in
            defer { done = true }
            return !done
        }
    }
}

enum RecorderError: LocalizedError {
    case noMicrophone
    case stalled

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "Parrot couldn't find a microphone to record from."
        case .stalled: "The microphone didn't respond. Try again, or pick another microphone."
        }
    }
}
