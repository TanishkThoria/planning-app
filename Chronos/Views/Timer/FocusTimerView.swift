import SwiftUI

/// The focus timer sheet: a big ring, Pomodoro / stopwatch toggle, and
/// controls. It ticks off a 1s timer but reads all values from wall-clock
/// timestamps in the controller, so it's accurate across backgrounding.
struct FocusTimerView: View {
    @EnvironmentObject private var timer: FocusTimerController
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.defaultListID) private var defaultListID = ""

    @State private var parkedThought = ""
    @State private var showParkedConfirmation = false
    @State private var selectedCategory: ActivityCategory?
    @State private var selectedHabitID: UUID?
    @State private var selectedGoalID: UUID?
    @State private var selectedProjectID: UUID?

    /// Optional task to focus on (from a block or task context menu).
    var presetTaskID: String?
    var presetTitle: String?

    @State private var now = Date()
    @State private var selectedMode: FocusTimerController.Mode = .pomodoro
    @State private var focusMinutes = 25
    @State private var breakMinutes = 5
    /// Forest-style soft stakes: a sprout that grows as you focus and wilts if
    /// you leave the app mid-session. Non-punitive — revive it and keep going.
    @State private var wilted = false
    @Environment(\.scenePhase) private var scenePhase
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            grabber

            if timer.isActive {
                activeContent
            } else {
                setupContent
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 420, height: 560)
        #else
        .presentationDetents([.medium, .large])
        #endif
        .onReceive(tick) { value in
            now = value
            timer.phaseElapsedIfNeeded(at: value)
        }
        .onAppear {
            focusMinutes = timer.focusMinutes
            breakMinutes = timer.breakMinutes
            selectedMode = timer.mode
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app mid-focus wilts the sprout (soft stakes).
            if phase == .background, timer.isActive, timer.isRunning, timer.phase == .focus {
                wilted = true
            }
        }
        .onChange(of: timer.isActive) { _, active in
            if !active { wilted = false }
        }
    }

    /// The sprout's stage — grows with focus progress, wilts if you left.
    private var growthEmoji: String {
        if wilted { return "🥀" }
        let p: Double
        if timer.mode == .pomodoro {
            p = timer.progress
        } else {
            p = min(1, timer.elapsed(at: now) / (25 * 60))   // 25 min ⇒ full grown
        }
        switch p {
        case ..<0.12: return "🌱"
        case ..<0.45: return "🌿"
        case ..<0.8: return "🪴"
        default: return "🌳"
        }
    }

    private var grabber: some View {
        HStack {
            Text(timer.isActive ? "Focus Session" : "Start Focusing")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Active

    private var activeContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(timer.taskTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if timer.mode == .pomodoro {
                Text(timer.phase == .focus ? "FOCUS" : "BREAK")
                    .font(.system(size: 12.5, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(timer.phase == .focus ? Theme.accentColor : Theme.success)
            }

            ZStack {
                Circle()
                    .stroke(Theme.fill, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: ringFraction)
                    .stroke(
                        timer.phase == .focus ? Theme.accentColor : Theme.success,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: ringFraction)
                VStack(spacing: 2) {
                    if timer.phase == .focus {
                        Text(growthEmoji)
                            .font(.system(size: 30))
                            .scaleEffect(wilted ? 0.9 : 1)
                            .animation(.snappy, value: growthEmoji)
                            .animation(.snappy, value: wilted)
                    }
                    Text(timeText)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    if timer.completedPomodoros > 0 {
                        Text("\(timer.completedPomodoros) 🍅")
                            .font(.system(size: 14.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(width: 220, height: 220)

            if wilted {
                Button {
                    withAnimation(.snappy) { wilted = false }
                    if !timer.isRunning { timer.resume() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("You stepped away — tap to replant & keep going")
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.warning.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 14) {
                controlButton(icon: "stop.fill", label: "End", tint: Theme.danger) {
                    timer.stop()
                    dismiss()
                }
                controlButton(
                    icon: timer.isRunning ? "pause.fill" : "play.fill",
                    label: timer.isRunning ? "Pause" : "Resume",
                    tint: Theme.accentColor,
                    prominent: true
                ) {
                    timer.toggle()
                }
                if timer.mode == .pomodoro {
                    controlButton(icon: "forward.fill", label: "Skip", tint: Theme.textSecondary) {
                        timer.advancePhase()
                    }
                }
            }

            parkAThought
        }
    }

    /// Distraction capture: a stray thought lands in your task inbox without
    /// you ever leaving the session — write it down, let it go, stay in.
    private var parkAThought: some View {
        HStack(spacing: 8) {
            Image(systemName: showParkedConfirmation ? "checkmark.circle.fill" : "tray.and.arrow.down")
                .font(.system(size: 14.5))
                .foregroundStyle(showParkedConfirmation ? Theme.success : Theme.textTertiary)
            TextField("Park a thought — it becomes a task", text: $parkedThought)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .submitLabel(.done)
                .onSubmit { parkThought() }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func parkThought() {
        let trimmed = parkedThought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var draft = TaskDraft()
        draft.title = trimmed
        draft.listID = defaultListID.isEmpty ? nil : defaultListID
        service.createTask(draft)
        parkedThought = ""
        Haptics.success()
        withAnimation(.snappy) { showParkedConfirmation = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.snappy) { showParkedConfirmation = false }
        }
    }

    private var ringFraction: Double {
        if timer.mode == .pomodoro {
            _ = now // keep view ticking
            return timer.progress
        }
        return 0
    }

    private var timeText: String {
        _ = now
        let seconds = timer.mode == .pomodoro ? timer.remaining() : timer.elapsed()
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: Setup

    private var setupContent: some View {
        VStack(spacing: 18) {
            Spacer()

            Picker("", selection: $selectedMode) {
                Text("Pomodoro").tag(FocusTimerController.Mode.pomodoro)
                Text("Stopwatch").tag(FocusTimerController.Mode.stopwatch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let title = presetTitle {
                HStack(spacing: 10) {
                    IconChip(icon: "target", tint: Color(hex: 0xFF7A59), size: 32)
                    Text(title)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            tagRow

            if selectedMode == .pomodoro {
                HStack(spacing: 8) {
                    presetChip("Quick start", 5, 5)
                    presetChip("Classic", 25, 5)
                    presetChip("Deep", 50, 10)
                    presetChip("Flow", 90, 15)
                }
                VStack(spacing: 8) {
                    stepperRow("Focus", value: $focusMinutes, range: 5...90, step: 5)
                    stepperRow("Break", value: $breakMinutes, range: 1...30, step: 1)
                }
            } else {
                Text("An open stopwatch — run it as long as you're heads-down. Time logs to your stats when you stop.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                timer.focusMinutes = focusMinutes
                timer.breakMinutes = breakMinutes
                timer.start(taskID: presetTaskID, title: presetTitle ?? "Focus", mode: selectedMode,
                            category: selectedCategory, habitID: selectedHabitID, goalID: selectedGoalID,
                            projectID: selectedProjectID)
            } label: {
                Text("Start")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Session tagging

    /// Optional tags so a session counts toward the right category, habit, or
    /// goal — not just the linked task.
    private var tagRow: some View {
        VStack(spacing: 8) {
            tagMenu(
                label: "Category",
                valueText: selectedCategory?.title ?? "Optional",
                icon: selectedCategory?.icon ?? "tag",
                tint: selectedCategory?.color ?? Theme.textTertiary
            ) {
                Button { selectedCategory = nil } label: { Label("None", systemImage: "xmark") }
                Divider()
                ForEach(ActivityCategory.allCases) { cat in
                    Button { selectedCategory = cat } label: { Label(cat.title, systemImage: cat.icon) }
                }
            }
            if !life.activeHabits.isEmpty {
                let habit = life.activeHabits.first { $0.id == selectedHabitID }
                tagMenu(
                    label: "Habit",
                    valueText: habit?.title ?? "Optional",
                    icon: habit?.iconName ?? "repeat",
                    tint: habit?.color ?? Theme.textTertiary
                ) {
                    Button { selectedHabitID = nil } label: { Label("None", systemImage: "xmark") }
                    Divider()
                    ForEach(life.activeHabits) { h in
                        Button { selectedHabitID = h.id } label: { Label(h.title, systemImage: h.iconName) }
                    }
                }
            }
            if !life.activeGoals.isEmpty {
                let goal = life.activeGoals.first { $0.id == selectedGoalID }
                tagMenu(
                    label: "Goal",
                    valueText: goal?.title ?? "Optional",
                    icon: goal?.kind.icon ?? "target",
                    tint: goal?.color ?? Theme.textTertiary
                ) {
                    Button { selectedGoalID = nil } label: { Label("None", systemImage: "xmark") }
                    Divider()
                    ForEach(life.activeGoals) { g in
                        Button { selectedGoalID = g.id } label: { Label(g.title, systemImage: g.kind.icon) }
                    }
                }
            }
            if !life.activeProjects.isEmpty {
                let project = life.activeProjects.first { $0.id == selectedProjectID }
                tagMenu(
                    label: "Project",
                    valueText: project.map { "\($0.emoji) \($0.title)" } ?? "Optional",
                    icon: "square.stack.3d.up",
                    tint: project?.color ?? Theme.textTertiary
                ) {
                    Button { selectedProjectID = nil } label: { Label("None", systemImage: "xmark") }
                    Divider()
                    ForEach(life.activeProjects) { p in
                        Button { selectedProjectID = p.id } label: { Label("\(p.emoji) \(p.title)", systemImage: "square.stack.3d.up") }
                    }
                }
                if selectedProjectID != nil {
                    Text("Time from this session logs to the project automatically.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func tagMenu<Content: View>(label: String, valueText: String, icon: String, tint: Color,
                                        @ViewBuilder menu: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Menu {
                menu()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                    Text(valueText)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(valueText == "Optional" ? Theme.textTertiary : Theme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// One-tap session shapes — "Quick start" is the 5-minute
    /// anti-procrastination special: commit to almost nothing, keep going
    /// once you're moving.
    private func presetChip(_ label: String, _ focus: Int, _ rest: Int) -> some View {
        let selected = focusMinutes == focus && breakMinutes == rest
        return Button {
            focusMinutes = focus
            breakMinutes = rest
            Haptics.selection()
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(focus)/\(rest)")
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Theme.accentColor : Theme.textSecondary)
            .background(selected ? Theme.accentColor.opacity(0.14) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Theme.accentColor.opacity(0.4) : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue) min")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func controlButton(icon: String, label: String, tint: Color, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(prominent ? Theme.bg : tint)
                    .frame(width: 54, height: 54)
                    .background(
                        prominent ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.fill),
                        in: Circle()
                    )
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Floating pill shown app-wide whenever a session is running.
struct FocusTimerPill: View {
    @EnvironmentObject private var timer: FocusTimerController
    @EnvironmentObject private var model: AppModel

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if timer.isActive {
            Button {
                model.focusTimerPresented = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: timer.phase == .focus ? "timer" : "cup.and.saucer.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(timer.phase == .focus ? Theme.accentColor : Theme.success)
                    Text(timeText)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text(timer.taskTitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: 120)
                    Button {
                        timer.toggle()
                    } label: {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.elevated, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .onReceive(tick) { value in
                now = value
                timer.phaseElapsedIfNeeded(at: value)
            }
        }
    }

    private var timeText: String {
        _ = now
        let seconds = timer.mode == .pomodoro ? timer.remaining() : timer.elapsed()
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
