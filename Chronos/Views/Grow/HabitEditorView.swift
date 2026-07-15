import SwiftUI

struct HabitEditorView: View {
    let context: HabitEditContext

    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var habit: Habit
    @State private var confirmingDelete = false

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
                    ForEach(HabitCadence.allCases) { c in Text(c.label).tag(c) }
                }
                .labelsHidden()
                .fixedSize()
            }

            if habit.cadence == .weekly {
                FieldRow(label: "Times per week") {
                    Stepper(value: $habit.weeklyTarget, in: 1...7) {
                        Text("\(habit.weeklyTarget)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .fixedSize()
                }
            }

            FieldRow(label: "Daily reminder") {
                Toggle("", isOn: Binding(
                    get: { habit.reminderMinutes != nil },
                    set: { habit.reminderMinutes = $0 ? (habit.reminderMinutes ?? 9 * 60) : nil }
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
            }

            if !context.isNew {
                heatmap
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete Habit")
                        .font(.system(size: 13, weight: .medium))
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

    private var iconRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ICON").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(icons, id: \.self) { name in
                        Button { habit.iconName = name } label: {
                            Image(systemName: name)
                                .font(.system(size: 15))
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
            Text("LAST \(weeks) WEEKS").font(.system(size: 10, weight: .semibold)).tracking(1.2)
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
