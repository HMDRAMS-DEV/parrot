import SwiftUI

/// Recorded calls on the left, the summary and transcript of the chosen one on the right.
struct CallsView: View {
    @Environment(ParrotStore.self) private var store
    @State private var selection: Call.ID?
    @State private var copies = 0
    @State private var deleting: Call?

    var body: some View {
        NavigationSplitView {
            List(store.calls.entries, selection: $selection) { call in
                VStack(alignment: .leading, spacing: 3) {
                    Text(call.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("\(call.started.formatted(date: .abbreviated, time: .shortened)) · \(Format.duration(call.duration))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("Delete", role: .destructive) { deleting = call }
                        .disabled(isRecording(call))
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let call = store.calls.entries.first(where: { $0.id == selection }) ?? live(selection) {
                CallDetail(call: call) { text in
                    copyToClipboard(text)
                    copies += 1
                }
            } else {
                ContentUnavailableView(
                    store.calls.entries.isEmpty ? "No calls yet" : "Pick a call",
                    systemImage: "phone",
                    description: Text(store.calls.entries.isEmpty ? "Click Record in the Parrot menu when a call starts." : "")
                )
            }
        }
        .onAppear { selection = selection ?? store.call?.id ?? store.calls.entries.first?.id }
        .confirmationDialog("Delete this call?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { call in
            Button("Delete", role: .destructive) {
                store.calls.delete(call)
                if selection == call.id { selection = nil }
            }
        } message: { _ in
            Text("This deletes its transcript and summary.")
        }
        .toast("Copied", trigger: copies)
        .frame(minWidth: 640, minHeight: 420)
    }

    /// The call being recorded has newer lines than the saved copy.
    private func live(_ id: Call.ID?) -> Call? {
        store.call?.id == id ? store.call : nil
    }

    private func isRecording(_ call: Call) -> Bool {
        store.call?.id == call.id && store.callState != .off
    }
}

private struct CallDetail: View {
    @Environment(ParrotStore.self) private var store
    let call: Call
    let onCopy: (String) -> Void

    var body: some View {
        let shown = store.call?.id == call.id ? store.call ?? call : call
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary(shown)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Transcript").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Copy") { onCopy(shown.transcript) }.disabled(shown.lines.isEmpty)
                    }
                    if shown.lines.isEmpty {
                        Text("No words yet.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    ForEach(Array(shown.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(line.speaker.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(line.speaker == .you ? Color.accentColor : .secondary)
                                .frame(width: 40, alignment: .leading)
                            Text(line.text)
                                .font(.system(size: 14))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    @ViewBuilder private func summary(_ call: Call) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Summary").font(.system(size: 13, weight: .semibold))
                Spacer()
                if store.summarizing.contains(call.id) {
                    ProgressView().controlSize(.small)
                } else if call.ended != nil {
                    Button(call.summary == nil ? "Summarize" : "Summarize Again") {
                        Task { await store.summarize(call) }
                    }
                    if let summary = call.summary {
                        Button("Copy") { onCopy(summary) }
                    }
                }
            }
            if let summary = call.summary {
                MarkdownText(summary)
            } else {
                Text(call.ended == nil ? "Parrot writes a summary when the call ends." : "No summary yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Renders the summarizer's headings and bullets, line by line.
private struct MarkdownText: View {
    let lines: [Substring]

    init(_ text: String) {
        lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("## ") {
                    Text(inline(line.dropFirst(3))).font(.system(size: 13, weight: .semibold)).padding(.top, 6)
                } else if line.hasPrefix("# ") {
                    Text(inline(line.dropFirst(2))).font(.system(size: 18, weight: .semibold))
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        // The model sometimes writes "- •" for a bullet.
                        Text(inline(line.dropFirst(2).drop { $0 == "•" || $0 == " " }))
                    }
                    .font(.system(size: 14))
                } else {
                    Text(inline(line)).font(.system(size: 14))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ text: Substring) -> AttributedString {
        (try? AttributedString(markdown: String(text))) ?? AttributedString(String(text))
    }
}
