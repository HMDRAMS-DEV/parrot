import Foundation
import Observation

/// A word or name the speech models get wrong, like "Alma" or "Kubernetes", with the ways they
/// tend to mishear it.
struct VocabTerm: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    /// Mishearings to replace with `text`, such as "alma" for "Alma" or "cube cuddle" for "kubectl".
    var aliases: [String] = []
}

/// Custom vocabulary, saved to vocabulary.json next to the history.
///
/// It is used three ways: Parakeet engines listen for the terms in the audio (FluidAudio's CTC
/// boosting), aliases are swapped for the term in every transcript, and the cleanup model gets
/// the terms as spelling hints.
@MainActor @Observable
final class Vocabulary {
    private(set) var terms: [VocabTerm] = []

    nonisolated static let file = History.folder.appending(path: "vocabulary.json")

    init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode([VocabTerm].self, from: data) {
            terms = saved
        }
    }

    func add(_ text: String, aliases: [String] = []) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !terms.contains(where: { $0.text.caseInsensitiveCompare(text) == .orderedSame }) else { return }
        terms.append(VocabTerm(text: text, aliases: Self.clean(aliases)))
        save()
    }

    func update(_ term: VocabTerm) {
        guard let index = terms.firstIndex(where: { $0.id == term.id }) else { return }
        var term = term
        term.aliases = Self.clean(term.aliases)
        terms[index] = term
        save()
    }

    func delete(_ term: VocabTerm) {
        terms.removeAll { $0.id == term.id }
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: History.folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(terms).write(to: Self.file, options: .atomic)
    }

    private static func clean(_ aliases: [String]) -> [String] {
        aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Replaces each alias, and each differently capitalized spelling of a term, with the term.
    /// Matches whole words only, so the alias "alma" doesn't touch "almanac".
    nonisolated static func apply(_ terms: [VocabTerm], to text: String) -> String {
        var text = text
        for term in terms {
            for spoken in [term.text] + term.aliases {
                let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: spoken) + "(?![\\p{L}\\p{N}])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: NSRegularExpression.escapedTemplate(for: term.text))
            }
        }
        return text
    }
}
