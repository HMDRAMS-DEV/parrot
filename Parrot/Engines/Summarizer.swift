import Foundation
import FoundationModels

/// Writes a call summary with Apple's on-device model.
///
/// The model reads about 4,000 tokens at a time, roughly 2,500 words with the instructions and
/// answer. Longer calls are summarized in parts first, then the parts are combined.
enum Summarizer {
    /// Words of transcript per request.
    static let chunkWords = 1_500

    private static let notesInstructions = """
        You take notes on part of a call transcript. Lines start with "You:" (the person you \
        write for) or "Them:" (everyone else). Write short bullet points of what was discussed, \
        decided, and promised, and who promised it. Use only what the transcript says.
        """

    private static let summaryInstructions = """
        You summarize a call for the person who was on it. Lines start with "You:" (that person) \
        or "Them:" (everyone else). Use only what the text says; never invent names, numbers, or \
        dates. Reply in this format:
        # A title of five words or fewer
        Two or three sentences on what the call was about.

        ## Decisions
        - One line per decision, or "None" if there were none

        ## Action items
        - One line per follow-up, starting with who owns it (You or Them), or "None"
        """

    static func summarize(_ call: Call) async throws -> String {
        let lines = call.lines.map { "\($0.speaker.label): \($0.text)" }
        guard !lines.isEmpty else { return "# Nothing said\nParrot didn't hear any words on this call." }
        var parts = chunk(lines)
        // Notes from every part, then notes of the notes, until they fit in one request.
        // Each round shrinks the text several times over.
        while parts.count > 1 {
            var notes: [String] = []
            for part in parts {
                notes.append(try await respond(part, instructions: notesInstructions, tokens: 300))
            }
            parts = chunk(notes)
        }
        return try await respond(parts[0], instructions: summaryInstructions, tokens: 600)
    }

    /// Groups lines into pieces of about `chunkWords` words.
    static func chunk(_ lines: [String]) -> [String] {
        var parts: [String] = [], current: [String] = [], words = 0
        for line in lines {
            let count = line.split(separator: " ").count
            if words + count > chunkWords, !current.isEmpty {
                parts.append(current.joined(separator: "\n"))
                current = []
                words = 0
            }
            current.append(line)
            words += count
        }
        if !current.isEmpty { parts.append(current.joined(separator: "\n")) }
        return parts
    }

    private static func respond(_ text: String, instructions: String, tokens: Int) async throws -> String {
        guard AppleCleaner.isAvailable else { throw SummarizerError.unavailable }
        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: tokens)
        return try await session.respond(to: text, options: options).content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SummarizerError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Apple Intelligence is off or still downloading, so Parrot can't summarize yet." }
}
