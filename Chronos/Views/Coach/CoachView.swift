import SwiftUI

/// The Coach tab: a conversational planning companion. You can type anything,
/// and when the device supports Apple Intelligence it answers with an
/// on-device LLM grounded in your real schedule, tasks, habits, and stats.
/// Where that isn't available it falls back to fast, data-aware heuristic
/// replies — so it always feels responsive and personal, never canned.
struct CoachView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var thinking = false
    @State private var didSeed = false
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

            conversation

            composer
        }
        .background(Theme.bg)
        .onReceive(clock) { now = $0 }
        .onAppear(perform: seedIfNeeded)
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
                    Circle().fill(assistant.isReady ? Theme.success : Theme.textTertiary)
                        .frame(width: 5, height: 5)
                    Text(assistant.modeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            HeaderIconButton(icon: "chart.bar.xaxis") { model.statsPresented = true }
            HeaderIconButton(icon: "square.and.pencil") { newConversation() }
        }
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { message in
                        MessageBubble(message: message, onAction: perform)
                            .id(message.id)
                    }
                    if thinking {
                        ThinkingBubble().id("thinking")
                    }
                    if messages.count <= 1 && !thinking {
                        starterChips
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .onChange(of: messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: thinking) { _, _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) {
            if thinking {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var starterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                .foregroundStyle(Theme.textTertiary)
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

    // MARK: Composer (quick actions + input)

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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !thinking
    }

    // MARK: Conversation flow

    private func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        messages.append(ChatMessage(role: .coach, text: openingLine()))
    }

    private func newConversation() {
        assistant.resetConversation()
        withAnimation(.snappy) {
            messages = [ChatMessage(role: .coach, text: openingLine())]
            input = ""
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !thinking else { return }
        withAnimation(.snappy) {
            messages.append(ChatMessage(role: .user, text: trimmed))
            input = ""
            thinking = true
        }
        let context = contextString()
        Task {
            let llm = await assistant.reply(to: trimmed, context: context)
            let reply: ChatMessage
            if let llm, !llm.trimmingCharacters(in: .whitespaces).isEmpty {
                reply = ChatMessage(role: .coach, text: llm)
            } else {
                reply = heuristicReply(for: trimmed)
            }
            withAnimation(.snappy) {
                thinking = false
                messages.append(reply)
            }
        }
    }

    // MARK: Grounding context for the model

    private func contextString() -> String {
        var lines: [String] = []
        lines.append("Now: \(Fmt.weekdayFull.string(from: now)), \(Fmt.time.string(from: now)).")

        let blocks = todayBlocks
        if let current = blocks.first(where: { $0.start <= now && now < $0.end }) {
            lines.append("Currently in the block \"\(current.title)\" until \(Fmt.time.string(from: current.end)).")
        }
        if let next = blocks.first(where: { $0.start > now }) {
            lines.append("Next block: \"\(next.title)\" at \(Fmt.time.string(from: next.start)).")
        }
        let planned = blocks
            .compactMap { $0.clamped(to: Date().startOfDay) }
            .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        if blocks.isEmpty {
            lines.append("Nothing is scheduled today yet.")
        } else {
            lines.append("Today has \(blocks.count) blocks, \(Fmt.duration(minutes: planned)) planned in a \(Fmt.duration(minutes: max(60, workEndMinutes - workStartMinutes))) working window.")
        }

        let open = service.tasks.filter { !$0.isCompleted && !$0.isSubtask }
        let overdue = service.tasks.filter { $0.isOverdue }.count
        let dueToday = open.filter { $0.isDueToday }.count
        lines.append("Open tasks: \(open.count) total, \(dueToday) due today, \(overdue) overdue.")
        let top = open
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(3).map(\.title)
        if !top.isEmpty { lines.append("Most pressing tasks: \(top.joined(separator: "; ")).") }

        let habitsDue = life.activeHabits.filter { $0.isDue(on: Date().startOfDay) }
        if !habitsDue.isEmpty {
            let done = habitsDue.filter { life.isDone($0, on: Date().startOfDay) }.count
            lines.append("Habits today: \(done)/\(habitsDue.count) done — \(habitsDue.map(\.title).joined(separator: ", ")).")
        }

        lines.append("This week: \(Fmt.duration(minutes: stats.focusMinutes)) focused, \(stats.tasksCompleted) tasks done, \(stats.streakDays)-day completion streak, \(Int((stats.completionRate * 100).rounded()))% of due tasks complete.")

        if profileStore.profile.isCalibrated {
            lines.append("Their daily routine and focus window are calibrated — respect their energy patterns and meal times.")
        }
        return lines.joined(separator: "\n")
    }

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

    private var todayBlocks: [TimeBlock] {
        service.blocks(on: Date().startOfDay, hiddenCalendars: model.hiddenCalendarIDs)
            .filter { !$0.isAllDay }
            .sorted { $0.start < $1.start }
    }

    // MARK: Heuristic fallback (also seeds variety so it never feels canned)

    private func openingLine() -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let greeting: String
        switch hour {
        case 5..<12: greeting = ["Morning!", "Good morning.", "Rise and plan —"].randomElement()!
        case 12..<17: greeting = ["Afternoon!", "Good afternoon.", "Hey —"].randomElement()!
        case 17..<22: greeting = ["Evening!", "Good evening.", "Winding down?"].randomElement()!
        default: greeting = ["Working late?", "Late one tonight?"].randomElement()!
        }
        let blocks = todayBlocks
        let tail: String
        if let current = blocks.first(where: { $0.start <= now && now < $0.end }) {
            tail = "You're in \(current.title) right now — need anything to stay on track?"
        } else if let next = blocks.first(where: { $0.start > now }) {
            tail = "Next up is \(next.title) at \(Fmt.time.string(from: next.start)). Want to prep, or plan the rest of the day?"
        } else if blocks.isEmpty {
            tail = "Your timeline's a blank canvas. Want me to help you plan the day?"
        } else {
            let overdue = service.tasks.filter { $0.isOverdue }.count
            tail = overdue > 0
                ? "Your scheduled blocks are done. There \(overdue == 1 ? "is" : "are") \(overdue) overdue task\(overdue == 1 ? "" : "s") — want to sweep them?"
                : "Your scheduled blocks are done for the day. Nicely handled."
        }
        return "\(greeting) \(tail)"
    }

    private func heuristicReply(for text: String) -> ChatMessage {
        let q = text.lowercased()
        if q.contains("focus") || q.contains("work on") || q.contains("right now") || q.contains("what should i do") {
            return focusNowReply()
        }
        if q.contains("overload") || q.contains("too much") || q.contains("busy") || q.contains("room") || q.contains("capacity") {
            return overloadReply()
        }
        if q.contains("slip") || q.contains("behind") || q.contains("overdue") || q.contains("miss") || q.contains("late") {
            return slippedReply()
        }
        if q.contains("week") || q.contains("how am i") || q.contains("progress") || q.contains("doing") {
            return weekReply()
        }
        if q.contains("plan") {
            return ChatMessage(role: .coach,
                               text: "Let's lay it out — I'll fit your open tasks into the free slots around what's already scheduled.",
                               action: .planDay, actionLabel: "Plan my day")
        }
        return ChatMessage(role: .coach,
                           text: "I can help you figure out what to focus on, whether you're overloaded, what's slipped, or how your week's going — and plan any of it with a tap. What's on your mind?")
    }

    private func focusNowReply() -> ChatMessage {
        if let current = todayBlocks.first(where: { $0.start <= now && now < $0.end }) {
            return ChatMessage(role: .coach,
                               text: "Stay with \(current.title) — it runs until \(Fmt.time.string(from: current.end)). Want a focus timer on it?",
                               action: .focus, actionLabel: "Start focus")
        }
        if let next = todayBlocks.first(where: { $0.start > now }) {
            let mins = max(1, Int(next.start.timeIntervalSince(now) / 60))
            return ChatMessage(role: .coach,
                               text: "\(next.title) starts at \(Fmt.time.string(from: next.start)) — about \(Fmt.duration(minutes: mins)) to wrap loose ends or get set up.")
        }
        let top = service.tasks
            .filter { !$0.isCompleted && !$0.isSubtask }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .first
        if let top {
            return ChatMessage(role: .coach,
                               text: "Nothing's scheduled right now. Your most pressing task is \(top.title) — want to block time for it?",
                               action: .planDay, actionLabel: "Plan my day")
        }
        return ChatMessage(role: .coach, text: "You're all clear — a good moment to breathe, or get ahead on tomorrow.")
    }

    private func overloadReply() -> ChatMessage {
        let planned = todayBlocks
            .compactMap { $0.clamped(to: Date().startOfDay) }
            .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        let capacity = max(60, workEndMinutes - workStartMinutes)
        let ratio = Double(planned) / Double(capacity)
        let dur = Fmt.duration(minutes: planned)
        if ratio >= 0.9 {
            return ChatMessage(role: .coach,
                               text: "You've booked \(dur) today — that's packed against your \(Fmt.duration(minutes: capacity)) window. If anything's optional, reflow to make room to breathe.",
                               action: .reflow, actionLabel: "Reflow today")
        }
        if ratio >= 0.5 {
            return ChatMessage(role: .coach, text: "\(dur) planned today — a solid, focused load with slack to spare. You're in good shape.")
        }
        if planned == 0 {
            return ChatMessage(role: .coach,
                               text: "Nothing booked yet today. Want me to turn your open tasks into real time blocks?",
                               action: .planDay, actionLabel: "Plan my day")
        }
        return ChatMessage(role: .coach,
                           text: "Only \(dur) planned today — plenty of room to add a deep-work block or pull tomorrow's work forward.",
                           action: .planDay, actionLabel: "Plan my day")
    }

    private func slippedReply() -> ChatMessage {
        let overdue = service.tasks.filter { $0.isOverdue }.count
        let pastIncomplete = todayBlocks.filter { block in
            guard block.end < now, let id = block.linkedTaskID else { return false }
            return service.task(withID: id)?.isCompleted == false
        }.count
        if overdue > 0 {
            return ChatMessage(role: .coach,
                               text: "You have \(overdue) overdue task\(overdue == 1 ? "" : "s"). Want to sweep them onto today in one move?",
                               action: .overdueSweep, actionLabel: "Sweep overdue")
        }
        if pastIncomplete > 0 {
            return ChatMessage(role: .coach,
                               text: "\(pastIncomplete) finished block\(pastIncomplete == 1 ? "" : "s") still have open tasks. Review them and reschedule what slipped?",
                               action: .review, actionLabel: "Review day")
        }
        return ChatMessage(role: .coach, text: "Nothing's slipped — no overdue tasks and every finished block is accounted for. Nicely done.")
    }

    private func weekReply() -> ChatMessage {
        let pct = Int((stats.completionRate * 100).rounded())
        return ChatMessage(role: .coach,
                           text: "This week you've focused \(Fmt.duration(minutes: stats.focusMinutes)), finished \(stats.tasksCompleted) task\(stats.tasksCompleted == 1 ? "" : "s"), kept a \(stats.streakDays)-day streak, and cleared \(pct)% of what's due. Want the full picture?",
                           action: .openStats, actionLabel: "See statistics")
    }

    // MARK: Actions

    func perform(_ action: QuickAction) {
        switch action {
        case .planDay: model.planDayPresented = true
        case .planWeek: model.planWeekPresented = true
        case .reflow: model.reflowPresented = true
        case .review: model.reviewPresented = true
        case .focus: model.startFocus(taskID: nil, title: "Focus")
        case .overdueSweep: model.overdueSweepPresented = true
        case .openStats: model.statsPresented = true
        case .recalibrate: model.calibrationPresented = true
        }
    }
}

// MARK: - Supporting types & views

enum QuickAction {
    case planDay, planWeek, reflow, review, focus, overdueSweep, openStats, recalibrate
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, coach }
    let id = UUID()
    let role: Role
    var text: String
    var action: QuickAction?
    var actionLabel: String?
}

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
                    Circle()
                        .fill(Theme.textTertiary)
                        .frame(width: 6, height: 6)
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
