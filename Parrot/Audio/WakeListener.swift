import AVFoundation
import FluidAudio

/// Listens all the time and cuts the audio into utterances: speech that ends with a pause.
/// A small voice detector (Silero, about 2 MB) runs on every quarter second of audio; nothing
/// is transcribed until someone stops talking.
@MainActor
final class WakeListener {
    struct Utterance {
        let samples: [Float]
        let startedAt: Date
    }

    /// How long a pause ends an utterance.
    static let pause: TimeInterval = 1.0
    /// Longer than this, an utterance is cut and handed over anyway.
    static let longest: TimeInterval = 120

    private var session: MicSession?
    private var loop: Task<Void, Never>?

    /// Starts listening on `input`. Utterances arrive on the main actor. `onPartial` gets the
    /// speech so far, every half second for the first two seconds, so the wake word can be
    /// heard before the speaker pauses.
    func start(from input: AudioInput, onPartial: @escaping @MainActor (Utterance) -> Void, onUtterance: @escaping @MainActor (Utterance) -> Void, onFailure: @escaping @MainActor (String) -> Void) {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self, bufferingPolicy: .bufferingNewest(400))
        do {
            session = try MicSession(from: input, onLost: onFailure) { continuation.yield($0) }
        } catch {
            onFailure(error.localizedDescription)
            return
        }
        loop = Task {
            do {
                try await Self.segment(stream, onPartial: onPartial, onUtterance: onUtterance)
            } catch is CancellationError {
            } catch {
                onFailure(error.localizedDescription)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        session?.stop()
        session = nil
    }

    /// How often, and for how long, `onPartial` gets the speech so far.
    static let partialEvery: TimeInterval = 0.5
    static let partialUntil: TimeInterval = 2

    static func segment(_ stream: AsyncStream<[Float]>, onPartial: (@MainActor (Utterance) -> Void)? = nil, onUtterance: @MainActor (Utterance) -> Void) async throws {
        let vad = try await VadManager()
        let rate = VadManager.sampleRate
        let config = VadSegmentationConfig(minSpeechDuration: 0.25, minSilenceDuration: pause, speechPadding: 0.2)
        var state = await vad.makeStreamState()

        // Audio not yet fed to the detector, and audio kept for the current utterance.
        var pending: [Float] = []
        var kept: [Float] = []
        var keptStart = 0
        var speechStart: Int?
        var startedAt = Date()
        var nextPartial = 0

        for await chunk in stream {
            try Task.checkCancellation()
            pending.append(contentsOf: chunk)
            while pending.count >= VadManager.chunkSize {
                let frame = Array(pending.prefix(VadManager.chunkSize))
                pending.removeFirst(VadManager.chunkSize)
                kept.append(contentsOf: frame)

                let result = try await vad.processStreamingChunk(frame, state: state, config: config)
                state = result.state
                if let event = result.event {
                    if event.isStart {
                        speechStart = event.sampleIndex
                        nextPartial = Int(partialEvery * Double(rate))
                        startedAt = Date(timeIntervalSinceNow: -Double(state.processedSamples - event.sampleIndex) / Double(rate))
                    } else if let start = speechStart {
                        let from = max(0, start - keptStart), to = min(kept.count, event.sampleIndex - keptStart)
                        if to > from { onUtterance(Utterance(samples: Array(kept[from..<to]), startedAt: startedAt)) }
                        speechStart = nil
                    }
                }

                if let onPartial, let start = speechStart, state.processedSamples - start >= nextPartial, nextPartial <= Int(partialUntil * Double(rate)) {
                    onPartial(Utterance(samples: Array(kept[max(0, start - keptStart)...]), startedAt: startedAt))
                    nextPartial += Int(partialEvery * Double(rate))
                }
                if let start = speechStart, state.processedSamples - start > Int(longest) * rate {
                    onUtterance(Utterance(samples: Array(kept[max(0, start - keptStart)...]), startedAt: startedAt))
                    speechStart = state.processedSamples
                }
                // `kept` always ends at `state.processedSamples`. Between utterances, it only needs
                // a second of lead-in for the detector's padding.
                if speechStart == nil, kept.count > 2 * rate {
                    let drop = kept.count - rate
                    kept.removeFirst(drop)
                    keptStart += drop
                }
            }
        }
        // The stream finished mid-sentence, as when a call recording stops. Cancelling (the wake
        // listener stopping) drops it instead.
        if !Task.isCancelled, let start = speechStart, kept.count > max(0, start - keptStart) {
            onUtterance(Utterance(samples: Array(kept[max(0, start - keptStart)...]), startedAt: startedAt))
        }
    }
}
