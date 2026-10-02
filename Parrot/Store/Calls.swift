import Foundation
import Observation

/// A recorded call: who said what, and a summary written after it ended. Only text is kept, no audio.
struct Call: Codable, Identifiable, Hashable {
    enum Speaker: String, Codable {
        /// The microphone.
        case you
        /// Everything the Mac played.
        case them

        var label: String { self == .you ? "You" : "Them" }
    }

    struct Line: Codable, Hashable {
        var speaker: Speaker
        var at: Date
        var text: String
    }

    var id = UUID()
    var started: Date
    var ended: Date?
    var lines: [Line] = []
    var summary: String?

    var duration: TimeInterval { (ended ?? .now).timeIntervalSince(started) }

    /// The first line of the summary, which the summarizer writes as a title.
    var title: String {
        summary?.split(separator: "\n").first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) } ?? "Call"
    }

    var transcript: String {
        lines.map { "\($0.speaker.label): \($0.text)" }.joined(separator: "\n")
    }

    /// Adds a line in time order. Lines arrive out of order because both sides are transcribed
    /// separately.
    mutating func insert(_ line: Line) {
        let index = lines.firstIndex { $0.at > line.at } ?? lines.endIndex
        lines.insert(line, at: index)
    }

    /// Drops lines the microphone picked up from the speakers. Without headphones, the mic hears
    /// the other side too, which would put their words in your mouth.
    mutating func removeEcho() {
        let theirs = lines.filter { $0.speaker == .them }
        lines.removeAll { line in
            line.speaker == .you && theirs.contains { abs($0.at.timeIntervalSince(line.at)) < 5 && WordErrorRate.rate(reference: $0.text, hypothesis: line.text) < 0.5 }
        }
    }
}

/// Recorded calls, newest first, saved to calls.json next to the history.
@MainActor @Observable
final class Calls {
    private(set) var entries: [Call] = []
    private let file = History.folder.appending(path: "calls.json")

    init() {
        if let data = try? Data(contentsOf: file) {
            entries = (try? JSONDecoder().decode([Call].self, from: data)) ?? []
        }
    }

    func save(_ call: Call) {
        if let index = entries.firstIndex(where: { $0.id == call.id }) {
            entries[index] = call
        } else {
            entries.insert(call, at: 0)
        }
        write()
    }

    func delete(_ call: Call) {
        entries.removeAll { $0.id == call.id }
        write()
    }

    private func write() {
        try? FileManager.default.createDirectory(at: History.folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: file, options: .atomic)
    }
}
