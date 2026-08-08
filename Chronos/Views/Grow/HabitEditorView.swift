import SwiftUI

struct HabitEditorView: View {
    let context: HabitEditContext

    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    @State private var habit: Habit
    @State private var confirmingDelete = false
    @State private var addedToTodo = false

    /// 1 = Sunday … 7 = Saturday, ordered to match the locale's first weekday.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private let icons = [
        "checkmark.seal", "figure.run", "book", "drop", "dumbbell", "leaf",
        "bed.double", "cup.and.saucer", "brain.head.profile", "heart", "pencil", "moon.stars",
    ]

    init(context: HabitEditContext) {
        self.context = context
        _habit = State(initialValue: context.habit)
    }

    var body: some View {
        EditorSheet(
            title: context.isNew ? "New Habit" : "Edit Habit",
            confirmDisabled: habit.title.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: { life.upsert(habit) }
        ) {
            TitleField(placeholder: "Habit name", text: $habit.title)

            iconRow
            colorRow

            FieldRow(label: "Cadence") {
                Picker("", selection: $habit.cadence) {
                    ForEach(HabitCadence.habitCases) { c in Text(c.label).tag(c) }
                }
                .labelsHidden()
                .fixedSize()
            }
            cadenceDetail

            FieldRow(label: "Reminder") {
                Toggle("", isOn: Binding(
                    get: { habit.reminderMinutes != nil },
                    set: {
                        habit.reminderMinutes = $0 ? (habit.reminderMinutes ?? 9 * 60) : nil
                        if !$0 { habit.anchored = false }
                    }
                ))
                .labelsHidden().toggleStyle(.switch)
            }
            if habit.reminderMinutes != nil {
                FieldRow(label: "At") {
                    DatePicker("", selection: Binding(
                        get: { Date().startOfDay.at(minutes: habit.reminderMinutes ?? 9 * 60) },
                        set: { habit.reminderMinutes = $0.minutesSinceMidnight }
                    ), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                }
                FieldRow(label: "Happens at this time") {
                    Toggle("", isOn: $habit.anchored).labelsHidden().toggleStyle(.switch)
                }
                Text(habit.anchored
                     ? "This habit is an appointment with yourself: it shows on your day at \(Fmt.time.string(from: Date().startOfDay.at(minutes: habit.reminderMinutes ?? 540))) and alerts you right then."
                     : "A gentle nudge at that time. Turn on “happens at this time” to place it on your timeline like an event.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
                if habit.anchored {
                    FieldRow(label: "For") {
                        Stepper(value: $habit.durationMinutes, in: 5...240, step: 5) {
                            Text(Fmt.duration(minutes: habit.durationMinutes))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .fixedSize()
                    }
                }
            }

            addToTodoButton

            if !context.isNew {
                heatmap
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete Habit")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
        .confirmationDialog("Delete this habit?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { life.deleteHabit(habit.id); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Cadence detail (parameters for the richer cadences)

    @ViewBuilder
    private var cadenceDetail: some View {
        switch habit.cadence {
        case .weekly:
            FieldRow(label: "Times per week") {
                Stepper(value: $habit.weeklyTarget, in: 1...7) {
                    Text("\(habit.weeklyTarget)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .fixedSize()
            }
        case .everyNDays:
            FieldRow(label: "Repeat every") {
                Stepper(value: $habit.intervalDays, in: 2...30) {
                    Text("\(habit.intervalDays) days")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .fixedSize()
            }
        case .customDays:
            weekdayPicker
        case .monthly:
            FieldRow(label: "Day of month") {
                Stepper(value: $habit.monthDay, in: 1...31) {
                    Text("The \(Habit.ordinal(habit.monthDay))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .fixedSize()
            }
        case .daily, .weekdays:
            EmptyView()
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ON THESE DAYS").font(.system(size: 11.5, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                ForEach(orderedWeekdays, id: \.self) { wd in
                    let on = habit.customWeekdays.contains(wd)
                    Button {
                        if on { habit.customWeekdays.removeAll { $0 == wd } }
                        else { habit.customWeekdays.append(wd) }
                        Haptics.light()
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[wd - 1])
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? Theme.onAccent : Theme.textSecondary)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(on ? AnyShapeStyle(habit.color) : AnyShapeStyle(Theme.fill),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: Add to today's to-do

    @ViewBuilder
    private var addToTodoButton: some View {
        let due = habit.isDue(on: Date())
        Button {
            service.createTask(habit.taskDraft())
            addedToTodo = true
            Haptics.success()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: addedToTodo ? "checkmark.circle.fill" : "text.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                Text(addedToTodo ? "Added to your to-dos" : "Add to today's to-do")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(addedToTodo ? Theme.success : Theme.accentColor)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background((addedToTodo ? Theme.success : Theme.accentColor).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(addedToTodo)
        Text(due
             ? "Drops this habit into your Reminders as a task for today\(habit.reminderMinutes != nil ? " at its reminder time" : "")."
             : "Not scheduled for today, but you can still add it as a to-do.")
            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 4)
    }

    private var iconRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ICON").font(.system(size: 11.5, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(icons, id: \.self) { name in
                        Button { habit.iconName = name } label: {
                            Image(systemName: name)
                                .font(.system(size: 16))
                                .foregroundStyle(habit.iconName == name ? Theme.bg : Theme.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(
                                    habit.iconName == name ? AnyShapeStyle(habit.color) : AnyShapeStyle(Theme.fill),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var colorRow: some View {
        HStack(spacing: 10) {
            ForEach(Palette.options, id: \.self) { hex in
                Button { habit.colorHex = hex } label: {
                    Circle().fill(Palette.color(hex)).frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(habit.colorHex == hex ? Theme.textPrimary : .clear, lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// GitHub-style completion heatmap for the last ~11 weeks.
    private var heatmap: some View {
        let weeks = 11
        let today = Date().startOfDay
        let start = today.startOfWeek.adding(days: -7 * (weeks - 1))
        return VStack(alignment: .leading, spacing: 8) {
            Text("LAST \(weeks) WEEKS").font(.system(size: 11.5, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = start.adding(days: w * 7 + d)
                            let done = life.isDone(habit, on: day)
                            let future = day > today
                            RoundedRectangle(cornerRadius: 2)
                                .fill(done ? habit.color : (future ? Color.clear : Theme.fill))
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
