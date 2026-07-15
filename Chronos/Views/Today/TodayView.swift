import SwiftUI

/// "Finish by end of day" — a focused, single-day command center distinct
/// from the timeline. Overdue at the top, then what's still ahead today
/// (upcoming blocks + tasks due today), then what's already done. Built for
/// the mid-day "what's left?" glance.
struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var timer: FocusTimerController
    @EnvironmentObject private var life: LifeStore

    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @AppStorage(Prefs.coachEnabled) private var coachEnabled = true

    private var today: Date { Date().startOfDay }

    private var overdue: [TaskItem] {
        service.tasks
            .filter { !$0.isCompleted && $0.isOverdue && !$0.isDueToday && !model.hiddenListIDs.contains($0.listID) }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    private var dueToday: [TaskItem] {
        service.tasks
            .filter { !$0.isCompleted && $0.isDueToday && !model.hiddenListIDs.contains($0.listID) }
            .sorted { a, b in
                // Timed tasks first (in due order), then untimed by priority.
                if a.dueHasTime != b.dueHasTime { return a.dueHasTime }
                if a.dueHasTime, let da = a.dueDate, let db = b.dueDate, da != db { return da < db }
                return a.priority.sortRank < b.priority.sortRank
            }
    }

    private var upcomingBlocks: [TimeBlock] {
        service.blocks(on: today, hiddenCalendars: model.hiddenCalendarIDs)
            .filter { !$0.isAllDay && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    private var doneToday: [TaskItem] {
        service.tasks
            .filter { $0.isCompleted && ($0.completionDate?.isToday ?? false) && !model.hiddenListIDs.contains($0.listID) }
    }

    private var remainingCount: Int { overdue.count + dueToday.count }

    private var dueHabits: [Habit] {
        life.activeHabits.filter { $0.isDue(on: today) }
    }

    // MARK: Carry-over

    private var carryOverBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(overdue.count) unfinished from before")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Bring them to today, or schedule them into open time.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            Button {
                Haptics.success()
                withAnimation(.snappy) { _ = service.rollOverdueToToday() }
            } label: {
                Text("Roll over")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Theme.warning, in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                model.overdueSweepPresented = true
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.warning)
            }
            .buttonStyle(.plain)
            .help("Schedule overdue into open time")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.warning.opacity(0.22), lineWidth: 1))
    }

    // MARK: Eat the frog

    /// Candidates for the frog: what's overdue or due today, hardest-first.
    private var frogCandidates: [TaskItem] {
        (overdue + dueToday).prefix(8).map { $0 }
    }

    @ViewBuilder
    private var frogCard: some View {
        if let id = model.frogTaskID, let task = service.task(withID: id) {
            if task.isCompleted {
                HStack(spacing: 8) {
                    Text("🐸").font(.system(size: 14))
                    Text("Frog eaten — the hardest thing is behind you.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.success)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("🐸").font(.system(size: 13))
                        Text("EAT THE FROG")
                            .font(.system(size: 10, weight: .bold)).tracking(1.2)
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Menu {
                            frogPickerItems
                            Divider()
                            Button(role: .destructive) { model.frogTaskID = nil } label: {
                                Label("Clear", systemImage: "xmark")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                    }
                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Button {
                            timer.focusMinutes = 5
                            timer.start(taskID: task.id, title: task.title, mode: .pomodoro)
                            model.focusTimerPresented = true
                            Haptics.medium()
                        } label: {
                            Label("Just start · 5 min", systemImage: "bolt.fill")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.bg)
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(Color.accentColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            Haptics.success()
                            withAnimation(.snappy) { service.toggleTaskCompletion(id: task.id) }
                        } label: {
                            Label("Done", systemImage: "checkmark")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .padding(12)
                .background(
                    LinearGradient(colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.04)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1))
            }
        } else if !frogCandidates.isEmpty {
            Menu {
                frogPickerItems
            } label: {
                HStack(spacing: 8) {
                    Text("🐸").font(.system(size: 13))
                    Text("Pick today's frog — the task you're most tempted to avoid")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
    }

    private var frogPickerItems: some View {
        ForEach(frogCandidates) { candidate in
            Button {
                model.frogTaskID = candidate.id
                Haptics.light()
            } label: {
                Label(candidate.title, systemImage: candidate.id == model.frogTaskID ? "checkmark" : "circle")
            }
        }
    }

    // MARK: Intentions

    private var intentionsCard: some View {
        let entry = life.entry(for: today)
        let intentions = (entry?.intentions ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Button {
            model.morningRitualPresented = true
        } label: {
            VStack(alignment: .leading, spacing: intentions.isEmpty ? 0 : 8) {
                HStack {
                    Label("Today's intentions", systemImage: "sunrise.fill")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
                if intentions.isEmpty {
                    Text("Set your top three for the day →")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)
                } else {
                    ForEach(Array(intentions.enumerated()), id: \.offset) { idx, text in
                        HStack(spacing: 8) {
                            Text("\(idx + 1)").font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.accentColor).frame(width: 14)
                            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .panel(padding: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Habits strip

    private var habitsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Habits", systemImage: "leaf.fill")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                let done = dueHabits.filter { life.doneToday($0) }.count
                Text("\(done)/\(dueHabits.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dueHabits) { habit in
                        let isDone = life.doneToday(habit)
                        Button {
                            withAnimation(.snappy) { life.toggle(habit, on: today) }
                            Haptics.success()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isDone ? "checkmark.circle.fill" : habit.iconName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(isDone ? habit.color : Theme.textSecondary)
                                Text(habit.title)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(isDone ? Theme.textPrimary : Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(isDone ? habit.color.opacity(0.15) : Theme.surface,
                                        in: Capsule())
                            .overlay(Capsule().strokeBorder(isDone ? habit.color.opacity(0.4) : Theme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.Metric.screen)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    dayActionsRow
                    frogCard
                    intentionsCard
                    if !dueHabits.isEmpty { habitsStrip }

                    if remainingCount == 0 && upcomingBlocks.isEmpty {
                        EmptyStateView(
                            icon: "checkmark.seal.fill",
                            title: "Nothing left today",
                            message: "You're clear for the rest of the day. Plan tomorrow, or enjoy the whitespace."
                        )
                    }

                    if !overdue.isEmpty {
                        carryOverBanner
                        sectionLabel("Overdue", color: Theme.danger, count: overdue.count)
                        ForEach(overdue) { TodayTaskRow(task: $0) }
                    }

                    if !upcomingBlocks.isEmpty {
                        sectionLabel("Coming up", color: Color.accentColor, count: upcomingBlocks.count)
                            .padding(.top, overdue.isEmpty ? 0 : 10)
                        ForEach(upcomingBlocks) { block in
                            upcomingBlockRow(block)
                        }
                    }

                    if !dueToday.isEmpty {
                        sectionLabel("Due today", color: Theme.warning, count: dueToday.count)
                            .padding(.top, 10)
                        ForEach(dueToday) { TodayTaskRow(task: $0) }
                    }

                    if !doneToday.isEmpty {
                        sectionLabel("Done", color: Theme.success, count: doneToday.count)
                            .padding(.top, 10)
                        ForEach(doneToday) { TodayTaskRow(task: $0) }
                    }
                }
                .padding(.horizontal, Theme.Metric.screen)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
        .onReceive(clock) { now = $0 }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(remainingCount == 0
                     ? "All tasks handled · \(Fmt.monthDay.string(from: today))"
                     : "\(remainingCount) to finish · \(Fmt.monthDay.string(from: today))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(remainingCount == 0 ? Theme.success : Theme.textSecondary)
            }
            Spacer()
            HeaderIconButton(icon: "command") {
                model.commandBarPresented = true
            }
            .help("Command bar (⌘K)")
            #if os(iOS)
            HeaderIconButton(icon: "gearshape") {
                model.settingsPresented = true
            }
            .help("Settings")
            #endif
            HeaderIconButton(icon: "plus", prominent: true) {
                model.quickAddPresented = true
            }
            .help("Quick add")
        }
    }

    /// The frequent day actions, as a labeled scrollable row — nothing hidden
    /// behind an unlabeled icon or a "More" menu. Anything rarer lives one tap
    /// away in the ⌘K command bar.
    private var dayActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                actionChip("Plan", "sunrise") { model.morningPlanningPresented = true }
                actionChip("Reflow", "arrow.triangle.2.circlepath") { model.reflowPresented = true }
                actionChip("Review", "checkmark.circle") { model.reviewPresented = true }
                actionChip("Focus", "timer") { model.startFocus(taskID: nil, title: "Focus") }
                actionChip("Now", "circle.circle") { model.nowModePresented = true }
                if coachEnabled {
                    actionChip("Coach", "sparkles") { model.coachPresented = true }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func actionChip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11.5, weight: .semibold))
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ title: String, color: Color, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(color)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .padding(.horizontal, 2)
    }

    private func upcomingBlockRow(_ block: TimeBlock) -> some View {
        Button {
            model.blockEditor = service.editorContext(for: block)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.time.string(from: block.start))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(block.isNow ? Color.accentColor : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if block.isNow {
                        Text("now")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 62, alignment: .trailing)

                RoundedRectangle(cornerRadius: 2).fill(block.color).frame(width: 3, height: 26)

                Text(block.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let url = block.meetingURL, block.end > now {
                    Link(destination: url) {
                        Label("Join", systemImage: "video.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(block.isNow ? Theme.bg : Color.accentColor)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(block.isNow ? AnyShapeStyle(Color.accentColor)
                                        : AnyShapeStyle(Color.accentColor.opacity(0.14)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    let taskID = block.linkedTaskID
                    model.focusTimerContext = FocusStartContext(taskID: taskID, title: block.title)
                    model.focusTimerPresented = true
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TodayTaskRow: View {
    let task: TaskItem

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if !task.isCompleted { Haptics.success() }
                withAnimation(.snappy) { service.toggleTaskCompletion(id: task.id) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        task.isCompleted ? Theme.success
                            : (task.priority == .none ? Theme.textTertiary : task.priority.color)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(task.isCompleted, color: Theme.textTertiary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if task.dueHasTime, let due = task.dueDate {
                        Text(Fmt.time.string(from: due))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(task.isOverdue ? Theme.danger : Theme.textTertiary)
                    }
                    if task.energy != .none {
                        Label(task.energy.label, systemImage: task.energy.icon)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(task.energy.color)
                    }
                    if let blocks = linkedFirst {
                        Label(Fmt.time.string(from: blocks.start), systemImage: "rectangle.stack")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Spacer(minLength: 4)

            Circle().fill(task.color).frame(width: 5, height: 5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .draggable(task.id)
        .onTapGesture {
            model.taskEditor = service.editorContext(for: task)
        }
    }

    private var linkedFirst: TimeBlock? {
        service.blocksLinked(to: task.id).filter { $0.start.isToday }.sorted { $0.start < $1.start }.first
    }
}
