import Foundation
import Testing
@testable import Parrot

struct VocabularyTests {
    @Test func aliasesBecomeTheTerm() {
        let terms = [VocabTerm(text: "Alma", aliases: ["alba", "elma"]), VocabTerm(text: "kubectl", aliases: ["cube cuddle"])]
        let text = Vocabulary.apply(terms, to: "Open alba and Elma, then run cube cuddle.")
        #expect(text == "Open Alma and Alma, then run kubectl.")
    }

    @Test func onlyWholeWordsMatch() {
        let text = Vocabulary.apply([VocabTerm(text: "Alma", aliases: ["alma"])], to: "An almanac from alma.")
        #expect(text == "An almanac from Alma.")
    }
}

struct CleanupTests {
    @Test func fillersAndPunctuationAreFaithful() {
        let faithful = Cleanup.isFaithful("I think we should ship on Friday.", to: "um i think we should uh ship on friday")
        #expect(faithful)
    }

    @Test func anAnswerIsNotFaithful() {
        let faithful = Cleanup.isFaithful("The capital of France is Paris.", to: "what is the capital of france")
        #expect(!faithful)
    }

    @Test func rephrasingIsNotFaithful() {
        let faithful = Cleanup.isFaithful("Let's release it at the end of the week and gather feedback.", to: "we should ship the app on friday and see what people say")
        #expect(!faithful)
    }
}

struct CallTests {
    @Test func linesStayInTimeOrder() {
        let start = Date()
        var call = Call(started: start)
        call.insert(.init(speaker: .them, at: start.addingTimeInterval(5), text: "Second"))
        call.insert(.init(speaker: .you, at: start.addingTimeInterval(1), text: "First"))
        call.insert(.init(speaker: .you, at: start.addingTimeInterval(9), text: "Third"))
        #expect(call.lines.map(\.text) == ["First", "Second", "Third"])
    }

    @Test func echoOfTheOtherSideIsDropped() {
        let start = Date()
        var call = Call(started: start)
        call.insert(.init(speaker: .them, at: start, text: "Can you send the deck by Friday?"))
        call.insert(.init(speaker: .you, at: start.addingTimeInterval(0.3), text: "can you send the deck by friday"))
        call.insert(.init(speaker: .you, at: start.addingTimeInterval(4), text: "Sure, I'll send it tomorrow."))
        call.removeEcho()
        #expect(call.lines.map(\.speaker) == [.them, .you])
    }

    @Test func longTranscriptsSplitIntoChunks() {
        let line = "You: " + Array(repeating: "word", count: 400).joined(separator: " ")
        let parts = Summarizer.chunk(Array(repeating: line, count: 10))
        #expect(parts.count == 4)
    }
}
