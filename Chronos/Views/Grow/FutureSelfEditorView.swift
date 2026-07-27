import SwiftUI

/// Define the aspirational identity and the 1/5/10-year visions. Writes to the
/// single `LifeStore.futureSelf` value.
struct FutureSelfEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var life: LifeStore

    @State private var draft = FutureSelf()
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
                    ForEach(Array(draft.attributes.enumerated()), id: \.offset) { i, _ in
                        HStack {
                            TextField("Attribute", text: Binding(
                                get: { i < draft.attributes.count ? draft.attributes[i] : "" },
                                set: { if i < draft.attributes.count { draft.attributes[i] = $0 } }
                            ))
                            Button {
                                if i < draft.attributes.count { draft.attributes.remove(at: i) }
                            } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Theme.danger) }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Add an attribute (\"Physically strong\")", text: $newAttribute)
                        Button {
                            let t = newAttribute.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty { draft.attributes.append(t); newAttribute = "" }
                        } label: { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentColor) }
                        .buttonStyle(.plain)
                    }
                }

                Section("The long arc") {
                    visionField("A year from now", text: $draft.visionOneYear)
                    visionField("Five years", text: $draft.visionFiveYear)
                    visionField("Ten years", text: $draft.visionTenYear)
                }

                Section("What that person does today") {
                    ForEach(Array(draft.dailyActions.enumerated()), id: \.offset) { i, _ in
                        HStack {
                            TextField("Daily action", text: Binding(
                                get: { i < draft.dailyActions.count ? draft.dailyActions[i] : "" },
                                set: { if i < draft.dailyActions.count { draft.dailyActions[i] = $0 } }
                            ))
                            Button {
                                if i < draft.dailyActions.count { draft.dailyActions.remove(at: i) }
                            } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Theme.danger) }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Add (\"90-minute deep work block\")", text: $newAction)
                        Button {
                            let t = newAction.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty { draft.dailyActions.append(t); newAction = "" }
                        } label: { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentColor) }
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
                    Button("Save") {
                        draft.attributes = draft.attributes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        draft.dailyActions = draft.dailyActions.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        life.updateFutureSelf(draft)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { if !loaded { draft = life.futureSelf; loaded = true } }
    }

    private func visionField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            TextField("Describe it", text: text, axis: .vertical).lineLimit(2...5)
        }
    }
}
