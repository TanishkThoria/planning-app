import SwiftUI

/// Long-horizon view of the growth data: mood & energy over the last month,
/// per-habit consistency grids, goal progress, and a browsable archive of
/// past reflections. The Grow tab shows today; this shows the trajectory.
struct TrendsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss


    private var today: Date { Date().startOfDay }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    habitsCard
                    if !life.activeGoals.isEmpty { goalsCard }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
        .chronosAppearance()
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trends")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your last few weeks, at a glance")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Mood & energy (last 30 days)

    private var last30: [Date] {
        (0..<30).reversed().map { today.adding(days: -$0) }
    }

    private func average(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var habitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Habit consistency · \(Self.gridWeeks) weeks")
            if life.activeHabits.isEmpty {
                Text("Add a habit in Grow and its consistency grid appears here.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(life.activeHabits) { habit in
                    habitRow(habit)
                }
            }
        }
        .panel()
    }

    /// Columns = weeks (oldest → newest), rows = weekdays: the GitHub/HabitKit
    /// contribution grid people love to fill in and share.
    private func habitRow(_ habit: Habit) -> some View {
        let last28 = (0..<28).map { today.adding(days: -$0) }
        let done = last28.filter { life.isDone(habit, on: $0) }.count
        let due = max(last28.filter { habit.isDue(on: $0) }.count, 1)
        let base = today.startOfWeek.adding(days: -7 * (Self.gridWeeks - 1))

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: habit.iconName)
                        .font(.system(size: 12.5)).foregroundStyle(habit.color)
                    Text(habit.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(life.streak(habit))d streak · \(done)/\(due)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            HStack(spacing: 3) {
                ForEach(0..<Self.gridWeeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { weekday in
                            cell(habit, day: base.adding(days: week * 7 + weekday))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func cell(_ habit: Habit, day: Date) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(cellColor(habit, day: day))
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
    }

    private func cellColor(_ habit: Habit, day: Date) -> Color {
        if day > today { return .clear }
        if life.isDone(habit, on: day) { return habit.color }
        if life.isFrozen(habit, on: day) { return Color.cyan.opacity(0.55) }
        return habit.isDue(on: day) ? Theme.fill : Theme.fill.opacity(0.4)
    }

    // MARK: Goals

    private var weekDays: [Date] {
        let start = today.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    private func weeklyMinutes(calendarID: String?) -> Int {
        weekDays.reduce(0) { acc, day in
            acc + service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs)
                .filter { !$0.isAllDay && (calendarID == nil || $0.calendarID == calendarID) }
                .compactMap { $0.clamped(to: day) }
                .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        }
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Goal progress")
            ForEach(life.activeGoals) { goal in
                goalRow(goal)
            }
        }
        .panel()
    }

    private func goalRow(_ goal: Goal) -> some View {
        let (fraction, caption): (Double, String) = {
            switch goal.kind {
            case .time:
                let minutes = weeklyMinutes(calendarID: goal.linkedCalendarID)
                let target = max(goal.weeklyHoursTarget * 60, 1)
                return (min(1, Double(minutes) / target),
                        "\(Fmt.duration(minutes: minutes)) of \(String(format: "%g h", goal.weeklyHoursTarget)) this week")
            case .milestone:
                let deadline = goal.deadline.map { " · due \(Fmt.monthDay.string(from: $0))" } ?? ""
                return (goal.milestoneProgress, "\(Int((goal.milestoneProgress * 100).rounded()))%\(deadline)")
            case .habitLink:
                guard let habit = life.activeHabits.first(where: { $0.id == goal.linkedHabitID }) else {
                    return (0, "habit removed")
                }
                let days = (0..<28).map { today.adding(days: -$0) }
                let due = days.filter { habit.isDue(on: $0) }.count
                let done = days.filter { life.isDone(habit, on: $0) }.count
                return (due == 0 ? 0 : Double(done) / Double(due), "\(done)/\(due) days · \(life.streak(habit))d streak")
            }
        }()

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: goal.kind.icon)
                        .font(.system(size: 12.5)).foregroundStyle(goal.color)
                    Text(goal.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(fraction >= 1 ? Theme.success : Theme.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill)
                    Capsule().fill(fraction >= 1 ? Theme.success : goal.color)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 2)
    }

}
