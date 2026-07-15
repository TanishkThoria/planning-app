import SwiftUI

/// Long-horizon view of the growth data: mood & energy over the last month,
/// per-habit consistency grids, goal progress, and a browsable archive of
/// past reflections. The Grow tab shows today; this shows the trajectory.
struct TrendsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var expandedEntry: String?

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
                    moodCard
                    habitsCard
                    if !life.activeGoals.isEmpty { goalsCard }
                    reflectionsCard
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

    private var moodCard: some View {
        let entries = last30.map { life.entry(for: $0) }
        let moods = entries.compactMap { $0?.mood }
        let energies = entries.compactMap { $0?.energy }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Mood & energy · 30 days")
                Spacer()
                if let avg = average(moods) {
                    Text(String(format: "mood %.1f · energy %@", avg,
                                average(energies).map { String(format: "%.1f", $0) } ?? "—"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            if moods.isEmpty && energies.isEmpty {
                Text("Log how the day felt in your evening reflection and the trend shows up here.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                valueStrip(label: "Mood", tint: Theme.accentColor, values: entries.map { $0?.mood })
                valueStrip(label: "Energy", tint: Theme.success, values: entries.map { $0?.energy })
                HStack {
                    Text(Fmt.monthDay.string(from: last30.first ?? today))
                    Spacer()
                    Text("Today")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .panel()
    }

    /// A 30-column strip of bars; missing days render as faint stubs.
    private func valueStrip(label: String, tint: Color, values: [Int?]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(value != nil ? tint : Theme.fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: value.map { CGFloat($0) / 5 * 34 + 4 } ?? 3)
                }
            }
            .frame(height: 38, alignment: .bottom)
        }
    }

    // MARK: Habit consistency (last 28 days)

    private static let gridWeeks = 15

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

    // MARK: Reflections archive

    private var pastEntries: [(day: Date, entry: JournalEntry)] {
        (1...90).compactMap { offset in
            let day = today.adding(days: -offset)
            guard let entry = life.entry(for: day), entry.hasMorning || entry.hasEvening else { return nil }
            return (day, entry)
        }
    }

    private var reflectionsCard: some View {
        let entries = pastEntries
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Reflections", trailing: entries.isEmpty ? nil : "\(entries.count) in 90 days")
            if entries.isEmpty {
                Text("Past morning intentions and evening reflections collect here.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(entries.prefix(30), id: \.entry.id) { item in
                    reflectionRow(item.day, item.entry)
                }
            }
        }
        .panel()
    }

    private func reflectionRow(_ day: Date, _ entry: JournalEntry) -> some View {
        let isOpen = expandedEntry == entry.dayKey
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expandedEntry = isOpen ? nil : entry.dayKey }
            } label: {
                HStack(spacing: 8) {
                    Text(Fmt.relativeDay(day))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let mood = entry.mood {
                        Label("\(mood)", systemImage: "face.smiling")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let energy = entry.energy {
                        Label("\(energy)", systemImage: "bolt")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 7) {
                    let intentions = entry.intentions.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    if !intentions.isEmpty {
                        detailLine("sunrise", "Intentions", intentions.joined(separator: " · "))
                    }
                    if !entry.wins.isEmpty { detailLine("trophy", "Wins", entry.wins) }
                    if !entry.improve.isEmpty { detailLine("arrow.up.forward", "Improve", entry.improve) }
                    if !entry.gratitude.isEmpty { detailLine("heart", "Grateful for", entry.gratitude) }
                    if !entry.notes.isEmpty { detailLine("note.text", "Notes", entry.notes) }
                }
                .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailLine(_ icon: String, _ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11.5)).foregroundStyle(Theme.accentColor)
                .frame(width: 14).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                Text(text)
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
