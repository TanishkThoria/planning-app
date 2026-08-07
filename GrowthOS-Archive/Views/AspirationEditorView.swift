import SwiftUI

/// Create or edit a vault item. The two reframing questions — what it represents
/// and which goal it depends on — are the whole point, so they're front and
/// centre.
struct AspirationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var life: LifeStore

    let context: AspirationEditContext
    @State private var draft: Aspiration

    init(context: AspirationEditContext) {
        self.context = context
        _draft = State(initialValue: context.aspiration)
    }

    private let emojis = ["✨", "⌚️", "👟", "🏔️", "🚗", "🏠", "📷", "🎸", "💻", "✈️", "💍", "🏆", "📚", "🎧"]

    var body: some View {
        NavigationStack {
            Form {
                Section("What you want") {
                    TextField("Name (\"Omega Speedmaster\")", text: $draft.title)
                    TextField("Cost or savings note (optional)", text: $draft.priceNote)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(emojis, id: \.self) { e in
                                Button { draft.emoji = e } label: {
                                    Text(e).font(.system(size: 22))
                                        .frame(width: 40, height: 40)
                                        .background(draft.emoji == e ? draft.color.opacity(0.2) : Theme.fill,
                                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(Palette.options, id: \.self) { hex in
                            Button { draft.colorHex = hex } label: {
                                Circle().fill(Palette.color(hex)).frame(width: 26, height: 26)
                                    .overlay(Circle().strokeBorder(Theme.textPrimary,
                                        lineWidth: draft.colorHex == hex ? 2.5 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    TextField("What version of yourself does this represent?",
                              text: $draft.meaning, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("What it represents")
                } footer: {
                    Text("Craftsmanship, achievement, financial freedom… name the identity, not just the object.")
                }

                Section("Evidence you're building") {
                    Menu {
                        Button("None") { draft.linkedPillarID = nil }
                        ForEach(life.activePillars) { p in
                            Button(p.name) { draft.linkedPillarID = p.id }
                        }
                    } label: {
                        pickerRow(icon: "figure.stand", label: "Identity pillar",
                                  value: draft.linkedPillarID.flatMap { life.pillar($0)?.name } ?? "None")
                    }
                    if !life.activeGoals.isEmpty {
                        Menu {
                            Button("None") { draft.linkedGoalID = nil }
                            ForEach(life.activeGoals) { g in
                                Button(g.title.isEmpty ? "Untitled goal" : g.title) { draft.linkedGoalID = g.id }
                            }
                        } label: {
                            pickerRow(icon: "target", label: "Goal it depends on",
                                      value: draft.linkedGoalID.flatMap { id in life.activeGoals.first { $0.id == id }?.title } ?? "None")
                        }
                    }
                }

                if !context.isNew {
                    Section {
                        Button { life.toggleAcquired(draft.id) ; dismiss() } label: {
                            Label(draft.isAcquired ? "Mark as not earned yet" : "I earned this",
                                  systemImage: draft.isAcquired ? "arrow.uturn.backward" : "checkmark.seal.fill")
                        }
                        Button(role: .destructive) { life.deleteAspiration(draft.id); dismiss() } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(context.isNew ? "New Aspiration" : "Edit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = "Aspiration" }
                        life.upsert(draft); dismiss()
                    }
                }
            }
        }
    }

    private func pickerRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value).foregroundStyle(Theme.textSecondary).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
    }
}
