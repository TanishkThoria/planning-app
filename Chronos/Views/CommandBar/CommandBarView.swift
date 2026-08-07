import SwiftUI

/// The universal command bar (⌘K) — Akiflow/Vimcal-style. Type to fuzzy-search
/// every action and destination in the app, or capture a new block/task
/// inline. One keystroke to anywhere, one keystroke to anything.
struct CommandBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var timer: FocusTimerController
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.coachEnabled) private var coachEnabled = true

    @State private var query = ""
    @FocusState private var focused: Bool

    struct Command: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let section: String
        let keywords: String
        let run: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        let results = filtered
                        if results.isEmpty {
                            createRow
                        } else {
                            if !trimmedQuery.isEmpty && looksCreatable {
                                createRow
                                sectionHeader("ACTIONS")
                            }
                            ForEach(groupedSections(results), id: \.self) { section in
                                sectionHeader(section)
                                ForEach(results.filter { $0.section == section }) { command in
                                    row(command)
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 560, height: 460)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "command")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentColor)
            TextField("Search actions, jump anywhere, or add…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit(runFirst)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold)).tracking(1.1)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ command: Command) -> some View {
        Button { perform(command.run) } label: {
            HStack(spacing: 12) {
                IconChip(icon: command.icon, tint: Theme.accentColor, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if !command.subtitle.isEmpty {
                        Text(command.subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var createRow: some View {
        Button {
            let text = trimmedQuery
            perform { model.quickAddPrefill = text; model.quickAddPresented = true }
        } label: {
            HStack(spacing: 12) {
                IconChip(icon: "plus.circle.fill", tint: Color(hex: 0x3FC97A), size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(trimmedQuery.isEmpty ? "Quick add…" : "Add \u{201C}\(trimmedQuery)\u{201D}")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Create a block or task with natural language")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(Theme.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Filtering

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Heuristic: the query has time/priority/estimate markers → it's capture.
    private var looksCreatable: Bool {
        let q = trimmedQuery.lowercased()
        return q.contains(where: \.isNumber) || q.contains("!") || q.contains("~")
            || q.hasPrefix("t ") || q.hasPrefix("todo ")
    }

    private var filtered: [Command] {
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty else { return commands }
        let tokens = q.split(separator: " ").map(String.init)
        return commands.filter { command in
            let haystack = (command.title + " " + command.keywords + " " + command.section).lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    private func groupedSections(_ results: [Command]) -> [String] {
        var seen: [String] = []
        for command in results where !seen.contains(command.section) { seen.append(command.section) }
        return seen
    }

    private func runFirst() {
        if let first = filtered.first {
            perform(first.run)
        } else if !trimmedQuery.isEmpty {
            let text = trimmedQuery
            perform { model.quickAddPrefill = text; model.quickAddPresented = true }
        }
    }

    /// Defer the action until the sheet is gone so we never present two sheets
    /// at once.
    private func perform(_ action: @escaping () -> Void) {
        Haptics.light()
        model.pendingCommandBarAction = action
        dismiss()
    }

    // MARK: Command catalogue

    private var commands: [Command] {
        var c: [Command] = []
        func add(_ id: String, _ title: String, _ subtitle: String, _ icon: String, _ section: String, _ keywords: String, _ run: @escaping () -> Void) {
            c.append(Command(id: id, title: title, subtitle: subtitle, icon: icon, section: section, keywords: keywords, run: run))
        }

        // Create
        add("new-block", "New Time Block", "Add a calendar block", "rectangle.stack.badge.plus", "Create", "event create add block", { model.newBlock() })
        add("new-task", "New Task", "Add a reminder", "checklist", "Create", "todo reminder create add", { model.newTask() })
        add("quick-add", "Quick Add", "Type it naturally", "sparkles", "Create", "capture natural language", { model.quickAddPresented = true })

        // Plan
        add("plan-day", "Plan My Day", "Auto-fill open time with tasks", "wand.and.stars", "Plan", "auto schedule fill", { model.planDayPresented = true })
        add("plan-week", "Plan My Week", "Spread tasks across the week", "calendar.badge.clock", "Plan", "auto schedule week", { model.planWeekPresented = true })
        add("plan-deadlines", "Plan Deadlines", "Work backwards from due dates", "graduationcap", "Plan", "study homework backwards deadline", { model.deadlinePlanPresented = true })
        add("morning", "Plan Today (Morning)", "The morning planning ritual", "sunrise", "Plan", "morning ritual intentions", { model.screen = .today; model.morningPlanningPresented = true })
        add("reflow", "Reflow Day", "Reschedule what slipped", "arrow.triangle.2.circlepath", "Plan", "move reschedule slipped", { model.reflowPresented = true })
        add("review", "Review Day", "End-of-day check-in", "checkmark.circle", "Plan", "evening review reschedule", { model.reviewPresented = true })
        add("roll-over", "Roll Overdue to Today", "Carry unfinished work forward", "arrow.turn.down.right", "Plan", "carry over overdue move today", { _ = service.rollOverdueToToday() })
        add("sweep", "Sweep Overdue", "Schedule overdue into open time", "tray.and.arrow.down", "Plan", "overdue backlog", { model.overdueSweepPresented = true })

        // Focus
        add("now", "Now Mode", "Distraction-free: just this moment", "circle.circle", "Focus", "focus distraction adhd now current", { model.nowModePresented = true })
        add("focus", "Start Focus Timer", "Pomodoro or stopwatch", "timer", "Focus", "pomodoro deep work session", { model.startFocus(taskID: nil, title: "Focus") })
        add("frog", "Eat the Frog", "5 minutes on today's hardest task", "bolt.fill", "Focus", "procrastination hardest avoid", {
            model.screen = .today
            if let id = model.frogTaskID, let frog = service.task(withID: id), !frog.isCompleted {
                timer.focusMinutes = 5
                timer.start(taskID: frog.id, title: frog.title, mode: .pomodoro)
                model.focusTimerPresented = true
            }
        })

        // Grow
        add("weekly-review", "Weekly Review", "Zoom out on the week", "calendar.badge.checkmark", "Grow", "weekly review", { model.weeklyReviewPresented = true })
        add("routines", "Guided Routines", "Hands-free step-by-step timer", "figure.walk.motion", "Grow", "routine morning wind down voice guided steps", { model.routinesPresented = true })
        add("trends", "Trends", "Habits & goals over time", "chart.line.uptrend.xyaxis", "Grow", "habits goals history", { model.trendsPresented = true })
        add("new-goal", "New Goal", "", "target", "Grow", "goal create", { model.goalEditor = GoalEditContext(goal: Goal(), isNew: true) })
        add("new-habit", "New Habit", "", "repeat", "Grow", "habit streak create", { model.habitEditor = HabitEditContext(habit: Habit(), isNew: true) })

        // Insights & tools
        add("stats", "Statistics", "Your productivity numbers", "chart.bar.xaxis", "Tools", "insights stats analytics", { model.statsPresented = true })
        add("time-report", "Time Report", "Where your hours actually went", "clock.arrow.circlepath", "Tools", "time report allocation where", { model.timeReportPresented = true })
        add("wrapped", "Year in Review", "Your year in time", "sparkles", "Tools", "wrapped year review recap", { model.wrappedPresented = true })
        add("availability", "Share Availability", "Copy your free slots as text", "square.and.arrow.up", "Tools", "free slots share schedule", { model.availabilityPresented = true })
        add("search", "Search", "Find any block or task", "magnifyingglass", "Tools", "find search", { model.searchPresented = true })
        add("filters", "Calendar Filters", "Show/hide calendars & lists", "line.3.horizontal.decrease.circle", "Tools", "hide show calendars lists", { model.calendarFilterPresented = true })
        add("templates", "Day Templates", "Apply a saved day shape", "square.on.square", "Tools", "template routine", { model.templatesPresented = true })
        add("budgets", "Time Budgets", "Weekly hour targets", "chart.pie", "Tools", "budget hours target", { model.budgetsPresented = true })
        add("recalibrate", "Recalibrate", "Update your routine & focus window", "slider.horizontal.3", "Tools", "calibrate profile routine", { model.calibrationPresented = true })
        add("school", LMSStore.shared.isConfigured ? "Manage Schools" : "Connect School", "Canvas / Schoology assignments", "graduationcap.fill", "Tools", "canvas schoology lms assignments", {
            if LMSStore.shared.isConfigured { model.lmsManagePresented = true } else { model.lmsSetupPresented = true }
        })
        add("tour", "Take the Tour", "Guided walkthrough", "map", "Tools", "tour help walkthrough", { TourController.shared.start() })

        // Chronos+ (paid layer) — surfaced per-capability, so a plain build
        // never advertises features it can't run, and a pre-transfer build shows
        // only what actually ships (e.g. Game Center leaderboards + widgets).
        if PaidFeatures.shared.anyCapabilityEntitled {
            add("chronos-plus", "Chronos+", "Manage your Chronos+ features", "sparkles", "Chronos+", "plus premium settings", { model.chronosPlusPresented = true })
        }
        if PaidFeatures.shared.isEntitled(.leaderboards) {
            add("leaderboard", "Leaderboard", "Weekly focus & momentum, ranked", "trophy", "Chronos+", "leaderboard rank compete game center", { model.leaderboardPresented = true })
        }
        if PaidFeatures.shared.isEntitled(.friends) {
            add("friends", "Friends", "See what friends are focusing on", "person.2", "Chronos+", "friends presence social", { model.friendsPresented = true })
        }

        // Navigate
        add("go-today", "Go to Today", "", "sun.max", "Go to", "today home", { model.screen = .today })
        add("go-calendar", "Go to Calendar", "", "calendar", "Go to", "calendar timeline", { model.screen = .calendar })
        add("go-tasks", "Go to Tasks", "", "checklist", "Go to", "tasks reminders", { model.screen = .tasks })
        add("go-grow", "Go to Grow", "", "leaf", "Go to", "grow habits goals", { model.screen = .grow })
        add("go-insights", "Go to Insights", "", "chart.bar", "Go to", "insights stats progress momentum", { model.screen = .insights })
        if coachEnabled {
            add("go-coach", "Open Coach", "Your daily briefing", "sparkles", "Go to", "coach assistant ai chat briefing", { openCoach() })
        }
        add("go-settings", "Settings", "", "gearshape", "Go to", "settings preferences", { openSettings() })
        add("view-day", "Day View", "", "calendar.day.timeline.left", "Go to", "day", { model.screen = .calendar; model.plannerMode = .day })
        add("view-week", "Week View", "", "calendar", "Go to", "week", { model.screen = .calendar; model.plannerMode = .week })
        add("view-month", "Month View", "", "square.grid.3x3", "Go to", "month", { model.screen = .calendar; model.plannerMode = .month })
        add("view-agenda", "Agenda View", "", "list.bullet.rectangle", "Go to", "agenda list", { model.screen = .calendar; model.plannerMode = .agenda })
        add("jump-today", "Jump to Today", "", "arrow.uturn.backward", "Go to", "today date jump", { model.goToToday() })
        add("jump-tomorrow", "Jump to Tomorrow", "", "arrow.right", "Go to", "tomorrow date jump", { model.openDay(Date().startOfDay.adding(days: 1)) })

        return c
    }

    private func openSettings() {
        #if os(iOS)
        model.settingsPresented = true
        #else
        model.screen = .settings
        #endif
    }

    private func openCoach() {
        #if os(iOS)
        model.coachPresented = true
        #else
        model.screen = .coach
        #endif
    }
}
