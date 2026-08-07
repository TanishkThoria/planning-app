import SwiftUI

/// The Aspiration Vault — desires reframed. Anything the user wants to own or
/// experience is saved here, but only alongside *what version of themselves it
/// represents* and *what evidence they're building toward it*. A watch stops
/// being a distraction and becomes a symbol of the person they're becoming.
struct AspirationVaultView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var life: LifeStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    if life.activeAspirations.isEmpty {
                        EmptyStateView(
                            icon: "sparkles",
                            title: "Nothing saved yet",
                            message: "Save something you want — then tie it to who you're becoming.",
                            actionTitle: "Add an aspiration"
                        ) {
                            model.aspirationEditor = AspirationEditContext(aspiration: Aspiration(), isNew: true)
                        }
                    } else {
                        ForEach(life.activeAspirations) { item in card(item) }
                    }
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Aspiration Vault")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.aspirationEditor = AspirationEditContext(aspiration: Aspiration(), isNew: true)
                    } label: { Image(systemName: "plus") }
                }
            }
        }
        .chronosAppearance()
        .sheet(item: $model.aspirationEditor) { context in
            AspirationEditorView(context: context)
        }
    }

    private var intro: some View {
        Text("Desire, redirected. Each thing you want is a symbol of who you're becoming — and a reason to keep building the evidence.")
            .font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func card(_ item: Aspiration) -> some View {
        let pillar = item.linkedPillarID.flatMap { life.pillar($0) }
        let goal = item.linkedGoalID.flatMap { id in life.activeGoals.first { $0.id == id } }
        return Button {
            model.aspirationEditor = AspirationEditContext(aspiration: item, isNew: false)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(item.emoji).font(.system(size: 30))
                        .frame(width: 48, height: 48)
                        .background(item.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            .strikethrough(item.isAcquired, color: Theme.textTertiary)
                        if !item.priceNote.isEmpty {
                            Text(item.priceNote).font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    if item.isAcquired {
                        Label("Earned", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.success)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.success.opacity(0.14), in: Capsule())
                    }
                }
                if !item.meaning.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "quote.opening").font(.system(size: 11)).foregroundStyle(item.color)
                        Text(item.meaning).font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if pillar != nil || goal != nil {
                    HStack(spacing: 8) {
                        if let pillar {
                            linkChip(pillar.iconName, pillar.name, pillar.color)
                        }
                        if let goal {
                            linkChip(goal.kind.icon, goal.title.isEmpty ? "Goal" : goal.title, goal.color)
                        }
                    }
                }
            }
            .panel()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { life.toggleAcquired(item.id) } label: {
                Label(item.isAcquired ? "Mark as not earned" : "Mark as earned",
                      systemImage: item.isAcquired ? "arrow.uturn.backward" : "checkmark.seal")
            }
            Button(role: .destructive) { life.deleteAspiration(item.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func linkChip(_ icon: String, _ text: String, _ tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
