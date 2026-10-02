import Foundation

struct Dictation: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    /// An `EngineID` raw value. A string, so history survives an engine being removed.
    var engine: String
    /// Length of the recording, in seconds.
    var audio: TimeInterval
    /// Time from releasing Option to having text, in seconds.
    var latency: TimeInterval
    /// What the engine heard, when cleanup changed it.
    var raw: String?

    var engineName: String { EngineID(rawValue: engine)?.name ?? engine }
}

/// Every dictation, newest first, in ~/Library/Application Support/Parrot. Recordings are kept
/// beside it as WAV files for the most recent `clipLimit` dictations, so engines can be compared
/// on real speech.
@MainActor @Observable
final class History {
    nonisolated static let folder = URL.applicationSupportDirectory.appending(path: "Parrot")
    nonisolated static let clips = folder.appending(path: "Clips")
    /// Clips with a matching .txt of the right words. `EngineEval` scores every engine on them.
    nonisolated static let evalSet = folder.appending(path: "Eval")

    private static let clipLimit = 300
    private let file = folder.appending(path: "history.json")

    private(set) var entries: [Dictation] = []

    init() {
        try? FileManager.default.createDirectory(at: Self.clips, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file) {
            entries = (try? JSONDecoder().decode([Dictation].self, from: data)) ?? []
        }
    }

    nonisolated static func clip(for entry: Dictation) -> URL {
        clips.appending(path: "\(entry.id.uuidString).wav")
    }

    func add(_ entry: Dictation, samples: [Float]) {
        try? WAV.write(samples, to: Self.clip(for: entry))
        entries.insert(entry, at: 0)
        for old in entries.dropFirst(Self.clipLimit) {
            try? FileManager.default.removeItem(at: Self.clip(for: old))
        }
        save()
    }

    func delete(_ entry: Dictation) {
        try? FileManager.default.removeItem(at: Self.clip(for: entry))
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Deletes every dictation and recording. The eval set stays.
    func clear() {
        try? FileManager.default.removeItem(at: Self.clips)
        try? FileManager.default.createDirectory(at: Self.clips, withIntermediateDirectories: true)
        entries = []
        save()
    }

    /// Copies the clip into the eval set, with this text as the reference. Fix the .txt by hand
    /// if the transcript was wrong.
    func addToEvalSet(_ entry: Dictation) throws {
        try FileManager.default.createDirectory(at: Self.evalSet, withIntermediateDirectories: true)
        let name = entry.id.uuidString
        let audio = Self.evalSet.appending(path: "\(name).wav")
        try? FileManager.default.removeItem(at: audio)
        try FileManager.default.copyItem(at: Self.clip(for: entry), to: audio)
        try entry.text.write(to: Self.evalSet.appending(path: "\(name).txt"), atomically: true, encoding: .utf8)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
