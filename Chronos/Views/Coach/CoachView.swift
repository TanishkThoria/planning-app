import SwiftUI

/// The Coach tab: an interactive planning + coaching surface. It greets you
/// with today's status, offers one-tap planning actions, answers common
/// planning questions from your live data (an on-device assistant), and
/// surfaces the prioritized suggestions from the heuristic Coach. Deep
/// statistics moved to their own screen, reachable from the header.
struct CoachView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60

    @State private var exchanges: [Exchange] = []
    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // MARK: Derived data

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
        Coach.suggestions(
            stats: stats,
            profile: profileStore.profile,
            tasks: service.tasks,
            signals: CoachInputs.signals(life: life, focusLog: focusLog)
        )
    }

    private var todayBlocks: [TimeBlock] {
        service.blocks(on: Date().startOfDay, hiddenCalendars: model.hiddenCalendarIDs)
            .filter { !$0.isAllDay }
            .sorted { $0.start < $1.start }
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
                    greetingCard
                    quickActions
                    assistantCard
                    if !suggestions.isEmpty { coachCard }
                    weekGlanceCard
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Coach")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your planning companion")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HeaderIconButton(icon: "chart.bar.xaxis", label: "Stats") {
                model.statsPresented = true
            }
            HeaderIconButton(icon: "slider.horizontal.3") {
                model.calibrationPresented = true
            }
        }
    }

    // MARK: Greeting

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Working late"
        }
    }

    private var statusLine: String {
        if let current = todayBlocks.first(where: { $0.start <= now && now < $0.end }) {
            return "You're in \(current.title) until \(Fmt.time.string(from: current.end))."
        }
        if let next = todayBlocks.first(where: { $0.start > now }) {
            return "Next up: \(next.title) at \(Fmt.time.string(from: next.start))."
        }
        if todayBlocks.isEmpty {
            return "Nothing on the timeline yet — let's build your day."
        }
        return "Your scheduled blocks are done for today."
    }

    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(statusLine)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        Button {
            perform(action)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Assistant

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 12)).foregroundStyle(Color.accentColor)
                Text("ASK CHRONOS")
                    .font(.system(size: 10.5, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if !exchanges.isEmpty {
                    Button("Clear") { withAnimation(.snappy) { exchanges.removeAll() } }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .buttonStyle(.plain)
                }
            }

            ForEach(exchanges) { exchange in
                VStack(alignment: .leading, spacing: 6) {
                    Text(exchange.question)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12)).foregroundStyle(Color.accentColor)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(exchange.reply.text)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let action = exchange.reply.action, let label = exchange.reply.actionLabel {
                                Button { perform(action) } label: {
                                    Text(label)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            FlowChips(prompts: AssistantPrompt.allCases) { prompt in
                ask(prompt)
            }
        }
        .panel()
    }

    private func ask(_ prompt: AssistantPrompt) {
        let reply = answer(for: prompt)
        withAnimation(.snappy) {
            exchanges.append(Exchange(question: prompt.label, reply: reply))
        }
    }

    // MARK: Coach suggestions

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Color.accentColor)
                Text("SUGGESTIONS")
                    .font(.system(size: 10.5, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            ForEach(suggestions.prefix(6)) { suggestion in
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

    // MARK: Week glance

    private var weekGlanceCard: some View {
        Button {
            model.statsPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "This week")
                    Spacer()
                    Text("See all")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                HStack(spacing: 10) {
                    glanceTile(Fmt.duration(minutes: stats.focusMinutes), "Focused")
                    glanceTile("\(stats.tasksCompleted)", "Done")
                    glanceTile("\(stats.streakDays)d", "Streak")
                    glanceTile("\(Int((stats.completionRate * 100).rounded()))%", "On track")
                }
            }
        }
        .buttonStyle(.plain)
        .panel()
    }

    private func glanceTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .semibold)).tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func perform(_ action: QuickAction) {
        switch action {
        case .planDay: model.planDayPresented = true
        case .planWeek: model.planWeekPresented = true
        case .reflow: model.reflowPresented = true
        case .review: model.reviewPresented = true
        case .focus: model.startFocus(taskID: nil, title: "Focus")
        case .overdueSweep: model.overdueSweepPresented = true
        }
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

    // MARK: On-device assistant answers

    private func answer(for prompt: AssistantPrompt) -> Reply {
        switch prompt {
        case .focusNow: return focusNowReply()
        case .overloaded: return overloadReply()
        case .slipped: return slippedReply()
        case .week: return weekReply()
        case .planToday: return Reply(text: "Let's lay it out. I'll place your open tasks in your free slots around what's already scheduled.", action: .planDay, actionLabel: "Plan my day")
        }
    }

    private func focusNowReply() -> Reply {
        if let current = todayBlocks.first(where: { $0.start <= now && now < $0.end }) {
            return Reply(text: "Stay with \(current.title) — it runs until \(Fmt.time.string(from: current.end)). Want to start a focus timer on it?",
                         action: .focus, actionLabel: "Start focus")
        }
        if let next = todayBlocks.first(where: { $0.start > now }) {
            let mins = max(1, Int(next.start.timeIntervalSince(now) / 60))
            return Reply(text: "\(next.title) starts at \(Fmt.time.string(from: next.start)) — about \(Fmt.duration(minutes: mins)) to prep or wrap up loose ends.")
        }
        let topTask = service.tasks
            .filter { !$0.isCompleted && !$0.isSubtask }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .first
        if let topTask {
            return Reply(text: "Nothing scheduled right now. Your most pressing task is \(topTask.title) — want to block time for it?",
                         action: .planDay, actionLabel: "Plan my day")
        }
        return Reply(text: "You're all clear. A good moment for a break, or to get ahead on tomorrow.")
    }

    private func overloadReply() -> Reply {
        let planned = todayBlocks
            .compactMap { $0.clamped(to: Date().startOfDay) }
            .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        let capacity = max(60, workEndMinutes - workStartMinutes)
        let ratio = Double(planned) / Double(capacity)
        let dur = Fmt.duration(minutes: planned)
        if ratio >= 0.9 {
            return Reply(text: "You've booked \(dur) today — that's packed against your \(Fmt.duration(minutes: capacity)) window. If something's optional, reflow to give yourself breathing room.",
                         action: .reflow, actionLabel: "Reflow today")
        }
        if ratio >= 0.5 {
            return Reply(text: "\(dur) planned today — a solid, focused load with some slack left. You're in good shape.")
        }
        if planned == 0 {
            return Reply(text: "Nothing booked yet today. Plan your day to turn open tasks into real time blocks.",
                         action: .planDay, actionLabel: "Plan my day")
        }
        return Reply(text: "Only \(dur) planned today — you have plenty of room to add a deep-work block or pull work forward.",
                     action: .planDay, actionLabel: "Plan my day")
    }

    private func slippedReply() -> Reply {
        let overdue = service.tasks.filter { $0.isOverdue }.count
        let pastIncomplete = todayBlocks.filter { block in
            guard block.end < now, let id = block.linkedTaskID else { return false }
            return service.task(withID: id)?.isCompleted == false
        }.count
        if overdue > 0 {
            return Reply(text: "You have \(overdue) overdue task\(overdue == 1 ? "" : "s"). Sweep them to today in one move.",
                         action: .overdueSweep, actionLabel: "Sweep overdue")
        }
        if pastIncomplete > 0 {
            return Reply(text: "\(pastIncomplete) finished block\(pastIncomplete == 1 ? "" : "s") still have open tasks. Review them and reschedule what slipped.",
                         action: .review, actionLabel: "Review day")
        }
        return Reply(text: "Nothing's slipped — no overdue tasks and every finished block is accounted for. Nicely done.")
    }

    private func weekReply() -> Reply {
        let pct = Int((stats.completionRate * 100).rounded())
        return Reply(text: "This week: \(Fmt.duration(minutes: stats.focusMinutes)) focused, \(stats.tasksCompleted) task\(stats.tasksCompleted == 1 ? "" : "s") done, a \(stats.streakDays)-day streak, and \(pct)% of due tasks complete. Full breakdown in Statistics.",
                     action: .openStats, actionLabel: "See statistics")
    }

    // MARK: Types

    enum QuickAction { case planDay, planWeek, reflow, review, focus, overdueSweep }

    private struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        let reply: Reply
    }

    /// An assistant answer with an optional deep-link action.
    private struct Reply {
        var text: String
        var action: ReplyAction?
        var actionLabel: String?
        init(text: String, action: ReplyAction? = nil, actionLabel: String? = nil) {
            self.text = text
            self.action = action
            self.actionLabel = actionLabel
        }
    }

    private enum ReplyAction { case planDay, reflow, review, focus, overdueSweep, openStats }

    private func perform(_ action: ReplyAction) {
        switch action {
        case .planDay: model.planDayPresented = true
        case .reflow: model.reflowPresented = true
        case .review: model.reviewPresented = true
        case .focus: model.startFocus(taskID: nil, title: "Focus")
        case .overdueSweep: model.overdueSweepPresented = true
        case .openStats: model.statsPresented = true
        }
    }

    enum AssistantPrompt: CaseIterable, Identifiable {
        case focusNow, overloaded, slipped, week, planToday
        var id: Self { self }
        var label: String {
            switch self {
            case .focusNow: return "What should I focus on now?"
            case .overloaded: return "Am I overloaded today?"
            case .slipped: return "What slipped?"
            case .week: return "How's my week going?"
            case .planToday: return "Plan my day"
            }
        }
    }
}

/// A wrapping row of tappable prompt chips.
private struct FlowChips: View {
    let prompts: [CoachView.AssistantPrompt]
    let onTap: (CoachView.AssistantPrompt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(prompts) { prompt in
                Button { onTap(prompt) } label: {
                    HStack(spacing: 7) {
                        Text(prompt.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
