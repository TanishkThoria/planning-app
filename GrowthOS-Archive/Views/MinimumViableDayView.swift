import SwiftUI

/// The morning question that fights all-or-nothing thinking: not "plan your
/// perfect day," but "what is the minimum version of today that keeps you
/// moving?" A daily mode sets the tone; must-wins define the floor; bonuses are
/// upside. Clearing the floor *is* a good day.
struct MinimumViableDayView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var life: LifeStore

    @State private var draft = DayIntent()
    @State private var loaded = false
    @State private var newMustWin = ""
    @State private var newBonus = ""

    private var today: Date { Date().startOfDay }
    private var mode: DailyMode? { draft.mode }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    modePicker
                    mustWinsSection
                    bonusSection
                    if draft.floorCleared { clearedNote }
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Today, on purpose")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .chronosAppearance()
        .onAppear { if !loaded { draft = life.intentOrNew(for: today); loaded = true } }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's the minimum version of today that keeps you moving?")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Name the floor, not the ceiling. Clear your must-wins and today counts — no matter what else happens.")
                .font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Mode

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Today's mode")
            HStack(spacing: 10) {
                ForEach(DailyMode.allCases) { m in modeTile(m) }
            }
            if let mode {
                Text(mode.guidance)
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    private func modeTile(_ m: DailyMode) -> some View {
        let on = draft.modeRaw == m.rawValue
        return Button {
            withAnimation(.snappy) { draft.modeRaw = m.rawValue }
            persist(); Haptics.light()
        } label: {
            VStack(spacing: 7) {
                IconChip(icon: m.icon, tint: m.color, size: 34)
                Text(m.title).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(on ? m.color : Theme.textPrimary)
                Text(m.tagline).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(on ? m.color.opacity(0.12) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(on ? m.color.opacity(0.5) : Theme.hairline, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Must-wins

    private var mustWinsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Must win")
                Spacer()
                if let mode {
                    Text("\(mode.suggestedMustWins) suggested")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textTertiary)
                }
            }
            ForEach(draft.mustWins) { item in itemRow(item, isBonus: false) }
            addRow(text: $newMustWin, placeholder: "A non-negotiable for today") {
                appendItem(&draft.mustWins, newMustWin); newMustWin = ""
            }
        }
    }

    private var bonusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Bonus")
            if draft.bonuses.isEmpty {
                Text("Extra credit — only if the must-wins are handled.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
            }
            ForEach(draft.bonuses) { item in itemRow(item, isBonus: true) }
            addRow(text: $newBonus, placeholder: "Something nice-to-have") {
                appendItem(&draft.bonuses, newBonus); newBonus = ""
            }
        }
    }

    private func itemRow(_ item: IntentItem, isBonus: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                toggle(item, isBonus: isBonus); Haptics.success()
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(item.isDone ? Theme.success : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            Text(item.text)
                .font(.system(size: 14.5))
                .foregroundStyle(item.isDone ? Theme.textTertiary : Theme.textPrimary)
                .strikethrough(item.isDone, color: Theme.textTertiary)
            Spacer(minLength: 4)
            Button { remove(item, isBonus: isBonus) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .panel(padding: 12)
    }

    private func addRow(text: Binding<String>, placeholder: String, add: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.accentColor)
            TextField(placeholder, text: text)
                .font(.system(size: 14.5))
                .onSubmit(add)
            if !text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add", action: add).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentColor).buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var clearedNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 20)).foregroundStyle(Theme.success)
            Text("Floor cleared. Today counts — everything from here is upside.")
                .font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Mutations (persist immediately so Today stays in sync)

    private func appendItem(_ list: inout [IntentItem], _ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        list.append(IntentItem(text: t))
        persist(); Haptics.light()
    }
    private func toggle(_ item: IntentItem, isBonus: Bool) {
        if isBonus, let i = draft.bonuses.firstIndex(where: { $0.id == item.id }) {
            draft.bonuses[i].isDone.toggle()
            draft.bonuses[i].doneEpoch = draft.bonuses[i].isDone ? Date().timeIntervalSince1970 : nil
        } else if let i = draft.mustWins.firstIndex(where: { $0.id == item.id }) {
            draft.mustWins[i].isDone.toggle()
            draft.mustWins[i].doneEpoch = draft.mustWins[i].isDone ? Date().timeIntervalSince1970 : nil
        }
        persist()
    }
    private func remove(_ item: IntentItem, isBonus: Bool) {
        if isBonus { draft.bonuses.removeAll { $0.id == item.id } }
        else { draft.mustWins.removeAll { $0.id == item.id } }
        persist()
    }
    private func persist() { life.upsert(draft) }
}
