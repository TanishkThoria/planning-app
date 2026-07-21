import SwiftUI

/// Personal growth, two ways: the ongoing "start doing / stop doing" list of
/// commitments you're holding yourself to, and a self-mirror where you name the
/// things you like about yourself and the things you're working on — then move
/// them to the like side as you turn them around.
struct PersonalGrowthView: View {
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var startDraft = ""
    @State private var stopDraft = ""
    @State private var likeDraft = ""
    @State private var dislikeDraft = ""
    @State private var editing: GrowthItem?
    @State private var editText = ""
    @State private var editingTrait: SelfTrait?
    @State private var editTraitText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    commitmentsCard(.start, draft: $startDraft)
                    commitmentsCard(.stop, draft: $stopDraft)
                    mirrorSection
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Personal growth")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .chronosAppearance()
        .alert("Edit", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Text", text: $editText)
            Button("Save") {
                if var item = editing {
                    item.text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !item.text.isEmpty { life.upsert(item) }
                    editing = nil
                }
            }
            Button("Cancel", role: .cancel) { editing = nil }
        }
        .alert("Edit", isPresented: Binding(get: { editingTrait != nil }, set: { if !$0 { editingTrait = nil } })) {
            TextField("Text", text: $editTraitText)
            Button("Save") {
                if var t = editingTrait {
                    t.text = editTraitText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.text.isEmpty { life.updateTrait(t) }
                    editingTrait = nil
                }
            }
            Button("Cancel", role: .cancel) { editingTrait = nil }
        }
    }

    // MARK: Start / stop commitments

    private func commitmentsCard(_ direction: GrowthDirection, draft: Binding<String>) -> some View {
        let items = life.commitments(direction)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: direction.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(direction.color)
                Text(direction.label)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            if items.isEmpty {
                Text(direction == .start
                     ? "Things you want to build into your life — “drink more water”, “call home weekly”."
                     : "Things you want to cut back on — “late-night scrolling”, “skipping breakfast”.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(items) { item in commitmentRow(item, direction: direction) }
            }
            addRow(placeholder: direction == .start ? "Start doing…" : "Stop doing…",
                   tint: direction.color, draft: draft) {
                commitGrowth(direction, text: draft.wrappedValue)
                draft.wrappedValue = ""
            }
        }
        .padding(14)
        .background(direction.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(direction.color.opacity(0.25), lineWidth: 1))
    }

    private func commitmentRow(_ item: GrowthItem, direction: GrowthDirection) -> some View {
        HStack(spacing: 10) {
            Circle().fill(direction.color).frame(width: 6, height: 6)
            Text(item.text)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            if item.daysHeld > 0 {
                Text("\(item.daysHeld)d")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { editText = item.text; editing = item }
        .contextMenu {
            Button { editText = item.text; editing = item } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { life.deleteGrowthItem(item.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func commitGrowth(_ direction: GrowthDirection, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        life.upsert(GrowthItem(text: trimmed, direction: direction))
        Haptics.light()
    }

    // MARK: Self-mirror

    private var mirrorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "The mirror")
                Spacer()
                if life.improvedTraitCount > 0 {
                    Label("\(life.improvedTraitCount) turned around", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.success)
                }
            }
            Text("Name what you like about yourself, and what you're working on. As you turn something around, move it to the like side.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            mirrorColumn(
                title: "I like about myself", tint: Color(hex: 0x5BD899), icon: "heart.fill",
                traits: life.likes, draft: $likeDraft, side: .like
            )
            mirrorColumn(
                title: "I'm working on", tint: Theme.warning, icon: "arrow.up.forward",
                traits: life.dislikes, draft: $dislikeDraft, side: .dislike
            )
        }
    }

    private func mirrorColumn(title: String, tint: Color, icon: String,
                              traits: [SelfTrait], draft: Binding<String>, side: SelfTraitSide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            if traits.isEmpty {
                Text(side == .like ? "What are you proud of?" : "What would you like to change?")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(traits) { trait in traitRow(trait, tint: tint, side: side) }
            }
            addRow(placeholder: side == .like ? "Something you like…" : "Something to work on…",
                   tint: tint, draft: draft) {
                life.addTrait(draft.wrappedValue, side: side)
                draft.wrappedValue = ""
                Haptics.light()
            }
        }
        .padding(14)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 1))
    }

    private func traitRow(_ trait: SelfTrait, tint: Color, side: SelfTraitSide) -> some View {
        HStack(spacing: 10) {
            if trait.wasImproved && side == .like {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(tint)
            } else {
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            Text(trait.text)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            if side == .dislike {
                Button {
                    withAnimation(.snappy) { life.moveTraitToLike(trait.id) }
                    Haptics.success()
                } label: {
                    HStack(spacing: 3) {
                        Text("Turned it around").font(.system(size: 11, weight: .semibold))
                        Image(systemName: "arrow.up.forward.circle.fill").font(.system(size: 14))
                    }
                    .foregroundStyle(Color(hex: 0x5BD899))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { editTraitText = trait.text; editingTrait = trait }
        .contextMenu {
            Button { editTraitText = trait.text; editingTrait = trait } label: { Label("Edit", systemImage: "pencil") }
            if side == .dislike {
                Button {
                    withAnimation(.snappy) { life.moveTraitToLike(trait.id) }; Haptics.success()
                } label: { Label("Move to likes", systemImage: "arrow.up.forward") }
            }
            Button(role: .destructive) { life.deleteTrait(trait.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: Shared add row

    private func addRow(placeholder: String, tint: Color, draft: Binding<String>, onAdd: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").font(.system(size: 17)).foregroundStyle(tint.opacity(0.8))
            TextField(placeholder, text: draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textPrimary)
                .onSubmit(onAdd)
            if !draft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: onAdd) {
                    Text("Add").font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
