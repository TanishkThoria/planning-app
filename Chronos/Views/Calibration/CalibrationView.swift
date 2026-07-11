import SwiftUI

/// The calibration wizard: a short interview about how you actually live —
/// sleep, meals, standing routines, when your brain works best, and how
/// rigid all of that is. The answers feed the auto-scheduler so Plan My Day
/// behaves like an assistant who knows you, not a bin-packer.
/// Runs on first launch and any time from Settings → Recalibrate.
struct CalibrationView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable {
        case welcome, sleep, meals, routines, rhythm, done

        var title: String {
            switch self {
            case .welcome: return "Calibration"
            case .sleep: return "Sleep"
            case .meals: return "Meals"
            case .routines: return "Routines"
            case .rhythm: return "Your rhythm"
            case .done: return "All set"
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var draft: PlannerProfile = PlannerProfile()
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stepContent
                }
                .padding(20)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer
        }
        .background(Theme.elevated)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(width: 560, height: 640)
        #endif
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = profileStore.profile
        }
    }

    private var headerBar: some View {
        VStack(spacing: 10) {
            HStack {
                if step != .welcome && step != .done {
                    Button("Back") { previous() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Button("Skip") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(step == .done ? Color.clear : Theme.textTertiary)
                        .disabled(step == .done)
                }
                Spacer()
                Text(step.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Skip") { dismiss() }.buttonStyle(.plain).font(.system(size: 13)).hidden()
            }

            // Progress dots
            HStack(spacing: 5) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Theme.fill)
                        .frame(width: item == step ? 18 : 6, height: 4)
                }
            }
            .animation(.snappy, value: step)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                next()
            } label: {
                Text(step == .done ? "Start Planning" : (step == .welcome ? "Let's go" : "Continue"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private func previous() {
        if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
    }

    private func next() {
        if step == .done {
            draft.isCalibrated = true
            profileStore.profile = draft
            dismiss()
        } else if let nextStep = Step(rawValue: step.rawValue + 1) {
            step = nextStep
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .sleep: sleepStep
        case .meals: mealsStep
        case .routines: routinesStep
        case .rhythm: rhythmStep
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            Text("Make Chronos yours")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("A two-minute interview about how your days actually work — when you sleep, when you eat, what's routine, and how flexible any of it is. Chronos uses this to plan around your life instead of over it.\n\nEverything stays on this device, and you can recalibrate anytime from Settings.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
        }
    }

    private var sleepStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIntro("When are you awake?", "Nothing gets scheduled outside these hours — this is the outer boundary of every plan.")
            FieldRow(label: "I usually wake up at") {
                timePicker(minutes: $draft.wakeMinutes)
            }
            FieldRow(label: "I'm usually in bed by") {
                timePicker(minutes: $draft.bedMinutes)
            }
            if draft.bedMinutes <= draft.wakeMinutes {
                Label("Bedtime should come after wake-up (Chronos doesn't plan across midnight yet).", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private var mealsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIntro("Meals", "Protected by default so tasks never get planned over lunch. Turn on \u{201C}put on calendar\u{201D} and Plan My Day will offer to block the meal itself.")
            ForEach($draft.meals) { $meal in
                VStack(spacing: 6) {
                    HStack {
                        Toggle(isOn: $meal.enabled) {
                            Text(meal.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .toggleStyle(.switch)
                    }
                    if meal.enabled {
                        FieldRow(label: "Around") {
                            timePicker(minutes: $meal.startMinutes)
                        }
                        FieldRow(label: "For about") {
                            durationPicker(minutes: $meal.durationMinutes, options: [15, 30, 45, 60, 90])
                        }
                        FieldRow(label: "Put on calendar in Plan My Day") {
                            Toggle("", isOn: $meal.autoBlock).labelsHidden().toggleStyle(.switch)
                        }
                    }
                }
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var routinesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIntro("Standing routines", "Gym, commute, school run, evening walk — recurring commitments the planner should respect (and can optionally put on the calendar).")

            ForEach($draft.routines) { $routine in
                RoutineEditorCard(routine: $routine) {
                    draft.routines.removeAll { $0.id == routine.id }
                }
            }

            Button {
                draft.routines.append(
                    RoutineItem(name: "New routine", startMinutes: 18 * 60, durationMinutes: 60)
                )
            } label: {
                Label("Add a routine", systemImage: "plus.circle.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            if draft.routines.isEmpty {
                Text("Totally fine to skip — you can add routines later.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var rhythmStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepIntro("How you work", "This shapes where Plan My Day puts hard things and how much it's allowed to bend your routines.")

            VStack(alignment: .leading, spacing: 6) {
                Text("MY BEST FOCUS IS IN THE")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                ForEach(FocusPeriod.allCases) { period in
                    choiceRow(
                        title: period.rawValue,
                        subtitle: period.description,
                        selected: draft.focus == period
                    ) { draft.focus = period }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("HOW FLEXIBLE ARE THESE ROUTINES?")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                ForEach(Flexibility.allCases) { level in
                    choiceRow(
                        title: level.rawValue,
                        subtitle: level.description,
                        selected: draft.flexibility == level
                    ) { draft.flexibility = level }
                }
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.success)
            Text("Chronos knows your day now")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                summaryRow("moon.zzz", "Awake \(minutesLabel(draft.wakeMinutes)) – \(minutesLabel(draft.bedMinutes))")
                summaryRow("fork.knife", "\(draft.meals.filter(\.enabled).count) protected meal\(draft.meals.filter(\.enabled).count == 1 ? "" : "s")")
                summaryRow("repeat", "\(draft.routines.count) routine\(draft.routines.count == 1 ? "" : "s")")
                summaryRow("brain.head.profile", "\(draft.focus.rawValue) focus · \(draft.flexibility.rawValue.lowercased()) schedule")
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Plan My Day will now protect meals and routines, aim your hardest tasks at your \(draft.focus.rawValue.lowercased()) focus window, and keep everything between wake-up and bedtime.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
        }
    }

    // MARK: Bits

    private func stepIntro(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
        }
    }

    private func choiceRow(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.accentColor : Theme.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(10)
            .background(
                selected ? Color.accentColor.opacity(0.1) : Theme.surface,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func minutesLabel(_ minutes: Int) -> String {
        Fmt.time.string(from: Date().startOfDay.at(minutes: minutes))
    }
}

// MARK: - Shared minute-based pickers

func timePicker(minutes: Binding<Int>) -> some View {
    DatePicker(
        "",
        selection: Binding(
            get: { Date().startOfDay.at(minutes: minutes.wrappedValue) },
            set: { minutes.wrappedValue = $0.minutesSinceMidnight }
        ),
        displayedComponents: [.hourAndMinute]
    )
    .labelsHidden()
}

func durationPicker(minutes: Binding<Int>, options: [Int]) -> some View {
    Picker("", selection: minutes) {
        ForEach(options, id: \.self) { option in
            Text(Fmt.duration(minutes: option)).tag(option)
        }
    }
    .labelsHidden()
    .fixedSize()
}

/// Inline editor for one standing routine.
private struct RoutineEditorCard: View {
    @Binding var routine: RoutineItem
    let onDelete: () -> Void

    private var daySymbols: [String] {
        Calendar.current.veryShortWeekdaySymbols // index 0 = Sunday = weekday 1
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                TextField("Routine name", text: $routine.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            FieldRow(label: "Starts") {
                timePicker(minutes: $routine.startMinutes)
            }
            FieldRow(label: "For about") {
                durationPicker(minutes: $routine.durationMinutes, options: [15, 30, 45, 60, 90, 120])
            }

            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { index in
                    let weekday = index + 1
                    let isOn = routine.weekdays.contains(weekday)
                    Button {
                        if isOn { routine.weekdays.remove(weekday) } else { routine.weekdays.insert(weekday) }
                    } label: {
                        Text(daySymbols[index])
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isOn ? Theme.bg : Theme.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(
                                isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fill),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.vertical, 2)

            FieldRow(label: "Put on calendar in Plan My Day") {
                Toggle("", isOn: $routine.autoBlock).labelsHidden().toggleStyle(.switch)
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
