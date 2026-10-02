import Foundation
import Testing
@testable import Parrot

/// Runs synthesized speech through the voice detector and the wake word, end to end. Downloads
/// the detector and a model, so it only runs on request:
///
///     TEST_RUNNER_PARROT_WAKE=1 xcodebuild ... test -only-testing:ParrotTests/WakeListenerCheck
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PARROT_WAKE"] != nil))
struct WakeListenerCheck {
    @Test @MainActor func splitsOnPausesAndFindsTheWakeWord() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "parrot-wake.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "Parrot, send Sarah the deck before lunch. [[slnc 1600]] I'm just thinking out loud here. [[slnc 1600]] Parrot. [[slnc 1600]] Remind me to call mom."]
        try say.run()
        say.waitUntilExit()
        let samples = try WAV.read(url)

        // Feed it like the microphone does: small chunks, then a second of silence to close out.
        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self)
        for start in stride(from: 0, to: samples.count, by: 1600) {
            continuation.yield(Array(samples[start..<min(start + 1600, samples.count)]))
        }
        continuation.yield([Float](repeating: 0, count: 32_000))
        continuation.finish()

        var utterances: [WakeListener.Utterance] = []
        try await WakeListener.segment(stream) { utterances.append($0) }

        let engine = EngineID.default.make()
        var texts: [String] = []
        for utterance in utterances { texts.append(try await engine.transcribe(utterance.samples)) }
        print("Utterances:", texts)

        #expect(texts.count == 4)
        let matches = texts.compactMap(WakeWord.match)
        #expect(matches.count == 2)
        #expect(matches.first?.hasPrefix("Send Sarah the deck before lunch") == true)
        #expect(matches.last == "")
    }
}
