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
    @EnvironmentObject private var focusLog: FocusLog
    @ObservedObject private var momentum = MomentumStore.shared

    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @AppStorage(Prefs.coachEnabled) private var coachEnabled = true
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60

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

    // MARK: Momentum / streak pressure

    private var momentumInput: MomentumEngine.Input {
        MomentumEngine.dailyInput(service: service, life: life, focusLog: focusLog,
                                  hiddenCalendars: model.hiddenCalendarIDs, frogTaskID: model.frogTaskID)
    }
    private var todayScore: Int { MomentumEngine.score(momentumInput) }

    /// A streak worth protecting, today still below "solid", and late enough in
    /// the day that it's genuinely at risk — the moment to apply pressure.
    private var streakAtRisk: Bool {
        let hour = Calendar.current.component(.hour, from: now)
        return momentum.streak() >= 2 && todayScore < MomentumStore.solidThreshold && hour >= 16
    }

    /// Always-on momentum widget: today's score ring, level, streak, and this
    /// week's day-dots — the positive anchor (the risk banner is the stick).
    private var momentumWidget: some View {
        let score = momentum.score(on: today)
        return Button { model.momentumDetailPresented = true } label: {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 9)
                    Circle().trim(from: 0, to: max(0.02, Double(score) / 100))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(score)").font(.system(size: 30, weight: .bold)).monospacedDigit()
                        Text("TODAY").font(.system(size: 10, weight: .bold)).tracking(0.6).opacity(0.85)
                    }
                    .foregroundStyle(Color.white)
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 4) {
                    Text(heroHeadline(score))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Level \(momentum.level) · \(momentum.levelTitle)")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(2).minimumScaleFactor(0.85)
                    if momentum.streak() > 0 {
                        Label("\(momentum.streak())-day streak", systemImage: "flame.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Color.white.opacity(0.22), in: Capsule())
                            .padding(.top, 3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Theme.accentColor, Theme.accentColor.opacity(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .shadow(color: Theme.accentColor.opacity(0.35), radius: 18, y: 10)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Momentum \(score) today, level \(momentum.level), \(momentum.streak()) day streak")
    }

    private func heroHeadline(_ score: Int) -> String {
        if score >= 100 { return "Perfect day! 🎉" }
        if score >= 70 { return "You're on a roll" }
        if score >= MomentumStore.solidThreshold { return "Nice momentum" }
        if score > 0 { return "You've started" }
        return "Let's get going"
    }

    private var streakRiskBanner: some View {
        let action = MomentumEngine.nextBestAction(momentumInput)
        return Button {
            model.momentumDetailPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your \(momentum.streak())-day streak is at risk")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(action?.tip ?? "You're at \(todayScore) — lift today's momentum to keep the streak alive.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 6)
                Text("Save it")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.danger, in: Capsule())
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.danger.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Project nudge

    /// The single most relevant project needing attention today — a weekly aim
    /// still open late in the week, or a project overdue for its check-in.
    private var projectAttention: (project: Project, message: String, cta: String)? {
        let weekday = Calendar.current.component(.weekday, from: now)
        let lateInWeek = weekday == 1 || weekday >= 5   // Thu–Sun
        if lateInWeek,
           let p = life.activeProjects.first(where: { proj in
               proj.weeklyGoal().map { !$0.isDone && !$0.text.isEmpty } ?? false
           }), let goal = p.weeklyGoal() {
            return (p, "This week's aim: \u{201C}\(goal.text)\u{201D}", "Open")
        }
        if let p = life.activeProjects.first(where: \.isUpdateDue) {
            return (p, "Due for a \(p.updateCadence.short.lowercased()) update", "Update")
        }
        return nil
    }

    @ViewBuilder
    private var projectNudge: some View {
        if let attention = projectAttention {
            let project = attention.project
            Button { model.projectsPresented = true } label: {
                HStack(spacing: 10) {
                    ProjectRing(progress: project.progress, color: project.color, emoji: project.emoji, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.title.isEmpty ? "Project" : project.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Text(attention.message)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2).minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 6)
                    Text(attention.cta)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(project.color)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(project.color.opacity(0.16), in: Capsule())
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(project.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(project.color.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Carry-over

    private var carryOverBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(overdue.count) unfinished from before")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Bring them to today, or schedule them into open time.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            Button {
                Haptics.success()
                withAnimation(.snappy) { _ = service.rollOverdueToToday() }
            } label: {
                Text("Roll over")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Theme.warning, in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                model.overdueSweepPresented = true
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14.5, weight: .semibold))
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
                    Text("🐸").font(.system(size: 15))
                    Text("Frog eaten — the hardest thing is behind you.")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.success)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("🐸").font(.system(size: 14.5))
                        Text("EAT THE FROG")
                            .font(.system(size: 11.5, weight: .bold)).tracking(1.2)
                            .foregroundStyle(Theme.accentColor)
                        Spacer()
                        Menu {
                            frogPickerItems
                            Divider()
                            Button(role: .destructive) { model.frogTaskID = nil } label: {
                                Label("Clear", systemImage: "xmark")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                    }
                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold))
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(Theme.accentColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            Haptics.success()
                            withAnimation(.snappy) { service.toggleTaskCompletion(id: task.id) }
                        } label: {
                            Label("Done", systemImage: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accentColor)
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(Theme.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .padding(12)
                .background(
                    LinearGradient(colors: [Theme.accentColor.opacity(0.14), Theme.accentColor.opacity(0.04)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.accentColor.opacity(0.25), lineWidth: 1))
            }
        } else if !frogCandidates.isEmpty {
            Menu {
                frogPickerItems
            } label: {
                HStack(spacing: 8) {
                    Text("🐸").font(.system(size: 14.5))
                    Text("Pick today's frog — the task you're most tempted to avoid")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
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
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                }
                if intentions.isEmpty {
                    Text("Set your top three for the day →")
                        .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)
                } else {
                    ForEach(Array(intentions.enumerated()), id: \.offset) { idx, text in
                        HStack(spacing: 8) {
                            Text("\(idx + 1)").font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(Theme.accentColor).frame(width: 14)
                            Text(text).font(.system(size: 14)).foregroundStyle(Theme.textPrimary).lineLimit(1)
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
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                let done = dueHabits.filter { life.doneToday($0) }.count
                Text("\(done)/\(dueHabits.count)")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
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
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(isDone ? habit.color : Theme.textSecondary)
                                Text(habit.title)
                                    .font(.system(size: 13, weight: .medium))
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
                    momentumWidget
                    intentCard
                    if streakAtRisk { streakRiskBanner }
                    dayLoadBanner
                    frogCard
                    intentionsCard
                    if !dueHabits.isEmpty { habitsStrip }
                    projectNudge

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
                        sectionLabel("Coming up", color: Theme.accentColor, count: upcomingBlocks.count)
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

    // MARK: Minimum Viable Day (mode + must-wins)

    @ViewBuilder
    private var intentCard: some View {
        let intent = life.intent(for: today)
        if let intent, !intent.mustWins.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let mode = intent.mode {
                        Label(mode.title, systemImage: mode.icon)
                            .font(.system(size: 11.5, weight: .bold)).foregroundStyle(mode.color)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(mode.color.opacity(0.14), in: Capsule())
                    }
                    Text("Must win").font(.system(size: 14.5, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 4)
                    Text("\(intent.mustWinsDone)/\(intent.mustWins.count)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(intent.floorCleared ? Theme.success : Theme.textSecondary)
                        .monospacedDigit()
                    Button { model.dayIntentPresented = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(intent.mustWins) { item in
                    Button {
                        withAnimation(.snappy) { life.toggleIntentItem(item.id, for: today) }
                        Haptics.success()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 19))
                                .foregroundStyle(item.isDone ? Theme.success : Theme.textTertiary)
                            Text(item.text)
                                .font(.system(size: 14))
                                .foregroundStyle(item.isDone ? Theme.textTertiary : Theme.textPrimary)
                                .strikethrough(item.isDone, color: Theme.textTertiary)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if intent.floorCleared {
                    Text("Floor cleared — today counts. 🎉")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.success)
                }
            }
            .panel()
        } else {
            Button { model.dayIntentPresented = true } label: {
                HStack(spacing: 12) {
                    IconChip(icon: "target", tint: Color(hex: 0x5B6CF0), size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set today's minimum")
                            .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text("The smallest version of today that keeps you moving")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .panel(padding: 12)
            }
            .buttonStyle(.plain)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<12: return "Good morning ☀️"
        case 12..<17: return "Good afternoon 🌤️"
        case 17..<22: return "Good evening 🌙"
        default: return "Hey there 👋"
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(remainingCount == 0
                     ? "All done for today · \(Fmt.monthDay.string(from: today))"
                     : "\(remainingCount) to go · \(Fmt.monthDay.string(from: today))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(remainingCount == 0 ? Theme.success : Theme.textSecondary)
            }
            Spacer()
            HeaderIconButton(icon: "command", accessibility: "Command bar") {
                model.commandBarPresented = true
            }
            .help("Command bar (⌘K)")
            #if os(iOS)
            HeaderIconButton(icon: "gearshape", accessibility: "Settings") {
                model.settingsPresented = true
            }
            .help("Settings")
            #endif
            HeaderIconButton(icon: "plus", prominent: true, accessibility: "Quick add") {
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
            HStack(spacing: 12) {
                actionTile("Plan", "sun.max.fill", Theme.accentColor) { model.morningPlanningPresented = true }
                actionTile("Focus", "timer", Color(hex: 0xFF7A59)) { model.startFocus(taskID: nil, title: "Focus") }
                actionTile("Review", "checkmark.circle.fill", Color(hex: 0x3FC97A)) { model.reviewPresented = true }
                actionTile("Reflow", "arrow.triangle.2.circlepath", Color(hex: 0x22C3C9)) { model.reflowPresented = true }
                actionTile("Now", "circle.circle.fill", Color(hex: 0x9C7BFA)) { model.nowModePresented = true }
                if coachEnabled, AssistantService.shared.isReady {
                    actionTile("Coach", "sparkles", Color(hex: 0xC86DD7)) { model.coachPresented = true }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    private func actionTile(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(colors: [color, color.opacity(0.78)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .shadow(color: color.opacity(0.35), radius: 8, y: 4)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 82)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
    }

    /// The realistic-workload guardrail: how the time your due tasks need
    /// compares to the free time you have left today.
    private var dayLoad: DayLoad.Result {
        DayLoad.compute(
            tasks: service.tasks,
            events: service.blocks(on: today, hiddenCalendars: model.hiddenCalendarIDs),
            workStart: workStartMinutes,
            workEnd: workEndMinutes,
            now: now
        )
    }

    @ViewBuilder
    private var dayLoadBanner: some View {
        let load = dayLoad
        if load.taskCount > 0 && load.committedMinutes > 0 {
            let over = load.overcommitted
            let tint = over ? Theme.warning : Theme.success
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: over ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(tint)
                    Text(over ? "Today looks overloaded" : "Today fits")
                        .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(Fmt.duration(minutes: load.committedMinutes)) / \(Fmt.duration(minutes: load.freeMinutes)) free")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(tint)
                            .frame(width: max(4, min(1.0, load.ratio) * geo.size.width))
                    }
                }
                .frame(height: 6)
                Text(over
                     ? "Your \(load.taskCount) due task\(load.taskCount == 1 ? "" : "s") need about \(Fmt.duration(minutes: load.overBy)) more than you have free. Trim, defer, or auto-fit what's left."
                     : "Your due tasks should fit the free time left today. Nice and realistic.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if over {
                    Button { model.planDayPresented = true } label: {
                        Label("Auto-fit my day", systemImage: "wand.and.stars")
                            .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 1))
        }
    }

    private func sectionLabel(_ title: String, color: Color, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(color)
            Spacer()
            Text("\(count)")
                .font(.system(size: 12, weight: .medium))
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(block.isNow ? Theme.accentColor : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if block.isNow {
                        Text("now")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Theme.accentColor)
                    }
                }
                .frame(width: 62, alignment: .trailing)

                RoundedRectangle(cornerRadius: 2).fill(block.color).frame(width: 3, height: 26)

                Text(block.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let url = block.meetingURL, block.end > now {
                    Link(destination: url) {
                        Label("Join", systemImage: "video.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(block.isNow ? Theme.bg : Theme.accentColor)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(block.isNow ? AnyShapeStyle(Theme.accentColor)
                                        : AnyShapeStyle(Theme.accentColor.opacity(0.14)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    let taskID = block.linkedTaskID
                    model.focusTimerContext = FocusStartContext(taskID: taskID, title: block.title)
                    model.focusTimerPresented = true
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
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
                    .font(.system(size: 24))
                    .foregroundStyle(
                        task.isCompleted ? Theme.success
                            : (task.priority == .none ? Theme.textTertiary : task.priority.color)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(task.isCompleted, color: Theme.textTertiary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if task.dueHasTime, let due = task.dueDate {
                        Text(Fmt.time.string(from: due))
                            .font(.system(size: 11.5))
                            .foregroundStyle(task.isOverdue ? Theme.danger : Theme.textTertiary)
                    }
                    if task.energy != .none {
                        Label(task.energy.label, systemImage: task.energy.icon)
                            .font(.system(size: 11.5))
                            .foregroundStyle(task.energy.color)
                    }
                    if let blocks = linkedFirst {
                        Label(Fmt.time.string(from: blocks.start), systemImage: "rectangle.stack")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.accentColor)
                    }
                }
            }

            Spacer(minLength: 4)

            Circle().fill(task.color).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
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
