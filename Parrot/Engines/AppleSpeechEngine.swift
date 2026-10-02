import AVFoundation
import Foundation
import Speech

/// macOS's on-device recognizer (SpeechAnalyzer). The language model is a system asset that
/// macOS downloads once and shares across apps.
actor AppleSpeechEngine: TranscriptionEngine {
    private let locale: Locale
    private var ready = false

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func prepare() async throws {
        guard !ready else { return }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw EngineError.unsupportedLanguage(locale.identifier)
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        ready = true
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await prepare()
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return "" }

        // The analyzer reads files in any format, so the clip goes through a temporary WAV.
        let url = FileManager.default.temporaryDirectory.appending(path: "parrot-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try WAV.write(samples, to: url)

        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let text = transcriber.results.reduce(into: "") { text, result in
            text += String(result.text.characters)
        }
        let file = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum EngineError: LocalizedError {
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let id): "Apple Speech doesn't support \(id) on this Mac."
        }
    }
}
