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
    @EnvironmentObject private var life: LifeStore

    private var weekDays: [Date] {
        let start = model.selectedDate.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    private var achievements: [Achievement] {
        let bestHabitStreak = life.activeHabits.map { life.streak($0) }.max() ?? 0
        return AchievementEngine.compute(.init(
            completionStreak: stats.streakDays,
            totalFocusMinutes: focusLog.sessions.reduce(0) { $0 + $1.actualMinutes },
            weekDeepMinutes: stats.deepMinutes,
            onTimeRate: stats.onTimeRate,
            datedCompleted: stats.datedCompleted,
            bestHabitStreak: bestHabitStreak,
            journalStreak: life.journalStreak,
            templatesSaved: life.templates.count,
            weekBlockCount: stats.blockCount
        ))
    }

    private var budgeted: [(cal: CalendarInfo, target: Double, minutes: Int)] {
        life.budgets.compactMap { budget in
            guard let cal = service.calendarInfo(withID: budget.calendarID) else { return nil }
            let minutes = weekDays.reduce(0) { acc, day in
                acc + service.blocks(on: day)
                    .filter { !$0.isAllDay && $0.calendarID == budget.calendarID }
                    .compactMap { $0.clamped(to: day) }
                    .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
            }
            return (cal, budget.weeklyHoursTarget, minutes)
        }
        .sorted { $0.cal.title < $1.cal.title }
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
        Coach.suggestions(
            stats: stats,
            profile: profileStore.profile,
            tasks: service.tasks,
            signals: coachSignals
        )
    }

    /// Draws habit, journal, and focus-timing signals from the lifestyle
    /// layer so the coach can reason about the whole person.
    private var coachSignals: Coach.Signals {
        var s = Coach.Signals()
        let habits = life.activeHabits
        s.habitCount = habits.count
        s.bestHabitStreak = habits.map { life.streak($0) }.max() ?? 0
        // Consistency: completed ÷ due over the last 7 days.
        var due = 0, done = 0
        for offset in 0..<7 {
            let day = Date().adding(days: -offset)
            for habit in habits where habit.isDue(on: day) {
                due += 1
                if life.isDone(habit, on: day) { done += 1 }
            }
        }
        s.habitConsistency = due == 0 ? 0 : Double(done) / Double(due)
        s.journalStreak = life.journalStreak

        // Average mood/energy from the last 7 journal entries.
        let recent = (0..<7).compactMap { life.entry(for: Date().adding(days: -$0)) }
        let moods = recent.compactMap { $0.mood }
        let energies = recent.compactMap { $0.energy }
        if !moods.isEmpty { s.avgMood7 = Double(moods.reduce(0, +)) / Double(moods.count) }
        if !energies.isEmpty { s.avgEnergy7 = Double(energies.reduce(0, +)) / Double(energies.count) }

        // Where timed focus actually lands, bucketed by period.
        var byPeriod: [FocusPeriod: Int] = [:]
        for session in focusLog.sessions(inLast: 21) {
            let hour = Calendar.current.component(.hour, from: session.start)
            let period: FocusPeriod = hour < 12 ? .morning : (hour < 17 ? .afternoon : .evening)
            byPeriod[period, default: 0] += session.actualMinutes
            s.focusSampleMinutes += session.actualMinutes
        }
        s.observedFocus = byPeriod.max { $0.value < $1.value }?.key
        return s
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
                    budgetsCard
                    hoursPerDayCard
                    if stats.deepMinutes + stats.shallowMinutes > 0 { energySplitCard }
                    timeByCalendarCard
                    achievementsCard
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

    // MARK: Budgets

    private var budgetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Time budgets")
                Spacer(minLength: 8)
                Button { model.budgetsPresented = true } label: {
                    Text(budgeted.isEmpty ? "Set" : "Edit")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            if budgeted.isEmpty {
                Text("Set weekly hour targets per calendar to keep your time honest.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(budgeted, id: \.cal.id) { entry in
                    let frac = entry.target > 0 ? Double(entry.minutes) / (entry.target * 60) : 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            HStack(spacing: 6) {
                                Circle().fill(entry.cal.color).frame(width: 7, height: 7)
                                Text(entry.cal.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            }
                            Spacer()
                            Text("\(Fmt.duration(minutes: entry.minutes)) / \(String(format: "%g h", entry.target))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(frac >= 1 ? Theme.success : Theme.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.fill)
                                Capsule().fill(frac >= 1 ? Theme.success : entry.cal.color)
                                    .frame(width: min(geo.size.width, geo.size.width * frac))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
        .panel()
    }

    // MARK: Achievements

    private var achievementsCard: some View {
        let unlocked = achievements.filter(\.unlocked)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Achievements", trailing: "\(unlocked.count)/\(achievements.count)")
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(achievements) { badge in
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(badge.unlocked ? Color.accentColor.opacity(0.18) : Theme.fill)
                                .frame(width: 40, height: 40)
                            Image(systemName: badge.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(badge.unlocked ? Color.accentColor : Theme.textTertiary)
                        }
                        Text(badge.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(badge.unlocked ? Theme.textPrimary : Theme.textTertiary)
                            .lineLimit(1)
                        if !badge.unlocked {
                            Text("\(Int(badge.progress * 100))%")
                                .font(.system(size: 8.5, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .help(badge.detail)
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
