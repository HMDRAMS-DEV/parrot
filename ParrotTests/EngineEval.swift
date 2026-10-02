import Foundation
import Testing
@testable import Parrot

/// Scores engines on the eval set: every .wav in ~/Library/Application Support/Parrot/Eval with a
/// .txt of the same name holding the right words. Add clips from the history window's
/// Add to Eval Set, then fix the .txt by hand where the transcript was wrong.
///
///     TEST_RUNNER_PARROT_EVAL=1 xcodebuild -project Parrot.xcodeproj -scheme Parrot \
///       -destination 'platform=macOS' test -only-testing:ParrotTests/EngineEval
///
/// Limit the engines with TEST_RUNNER_PARROT_ENGINES=parakeetV2,phonon2. The report prints and
/// lands in $TMPDIR/ParrotEval/report.md.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PARROT_EVAL"] != nil), .serialized)
struct EngineEval {
    struct Clip {
        let name: String
        let samples: [Float]
        let reference: String
        var seconds: Double { Double(samples.count) / Recorder.sampleRate }
    }

    @Test func scoreEngines() async throws {
        let clips = try loadClips()
        try #require(!clips.isEmpty, "No clips with references in \(History.evalSet.path)")
        let audio = clips.reduce(0) { $0 + $1.seconds }

        var lines = [
            "# Parrot eval",
            "",
            "\(clips.count) clips, \(Format.seconds(audio)) of speech. WER is total word edits over total reference words.",
            "",
            "| Engine | WER | Load | Transcribe | Speed |",
            "|---|---:|---:|---:|---:|",
        ]
        var misses: [String] = []

        for id in engines() {
            let engine = id.make()
            let loadStart = ContinuousClock.now
            do {
                try await engine.prepare()
            } catch {
                lines.append("| \(id.name) | failed: \(error.localizedDescription) | | | |")
                continue
            }
            let load = (ContinuousClock.now - loadStart) / .seconds(1)

            var edits = 0, words = 0, busy = 0.0
            for clip in clips {
                let start = ContinuousClock.now
                let text = try await engine.transcribe(clip.samples)
                busy += (ContinuousClock.now - start) / .seconds(1)
                let score = WordErrorRate.edits(reference: clip.reference, hypothesis: text)
                edits += score.edits
                words += score.words
                if score.edits > 0 { misses.append("- **\(id.name)**, \(clip.name): \(text)") }
            }
            let wer = words == 0 ? 0 : Double(edits) / Double(words) * 100
            lines.append("| \(id.name) | \(String(format: "%.2f%%", wer)) | \(Format.seconds(load)) | \(Format.seconds(busy)) | \(Int((audio / max(busy, 0.001)).rounded()))x |")
        }

        if !misses.isEmpty { lines += ["", "## Misses", ""] + misses }
        let report = lines.joined(separator: "\n")
        print(report)
        let folder = FileManager.default.temporaryDirectory.appending(path: "ParrotEval")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try report.write(to: folder.appending(path: "report.md"), atomically: true, encoding: .utf8)
    }

    private func engines() -> [EngineID] {
        guard let list = ProcessInfo.processInfo.environment["PARROT_ENGINES"] else { return EngineID.allCases }
        return list.split(separator: ",").compactMap { EngineID(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }

    private func loadClips() throws -> [Clip] {
        let files = (try? FileManager.default.contentsOfDirectory(at: History.evalSet, includingPropertiesForKeys: nil)) ?? []
        return try files.filter { $0.pathExtension == "wav" }.sorted { $0.path < $1.path }.compactMap { url in
            let txt = url.deletingPathExtension().appendingPathExtension("txt")
            guard let reference = try? String(contentsOf: txt, encoding: .utf8) else { return nil }
            return Clip(name: url.deletingPathExtension().lastPathComponent, samples: try WAV.read(url), reference: reference)
        }
    }
}
