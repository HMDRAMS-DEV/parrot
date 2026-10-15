import Foundation
import Testing
@testable import Parrot

/// Runs S1-mini on the examples from its model card. Downloads the model (630 MB), so it only
/// runs on request:
///
///     TEST_RUNNER_PARROT_S1MINI=1 xcodebuild ... test -only-testing:ParrotTests/S1MiniCheck
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PARROT_S1MINI"] != nil))
struct S1MiniCheck {
    @Test func cleansTheModelCardExamples() async throws {
        let cleaner = S1MiniCleaner()
        let examples = [
            "i think the answer is forty two no sorry forty three",
            "let's meet at half past two tomorrow uh actually make it three fifteen p m",
            "send it to support at superwhisper dot com",
            "hmm im gonna be late um can you uh tell the team to start without me",
            "what is the capital of france",
            "um so i was thinking we could uh ship on friday you know and then like see what people say",
        ]
        for text in examples {
            let start = ContinuousClock.now
            let raw = try await cleaner.clean(text, vocabulary: [])
            let kept = cleaner.isFaithful(raw, to: text) ? "kept" : "rejected"
            print("S1-mini \(ContinuousClock.now - start), \(kept): \(text) -> \(raw)")
        }
        #expect(await Cleanup.guarded(examples[0], with: cleaner, vocabulary: []) == "I think the answer is 43.")
    }
}
