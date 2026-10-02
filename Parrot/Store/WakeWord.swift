import Foundation

/// Finds the wake word at the start of an utterance and returns what was said after it. The
/// word is "Oy" (or the original "Parrot") unless the user picks another in settings.
///
/// Speech models spell an unexpected name a few ways, so near misses count. Only the start of an
/// utterance counts, so mentioning a parrot mid-sentence doesn't trigger dictation.
enum WakeWord {
    static let standard = "Oy"
    static let oySpellings: Set<String> = [
        // Parakeet Ultra wrote "Oi" most often for "Oy" in testing, then "Oy" and "Hoy". It also
        // wrote "Oh" a third of the time, which can't count: "Oh, I forgot" is everyday speech.
        "oy", "oi", "hoy", "oye", "ahoy", "ahoi",
    ]
    static let parrotSpellings: Set<String> = [
        "parrot", "parrots", "parrot's", "parot", "parrott", "perrot", "perot", "pierrot", "parro", "pareto",
    ]
    /// Mishearings of "Parrot" said on its own, which gives the model no context. They only count
    /// as the whole utterance, so "Parents are visiting" doesn't trigger.
    static let soloSpellings: Set<String> = ["lloyd", "alloy", "parent", "parents", "carrot", "carrots", "barrett", "perret", "parrat", "pirate"]
    private static let lead: Set<String> = ["hey", "hi", "ok", "okay", "yo"]

    /// The single word to listen for, from what the user typed: "Hey Jarvis!" becomes "jarvis".
    /// nil when nothing usable is left.
    static func normalized(_ typed: String) -> String? {
        WordErrorRate.words(typed).first { !lead.contains($0) }
    }

    /// The words that count as `word`. Oy and Parrot have known mishearings; any other word
    /// counts as itself and its plural.
    static func spellings(for word: String) -> (words: Set<String>, solo: Set<String>) {
        switch normalized(word) ?? normalized(standard)! {
        case "oy": (oySpellings.union(parrotSpellings), soloSpellings)
        case "parrot": (parrotSpellings, soloSpellings)
        case let custom: ([custom, custom + "s", custom + "'s"], [])
        }
    }

    /// nil when the utterance doesn't start with the wake word. Otherwise the rest, which is
    /// empty when the wake word was said on its own.
    static func match(_ text: String, word: String = standard) -> String? {
        let (known, solo) = spellings(for: word)
        let all = WordErrorRate.words(text)
        if let last = all.last, all.count <= 2, solo.contains(last), all.dropLast().allSatisfy(lead.contains) {
            return ""
        }
        var rest = Substring(text)
        var sawWord = false
        for _ in 0..<2 {
            rest = rest.drop { !$0.isLetter && !$0.isNumber }
            let word = rest.prefix { $0.isLetter || $0 == "'" }
            let lower = word.lowercased()
            if known.contains(lower) {
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
            guard !word.isEmpty, known.contains(word.lowercased()) else { break }
            rest = next.dropFirst(word.count)
        }
        let words = rest.drop { !$0.isLetter && !$0.isNumber }.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// What to type from a whole utterance whose start already matched the wake word, with
    /// `heardStart` being what came after the wake word then. Over a long utterance the model
    /// often spells the wake word differently ("Oh") or leaves it out, so the utterance is kept
    /// either way: a misheard wake word is dropped, and anything else is typed in full.
    static func rest(of text: String, heardStart: String, word: String = standard) -> String {
        if let rest = match(text, word: word) { return rest }
        let all = WordErrorRate.words(text)
        // Line the transcript up with what followed the wake word the first time.
        if let anchor = WordErrorRate.words(heardStart).first, let at = all.prefix(3).firstIndex(of: anchor) {
            return dropping(at, wordsFrom: text)
        }
        // A short word one letter off a known spelling, like "Oh" for "Oy". Not "I" or "a", which
        // usually start the sentence itself.
        let (known, _) = spellings(for: word)
        if let first = all.first, (2...4).contains(first.count), known.contains(where: { oneEditApart($0, first) }) {
            return dropping(1, wordsFrom: text)
        }
        return dropping(0, wordsFrom: text)
    }

    /// `text` without its first `count` words, capitalized.
    private static func dropping(_ count: Int, wordsFrom text: String) -> String {
        var rest = Substring(text)
        for _ in 0..<count {
            rest = rest.drop { !$0.isLetter && !$0.isNumber }
            rest = rest.dropFirst(rest.prefix { $0.isLetter || $0.isNumber || $0 == "'" }.count)
        }
        let words = rest.drop { !$0.isLetter && !$0.isNumber }.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private static func oneEditApart(_ a: String, _ b: String) -> Bool {
        let b = Array(b)
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var next = [i + 1]
            for (j, y) in b.enumerated() {
                next.append(min(row[j + 1] + 1, next[j] + 1, row[j] + (x == y ? 0 : 1)))
            }
            row = next
        }
        return row[b.count] <= 1
    }
}
