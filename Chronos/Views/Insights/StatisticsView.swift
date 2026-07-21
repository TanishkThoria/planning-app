import SwiftUI

/// Detailed account statistics, reached from a menu rather than a primary
/// tab: headline stat tiles, three behavioural rings (completion / on-time /
/// plan adherence), a single-hue planned-vs-focused day strip, time-by-calendar
/// identity bars, a deep/shallow split, budgets, and achievements. The
/// interactive coaching lives in the Coach tab now.
struct StatisticsView: View {
    /// When presented as a sheet, shows a close button in the header.
    var onClose: (() -> Void)?

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore

    @State private var showTimeReport = false
    @State private var showWrapped = false
    @State private var selectedAchievementID: String?

    private var weekDays: [Date] {
        let start = model.selectedDate.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    private var achievements: [Achievement] {
        let bestHabitStreak = life.activeHabits.map { life.streak($0) }.max() ?? 0
        let momentum = MomentumStore.shared
        let bestRoutineStreak = RoutineStore.shared.trackedRoutines.map { RoutineStore.shared.streak($0) }.max() ?? 0
        return AchievementEngine.compute(.init(
            completionStreak: stats.streakDays,
            totalFocusMinutes: focusLog.sessions.reduce(0) { $0 + $1.actualMinutes },
            weekDeepMinutes: stats.deepMinutes,
            onTimeRate: stats.onTimeRate,
            datedCompleted: stats.datedCompleted,
            bestHabitStreak: bestHabitStreak,
            journalStreak: life.journalStreak,
            templatesSaved: life.templates.count,
            weekBlockCount: stats.blockCount,
            momentumLevel: momentum.level,
            momentumStreak: momentum.streak(),
            perfectDays: momentum.perfectDays,
            solidDays: momentum.solidDays,
            bestRoutineStreak: bestRoutineStreak
        ))
    }

    private var budgeted: [(category: ActivityCategory, target: Double, minutes: Int)] {
        guard !life.categoryBudgets.isEmpty else { return [] }
        var totals: [ActivityCategory: Int] = [:]
        for day in weekDays {
            for block in service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs) where !block.isAllDay {
                guard let clamped = block.clamped(to: day) else { continue }
                let m = Int(clamped.end.timeIntervalSince(clamped.start) / 60)
                guard m > 0 else { continue }
                totals[TagStore.shared.category(for: block), default: 0] += m
            }
        }
        return life.budgetedCategories.map { ($0.category, $0.weeklyHoursTarget, totals[$0.category] ?? 0) }
    }

    private var stats: StatsEngine.Stats {
        StatsEngine.compute(
            days: weekDays,
            blocks: { service.blocks(on: $0, hiddenCalendars: model.hiddenCalendarIDs) },
            allTasks: service.tasks,
            taskLookup: { service.task(withID: $0) },
            sessions: focusLog.sessions,
            isEventSkipped: { EventOutcomeStore.shared.isSkipped($0.id) }
        )
    }

    private var lastWeekStats: StatsEngine.Stats {
        let previous = weekDays.map { $0.adding(days: -7) }
        return StatsEngine.compute(
            days: previous,
            blocks: { service.blocks(on: $0, hiddenCalendars: model.hiddenCalendarIDs) },
            allTasks: service.tasks,
            taskLookup: { service.task(withID: $0) },
            sessions: focusLog.sessions,
            isEventSkipped: { EventOutcomeStore.shared.isSkipped($0.id) }
        )
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
                    weekOverWeekCard
                    ringsCard
                    budgetsCard
                    hoursPerDayCard
                    if stats.deepMinutes + stats.shallowMinutes > 0 { energySplitCard }
                    timeByCalendarCard
                    achievementsCard
                    detailCard
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
        .sheet(isPresented: $showTimeReport) { TimeReportView() }
        .sheet(isPresented: $showWrapped) { WrappedView() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Statistics")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let first = weekDays.first, let last = weekDays.last {
                    Text("\(Fmt.monthDay.string(from: first)) – \(Fmt.monthDay.string(from: last))")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            HeaderIconButton(icon: "clock.arrow.circlepath") { showTimeReport = true }
                .help("Time Report — where your hours went")
            HeaderIconButton(icon: "sparkles") { showWrapped = true }
                .help("Year in Review")
            DateNavigator()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
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

    // MARK: Week over week

    private var weekOverWeekCard: some View {
        let this = stats
        let last = lastWeekStats
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "This week vs last")
            VStack(spacing: 10) {
                compareRow("Focused", "timer", this.focusMinutes, last.focusMinutes, isMinutes: true)
                compareRow("Timeblocked", "rectangle.stack", this.plannedMinutes, last.plannedMinutes, isMinutes: true)
                compareRow("Tasks done", "checkmark.circle", this.tasksCompleted, last.tasksCompleted, isMinutes: false)
                compareRow("Deep work", "brain.head.profile", this.deepMinutes, last.deepMinutes, isMinutes: true)
            }
        }
        .panel()
    }

    private func compareRow(_ label: String, _ icon: String, _ current: Int, _ previous: Int, isMinutes: Bool) -> some View {
        let delta = current - previous
        let pct = previous > 0 ? Int((Double(delta) / Double(previous) * 100).rounded()) : (current > 0 ? 100 : 0)
        let up = delta >= 0
        return HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary).frame(width: 18)
            Text(label).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(isMinutes ? Fmt.duration(minutes: current) : "\(current)")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if delta != 0 {
                HStack(spacing: 2) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(abs(pct))%")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(up ? Theme.success : Theme.danger)
                .frame(width: 52, alignment: .trailing)
            } else {
                Text("—").font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
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
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(caption)
                    .font(.system(size: 10))
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
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        ZStack(alignment: .bottom) {
                            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                                .fill(entry.day.isToday ? Theme.accentColor : Theme.accentColor.opacity(0.4))
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
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(entry.day.isToday ? Theme.accentColor : Theme.textTertiary)
                    }
                }
            }
            .frame(height: 130, alignment: .bottom)
            if stats.focusMinutes > 0 {
                HStack(spacing: 6) {
                    Circle().fill(Theme.success).frame(width: 6, height: 6)
                    Text("Focused time logged").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
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
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
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
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 10) {
                    ForEach(data, id: \.calendar.id) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                HStack(spacing: 6) {
                                    Circle().fill(entry.calendar.color).frame(width: 7, height: 7)
                                    Text(entry.calendar.title)
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                Spacer()
                                Text(Fmt.duration(minutes: entry.minutes))
                                    .font(.system(size: 13, weight: .semibold))
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
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
            if budgeted.isEmpty {
                Text("Set weekly hour targets per category (Work, Gym, Social…) to keep your time honest.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(budgeted, id: \.category) { entry in
                    let frac = entry.target > 0 ? Double(entry.minutes) / (entry.target * 60) : 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: entry.category.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(entry.category.color)
                                Text(entry.category.title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            }
                            Spacer()
                            Text("\(Fmt.duration(minutes: entry.minutes)) / \(String(format: "%g h", entry.target))")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(frac >= 1 ? Theme.success : Theme.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.fill)
                                Capsule().fill(frac >= 1 ? Theme.success : entry.category.color)
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

    /// The badge whose description is shown in the strip: whatever's tapped, or
    /// (by default) the one you're closest to earning.
    private var focusedAchievement: Achievement? {
        if let id = selectedAchievementID, let match = achievements.first(where: { $0.id == id }) { return match }
        return achievements.filter { !$0.unlocked }.max(by: { $0.progress < $1.progress })
            ?? achievements.first
    }

    private var achievementsCard: some View {
        let unlocked = achievements.filter(\.unlocked)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Achievements", trailing: "\(unlocked.count)/\(achievements.count)")
                Spacer(minLength: 8)
                Button { model.achievementsPresented = true } label: {
                    Text("See all").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(achievements) { badge in
                    achievementBadge(badge)
                }
            }
            if let focused = focusedAchievement {
                achievementDetailStrip(focused)
            }
        }
        .panel()
    }

    private func achievementBadge(_ badge: Achievement) -> some View {
        let selected = focusedAchievement?.id == badge.id
        return Button {
            withAnimation(.snappy) { selectedAchievementID = badge.id }
            Haptics.selection()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(badge.unlocked ? badge.tier.color.opacity(0.2) : Theme.fill)
                        .frame(width: 42, height: 42)
                    if badge.unlocked {
                        Circle().strokeBorder(badge.tier.color.opacity(0.5), lineWidth: 1.5).frame(width: 42, height: 42)
                    } else {
                        Circle().trim(from: 0, to: max(0.02, badge.progress))
                            .stroke(Theme.textTertiary.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 42, height: 42)
                    }
                    Image(systemName: badge.icon)
                        .font(.system(size: 17))
                        .foregroundStyle(badge.unlocked ? badge.tier.color : Theme.textTertiary)
                }
                Text(badge.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(badge.unlocked ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(badge.unlocked ? badge.tier.label : badge.progressText)
                    .font(.system(size: 9.5, weight: badge.unlocked ? .semibold : .regular))
                    .foregroundStyle(badge.unlocked ? badge.tier.color : Theme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10).padding(.horizontal, 4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Theme.accentColor
                              : (badge.unlocked ? badge.tier.color.opacity(0.25) : Color.clear),
                              lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    /// The inline description of the focused badge — so every achievement's
    /// meaning is right here on the stats screen, not hidden behind a tooltip.
    private func achievementDetailStrip(_ badge: Achievement) -> some View {
        HStack(spacing: 10) {
            Image(systemName: badge.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(badge.unlocked ? badge.tier.color : Theme.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(badge.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(badge.tier.label.uppercased())
                        .font(.system(size: 8.5, weight: .bold)).tracking(0.5)
                        .foregroundStyle(badge.tier.color)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(badge.tier.color.opacity(0.16), in: Capsule())
                    if badge.unlocked {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(badge.tier.color)
                    }
                }
                Text(badge.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !badge.unlocked {
                    Text(badge.progressText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            Image(systemName: icon).font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary).frame(width: 16)
            Text(label).font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }
}
