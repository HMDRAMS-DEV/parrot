import SwiftUI

/// Every dictation, newest first. Right-click a row to compare engines on that recording or add
/// it to the eval set.
struct HistoryView: View {
    @Environment(ParrotStore.self) private var store
    @State private var query = ""
    @State private var comparing: Dictation?
    @State private var copies = 0
    @State private var confirmingClear = false

    var body: some View {
        let entries = filtered
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Nothing yet" : "No matches",
                    systemImage: "bird",
                    description: Text(query.isEmpty ? "Tap Option, speak, and tap Option again." : "Try other words.")
                )
            } else {
                List(entries) { entry in
                    Row(entry: entry) { copy(entry.text) }
                        .contextMenu {
                            Button("Copy") { copy(entry.text) }
                            Button("Compare Models…") { comparing = entry }
                                .disabled(!hasClip(entry))
                            Button("Add to Eval Set") { try? store.history.addToEvalSet(entry) }
                                .disabled(!hasClip(entry))
                            Button("Show Recording in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([History.clip(for: entry)])
                            }
                            .disabled(!hasClip(entry))
                            Divider()
                            Button("Delete", role: .destructive) { store.history.delete(entry) }
                        }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $query)
        .toolbar {
            Button("Clear History", systemImage: "trash") { confirmingClear = true }
                .disabled(store.history.entries.isEmpty)
                .help("Clear History")
        }
        .confirmationDialog("Clear all \(store.history.entries.count) dictations?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { store.history.clear() }
        } message: {
            Text("This deletes their text and recordings. Your eval set stays.")
        }
        .toast("Copied", trigger: copies)
        .frame(minWidth: 480, minHeight: 360)
        .sheet(item: $comparing) { CompareView(entry: $0) }
    }

    private func copy(_ text: String) {
        copyToClipboard(text)
        copies += 1
    }

    private var filtered: [Dictation] {
        guard !query.isEmpty else { return store.history.entries }
        return store.history.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private func hasClip(_ entry: Dictation) -> Bool {
        FileManager.default.fileExists(atPath: History.clip(for: entry).path)
    }
}

private struct Row: View {
    let entry: Dictation
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.engineName) · \(Format.seconds(entry.audio)) of speech · ready in \(Format.seconds(entry.latency))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
        .padding(.vertical, 4)
    }
}

/// One recording through every engine, side by side.
private struct CompareView: View {
    @Environment(ParrotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: Dictation

    @State private var results: [EngineID: Result<(text: String, seconds: Double), any Error>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compare models").display(18)
            Text("\(Format.seconds(entry.audio)) recording. Word errors are counted against what you dictated with \(entry.engineName).")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(EngineID.allCases) { id in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(id.name).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(meta(id)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            switch results[id] {
                            case nil: ProgressView().controlSize(.small)
                            case .success(let result): Text(result.text).font(.system(size: 13)).textSelection(.enabled)
                            case .failure(let error): Text(error.localizedDescription).font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tile()
                    }
                }
            }

            HStack {
                Text("Timings include loading a model the first time.").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .task {
            // One at a time, so the timings don't fight over the Neural Engine.
            for id in EngineID.allCases {
                do {
                    results[id] = .success(try await store.rerun(entry, with: id))
                } catch {
                    results[id] = .failure(error)
                }
            }
        }
    }

    private func meta(_ id: EngineID) -> String {
        guard case .success(let result) = results[id] else { return "" }
        let wer = WordErrorRate.rate(reference: entry.text, hypothesis: result.text)
        return "\(Format.seconds(result.seconds)) · \(Int((wer * 100).rounded()))% different"
    }
}
