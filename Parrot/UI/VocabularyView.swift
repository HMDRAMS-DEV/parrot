import SwiftUI

/// Names and terms Parrot should spell right, each with the ways the models mishear it.
struct VocabularyView: View {
    @Environment(ParrotStore.self) private var store
    @State private var newTerm = ""
    @State private var newAliases = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Words Parrot should spell your way, like names, products, and jargon. Add how it mishears them, separated by commas, and Parrot swaps them in.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TextField("Word or name, like Alma", text: $newTerm)
                        .frame(width: 180)
                    TextField("Heard as, like Alba, Elma", text: $newAliases)
                    Button("Add", action: add)
                        .buttonStyle(PillButtonStyle())
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            }
            .padding(16)

            Divider()

            if store.vocabulary.terms.isEmpty {
                ContentUnavailableView("No words yet", systemImage: "character.book.closed", description: Text("Add a name Parrot keeps getting wrong."))
            } else {
                List {
                    ForEach(store.vocabulary.terms) { term in
                        TermRow(term: term)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private func add() {
        store.vocabulary.add(newTerm, aliases: newAliases.split(separator: ",").map(String.init))
        newTerm = ""
        newAliases = ""
    }
}

private struct TermRow: View {
    @Environment(ParrotStore.self) private var store
    let term: VocabTerm
    @State private var aliases = ""

    var body: some View {
        HStack(spacing: 12) {
            Text(term.text)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)
            TextField("Heard as", text: $aliases)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit(save)
            Button("Delete", systemImage: "trash") { store.vocabulary.delete(term) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete")
        }
        .padding(.vertical, 2)
        .onAppear { aliases = term.aliases.joined(separator: ", ") }
        .onChange(of: aliases) { save() }
    }

    private func save() {
        var term = term
        term.aliases = aliases.split(separator: ",").map(String.init)
        guard term.aliases.map({ $0.trimmingCharacters(in: .whitespaces) }) != self.term.aliases else { return }
        store.vocabulary.update(term)
    }
}
