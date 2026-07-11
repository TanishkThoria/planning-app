import SwiftUI

/// Weekly review: where the hours actually went. Headline numbers as stat
/// tiles; time-by-calendar as a labeled bar list (each bar wears its
/// calendar's own color — identity, not decoration); hours-per-day as a
/// single-hue column strip since that's one measure over time.
struct InsightsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    private var weekDays: [Date] {
        let start = model.selectedDate.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    // MARK: Derived metrics

    /// Timed, visible block-minutes per day of the selected week.
    private var minutesPerDay: [(day: Date, minutes: Int)] {
        weekDays.map { day in
            let minutes = service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs)
                .filter { !$0.isAllDay }
                .compactMap { $0.clamped(to: day) }
                .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
            return (day, minutes)
        }
    }

    private var weekBlocks: [TimeBlock] {
        weekDays.flatMap { day in
            service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs)
                .filter { !$0.isAllDay }
        }
    }

    private var minutesByCalendar: [(calendar: CalendarInfo, minutes: Int)] {
        var totals: [String: Int] = [:]
        for day in weekDays {
            for block in service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs) where !block.isAllDay {
                if let clamped = block.clamped(to: day) {
                    totals[block.calendarID, default: 0] += Int(clamped.end.timeIntervalSince(clamped.start) / 60)
                }
            }
        }
        return totals
            .compactMap { id, minutes in
                service.calendarInfo(withID: id).map { ($0, minutes) }
            }
            .sorted { $0.1 > $1.1 }
    }

    private var completedThisWeek: [TaskItem] {
        guard let first = weekDays.first, let last = weekDays.last else { return [] }
        return service.tasks.filter { task in
            guard task.isCompleted, let done = task.completionDate else { return false }
            return done >= first.startOfDay && done <= last.endOfDay
        }
    }

    private var tasksDueThisWeek: [TaskItem] {
        guard let first = weekDays.first, let last = weekDays.last else { return [] }
        return service.tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return due >= first.startOfDay && due <= last.endOfDay
        }
    }

    private var completionRate: Double {
        let due = tasksDueThisWeek
        guard !due.isEmpty else { return 0 }
        return Double(due.filter(\.isCompleted).count) / Double(due.count)
    }

    private var totalMinutes: Int { minutesPerDay.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statTiles
                    hoursPerDayCard
                    timeByCalendarCard
                    detailCard
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Insights")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                if let first = weekDays.first, let last = weekDays.last {
                    Text("\(Fmt.monthDay.string(from: first)) – \(Fmt.monthDay.string(from: last))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            DateNavigator()
        }
    }

    // MARK: Stat tiles

    private var statTiles: some View {
        HStack(spacing: 10) {
            statTile(
                value: Fmt.duration(minutes: totalMinutes),
                label: "Timeblocked"
            )
            statTile(
                value: "\(weekBlocks.count)",
                label: "Blocks"
            )
            statTile(
                value: "\(completedThisWeek.count)",
                label: "Tasks done"
            )
            ringTile
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var ringTile: some View {
        HStack(spacing: 10) {
            ProgressRing(fraction: completionRate, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(tasksDueThisWeek.isEmpty ? "—" : "\(Int((completionRate * 100).rounded()))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("DUE DONE")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    // MARK: Hours per day (single measure over time → one hue)

    private var hoursPerDayCard: some View {
        let data = minutesPerDay
        let maxMinutes = max(data.map(\.minutes).max() ?? 0, 1)
        let busiest = data.max { $0.minutes < $1.minutes }

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Hours per day",
                trailing: busiest.flatMap { $0.minutes > 0
                    ? "peak \(Fmt.weekdayShort.string(from: $0.day)) · \(Fmt.duration(minutes: $0.minutes))"
                    : nil
                }
            )

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(data, id: \.day) { entry in
                    VStack(spacing: 5) {
                        // Direct label on the peak only — selective labeling.
                        Text(entry.minutes == busiest?.minutes && entry.minutes > 0
                             ? Fmt.duration(minutes: entry.minutes) : " ")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)

                        UnevenRoundedRectangle(
                            topLeadingRadius: 4, bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0, topTrailingRadius: 4,
                            style: .continuous
                        )
                        .fill(entry.day.isToday ? Color.accentColor : Color.accentColor.opacity(0.45))
                        .frame(height: max(CGFloat(entry.minutes) / CGFloat(maxMinutes) * 90, entry.minutes > 0 ? 3 : 1))
                        .frame(maxWidth: .infinity)

                        Text(Fmt.weekdayShort.string(from: entry.day).prefix(1))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(entry.day.isToday ? Color.accentColor : Theme.textTertiary)
                    }
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
        .panel()
    }

    // MARK: Time by calendar (identity → each entity keeps its own color)

    private var timeByCalendarCard: some View {
        let data = minutesByCalendar
        let maxMinutes = max(data.map(\.minutes).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Time by calendar")

            if data.isEmpty {
                Text("No blocks this week yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 10) {
                    ForEach(data, id: \.calendar.id) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                HStack(spacing: 6) {
                                    Circle().fill(entry.calendar.color).frame(width: 7, height: 7)
                                    Text(entry.calendar.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                Spacer()
                                Text(Fmt.duration(minutes: entry.minutes))
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            GeometryReader { geo in
                                Capsule()
                                    .fill(entry.calendar.color)
                                    .frame(width: max(geo.size.width * CGFloat(entry.minutes) / CGFloat(maxMinutes), 4))
                            }
                            .frame(height: 5)
                            .background(Theme.fill, in: Capsule())
                        }
                    }
                }
            }
        }
        .panel()
    }

    // MARK: Texture facts

    private var detailCard: some View {
        let blocks = weekBlocks
        let avg = blocks.isEmpty ? 0 : blocks.map(\.durationMinutes).reduce(0, +) / blocks.count
        let longest = blocks.max { $0.durationMinutes < $1.durationMinutes }
        let linked = blocks.filter { $0.linkedTaskID != nil }.count

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Texture")
            factRow(icon: "ruler", label: "Average block length", value: blocks.isEmpty ? "—" : Fmt.duration(minutes: avg))
            factRow(
                icon: "trophy",
                label: "Longest block",
                value: longest.map { "\($0.title) · \(Fmt.duration(minutes: $0.durationMinutes))" } ?? "—"
            )
            factRow(
                icon: "link",
                label: "Blocks linked to tasks",
                value: blocks.isEmpty ? "—" : "\(linked) of \(blocks.count)"
            )
        }
        .panel()
    }

    private func factRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }
}
