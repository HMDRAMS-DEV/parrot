import Foundation

/// Finds the wake word, "Oy" (or the original "Parrot"), at the start of an utterance and
/// returns what was said after it.
///
/// Speech models spell an unexpected name a few ways, so near misses count. Only the start of an
/// utterance counts, so mentioning a parrot mid-sentence doesn't trigger dictation.
enum WakeWord {
    static let spellings: Set<String> = [
        // Parakeet Ultra wrote "Oi" most often for "Oy" in testing, then "Oy" and "Hoy". It also
        // wrote "Oh" a third of the time, which can't count: "Oh, I forgot" is everyday speech.
        "oy", "oi", "hoy", "oye", "ahoy", "ahoi",
        "parrot", "parrots", "parrot's", "parot", "parrott", "perrot", "perot", "pierrot", "parro", "pareto",
    ]
    /// Mishearings of "Parrot" said on its own, which gives the model no context. They only count
    /// as the whole utterance, so "Parents are visiting" doesn't trigger.
    static let soloSpellings: Set<String> = ["lloyd", "alloy", "parent", "parents", "carrot", "carrots", "barrett", "perret", "parrat", "pirate"]
    private static let lead: Set<String> = ["hey", "hi", "ok", "okay", "yo"]

    /// nil when the utterance doesn't start with the wake word. Otherwise the rest, which is
    /// empty when the wake word was said on its own.
    static func match(_ text: String) -> String? {
        let all = WordErrorRate.words(text)
        if let last = all.last, all.count <= 2, soloSpellings.contains(last), all.dropLast().allSatisfy(lead.contains) {
            return ""
        }
        var rest = Substring(text)
        var sawWord = false
        for _ in 0..<2 {
            rest = rest.drop { !$0.isLetter && !$0.isNumber }
            let word = rest.prefix { $0.isLetter || $0 == "'" }
            let lower = word.lowercased()
            if spellings.contains(lower) {
                rest = rest.dropFirst(word.count)
                sawWord = true
                break
            }
            guard lead.contains(lower) else { return nil }
            rest = rest.dropFirst(word.count)
        }
        guard sawWord else { return nil }
        // "Oy oy" is said twice on purpose. Drop the repeats.
        while true {
            let next = rest.drop { !$0.isLetter && !$0.isNumber }
            let word = next.prefix { $0.isLetter || $0 == "'" }
            guard !word.isEmpty, spellings.contains(word.lowercased()) else { break }
            rest = next.dropFirst(word.count)
        }
        let words = rest.drop { !$0.isLetter && !$0.isNumber }.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
