import SwiftUI

/// Nice-to-haves: the fun, restful, only-if-there's-time things. This is the
/// reward side of the app — clear your real work and the leftover time in your
/// day becomes room for these. You can drop one straight into the next free slot.
struct NiceToHavesView: View {
    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.workStartMinutes) private var workStart = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEnd = 18 * 60
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15

    @State private var editing: NiceToHave?
    @State private var scheduledNote: String?

    private var today: Date { Date().startOfDay }
    private var items: [NiceToHave] { life.activeNiceToHaves }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rewardCard
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(items) { item in row(item) }
                    }
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Nice-to-haves")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = NiceToHave() } label: { Image(systemName: "plus") }
                }
            }
        }
        .chronosAppearance()
        .sheet(item: $editing) { item in
            NiceToHaveEditor(item: item, isNew: !items.contains { $0.id == item.id })
        }
    }

    // MARK: Reward card (the motivation)

    private var rewardCard: some View {
        let load = DayLoad.compute(tasks: service.tasks, events: service.blocks(on: today),
                                   workStart: workStart, workEnd: workEnd)
        let leftover = max(0, load.freeMinutes - load.committedMinutes)
        let earned = leftover >= 20
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: earned ? "gift.fill" : "hourglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(earned ? Theme.success : Theme.warning)
                Text(earned ? "You've earned some downtime" : "Finish your must-dos first")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text(earned
                 ? "About \(Fmt.duration(minutes: leftover)) of breathing room in your day after your committed work. Treat yourself — drop one of these into the gap."
                 : (load.committedMinutes > 0
                    ? "Your due-today work fills the time you have left. Clear it, and this space opens up for the fun stuff."
                    : "No must-dos due today — the day is yours. Pick something you'd enjoy."))
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let scheduledNote {
                Label(scheduledNote, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.success)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [(earned ? Theme.success : Theme.warning).opacity(0.14), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: Row

    private func row(_ item: NiceToHave) -> some View {
        HStack(spacing: 12) {
            Text(item.emoji)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(item.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Fmt.duration(minutes: item.estimateMinutes))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    if let last = item.lastEnjoyedDate {
                        Text("· last \(Fmt.relativeDay(last).lowercased())")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            Button { schedule(item) } label: {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { editing = item }
        .contextMenu {
            Button { schedule(item) } label: { Label("Add to next free slot", systemImage: "calendar.badge.plus") }
            Button { life.markEnjoyed(item.id); Haptics.success() } label: { Label("Mark enjoyed", systemImage: "checkmark.circle") }
            Button { editing = item } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { life.deleteNiceToHave(item.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 32))
                .foregroundStyle(Theme.warning)
            Text("What would you do with free time?")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("A walk, an episode, that video game, calling a friend. List the things worth doing when the work is done — then reward yourself.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { editing = NiceToHave() } label: {
                Text("Add a nice-to-have")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }

    // MARK: Scheduling

    private func schedule(_ item: NiceToHave) {
        let existing = (0..<7).flatMap { service.blocks(on: today.adding(days: $0)) }
        let start = AutoScheduler.nextFreeSlot(
            after: Date(), minutes: item.estimateMinutes, existing: existing,
            workStartMinutes: workStart, workEndMinutes: workEnd,
            snapMinutes: snapMinutes, profile: profileStore.profile
        )
        var draft = BlockDraft()
        draft.title = "\(item.emoji) \(item.title)".trimmingCharacters(in: .whitespaces)
        draft.start = start
        draft.end = start.adding(minutes: item.estimateMinutes)
        draft.availability = .free
        service.createBlock(draft)
        life.markEnjoyed(item.id)
        Haptics.success()
        let when = Calendar.current.isDateInToday(start)
            ? "today at \(Fmt.time.string(from: start))"
            : "\(Fmt.relativeDay(start)) at \(Fmt.time.string(from: start))"
        withAnimation { scheduledNote = "Added “\(item.title)” \(when)" }
    }
}

// MARK: - Editor

struct NiceToHaveEditor: View {
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var item: NiceToHave
    @State private var confirmingDelete = false
    let isNew: Bool

    private let emojis = ["✨", "🎮", "📺", "🚶", "📖", "🎧", "🛁", "☕️", "🍿", "🎨", "🌳", "😴", "🧩", "🎸", "📱", "🍩"]
    private let estimates = [15, 30, 45, 60, 90, 120]

    init(item: NiceToHave, isNew: Bool) {
        _item = State(initialValue: item)
        self.isNew = isNew
    }

    var body: some View {
        EditorSheet(
            title: isNew ? "New Nice-to-have" : "Edit",
            confirmDisabled: item.title.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: { life.upsert(item) }
        ) {
            TitleField(placeholder: "Something fun…", text: $item.title)
            emojiRow
            colorRow
            VStack(alignment: .leading, spacing: 8) {
                Text("TIME IT TAKES").font(.system(size: 11.5, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
                HStack(spacing: 6) {
                    ForEach(estimates, id: \.self) { m in
                        Button { item.estimateMinutes = m } label: {
                            Text(Fmt.duration(minutes: m))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(item.estimateMinutes == m ? Theme.bg : Theme.textSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(item.estimateMinutes == m ? AnyShapeStyle(Theme.accentColor) : AnyShapeStyle(Theme.fill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            if !isNew {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog("Delete this?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { life.deleteNiceToHave(item.id); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var emojiRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ICON").font(.system(size: 11.5, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(emojis, id: \.self) { e in
                        Button { item.emoji = e } label: {
                            Text(e).font(.system(size: 20))
                                .frame(width: 38, height: 38)
                                .background(item.emoji == e ? AnyShapeStyle(item.color.opacity(0.22)) : AnyShapeStyle(Theme.fill),
                                           in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(item.emoji == e ? item.color : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var colorRow: some View {
        HStack(spacing: 10) {
            ForEach(Palette.options, id: \.self) { hex in
                Button { item.colorHex = hex } label: {
                    Circle().fill(Palette.color(hex)).frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(item.colorHex == hex ? Theme.textPrimary : .clear, lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
