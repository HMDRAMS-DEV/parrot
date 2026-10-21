import Foundation
import HuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// S1-mini by Superwhisper: Qwen3 0.6B trained only to clean dictation. Beyond punctuation and
/// fillers, it resolves self-corrections ("forty two no sorry forty three" becomes "43") and
/// writes numbers, dates, and emails. Runs on the GPU with MLX, 8-bit weights from
/// mlx-community, downloaded to ~/Library/Application Support/Parrot/Models on first use.
actor S1MiniCleaner: Cleaner {
    static let repo = "mlx-community/S1-mini-MLX-8bit"
    static let folder = URL.applicationSupportDirectory.appending(path: "Parrot/Models")

    // The model card asks for this exact prompt and a control line before the transcript.
    private static let instructions = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."
    private static let control = "[Styling: semi-formal] [Structure: prose] [Context: general]"

    private var loading: Task<ModelContainer, any Error>?

    /// Whether picking it needs a download first.
    static var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: "models--" + repo.replacingOccurrences(of: "/", with: "--")).path)
    }

    /// Downloads the model if needed and loads it. Safe to call again. `progress` reports the
    /// download, 0 to 1, to the first caller only.
    func load(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> ModelContainer {
        let task = loading ?? Task {
            let hub = HubClient(cache: HubCache(cacheDirectory: Self.folder))
            return try await loadModelContainer(from: HubDownloader(hub: hub), using: TokenizerLoader(), id: Self.repo) { progress($0.fractionCompleted) }
        }
        loading = task
        do {
            return try await task.value
        } catch {
            loading = nil
            throw error
        }
    }

    func clean(_ text: String, vocabulary: [String]) async throws -> String {
        let model = try await load()
        // Thinking on gives blank output. Greedy, with room for 1.3 times the input.
        let input = UserInput(
            chat: [.system(Self.instructions), .user(Self.control + "\n" + text)],
            additionalContext: ["enable_thinking": false])
        let limit = await model.encode(text).count * 13 / 10 + 32
        let prepared = try await model.prepare(input: input)
        var output = ""
        for await generation in try await model.generate(input: prepared, parameters: GenerateParameters(maxTokens: limit, temperature: 0)) {
            if case .chunk(let chunk) = generation { output += chunk }
        }
        return output
    }

    nonisolated func isFaithful(_ cleaned: String, to original: String) -> Bool {
        Cleanup.addsNoWords(cleaned, to: original)
    }
}

// mlx-swift-lm ships these two bridges as macros, which Xcode makes you trust before building.

private struct HubDownloader: MLXLMCommon.Downloader {
    let hub: HubClient

    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool, progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        guard let repo = Repo.ID(rawValue: id) else { throw CocoaError(.fileNoSuchFile) }
        return try await hub.downloadSnapshot(of: repo, revision: revision ?? "main", matching: patterns) { @MainActor progress in
            progressHandler(progress)
        }
    }
}

private struct TokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
