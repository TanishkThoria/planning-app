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
            CoachBriefingView()
        }
    }
}

// MARK: - Chat (on-device AI available)

struct CoachChatView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore

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
        .onChange(of: model.screen) { oldScreen, newScreen in
            if oldScreen == .coach, newScreen != .coach {
                store.archiveIfLeaving()
            } else if newScreen == .coach {
                seedIfEmpty()
            }
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
                Circle().fill(Color.accentColor.opacity(0.16)).frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Coach")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 5) {
                    Circle().fill(Theme.success).frame(width: 5, height: 5)
                    Text("On-device AI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            OverflowMenu { InsightsMenu() }
            HeaderIconButton(icon: "square.and.pencil") { newConversation() }
        }
    }

    // MARK: Continue-previous banner

    private var continueBanner: some View {
        Button { withAnimation(.snappy) { store.restore() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Continue previous conversation")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.10))
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
                    // Resting state: the same warm briefing as non-AI devices,
                    // with example prompts so the chat is discoverable.
                    VStack(alignment: .leading, spacing: 16) {
                        BriefingContent()
                        starterChips
                    }
                    .padding(18)
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

    private var starterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("ASK YOUR COACH")
                    .font(.system(size: 10.5, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(Starter.allCases) { starter in
                Button { send(starter.text) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: starter.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickChip("Plan day", "wand.and.stars", .planDay)
                    quickChip("Plan week", "calendar.badge.clock", .planWeek)
                    quickChip("Reflow", "arrow.triangle.2.circlepath", .reflow)
                    quickChip("Focus", "timer", .focus)
                    quickChip("Review", "checkmark.circle", .review)
                    quickChip("Sweep overdue", "tray.and.arrow.down", .overdueSweep)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            inputBar
        }
        .background(Theme.bg)
    }

    private func quickChip(_ title: String, _ icon: String, _ action: QuickAction) -> some View {
        Button { perform(action) } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
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
                    .background(canSend ? Color.accentColor : Theme.fill, in: Circle())
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
        if profileStore.profile.isCalibrated {
            lines.append("Their routine and focus window are calibrated — respect their energy patterns and meal times.")
        }
        return lines.joined(separator: "\n")
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
}

// MARK: - Supporting views

private enum Starter: CaseIterable, Identifiable {
    case focus, overloaded, slipped, week, plan
    var id: Self { self }
    var text: String {
        switch self {
        case .focus: return "What should I focus on now?"
        case .overloaded: return "Am I overloaded today?"
        case .slipped: return "What's slipped?"
        case .week: return "How's my week going?"
        case .plan: return "Help me plan my day"
        }
    }
    var icon: String {
        switch self {
        case .focus: return "scope"
        case .overloaded: return "gauge.with.dots.needle.67percent"
        case .slipped: return "exclamationmark.arrow.circlepath"
        case .week: return "chart.line.uptrend.xyaxis"
        case .plan: return "wand.and.stars"
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
                    .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        } else {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.16)).frame(width: 26, height: 26)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
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
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
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
                Circle().fill(Color.accentColor.opacity(0.16)).frame(width: 26, height: 26)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
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
