import SwiftUI

/// The focus timer sheet: a big ring, Pomodoro / stopwatch toggle, and
/// controls. It ticks off a 1s timer but reads all values from wall-clock
/// timestamps in the controller, so it's accurate across backgrounding.
struct FocusTimerView: View {
    @EnvironmentObject private var timer: FocusTimerController
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.defaultListID) private var defaultListID = ""

    @State private var parkedThought = ""
    @State private var showParkedConfirmation = false

    /// Optional task to focus on (from a block or task context menu).
    var presetTaskID: String?
    var presetTitle: String?

    @State private var now = Date()
    @State private var selectedMode: FocusTimerController.Mode = .pomodoro
    @State private var focusMinutes = 25
    @State private var breakMinutes = 5
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
    }

    private var grabber: some View {
        HStack {
            Text(timer.isActive ? "Focus Session" : "Start Focusing")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if timer.mode == .pomodoro {
                Text(timer.phase == .focus ? "FOCUS" : "BREAK")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(timer.phase == .focus ? Color.accentColor : Theme.success)
            }

            ZStack {
                Circle()
                    .stroke(Theme.fill, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: ringFraction)
                    .stroke(
                        timer.phase == .focus ? Color.accentColor : Theme.success,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: ringFraction)
                VStack(spacing: 4) {
                    Text(timeText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    if timer.completedPomodoros > 0 {
                        Text("\(timer.completedPomodoros) 🍅")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(width: 220, height: 220)

            Spacer()

            HStack(spacing: 14) {
                controlButton(icon: "stop.fill", label: "End", tint: Theme.danger) {
                    timer.stop()
                    dismiss()
                }
                controlButton(
                    icon: timer.isRunning ? "pause.fill" : "play.fill",
                    label: timer.isRunning ? "Pause" : "Resume",
                    tint: Color.accentColor,
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
                .font(.system(size: 13))
                .foregroundStyle(showParkedConfirmation ? Theme.success : Theme.textTertiary)
            TextField("Park a thought — it becomes a task", text: $parkedThought)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
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
                HStack(spacing: 8) {
                    Image(systemName: "target").foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

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
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                timer.focusMinutes = focusMinutes
                timer.breakMinutes = breakMinutes
                timer.start(taskID: presetTaskID, title: presetTitle ?? "Focus", mode: selectedMode)
            } label: {
                Text("Start")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
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
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(focus)/\(rest)")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.accentColor : Theme.textSecondary)
            .background(selected ? Color.accentColor.opacity(0.14) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.4) : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue) min")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(prominent ? Theme.bg : tint)
                    .frame(width: 54, height: 54)
                    .background(
                        prominent ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.fill),
                        in: Circle()
                    )
                Text(label)
                    .font(.system(size: 10, weight: .medium))
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(timer.phase == .focus ? Color.accentColor : Theme.success)
                    Text(timeText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text(timer.taskTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: 120)
                    Button {
                        timer.toggle()
                    } label: {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
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
