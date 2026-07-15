import SwiftUI

/// The Coach tab. When the device has on-device AI it's a full chat companion;
/// otherwise it's a warm daily briefing (no dead chatbox). The choice is made
/// once here so the two experiences never bleed into each other.
struct CoachView: View {
    private let assistant = AssistantService.shared

    var body: some View {
        if assistant.isReady {
            CoachChatView()
        } else {
            CoachUnavailableView()
        }
    }
}

/// Shown only if the Coach is somehow opened on a device without on-device AI
/// (its entry points are hidden there). Honest, not a dead chatbox.
struct CoachUnavailableView: View {
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss
    private let assistant = AssistantService.shared

    var body: some View {
        VStack(spacing: 14) {
            if isPresented {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding([.top, .horizontal], 16)
            }
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(Theme.accentColor)
            Text("Coach needs Apple Intelligence")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text(unavailableReason)
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
            Text("Everything the Coach would do — planning, focus, momentum, insights — is already one tap away across the app.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .chronosAppearance()
    }

    private var unavailableReason: String {
        if case .unavailable(let msg) = assistant.status { return msg }
        return "On-device AI isn't available on this device."
    }
}

// MARK: - Chat (on-device AI available)

struct CoachChatView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60

    @ObservedObject private var store = CoachStore.shared
    @State private var input = ""
    @State private var thinking = false
    @State private var now = Date()
    @FocusState private var inputFocused: Bool

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let assistant = AssistantService.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            if store.hasArchive && !store.hasRealConversation {
                continueBanner
            }

            conversation
            composer
        }
        .background(Theme.bg)
        .onReceive(clock) { now = $0 }
        .onAppear { seedIfEmpty() }
        .task { if PaidFeatures.shared.isReady(.friends) { await SocialService.shared.refreshFriends() } }
        .onChange(of: model.screen) { oldScreen, newScreen in
            if oldScreen == .coach, newScreen != .coach {
                store.archiveIfLeaving()
            } else if newScreen == .coach {
                seedIfEmpty()
            }
        }
        .onDisappear {
            // When Coach is a sheet (iPhone), archive on dismiss too.
            if isPresented { store.archiveIfLeaving() }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { inputFocused = false }
            }
        }
        #endif
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.accentColor.opacity(0.16)).frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Coach")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 5) {
                    Circle().fill(Theme.success).frame(width: 5, height: 5)
                    Text("On-device AI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            HeaderIconButton(icon: "square.and.pencil") { newConversation() }
            if isPresented {
                HeaderIconButton(icon: "xmark") { dismiss() }
            }
        }
    }

    // MARK: Continue-previous banner

    private var continueBanner: some View {
        Button { withAnimation(.snappy) { store.restore() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                Text("Continue previous conversation")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.accentColor.opacity(0.10))
        }
        .buttonStyle(.plain)
    }

    // MARK: Conversation

    @ViewBuilder
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.hasRealConversation {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(store.messages) { message in
                            MessageBubble(message: message) { perform($0) }
                                .id(message.id)
                        }
                        if thinking { ThinkingBubble().id("thinking") }
                    }
                    .padding(18)
                } else {
                    restingState.padding(18)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: thinking) { _, _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) {
            if thinking {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = store.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: Personalized resting state (LLM devices only)

    private var restingState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(personalGreeting)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("I can see your schedule, momentum, focus, and what your friends are up to. Ask me anything, or start here.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let insights = coachInsights
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FOR YOU RIGHT NOW")
                        .font(.system(size: 10.5, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(insights) { insight in
                        insightCard(insight)
                    }
                }
            }

            starterChips
        }
    }

    private func insightCard(_ insight: CoachInsight) -> some View {
        Button { insight.run() } label: {
            HStack(spacing: 12) {
                Image(systemName: insight.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: insight.tint))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: insight.tint).opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(insight.detail).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Text(insight.actionLabel)
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.accentColor)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var personalGreeting: String {
        let name = SocialService.shared.myDisplayName
        let first = name == "Me" ? "" : ", \(name.split(separator: " ").first.map(String.init) ?? name)"
        let h = Calendar.current.component(.hour, from: now)
        let base = h < 5 ? "Still up" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return "\(base)\(first)."
    }

    private var starterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                Text("ASK YOUR COACH")
                    .font(.system(size: 10.5, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(Starter.allCases) { starter in
                Button { send(starter.text) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: starter.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                            .frame(width: 18)
                        Text(starter.text)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            inputBar
        }
        .background(Theme.bg)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your coach anything…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...4)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send(input) }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))

            Button { send(input) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.bg)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Theme.accentColor : Theme.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !thinking
    }

    // MARK: Flow

    private func seedIfEmpty() {
        guard store.messages.isEmpty else { return }
        store.messages.append(ChatMessage(role: .coach, text: PlannerBrief.greeting(context)))
    }

    private func newConversation() {
        assistant.resetConversation()
        store.clear()
        withAnimation(.snappy) {
            store.messages = [ChatMessage(role: .coach, text: PlannerBrief.greeting(context))]
            input = ""
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !thinking else { return }
        withAnimation(.snappy) {
            store.messages.append(ChatMessage(role: .user, text: trimmed))
            input = ""
            thinking = true
        }
        let ctx = groundingString()
        Task {
            let llm = await assistant.reply(to: trimmed, context: ctx)
            let reply: ChatMessage
            if let llm, !llm.trimmingCharacters(in: .whitespaces).isEmpty {
                reply = ChatMessage(role: .coach, text: llm)
            } else {
                reply = heuristicReply(for: trimmed)
            }
            withAnimation(.snappy) {
                thinking = false
                store.messages.append(reply)
            }
        }
    }

    // MARK: Grounding + fallback

    private func groundingString() -> String {
        var lines: [String] = []
        lines.append("Now: \(Fmt.weekdayFull.string(from: now)), \(Fmt.time.string(from: now)).")
        let blocks = todayBlocks
        if let current = blocks.first(where: { $0.start <= now && now < $0.end }) {
            lines.append("Currently in the block \"\(current.title)\" until \(Fmt.time.string(from: current.end)).")
        }
        if let next = blocks.first(where: { $0.start > now }) {
            lines.append("Next block: \"\(next.title)\" at \(Fmt.time.string(from: next.start)).")
        }
        let planned = blocks.compactMap { $0.clamped(to: Date().startOfDay) }
            .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        lines.append(blocks.isEmpty
            ? "Nothing is scheduled today yet."
            : "Today has \(blocks.count) blocks, \(Fmt.duration(minutes: planned)) planned in a \(Fmt.duration(minutes: max(60, workEndMinutes - workStartMinutes))) working window.")
        let open = service.tasks.filter { !$0.isCompleted && !$0.isSubtask }
        let overdue = service.tasks.filter { $0.isOverdue }.count
        lines.append("Open tasks: \(open.count) total, \(open.filter { $0.isDueToday }.count) due today, \(overdue) overdue.")
        let top = open.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }.prefix(3).map(\.title)
        if !top.isEmpty { lines.append("Most pressing tasks: \(top.joined(separator: "; ")).") }
        let habitsDue = life.activeHabits.filter { $0.isDue(on: Date().startOfDay) }
        if !habitsDue.isEmpty {
            let done = habitsDue.filter { life.isDone($0, on: Date().startOfDay) }.count
            lines.append("Habits today: \(done)/\(habitsDue.count) done — \(habitsDue.map(\.title).joined(separator: ", ")).")
        }
        lines.append("This week: \(Fmt.duration(minutes: stats.focusMinutes)) focused, \(stats.tasksCompleted) tasks done, \(stats.streakDays)-day streak, \(Int((stats.completionRate * 100).rounded()))% of due tasks complete.")

        // Momentum + streaks
        let mStore = MomentumStore.shared
        let mScore = MomentumEngine.score(momentumInput)
        lines.append("Momentum today: \(mScore)/100 (level \(mStore.level), \(mStore.levelTitle)). Streak \(mStore.streak()) days, best ever \(mStore.bestStreak()), \(mStore.availableFreezes) freezes banked.")
        if let boost = MomentumEngine.nextBestAction(momentumInput) {
            lines.append("Biggest momentum boost left today: \(boost.tip)")
        }

        // Realistic workload
        let load = DayLoad.compute(tasks: service.tasks, events: todayBlocks, workStart: workStartMinutes, workEnd: workEndMinutes, now: now)
        if load.taskCount > 0 {
            lines.append(load.overcommitted
                ? "Overcommitted: \(load.taskCount) due tasks need ~\(Fmt.duration(minutes: load.committedMinutes)) but only \(Fmt.duration(minutes: load.freeMinutes)) is free — about \(Fmt.duration(minutes: load.overBy)) over."
                : "Workload realistic: \(Fmt.duration(minutes: load.committedMinutes)) of due tasks fits the \(Fmt.duration(minutes: load.freeMinutes)) free.")
        }

        // Focus integrity (soft, on-device — no Screen Time needed)
        let weekSessions = focusLog.sessions(inLast: 7)
        if !weekSessions.isEmpty {
            let finished = weekSessions.filter(\.completedFullDuration).count
            lines.append("Focus sessions this week: \(weekSessions.count), \(finished) finished without leaving.")
        }

        // Category mix this week — what kinds of things they spend time on.
        let weekStart = Date().startOfWeek
        var catTotals: [ActivityCategory: Int] = [:]
        for day in (0..<7).map({ weekStart.adding(days: $0) }) {
            for b in service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs) where !b.isAllDay {
                catTotals[TagStore.shared.category(for: b), default: 0] += b.durationMinutes
            }
        }
        let topCats = catTotals.sorted { $0.value > $1.value }.prefix(4)
        if !topCats.isEmpty {
            lines.append("Time by category this week: " + topCats.map { "\($0.key.title) \(Fmt.duration(minutes: $0.value))" }.joined(separator: ", ") + ". Use this to notice imbalance (e.g. lots of work, no rest or fitness) and tailor suggestions.")
        }

        // Friends (only what they've shared)
        let friends = SocialService.shared.friends
        if !friends.isEmpty {
            let focusing = friends.filter { $0.isLive && $0.presence.busy == .headsDown }
            if !focusing.isEmpty {
                lines.append("Friends focusing right now: \(focusing.map { $0.presence.displayName }.joined(separator: ", ")). Suggest joining them if the user wants accountability.")
            }
            let summary = friends.prefix(4).map { "\($0.presence.displayName) (\($0.presence.streakDays)d streak, \(Fmt.duration(minutes: $0.presence.weeklyFocus)) this week)" }
            lines.append("Friends: \(summary.joined(separator: "; ")).")
        }

        // Routines available
        let routines = RoutineStore.shared.routines
        if !routines.isEmpty {
            lines.append("Saved routines they can run: \(routines.map(\.name).joined(separator: ", ")).")
        }

        if profileStore.profile.isCalibrated {
            let p = profileStore.profile
            lines.append("Calibrated: best focus in the \(p.focus.rawValue.lowercased()), \(p.flexibility.rawValue.lowercased()) schedule — respect their energy patterns and meal times.")
        }
        return lines.joined(separator: "\n")
    }

    /// The momentum inputs, computed the same way the Momentum card does.
    private var momentumInput: MomentumEngine.Input {
        let today = Date().startOfDay
        let blocks = service.blocks(on: today, hiddenCalendars: model.hiddenCalendarIDs).filter { !$0.isAllDay }
        let entry = life.entry(for: today)
        let habitsDue = life.activeHabits.filter { $0.isDue(on: today) }
        let frog = model.frogTaskID.flatMap { service.task(withID: $0) }
        return MomentumEngine.Input(
            plannedBlocks: blocks.count,
            didMorningPlan: entry?.hasMorning ?? false,
            tasksCompletedToday: service.tasks.filter { $0.isCompleted && ($0.completionDate?.isToday ?? false) }.count,
            focusMinutesToday: focusLog.sessions(on: today).reduce(0) { $0 + $1.actualMinutes },
            habitsDue: habitsDue.count,
            habitsDone: habitsDue.filter { life.isDone($0, on: today) }.count,
            journaledEvening: entry?.hasEvening ?? false,
            frogEaten: frog?.isCompleted ?? false
        )
    }

    private func heuristicReply(for text: String) -> ChatMessage {
        let q = text.lowercased()
        let ctx = context
        func msg(_ item: PlannerBrief.Item) -> ChatMessage {
            ChatMessage(role: .coach, text: item.message, action: item.action, actionLabel: item.actionLabel)
        }
        if q.contains("focus") || q.contains("work on") || q.contains("right now") || q.contains("what should i do") {
            return msg(PlannerBrief.focus(ctx))
        }
        if q.contains("overload") || q.contains("too much") || q.contains("busy") || q.contains("room") || q.contains("load") || q.contains("capacity") {
            return msg(PlannerBrief.load(ctx))
        }
        if q.contains("slip") || q.contains("behind") || q.contains("overdue") || q.contains("miss") {
            if let loose = PlannerBrief.looseEnds(ctx) { return msg(loose) }
            return ChatMessage(role: .coach, text: "Nothing's slipped — no overdue tasks and every finished block is accounted for. Nicely done.")
        }
        if q.contains("week") || q.contains("how am i") || q.contains("progress") || q.contains("doing") {
            return msg(PlannerBrief.week(ctx))
        }
        if q.contains("plan") {
            return ChatMessage(role: .coach, text: "Let's lay it out — I'll fit your open tasks into the free slots around what's already scheduled.", action: .planDay, actionLabel: "Plan my day")
        }
        return ChatMessage(role: .coach, text: "I can help you figure out what to focus on, whether you're overloaded, what's slipped, or how your week's going — and plan any of it with a tap. What's on your mind?")
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

    private func perform(_ action: QuickAction) {
        performCoachAction(action, on: model)
    }

    /// Proactive, tap-to-act cards built live from the user's real situation —
    /// the "superpower" feel. Top few by priority.
    private var coachInsights: [CoachInsight] {
        var out: [CoachInsight] = []

        let focusing = SocialService.shared.friends.filter { $0.isLive && $0.presence.busy == .headsDown }
        if let f = focusing.first {
            out.append(CoachInsight(icon: "person.2.fill", tint: 0x7C8CF8,
                title: "\(f.presence.displayName) is focusing now",
                detail: focusing.count > 1 ? "\(focusing.count) friends are heads-down — join them." : "Study alongside them for accountability.",
                actionLabel: "Join") { model.startFocus(taskID: nil, title: "Focus") })
        }

        let load = DayLoad.compute(tasks: service.tasks, events: todayBlocks, workStart: workStartMinutes, workEnd: workEndMinutes, now: now)
        if load.overcommitted {
            out.append(CoachInsight(icon: "exclamationmark.triangle.fill", tint: 0xF2B95C,
                title: "Today's a stretch",
                detail: "Your due tasks need ~\(Fmt.duration(minutes: load.overBy)) more than the free time you have.",
                actionLabel: "Auto-fit") { performCoachAction(.planDay, on: model) })
        } else if todayBlocks.isEmpty, service.tasks.contains(where: { $0.isDueToday && !$0.isCompleted }) {
            out.append(CoachInsight(icon: "wand.and.stars", tint: 0x7C8CF8,
                title: "Nothing scheduled yet",
                detail: "Want me to lay your day out around what's due?",
                actionLabel: "Plan") { performCoachAction(.planDay, on: model) })
        }

        if MomentumEngine.score(momentumInput) < 100, let boost = MomentumEngine.nextBestAction(momentumInput) {
            out.append(CoachInsight(icon: boost.icon, tint: 0x5BD899,
                title: "Boost your momentum",
                detail: boost.tip,
                actionLabel: "Details") { model.momentumDetailPresented = true })
        }

        if let loose = PlannerBrief.looseEnds(context) {
            out.append(CoachInsight(icon: "tray.and.arrow.down", tint: 0xFF6B6B,
                title: "Loose ends to tie up",
                detail: loose.message,
                actionLabel: loose.actionLabel ?? "Fix") {
                    if let a = loose.action { performCoachAction(a, on: model) }
                })
        }

        return Array(out.prefix(3))
    }
}

/// A proactive Coach suggestion card.
private struct CoachInsight: Identifiable {
    let id = UUID()
    let icon: String
    let tint: UInt32
    let title: String
    let detail: String
    let actionLabel: String
    let run: () -> Void
}

// MARK: - Supporting views

private enum Starter: CaseIterable, Identifiable {
    case focus, plan, overloaded, momentum, friends, week
    var id: Self { self }
    var text: String {
        switch self {
        case .focus: return "What should I focus on right now?"
        case .plan: return "Help me plan my day"
        case .overloaded: return "Am I overloaded today?"
        case .momentum: return "How do I boost my momentum?"
        case .friends: return "What are my friends up to?"
        case .week: return "How's my week going?"
        }
    }
    var icon: String {
        switch self {
        case .focus: return "scope"
        case .plan: return "wand.and.stars"
        case .overloaded: return "gauge.with.dots.needle.67percent"
        case .momentum: return "bolt.fill"
        case .friends: return "person.2.fill"
        case .week: return "chart.line.uptrend.xyaxis"
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let onAction: (QuickAction) -> Void

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(Theme.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        } else {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    Circle().fill(Theme.accentColor.opacity(0.16)).frame(width: 26, height: 26)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.text)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    if let action = message.action, let label = message.actionLabel {
                        Button { onAction(action) } label: {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.accentColor)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Theme.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 12)
            }
        }
    }
}

private struct ThinkingBubble: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Circle().fill(Theme.accentColor.opacity(0.16)).frame(width: 26, height: 26)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
            }
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(Theme.textTertiary).frame(width: 6, height: 6)
                        .opacity(phase == i ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            Spacer(minLength: 12)
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
