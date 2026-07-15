import SwiftUI

struct GoalEditorView: View {
    let context: GoalEditContext

    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var goal: Goal
    @State private var confirmingDelete = false

    init(context: GoalEditContext) {
        self.context = context
        _goal = State(initialValue: context.goal)
    }

    var body: some View {
        EditorSheet(
            title: context.isNew ? "New Goal" : "Edit Goal",
            confirmDisabled: goal.title.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: { life.upsert(goal) }
        ) {
            TitleField(placeholder: "What do you want to achieve?", text: $goal.title)

            colorRow

            FieldRow(label: "Type") {
                Picker("", selection: $goal.kind) {
                    ForEach(GoalKind.allCases) { kind in Text(kind.label).tag(kind) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            switch goal.kind {
            case .time: timeFields
            case .milestone: milestoneFields
            case .habitLink: habitFields
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("NOTE").font(.system(size: 11.5, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                TextEditor(text: $goal.detail)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60)
                    .padding(8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            if !context.isNew {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete Goal")
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
        .confirmationDialog("Delete this goal?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { life.deleteGoal(goal.id); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COLOR").font(.system(size: 11.5, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 10) {
                ForEach(Palette.options, id: \.self) { hex in
                    Button { goal.colorHex = hex } label: {
                        Circle().fill(Palette.color(hex)).frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(
                                goal.colorHex == hex ? Theme.textPrimary : .clear, lineWidth: 2).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var timeFields: some View {
        VStack(spacing: 6) {
            FieldRow(label: "Hours per week") {
                Stepper(value: $goal.weeklyHoursTarget, in: 0.5...80, step: 0.5) {
                    Text(String(format: "%g h", goal.weeklyHoursTarget))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .fixedSize()
            }
            FieldRow(label: "On calendar") {
                Menu {
                    Button { goal.linkedCalendarID = nil } label: {
                        Label("Any calendar", systemImage: goal.linkedCalendarID == nil ? "checkmark" : "circle")
                    }
                    ForEach(service.calendars) { cal in
                        Button { goal.linkedCalendarID = cal.id } label: {
                            Label(cal.title, systemImage: goal.linkedCalendarID == cal.id ? "checkmark" : "circle.fill")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(service.calendarInfo(withID: goal.linkedCalendarID)?.title ?? "Any calendar")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .fixedSize()
            }
            Text("Progress tracks the hours you timeblock on this calendar each week.")
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var milestoneFields: some View {
        VStack(spacing: 6) {
            FieldRow(label: "Deadline") {
                DatePicker("", selection: Binding(
                    get: { goal.deadline ?? Date().adding(days: 30) },
                    set: { goal.deadline = $0 }
                ), displayedComponents: [.date])
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Progress").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(Int((goal.milestoneProgress * 100).rounded()))%")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Slider(value: $goal.milestoneProgress, in: 0...1)
                    .tint(goal.color)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var habitFields: some View {
        FieldRow(label: "Habit") {
            Menu {
                ForEach(life.activeHabits) { habit in
                    Button { goal.linkedHabitID = habit.id } label: {
                        Label(habit.title, systemImage: goal.linkedHabitID == habit.id ? "checkmark" : "circle")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(life.habits.first(where: { $0.id == goal.linkedHabitID })?.title ?? "Choose…")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .fixedSize()
        }
    }
}
