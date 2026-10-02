import SwiftUI

/// The speech models, what each takes on disk, and a way to delete the ones you don't use.
struct ModelsView: View {
    @Environment(ParrotStore.self) private var store
    /// Bytes on disk per downloaded model. Read on open and after each change, since
    /// enumerating a model folder is too slow to do on every redraw.
    @State private var sizes: [EngineID: Int64] = [:]
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Models download the first time you pick them. Delete the ones you don't use to free up space. Picking one again downloads it again.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red)
                }
            }
            .padding(16)

            Divider()

            List {
                ForEach(EngineID.allCases) { id in
                    ModelRow(id: id, bytes: sizes[id]) { delete(id) }
                }
            }
            .listStyle(.inset)

            Divider()

            Text("Downloaded models use \(format(sizes.values.reduce(0, +))) on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 520, minHeight: 380)
        .onAppear(perform: measure)
        .onChange(of: store.engineStates) { measure() }
    }

    private func measure() {
        sizes = Dictionary(uniqueKeysWithValues: EngineID.allCases.compactMap { id in id.downloadedBytes.map { (id, $0) } })
    }

    private func delete(_ id: EngineID) {
        do {
            try store.deleteModel(id)
            error = nil
        } catch {
            self.error = "Couldn't delete \(id.name): \(error.localizedDescription)"
        }
        measure()
    }
}

private struct ModelRow: View {
    @Environment(ParrotStore.self) private var store
    let id: EngineID
    let bytes: Int64?
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(id.name).font(.system(size: 14, weight: .medium))
                Text(status).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if bytes != nil, id != store.engineID, store.engineStates[id] != .loading {
                Button("Delete", systemImage: "trash", action: delete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Delete \(id.name)")
            }
        }
        .padding(.vertical, 3)
    }

    private var status: String {
        if id.downloadFolder == nil { return "Built into macOS" }
        if store.engineStates[id] == .loading { return "Downloading or loading…" }
        guard let bytes else { return "Not downloaded" }
        return id == store.engineID ? "\(format(bytes)), in use" : format(bytes)
    }
}

private func format(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
