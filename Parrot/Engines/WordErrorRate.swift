import Foundation

/// Word error rate: the word edits (substitutions, insertions, deletions) needed to turn the
/// hypothesis into the reference, over the reference's word count. Case and punctuation don't count.
enum WordErrorRate {
    static func words(_ text: String) -> [String] {
        let kept = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "'" ? Character(scalar) : " "
        }
        return String(kept).split(separator: " ").map(String.init)
    }

    /// Edits and reference length, so a set of clips can be scored as a whole.
    static func edits(reference: String, hypothesis: String) -> (edits: Int, words: Int) {
        let ref = words(reference), hyp = words(hypothesis)
        guard !ref.isEmpty, !hyp.isEmpty else { return (max(ref.count, hyp.count), ref.count) }
        var row = Array(0...hyp.count)
        for i in 1...ref.count {
            var previous = row[0]
            row[0] = i
            for j in 1...hyp.count {
                let current = row[j]
                row[j] = ref[i - 1] == hyp[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = current
            }
        }
        return (row[hyp.count], ref.count)
    }

    static func rate(reference: String, hypothesis: String) -> Double {
        let (edits, words) = edits(reference: reference, hypothesis: hypothesis)
        return words == 0 ? (edits == 0 ? 0 : 1) : Double(edits) / Double(words)
    }
}
