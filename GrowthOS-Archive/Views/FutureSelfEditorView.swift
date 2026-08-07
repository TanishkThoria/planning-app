import SwiftUI

/// Define the aspirational identity and the 1/5/10-year visions. Writes to the
/// single `LifeStore.futureSelf` value.
struct FutureSelfEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var life: LifeStore

    /// A stably-identified editable line, so deleting a middle row doesn't make
    /// the text fields shuffle (which happens when ForEach keys on the index).
    private struct Row: Identifiable, Hashable {
        let id = UUID()
        var text: String
    }

    @State private var draft = FutureSelf()
    @State private var attrRows: [Row] = []
    @State private var actionRows: [Row] = []
    @State private var loaded = false
    @State private var newAttribute = ""
    @State private var newAction = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Who you're becoming") {
                    TextField("Name (\"The disciplined engineer-athlete\")", text: $draft.name)
                    TextField("One honest sentence", text: $draft.summary, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Attributes") {
                    ForEach($attrRows) { $row in
                        HStack {
                            TextField("Attribute", text: $row.text)
                            Button { attrRows.removeAll { $0.id == row.id } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Theme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Add an attribute (\"Physically strong\")", text: $newAttribute)
                            .onSubmit(addAttribute)
                        Button(action: addAttribute) {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("The long arc") {
                    visionField("A year from now", text: $draft.visionOneYear)
                    visionField("Five years", text: $draft.visionFiveYear)
                    visionField("Ten years", text: $draft.visionTenYear)
                }

                Section("What that person does today") {
                    ForEach($actionRows) { $row in
                        HStack {
                            TextField("Daily action", text: $row.text)
                            Button { actionRows.removeAll { $0.id == row.id } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Theme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Add (\"90-minute deep work block\")", text: $newAction)
                            .onSubmit(addAction)
                        Button(action: addAction) {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Future Self")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .onAppear {
            if !loaded {
                draft = life.futureSelf
                attrRows = draft.attributes.map { Row(text: $0) }
                actionRows = draft.dailyActions.map { Row(text: $0) }
                loaded = true
            }
        }
    }

    private func addAttribute() {
        let t = newAttribute.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        attrRows.append(Row(text: t)); newAttribute = ""
    }

    private func addAction() {
        let t = newAction.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        actionRows.append(Row(text: t)); newAction = ""
    }

    private func save() {
        draft.attributes = attrRows.map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        draft.dailyActions = actionRows.map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        life.updateFutureSelf(draft)
        dismiss()
    }

    private func visionField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            TextField("Describe it", text: text, axis: .vertical).lineLimit(2...5)
        }
    }
}
