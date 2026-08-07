import SwiftUI

/// The shared briefing card stack: a warm greeting, the few things worth
/// knowing right now, prioritized suggestions, one-tap planning, and a week
/// glance. Used as the whole screen on non-AI devices, and as the resting
/// state of the AI chat (before you start a conversation) so both feel alike.
struct BriefingContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60

    /// When true, the greeting is drawn as a plain line (the AI chat shows its
    /// own header greeting), otherwise as the full gradient hero card.
    var showsGreeting = true

    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    /// When this briefing is itself hosted in a sheet (the iPhone Coach), an
    /// action that opens another RootView sheet must dismiss this one first, or
    /// the new sheet presents behind it.
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsGreeting { greetingCard }
            MomentumCard()
            insightCard(PlannerBrief.focus(context))
            insightCard(PlannerBrief.load(context))
            if let loose = PlannerBrief.looseEnds(context) {
                insightCard(loose)
            }
            if !suggestions.isEmpty { suggestionsCard }
            quickActions
            weekGlance
        }
        .onReceive(clock) { now = $0 }
    }

    // MARK: Greeting

    private var greetingCard: some View {
        Text(PlannerBrief.greeting(context))
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                LinearGradient(colors: [Theme.accentColor.opacity(0.16), Theme.accentColor.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accentColor.opacity(0.2), lineWidth: 1))
    }

    // MARK: Insight card

    private func insightCard(_ item: PlannerBrief.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconChip(icon: item.icon, tint: item.tint, size: 38)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(item.message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = item.action, let label = item.actionLabel {
                    Button { performCoachAction(action, on: model) } label: {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
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
                Image(systemName: "lightbulb").font(.system(size: 13.5)).foregroundStyle(Theme.accentColor)
                Text("SUGGESTIONS")
                    .font(.system(size: 12, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            ForEach(suggestions.prefix(4)) { suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: suggestion.tone.icon)
                        .font(.system(size: 14.5))
                        .foregroundStyle(suggestion.tone.color)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(suggestion.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(suggestion.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let action = suggestion.action, let label = suggestion.actionLabel {
                            Button { perform(action) } label: {
                                Text(label)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Theme.accentColor)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Theme.accentColor.opacity(0.12), in: Capsule())
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
                actionTile("Plan my day", "wand.and.stars", Theme.accentColor, .planDay)
                actionTile("Plan my week", "calendar.badge.clock", Color(hex: 0x4C9BFF), .planWeek)
                actionTile("Plan deadlines", "graduationcap", Color(hex: 0x9C7BFA), .deadlines)
                actionTile("Reflow today", "arrow.triangle.2.circlepath", Color(hex: 0x22C3C9), .reflow)
                actionTile("Review day", "checkmark.circle", Color(hex: 0x3FC97A), .review)
                actionTile("Start focus", "timer", Color(hex: 0xFF7A59), .focus)
                actionTile("Sweep overdue", "tray.and.arrow.down", Color(hex: 0xFFB23E), .overdueSweep)
                actionTile("Share availability", "square.and.arrow.up", Color(hex: 0xFF6B9D), .availability)
            }
        }
        .panel()
    }

    private func actionTile(_ title: String, _ icon: String, _ tint: Color, _ action: QuickAction) -> some View {
        Button { performCoachAction(action, on: model) } label: {
            HStack(spacing: 10) {
                IconChip(icon: icon, tint: tint, size: 30)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: Week glance

    private var weekGlance: some View {
        Button { model.statsPresented = true } label: {
            HStack(spacing: 12) {
                IconChip(icon: "chart.bar.xaxis", tint: Theme.accentColor, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Fmt.duration(minutes: stats.focusMinutes)) focused · \(stats.tasksCompleted) done · \(stats.streakDays)d streak")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .semibold))
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
            sessions: focusLog.sessions,
            isEventSkipped: { EventOutcomeStore.shared.isSkipped($0.id) }
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
        let base = Coach.suggestions(
            stats: stats,
            profile: profileStore.profile,
            tasks: service.tasks,
            signals: CoachInputs.signals(life: life, focusLog: focusLog),
            projects: life.activeProjects
        )
        return base.sorted { $0.weight > $1.weight }
    }

    private func perform(_ action: Coach.Action) {
        // If we're inside a sheet, close it first and open the target on the next
        // runloop so the two RootView sheets don't collide.
        if isPresented {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { runAction(action) }
        } else {
            runAction(action)
        }
    }

    private func runAction(_ action: Coach.Action) {
        switch action {
        case .recalibrate: model.calibrationPresented = true
        case .planDay: model.planDayPresented = true
        case .planWeek: model.planWeekPresented = true
        case .reflow: model.reflowPresented = true
        case .openGrow: model.screen = .grow
        case .addHabit: model.habitEditor = HabitEditContext(habit: Habit(), isNew: true)
        case .focusTimer: model.startFocus(taskID: nil, title: "Focus")
        case .overdueSweep: model.overdueSweepPresented = true
        case .openProjects: model.projectsPresented = true
        }
    }
}
