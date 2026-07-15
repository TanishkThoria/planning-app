import SwiftUI

/// One-move backlog rescue: takes every overdue task and lays it across the
/// next several days' free time (profile-aware), so an intimidating pile of
/// red becomes a plan. Preview, then commit.
struct OverdueSweepView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.planDayGapMinutes) private var gapMinutes = 5
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    private var overdue: [TaskItem] {
        let scheduled = Set(service.blocks.compactMap(\.linkedTaskID))
        return service.tasks
            .filter { !$0.isCompleted && $0.isOverdue && !$0.isSubtask
                && !scheduled.contains($0.id) && !model.hiddenListIDs.contains($0.listID) }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    private var days: [Date] {
        (0..<7).map { Date().startOfDay.adding(days: $0) }
    }

    private var planByDay: [Date: [AutoScheduler.Proposal]] {
        AutoScheduler.planWeek(
            tasks: overdue, existing: service.blocks, days: days,
            workStartMinutes: workStartMinutes, workEndMinutes: workEndMinutes,
            snapMinutes: snapMinutes, defaultMinutes: defaultBlockMinutes,
            gapPaddingMinutes: gapMinutes, profile: profileStore.profile
        )
    }

    private var total: Int { planByDay.values.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            if overdue.isEmpty {
                EmptyStateView(icon: "checkmark.seal.fill", title: "No overdue tasks",
                               message: "Your backlog is clear. Beautiful.")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(overdue.count) overdue task\(overdue.count == 1 ? "" : "s") — here's where they'd land:")
                            .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
                        ForEach(planByDay.keys.sorted(), id: \.self) { day in
                            dayGroup(day, planByDay[day] ?? [])
                        }
                        if total < overdue.count {
                            Label("\(overdue.count - total) didn't fit in the next 7 days — free up time or shorten estimates.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.warning)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer
        }
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 480, height: 600)
        #else
        .presentationDetents([.large])
        #endif
    }

    private var headerBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain).font(.system(size: 14.5)).foregroundStyle(Theme.textSecondary)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("Clear Overdue").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Cancel").font(.system(size: 14.5)).hidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func dayGroup(_ day: Date, _ proposals: [AutoScheduler.Proposal]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Fmt.relativeDay(day))
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(day.isToday ? Theme.accentColor : Theme.textPrimary).padding(.leading, 2)
            ForEach(proposals) { p in
                HStack(spacing: 10) {
                    Text(Fmt.time.string(from: p.start))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 60, alignment: .leading)
                    Text(p.task.title).font(.system(size: 14)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    Text(Fmt.duration(minutes: p.minutes)).font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(total == 0 ? "" : "\(total) block\(total == 1 ? "" : "s") will be created")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                let snapshot = planByDay
                for (_, proposals) in snapshot {
                    for p in proposals {
                        service.scheduleTask(p.task, at: p.start, minutes: p.minutes,
                                             calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID)
                        // Sweeping an overdue task forward is a punt — keep
                        // the honest tally.
                        service.bumpPuntCount(id: p.task.id)
                    }
                }
                Haptics.success()
                dismiss()
            } label: {
                Text("Schedule All")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.bg)
                    .padding(.horizontal, 18).padding(.vertical, 7)
                    .background(Theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(total == 0).opacity(total == 0 ? 0.4 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }
}
