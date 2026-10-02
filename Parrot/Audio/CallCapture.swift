import Foundation

/// Records both sides of a call at once: the microphone is "you", everything the Mac plays is
/// "them". Each side is cut into utterances by its own voice detector, so they can be
/// transcribed while the call goes on.
@MainActor
final class CallCapture {
    private var mic: MicSession?
    private var system: SystemAudio?
    private var streams: [AsyncStream<[Float]>.Continuation] = []
    private var loops: [Task<Void, Never>] = []

    func start(mic input: AudioInput?, onUtterance: @escaping @MainActor (Call.Speaker, WakeListener.Utterance) -> Void, onFailure: @escaping @MainActor (String) -> Void) throws {
        // Unbounded: a call can't afford to drop audio while the detector catches up.
        let (theirs, theirStream) = AsyncStream.makeStream(of: [Float].self)
        let (yours, yourStream) = AsyncStream.makeStream(of: [Float].self)
        streams = [theirStream, yourStream]
        do {
            system = try SystemAudio { theirStream.yield($0) }
            mic = try MicSession(from: input, onLost: onFailure) { yourStream.yield($0) }
        } catch {
            stopAudio()
            throw error
        }
        loops = [(Call.Speaker.them, theirs), (.you, yours)].map { speaker, stream in
            Task {
                do {
                    try await WakeListener.segment(stream) { onUtterance(speaker, $0) }
                } catch {
                    onFailure(error.localizedDescription)
                }
            }
        }
    }

    /// Stops recording, and returns once the last words of both sides have been handed over.
    func stop() async {
        stopAudio()
        for loop in loops { await loop.value }
        loops = []
    }

    private func stopAudio() {
        system?.stop()
        mic?.stop()
        system = nil
        mic = nil
        for stream in streams { stream.finish() }
        streams = []
    }
}
