import SwiftUI

/// "My Manual" — a living operating manual the user writes about how they
/// actually work: principles they stand for, rules they don't break, patterns
/// they've noticed in themselves, and the solutions that reliably work. The
/// Coach reads this to give advice that fits the person, not a generic template.
struct MyManualView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var life: LifeStore

    @State private var drafts: [ManualCategory: String] = [:]
    @State private var editing: ManualNote?
    @State private var editText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    ForEach(ManualCategory.allCases) { category in
                        section(category)
                    }
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("My Manual")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .chronosAppearance()
        .alert("Edit", isPresented: Binding(
            get: { editing != nil }, set: { if !$0 { editing = nil; editText = "" } }
        )) {
            TextField("Text", text: $editText)
            Button("Save") {
                if var note = editing {
                    note.text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if note.text.isEmpty { life.deleteManualNote(note.id) } else { life.upsert(note) }
                }
                editing = nil; editText = ""
            }
            Button("Cancel", role: .cancel) { editing = nil; editText = "" }
        }
    }

    private var intro: some View {
        Text("The operating manual for you. Chronos and your coach use this to give advice that fits how you actually work — not a generic template.")
            .font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func section(_ category: ManualCategory) -> some View {
        let notes = life.notes(category)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconChip(icon: category.icon, tint: category.color, size: 32)
                Text(category.title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            if notes.isEmpty {
                Text(category.prompt)
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(notes) { note in noteRow(note, tint: category.color) }
            }
            addRow(category)
        }
        .padding(14)
        .background(category.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(category.color.opacity(0.22), lineWidth: 1))
    }

    private func noteRow(_ note: ManualNote, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 6)
            Text(note.text).font(.system(size: 14.5)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { editing = note; editText = note.text }
        .contextMenu {
            Button { editing = note; editText = note.text } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { life.deleteManualNote(note.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func addRow(_ category: ManualCategory) -> some View {
        let binding = Binding(
            get: { drafts[category] ?? "" },
            set: { drafts[category] = $0 }
        )
        return HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(category.color)
            TextField("Add a \(category.singular.lowercased())", text: binding)
                .font(.system(size: 14))
                .onSubmit { commit(category) }
            if !(drafts[category] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add") { commit(category) }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(category.color).buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func commit(_ category: ManualCategory) {
        let text = (drafts[category] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        life.upsert(ManualNote(category: category, text: text))
        drafts[category] = ""
        Haptics.light()
    }
}
