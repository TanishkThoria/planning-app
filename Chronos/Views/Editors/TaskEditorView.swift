import SwiftUI

struct TaskEditorView: View {
    let context: TaskEditorContext

    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TaskDraft
    @State private var confirmingDelete = false
    @State private var newSubtaskTitle = ""

    private var isNew: Bool { context.existingID == nil }

    private let estimateOptions: [Int?] = [nil, 15, 30, 45, 60, 90, 120, 180, 240]

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

                FieldRow(label: "Time estimate") {
                    Picker("", selection: $draft.estimateMinutes) {
                        ForEach(estimateOptions, id: \.self) { option in
                            Text(option.map { Fmt.duration(minutes: $0) } ?? "None")
                                .tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
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
