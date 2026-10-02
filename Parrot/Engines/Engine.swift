import Foundation

/// A speech-to-text model Parrot can dictate with.
///
/// Engines take 16 kHz mono Float samples and return text. `prepare()` downloads and loads the
/// model and may take a while the first time; Parrot calls it once per engine and keeps it loaded.
protocol TranscriptionEngine: Actor {
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
    /// Terms to listen for. Engines that can't bias toward words ignore this; Parrot still
    /// swaps aliases in every transcript.
    func useVocabulary(_ terms: [VocabTerm]) async
}

extension TranscriptionEngine {
    func useVocabulary(_ terms: [VocabTerm]) async {}
}

/// Every engine Parrot knows about. To add one, add a case, describe it, and return it from
/// `make()`. The menu, the history window's Compare, and the eval test all pick it up from here.
enum EngineID: String, CaseIterable, Codable, Identifiable, Sendable {
    // Newest first.
    case parakeetUltra
    case phonon2
    case parakeetRedux
    case parakeetV3
    case parakeetV2
    case apple

    static let `default`: EngineID = .parakeetUltra

    var id: String { rawValue }

    var name: String {
        switch self {
        case .parakeetV2: "Parakeet v2"
        case .phonon2: "Phonon-2"
        case .parakeetV3: "Parakeet v3"
        case .parakeetUltra: "Parakeet Ultra"
        case .parakeetRedux: "Parakeet Redux"
        case .apple: "Apple Speech"
        }
    }

    var detail: String {
        switch self {
        case .parakeetUltra: "Moondream, Sep 2026. Parakeet v3 post-trained at full precision. Most accurate here. 25 languages."
        case .phonon2: "Fermion, Sep 2026. Parakeet v3 squeezed to five values per weight. English. First load takes about a minute."
        case .parakeetRedux: "Moondream, Sep 2026. Ternary Parakeet v3, 178 MB. 25 languages."
        case .parakeetV3: "NVIDIA, 2025. 25 European languages, detects which one you speak."
        case .parakeetV2: "NVIDIA, 2025. English only."
        case .apple: "Built into macOS. No download, uses the system language."
        }
    }

    func make() -> any TranscriptionEngine {
        switch self {
        case .parakeetV2: ParakeetEngine(version: .v2)
        case .phonon2: ParakeetEngine(version: .phonon2)
        case .parakeetV3: ParakeetEngine(version: .v3)
        case .parakeetUltra: ParakeetEngine(version: .ultra)
        case .parakeetRedux: ParakeetEngine(version: .redux)
        case .apple: AppleSpeechEngine()
        }
    }
}
