import SwiftUI

/// Weekly review, deepened: headline stat tiles, three behavioural rings
/// (completion / on-time / plan adherence), a single-hue planned-vs-focused
/// day strip, time-by-calendar identity bars, a deep/shallow split, and the
/// on-device Coach's prioritized suggestions.
struct InsightsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var focusLog: FocusLog

    private var weekDays: [Date] {
        let start = model.selectedDate.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    private var stats: StatsEngine.Stats {
        StatsEngine.compute(
            days: weekDays,
            blocks: { service.blocks(on: $0, hiddenCalendars: model.hiddenCalendarIDs) },
            allTasks: service.tasks,
            taskLookup: { service.task(withID: $0) },
            sessions: focusLog.sessions
        )
    }

    private var suggestions: [Coach.Suggestion] {
        Coach.suggestions(stats: stats, profile: profileStore.profile, tasks: service.tasks)
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
            .compactMap { id, minutes in service.calendarInfo(withID: id).map { ($0, minutes) } }
            .sorted { $0.1 > $1.1 }
    }

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
                    ringsCard
                    hoursPerDayCard
                    if stats.deepMinutes + stats.shallowMinutes > 0 { energySplitCard }
                    timeByCalendarCard
                    coachCard
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
            statTile(Fmt.duration(minutes: stats.plannedMinutes), "Timeblocked")
            statTile(Fmt.duration(minutes: stats.focusMinutes), "Focused")
            statTile("\(stats.tasksCompleted)", "Done")
            statTile("\(stats.streakDays)d", "Streak")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(padding: 12)
    }

    // MARK: Rings

    private var ringsCard: some View {
        HStack(spacing: 10) {
            ringMetric("Completed", fraction: stats.completionRate, caption: "\(stats.tasksDueCompleted)/\(stats.tasksDue) due")
            ringMetric("On time", fraction: stats.onTimeRate, caption: "\(stats.onTimeCompleted)/\(stats.datedCompleted) dated")
            ringMetric("Adherence", fraction: stats.adherenceRate, caption: "\(stats.adherenceMet)/\(stats.adherenceEligible) blocks")
        }
    }

    private func ringMetric(_ title: String, fraction: Double, caption: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                ProgressRing(fraction: fraction, size: 52, lineWidth: 5)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(caption)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .panel(padding: 12)
    }

    // MARK: Hours per day (single measure over time → one hue; focus overlaid)

    private var hoursPerDayCard: some View {
        let data = stats.perDay
        let maxMinutes = max(data.map(\.plannedMinutes).max() ?? 0, 1)
        let busiest = stats.busiestDay

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Hours per day",
                trailing: busiest.flatMap { $0.plannedMinutes > 0
                    ? "peak \(Fmt.weekdayShort.string(from: $0.day)) · \(Fmt.duration(minutes: $0.plannedMinutes))"
                    : nil }
            )
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(data) { entry in
                    VStack(spacing: 5) {
                        Text(entry.plannedMinutes == busiest?.plannedMinutes && entry.plannedMinutes > 0
                             ? Fmt.duration(minutes: entry.plannedMinutes) : " ")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        ZStack(alignment: .bottom) {
                            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                                .fill(entry.day.isToday ? Color.accentColor : Color.accentColor.opacity(0.4))
                                .frame(height: max(CGFloat(entry.plannedMinutes) / CGFloat(maxMinutes) * 90, entry.plannedMinutes > 0 ? 3 : 1))
                            // Focused-time overlay (darker cap) shows how much
                            // planned time was actually timed.
                            if entry.focusMinutes > 0 {
                                UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                                    .fill(Theme.success)
                                    .frame(height: max(CGFloat(min(entry.focusMinutes, entry.plannedMinutes)) / CGFloat(maxMinutes) * 90, 2))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        Text(Fmt.weekdayShort.string(from: entry.day).prefix(1))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(entry.day.isToday ? Color.accentColor : Theme.textTertiary)
                    }
                }
            }
            .frame(height: 130, alignment: .bottom)
            if stats.focusMinutes > 0 {
                HStack(spacing: 6) {
                    Circle().fill(Theme.success).frame(width: 6, height: 6)
                    Text("Focused time logged").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .panel()
    }

    // MARK: Deep vs shallow

    private var energySplitCard: some View {
        let deep = stats.deepMinutes
        let shallow = stats.shallowMinutes
        let total = max(deep + shallow, 1)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Deep vs shallow", trailing: Fmt.duration(minutes: deep + shallow))
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if deep > 0 {
                        Capsule().fill(TaskEnergy.deep.color)
                            .frame(width: max((geo.size.width - 2) * CGFloat(deep) / CGFloat(total), 3))
                    }
                    if shallow > 0 {
                        Capsule().fill(TaskEnergy.shallow.color)
                            .frame(width: max((geo.size.width - 2) * CGFloat(shallow) / CGFloat(total), 3))
                    }
                }
            }
            .frame(height: 10)
            HStack(spacing: 16) {
                legendDot(TaskEnergy.deep.color, "Deep · \(Fmt.duration(minutes: deep))")
                legendDot(TaskEnergy.shallow.color, "Shallow · \(Fmt.duration(minutes: shallow))")
            }
        }
        .panel()
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Time by calendar

    private var timeByCalendarCard: some View {
        let data = minutesByCalendar
        let maxMinutes = max(data.map(\.minutes).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Time by calendar")
            if data.isEmpty {
                Text("No blocks this week yet.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
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
                                Capsule().fill(entry.calendar.color)
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

    // MARK: Coach

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Color.accentColor)
                Text("COACH")
                    .font(.system(size: 10.5, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            ForEach(suggestions.prefix(4)) { suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: suggestion.tone.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(suggestion.tone.color)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(suggestion.detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .panel()
    }

    // MARK: Texture

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Texture")
            factRow("ruler", "Average block length", stats.blockCount == 0 ? "—" : Fmt.duration(minutes: stats.avgBlockMinutes))
            factRow("trophy", "Longest block",
                    stats.longestBlockTitle.map { "\($0) · \(Fmt.duration(minutes: stats.longestBlockMinutes))" } ?? "—")
            factRow("link", "Blocks linked to tasks",
                    stats.blockCount == 0 ? "—" : "\(stats.linkedBlocks) of \(stats.blockCount)")
            factRow("timer", "Focus sessions", "\(stats.focusSessions)")
            factRow("exclamationmark.circle", "Open overdue tasks", "\(stats.overdueNow)")
        }
        .panel()
    }

    private func factRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.textTertiary).frame(width: 16)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }
}
