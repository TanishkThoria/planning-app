import SwiftUI

/// The Coach screen for devices without on-device AI. Instead of an empty
/// chatbot, it's a warm daily briefing: a greeting, the few things worth
/// knowing right now (what to focus on, today's load, loose ends), the
/// prioritized suggestions, one-tap planning, and a glance at the week. All
/// grounded in live data so it feels personal, not canned.
struct CoachBriefingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60

    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    greetingCard
                    insightCard(PlannerBrief.focus(context))
                    insightCard(PlannerBrief.load(context))
                    if let loose = PlannerBrief.looseEnds(context) {
                        insightCard(loose)
                    }
                    if !suggestions.isEmpty { suggestionsCard }
                    quickActions
                    weekGlance
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
        .onReceive(clock) { now = $0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.16)).frame(width: 34, height: 34)
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Coach")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your daily briefing")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HeaderIconButton(icon: "chart.bar.xaxis") { model.statsPresented = true }
            HeaderIconButton(icon: "slider.horizontal.3") { model.calibrationPresented = true }
        }
    }

    // MARK: Greeting

    private var greetingCard: some View {
        Text(PlannerBrief.greeting(context))
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                LinearGradient(colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1))
    }

    // MARK: Insight card

    private func insightCard(_ item: PlannerBrief.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.tint.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.tint)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(item.message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = item.action, let label = item.actionLabel {
                    Button { performCoachAction(action, on: model) } label: {
                        Text(label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(item.tint)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(item.tint.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .panel()
    }

    // MARK: Suggestions

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb").font(.system(size: 12)).foregroundStyle(Color.accentColor)
                Text("SUGGESTIONS")
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(suggestion.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(suggestion.detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let action = suggestion.action, let label = suggestion.actionLabel {
                            Button { perform(action) } label: {
                                Text(label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 1)
                        }
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .panel()
    }

    // MARK: Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Plan")
            let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
            LazyVGrid(columns: columns, spacing: 10) {
                actionTile("Plan my day", "wand.and.stars", .planDay)
                actionTile("Plan my week", "calendar.badge.clock", .planWeek)
                actionTile("Reflow today", "arrow.triangle.2.circlepath", .reflow)
                actionTile("Review day", "checkmark.circle", .review)
                actionTile("Start focus", "timer", .focus)
                actionTile("Sweep overdue", "tray.and.arrow.down", .overdueSweep)
            }
        }
        .panel()
    }

    private func actionTile(_ title: String, _ icon: String, _ action: QuickAction) -> some View {
        Button { performCoachAction(action, on: model) } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Week glance

    private var weekGlance: some View {
        Button { model.statsPresented = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Fmt.duration(minutes: stats.focusMinutes)) focused · \(stats.tasksCompleted) done · \(stats.streakDays)d streak")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .panel()
        }
        .buttonStyle(.plain)
    }

    // MARK: Data

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

    private var todayBlocks: [TimeBlock] {
        service.blocks(on: Date().startOfDay, hiddenCalendars: model.hiddenCalendarIDs)
            .filter { !$0.isAllDay }
            .sorted { $0.start < $1.start }
    }

    private var context: PlannerContext {
        PlannerContext(
            now: now,
            todayBlocks: todayBlocks,
            tasks: service.tasks,
            taskLookup: { service.task(withID: $0) },
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            stats: stats
        )
    }

    private var suggestions: [Coach.Suggestion] {
        Coach.suggestions(
            stats: stats,
            profile: profileStore.profile,
            tasks: service.tasks,
            signals: CoachInputs.signals(life: life, focusLog: focusLog)
        )
    }

    private func perform(_ action: Coach.Action) {
        switch action {
        case .recalibrate: model.calibrationPresented = true
        case .planDay: model.planDayPresented = true
        case .planWeek: model.planWeekPresented = true
        case .reflow: model.reflowPresented = true
        case .openGrow: model.screen = .grow
        case .addHabit: model.habitEditor = HabitEditContext(habit: Habit(), isNew: true)
        case .morningRitual: model.morningRitualPresented = true
        case .eveningRitual: model.eveningRitualPresented = true
        case .focusTimer: model.startFocus(taskID: nil, title: "Focus")
        case .overdueSweep: model.overdueSweepPresented = true
        }
    }
}
