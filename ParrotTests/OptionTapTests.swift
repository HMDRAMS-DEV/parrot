import Testing
@testable import Parrot

struct OptionTapTests {
    @Test func quickTapFires() {
        var detector = OptionTapDetector()
        let fired1 = detector.modifiersChanged(option: true, others: false, at: 0)
        #expect(!fired1)
        let fired2 = detector.modifiersChanged(option: false, others: false, at: 0.15)
        #expect(fired2)
    }

    @Test func longHoldDoesNotFire() {
        var detector = OptionTapDetector()
        _ = detector.modifiersChanged(option: true, others: false, at: 0)
        let fired1 = detector.modifiersChanged(option: false, others: false, at: 0.9)
        #expect(!fired1)
    }

    @Test func optionShortcutDoesNotFire() {
        var detector = OptionTapDetector()
        _ = detector.modifiersChanged(option: true, others: false, at: 0)
        detector.interrupted()
        let fired1 = detector.modifiersChanged(option: false, others: false, at: 0.1)
        #expect(!fired1)
    }

    @Test func addingAModifierSpoilsUntilAllLift() {
        var detector = OptionTapDetector()
        _ = detector.modifiersChanged(option: true, others: false, at: 0)
        _ = detector.modifiersChanged(option: true, others: true, at: 0.05)
        // Command lifts first, Option is still down: not a fresh tap.
        _ = detector.modifiersChanged(option: true, others: false, at: 0.1)
        let fired1 = detector.modifiersChanged(option: false, others: false, at: 0.15)
        #expect(!fired1)
        // The next clean tap works.
        _ = detector.modifiersChanged(option: true, others: false, at: 1)
        let fired2 = detector.modifiersChanged(option: false, others: false, at: 1.1)
        #expect(fired2)
    }

    @Test func otherModifierFirstDoesNotArm() {
        var detector = OptionTapDetector()
        _ = detector.modifiersChanged(option: false, others: true, at: 0)
        _ = detector.modifiersChanged(option: true, others: true, at: 0.05)
        let fired1 = detector.modifiersChanged(option: false, others: false, at: 0.1)
        #expect(!fired1)
    }
}

struct WordErrorRateTests {
    @Test func ignoresCaseAndPunctuation() {
        #expect(WordErrorRate.rate(reference: "Hello, world.", hypothesis: "hello world") == 0)
    }

    @Test func countsEdits() {
        // One substitution, one deletion over four words.
        #expect(WordErrorRate.rate(reference: "the cat sat down", hypothesis: "the bat sat") == 0.5)
    }

    @Test func keepsApostrophes() {
        #expect(WordErrorRate.words("Don't stop") == ["don't", "stop"])
    }

    @Test func emptyCases() {
        #expect(WordErrorRate.rate(reference: "", hypothesis: "") == 0)
        #expect(WordErrorRate.rate(reference: "one two", hypothesis: "") == 1)
    }
}

struct WakeWordTests {
    @Test func findsTheWakeWordAndKeepsTheRest() {
        #expect(WakeWord.match("Parrot, send Sarah the deck.") == "Send Sarah the deck.")
        #expect(WakeWord.match("Hey Parrot remind me at 5.") == "Remind me at 5.")
        #expect(WakeWord.match("Perot. Draft a reply") == "Draft a reply")
        #expect(WakeWord.match("Oi, send the deck to Sarah.") == "Send the deck to Sarah.")
        #expect(WakeWord.match("Oi oi, open the notes.") == "Open the notes.")
        #expect(WakeWord.match("Hey oi! Call mom") == "Call mom")
    }

    @Test func wakeWordAlone() {
        #expect(WakeWord.match("Parrot.") == "")
        #expect(WakeWord.match("Parent.") == "")
        #expect(WakeWord.match("Oi.") == "")
        #expect(WakeWord.match("Lloyd.") == "")
        #expect(WakeWord.match("Hey, carrot!") == "")
    }

    @Test func soundAlikesNeedToStandAlone() {
        #expect(WakeWord.match("Parents are visiting this weekend.") == nil)
    }

    @Test func ignoresOtherSpeech() {
        #expect(WakeWord.match("My parrot is loud.") == nil)
        #expect(WakeWord.match("Oh, I forgot.") == nil)
        #expect(WakeWord.match("Boy, that was close.") == nil)
        #expect(WakeWord.match("Lloyd called about the invoice.") == nil)
        #expect(WakeWord.match("Hey, how are you?") == nil)
        #expect(WakeWord.match("") == nil)
    }
}
