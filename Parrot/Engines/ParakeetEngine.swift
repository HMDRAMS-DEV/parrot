import FluidAudio
import Foundation

/// NVIDIA Parakeet and its derivatives, run on the Neural Engine through FluidAudio. Models
/// download to ~/Library/Application Support/FluidAudio/Models on first use.
actor ParakeetEngine: TranscriptionEngine {
    private let version: AsrModelVersion
    private var manager: AsrManager?
    private var boosting: VocabularyBoostingSession?
    private var vocabulary: [VocabTerm] = []
    private var ctc: CtcModels?

    init(version: AsrModelVersion) {
        self.version = version
    }

    func prepare() async throws {
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: version)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await prepare()
        guard let manager else { return "" }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state)
        guard let boosting else { return result.text }
        // A small CTC model (110M) listens for the terms in the same audio and swaps in a term
        // where the transcript has a near miss with good acoustic evidence.
        return await boosting.rescore(text: result.text, tokenTimings: result.tokenTimings ?? [], audioSamples: samples)?.text ?? result.text
    }

    func useVocabulary(_ terms: [VocabTerm]) async {
        guard terms != vocabulary else { return }
        vocabulary = terms
        guard !terms.isEmpty else {
            boosting = nil
            return
        }
        do {
            let context = CustomVocabularyContext(terms: terms.map { CustomVocabularyTerm(text: $0.text, aliases: $0.aliases.isEmpty ? nil : $0.aliases) })
            let ctc: CtcModels
            if let loaded = self.ctc {
                ctc = loaded
            } else {
                ctc = try await CtcModels.downloadAndLoad()
                self.ctc = ctc
            }
            // The stricter config keeps the spotter from replacing unrelated words: with the default,
            // "The parakeet model" became "FluidAudio".
            let session = try await VocabularyBoostingSession(vocabulary: context, ctcModels: ctc, config: VocabularyBoostingSession.itnDefaultConfig)
            // A newer list may have arrived while the models loaded.
            if vocabulary == terms { boosting = session }
        } catch {
            // Boosting is a bonus. Aliases and cleanup still apply without it.
            if vocabulary == terms { boosting = nil }
        }
    }
}

extension EngineID {
    /// Where FluidAudio keeps this model's download. nil for models that ship with macOS.
    var downloadFolder: URL? {
        let version: AsrModelVersion
        switch self {
        case .parakeetUltra: version = .ultra
        case .phonon2: version = .phonon2
        case .parakeetRedux: version = .redux
        case .parakeetV3: version = .v3
        case .parakeetV2: version = .v2
        case .apple: return nil
        }
        return AsrModels.defaultCacheDirectory(for: version)
    }

    /// Bytes the download takes on disk, or nil when it isn't downloaded.
    var downloadedBytes: Int64? {
        guard let folder = downloadFolder, FileManager.default.fileExists(atPath: folder.path) else { return nil }
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
