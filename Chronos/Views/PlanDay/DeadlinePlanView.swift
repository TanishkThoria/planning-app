import SwiftUI

/// Deadline work-back planner: takes everything due in the next week or two,
/// figures out how much work each item still needs (estimate minus what's
/// already scheduled), and spreads study sessions across the days *before*
/// each deadline — earliest deadlines first, capped per day so no single day
/// becomes a marathon. The antidote to "it's due tomorrow and I haven't
/// started."
struct DeadlinePlanView: View {
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

    @State private var horizonDays = 7
    @State private var dailyCapMinutes = 180

    private var now: Date { Date() }

    /// Due-dated, incomplete work with meaningful remaining effort.
    private var candidates: [TaskItem] {
        let horizonEnd = now.startOfDay.adding(days: horizonDays)
        return service.tasks.compactMap { task in
            guard !task.isCompleted, !task.isSubtask,
                  let due = task.dueDate,
                  due <= horizonEnd, due.endOfDay >= now
            else { return nil }
            let scheduled = service.blocksLinked(to: task.id)
                .filter { $0.end > now }
                .reduce(0) { $0 + $1.durationMinutes }
            let remaining = (task.estimateMinutes ?? defaultBlockMinutes) - scheduled
            guard remaining >= 10 else { return nil }
            var adjusted = task
            adjusted.estimateMinutes = remaining
            return adjusted
        }
    }

    private var planByDay: [Date: [AutoScheduler.Proposal]] {
        AutoScheduler.planDeadlines(
            tasks: candidates,
            existing: service.blocks,
            horizonDays: horizonDays,
            maxDailyMinutes: dailyCapMinutes,
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            snapMinutes: snapMinutes,
            defaultMinutes: defaultBlockMinutes,
            gapPaddingMinutes: gapMinutes,
            profile: profileStore.profile,
            now: now
        )
    }

    /// Tasks whose remaining effort didn't fully fit before their deadline.
    private func unplaced(in plan: [Date: [AutoScheduler.Proposal]]) -> [TaskItem] {
        var placed: [String: Int] = [:]
        for proposals in plan.values {
            for proposal in proposals { placed[proposal.task.id, default: 0] += proposal.minutes }
        }
        return candidates.filter { task in
            (placed[task.id] ?? 0) < (task.estimateMinutes ?? defaultBlockMinutes) - 5
        }
    }

    var body: some View {
        let plan = planByDay
        let days = plan.keys.sorted()
        let totalMinutes = plan.values.flatMap { $0 }.reduce(0) { $0 + $1.minutes }
        let missed = unplaced(in: plan)

        return VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    controls

                    if candidates.isEmpty {
                        EmptyStateView(
                            icon: "checkmark.seal",
                            title: "No deadlines need planning",
                            message: "Everything due in the next \(horizonDays) days is either done, fully scheduled, or has no due date. Add estimates to tasks so I know how much time they need."
                        )
                    } else {
                        ForEach(days, id: \.self) { day in
                            daySection(day, proposals: plan[day] ?? [])
                        }
                        if !missed.isEmpty {
                            missedCard(missed)
                        }
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)

            footer(totalMinutes: totalMinutes, sessionCount: plan.values.flatMap { $0 }.count)
        }
        .background(Theme.bg)
        .chronosAppearance()
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 560)
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Plan Deadlines")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Work backwards from every due date")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LOOK AHEAD")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                Picker("", selection: $horizonDays) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("MAX STUDY / DAY")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                Picker("", selection: $dailyCapMinutes) {
                    Text("2h").tag(120)
                    Text("3h").tag(180)
                    Text("4h").tag(240)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
        }
    }

    private func daySection(_ day: Date, proposals: [AutoScheduler.Proposal]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Fmt.relativeDay(day))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(day.isToday ? Theme.accentColor : Theme.textPrimary)
                Spacer()
                Text(Fmt.duration(minutes: proposals.reduce(0) { $0 + $1.minutes }))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.leading, 2)

            ForEach(proposals) { proposal in
                HStack(spacing: 10) {
                    Text(Fmt.time.string(from: proposal.start))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 60, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(proposal.task.title)
                            .font(.system(size: 14)).foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if let due = proposal.task.dueDate {
                            Text("due \(Fmt.relativeDay(due))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer()
                    Text(Fmt.duration(minutes: proposal.minutes))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private func missedCard(_ tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Couldn't fully fit before the deadline", systemImage: "exclamationmark.triangle")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.warning)
            ForEach(tasks.prefix(5)) { task in
                Text("• \(task.title)")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Text("Free up time, raise the daily cap, or trim these estimates.")
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func footer(totalMinutes: Int, sessionCount: Int) -> some View {
        HStack {
            Text(sessionCount == 0 ? "Nothing to schedule"
                 : "\(sessionCount) session\(sessionCount == 1 ? "" : "s") · \(Fmt.duration(minutes: totalMinutes))")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                apply()
            } label: {
                Text("Add to Calendar")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sessionCount == 0)
            .opacity(sessionCount == 0 ? 0.4 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func apply() {
        for (_, proposals) in planByDay {
            for proposal in proposals {
                service.scheduleTask(
                    proposal.task,
                    at: proposal.start,
                    minutes: proposal.minutes,
                    calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID
                )
            }
        }
        Haptics.success()
        dismiss()
    }
}
