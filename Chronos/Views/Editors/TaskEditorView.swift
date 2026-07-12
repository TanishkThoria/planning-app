import SwiftUI

struct TaskEditorView: View {
    let context: TaskEditorContext

    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var model: AppModel

    @State private var draft: TaskDraft
    @State private var confirmingDelete = false
    @State private var newSubtaskTitle = ""

    private var isNew: Bool { context.existingID == nil }

    private let estimateChips: [Int] = [5, 15, 30, 45, 60, 90, 120, 240, 480]
    private let sessionChips: [Int] = [25, 30, 45, 60, 90, 120]

    init(context: TaskEditorContext) {
        self.context = context
        var draft = context.draft
        if draft.listID == nil {
            draft.listID = UserDefaults.standard.string(forKey: Prefs.defaultListID)
        }
        _draft = State(initialValue: draft)
    }

    var body: some View {
        EditorSheet(
            title: isNew ? "New Task" : "Edit Task",
            confirmDisabled: draft.title.trimmingCharacters(in: .whitespaces).isEmpty && isNew,
            onConfirm: save
        ) {
            TitleField(placeholder: "Task title", text: $draft.title)

            VStack(spacing: 6) {
                CalendarPickerRow(label: "List", options: service.taskLists, selection: $draft.listID)

                if !isNew {
                    FieldRow(label: "Completed") {
                        Toggle("", isOn: $draft.isCompleted)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }

            VStack(spacing: 6) {
                FieldRow(label: "Due date") {
                    Toggle("", isOn: $draft.hasDue)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if draft.hasDue {
                    FieldRow(label: "Date") {
                        DatePicker("", selection: $draft.due, displayedComponents: [.date])
                            .labelsHidden()
                    }
                    FieldRow(label: "Time") {
                        HStack(spacing: 10) {
                            if draft.hasTime {
                                DatePicker("", selection: $draft.due, displayedComponents: [.hourAndMinute])
                                    .labelsHidden()
                            }
                            Toggle("", isOn: $draft.hasTime)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                    FieldRow(label: "Repeat") {
                        Picker("", selection: $draft.recurrence) {
                            if draft.originalRecurrence == .custom {
                                Text("Custom").tag(RecurrenceOption.custom)
                            }
                            ForEach(RecurrenceOption.pickable) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            VStack(spacing: 6) {
                FieldRow(label: "Priority") {
                    Picker("", selection: $draft.priority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }

                FieldRow(label: "Effort") {
                    Picker("", selection: $draft.energy) {
                        ForEach(TaskEnergy.allCases) { energy in
                            Label(energy.label, systemImage: energy.icon).tag(energy)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }

            estimateSection

            if !isNew, let taskID = context.existingID {
                Button {
                    dismiss()
                    model.startFocus(taskID: taskID, title: draft.title)
                } label: {
                    Label("Start focus timer", systemImage: "timer")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let taskID = context.existingID, draft.parentID == nil {
                subtasksSection(taskID: taskID)
            } else if isNew {
                Text("Save the task first to add subtasks.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("NOTES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                TextEditor(text: $draft.notes)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 70)
                    .padding(8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            if !isNew {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Text("Delete Task")
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
        .confirmationDialog("Delete this task?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = context.existingID {
                    service.deleteTask(id: id)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Granular estimate (5-min steps up to a multi-hour project) plus
    /// optional chunking into sessions across days.
    private var estimateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TIME ESTIMATE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(draft.estimateMinutes.map { Fmt.duration(minutes: $0) } ?? "Not set")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(draft.estimateMinutes == nil ? Theme.textTertiary : Theme.textPrimary)
            }

            // Fine stepper (5-min granularity, 5m … 12h).
            HStack(spacing: 10) {
                Stepper(
                    value: Binding(
                        get: { draft.estimateMinutes ?? 0 },
                        set: { draft.estimateMinutes = $0 <= 0 ? nil : min($0, 720) }
                    ),
                    in: 0...720,
                    step: 5
                ) {
                    Text(draft.estimateMinutes.map { Fmt.duration(minutes: $0) } ?? "None")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                if draft.estimateMinutes != nil {
                    Button {
                        draft.estimateMinutes = nil
                        draft.sessionMinutes = nil
                    } label: {
                        Text("Clear").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            // Quick presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(estimateChips, id: \.self) { minutes in
                        Button {
                            draft.estimateMinutes = minutes
                        } label: {
                            Text(Fmt.duration(minutes: minutes))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(draft.estimateMinutes == minutes ? Theme.bg : Theme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    draft.estimateMinutes == minutes ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Chunking — only meaningful for larger tasks.
            if let est = draft.estimateMinutes, est > 60 {
                VStack(spacing: 6) {
                    FieldRow(label: "Split into sessions") {
                        Toggle("", isOn: Binding(
                            get: { draft.sessionMinutes != nil },
                            set: { draft.sessionMinutes = $0 ? min(60, est) : nil }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    if let session = draft.sessionMinutes {
                        HStack(spacing: 6) {
                            ForEach(sessionChips.filter { $0 < est }, id: \.self) { minutes in
                                Button {
                                    draft.sessionMinutes = minutes
                                } label: {
                                    Text(Fmt.duration(minutes: minutes))
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(session == minutes ? Theme.bg : Theme.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            session == minutes ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fill),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Chronos will schedule \(Int(ceil(Double(est) / Double(max(session, 1))))) sessions of \(Fmt.duration(minutes: session)), spread across days as needed.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// Subtasks are real reminders linked to this one; changes here apply
    /// immediately (they don't wait for Save).
    private func subtasksSection(taskID: String) -> some View {
        let subtasks = service.subtasks(of: taskID)
        return VStack(alignment: .leading, spacing: 6) {
            Text("SUBTASKS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textTertiary)

            ForEach(subtasks) { subtask in
                HStack(spacing: 9) {
                    Button {
                        service.toggleTaskCompletion(id: subtask.id)
                    } label: {
                        Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(subtask.isCompleted ? Theme.success : Theme.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Text(subtask.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(subtask.isCompleted ? Theme.textTertiary : Theme.textPrimary)
                        .strikethrough(subtask.isCompleted, color: Theme.textTertiary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        service.deleteTask(id: subtask.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Add a subtask", text: $newSubtaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit {
                        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        service.createSubtask(parentID: taskID, title: title)
                        newSubtaskTitle = ""
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text("Each subtask is a real reminder — drag it onto the timeline to give it its own block.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func save() {
        if let id = context.existingID {
            service.updateTask(id: id, with: draft)
        } else {
            service.createTask(draft)
        }
    }
}
