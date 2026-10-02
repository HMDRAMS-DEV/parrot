import AVFoundation
import Synchronization

/// Records a microphone as 16 kHz mono Float samples, the format every engine takes.
@MainActor
final class Recorder {
    nonisolated static let sampleRate: Double = 16_000

    private var session: MicSession?
    private let samples = Samples()

    /// Records from `input`, or the system default when it's nil or unplugged.
    func start(from input: AudioInput?) throws {
        samples.reset()
        let collected = samples
        session = try MicSession(from: input) { chunk in collected.append(chunk) }
    }

    /// Stops recording and returns everything captured since `start()`.
    func stop() -> [Float] {
        session?.stop()
        session = nil
        return samples.reset()
    }

    private final class Samples: Sendable {
        private let buffer = Mutex<[Float]>([])

        func append(_ chunk: [Float]) {
            buffer.withLock { $0.append(contentsOf: chunk) }
        }

        @discardableResult func reset() -> [Float] {
            buffer.withLock { taken in
                defer { taken = [] }
                return taken
            }
        }
    }
}

/// An audio engine on a microphone, handing 16 kHz mono chunks to `deliver` on the audio
/// thread. Each session gets a fresh engine, so switching microphones is clean.
@MainActor
final class MicSession {
    private let engine = AVAudioEngine()
    private var observer: (any NSObjectProtocol)?

    /// - Parameter onLost: called when the engine stopped and couldn't start again, usually
    ///   because the microphone was unplugged.
    init(from input: AudioInput?, onLost: (@MainActor (String) -> Void)? = nil, deliver: @escaping @Sendable ([Float]) -> Void) throws {
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
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [engine] _ in
            MainActor.assumeIsolated {
                guard !engine.isRunning else { return }
                do {
                    try engine.start()
                } catch {
                    onLost?(error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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

enum RecorderError: LocalizedError {
    case noMicrophone

    var errorDescription: String? { "Parrot couldn't find a microphone to record from." }
}
