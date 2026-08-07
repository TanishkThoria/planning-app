import SwiftUI

/// Create or edit a life event on the memory timeline.
struct MemoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var life: LifeStore

    let context: MemoryEditContext
    @State private var draft: LifeEvent
    @State private var date: Date

    init(context: MemoryEditContext) {
        self.context = context
        var e = context.event
        if e.epoch == 0 { e.epoch = Date().timeIntervalSince1970 }
        _draft = State(initialValue: e)
        _date = State(initialValue: Date(timeIntervalSince1970: e.epoch == 0 ? Date().timeIntervalSince1970 : e.epoch))
    }

    private let emojis = ["", "🎓", "🏆", "🚀", "💼", "🏅", "❤️", "✈️", "🎉", "📚", "💡", "🏔️", "🎂", "⭐️"]

    var body: some View {
        NavigationStack {
            Form {
                Section("The moment") {
                    TextField("What happened? (\"Accepted into college\")", text: $draft.title)
                    TextField("A note (optional)", text: $draft.note, axis: .vertical).lineLimit(1...4)
                    DatePicker("When", selection: $date, displayedComponents: .date)
                }

                Section("Kind") {
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(LifeEventKind.allCases) { k in
                            Label(k.label, systemImage: k.icon).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                        ForEach(emojis, id: \.self) { e in
                            Button { draft.emoji = e; Haptics.light() } label: {
                                Group {
                                    if e.isEmpty {
                                        Image(systemName: draft.kind.icon).font(.system(size: 15))
                                            .foregroundStyle(draft.emoji.isEmpty ? Color.white : Theme.textSecondary)
                                    } else {
                                        Text(e).font(.system(size: 20))
                                    }
                                }
                                .frame(width: 38, height: 38)
                                .background(draft.emoji == e ? draft.kind.color : Theme.fill,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !context.isNew {
                    Section {
                        Button(role: .destructive) { life.deleteEvent(draft.id); dismiss() } label: {
                            Label("Delete memory", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(context.isNew ? "New Memory" : "Edit Memory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = "A moment" }
                        draft.epoch = date.timeIntervalSince1970
                        if context.isNew { life.addEvent(draft) } else { life.updateEvent(draft) }
                        dismiss()
                    }
                }
            }
        }
    }
}
