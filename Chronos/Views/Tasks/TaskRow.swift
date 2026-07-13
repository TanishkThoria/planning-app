import SwiftUI

/// Full-detail task row used in the Tasks screen. Drag it onto a timeline,
/// or use the bolt button / context menu to schedule it.
struct TaskRow: View {
    let task: TaskItem
    var selectionMode = false
    var isSelected = false
    var onToggleSelection: () -> Void = {}

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore

    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    private var linkedBlocks: [TimeBlock] {
        service.blocksLinked(to: task.id)
    }

    private var subtasks: [TaskItem] {
        service.subtasks(of: task.id)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Theme.textTertiary)
                    .padding(.top, 1)
            } else {
                Button {
                    if !task.isCompleted { Haptics.success() }
                    withAnimation(.snappy) { service.toggleTaskCompletion(id: task.id) }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(
                            task.isCompleted
                                ? Theme.success
                                : (task.priority == .none ? Theme.textTertiary : task.priority.color)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.textPrimary)
                        .strikethrough(task.isCompleted, color: Theme.textTertiary)
                        .lineLimit(2)
                    if task.priority != .none {
                        Text(task.priority.badge)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(task.priority.color)
                    }
                    if task.energy != .none {
                        Image(systemName: task.energy.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(task.energy.color)
                    }
                }

                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let due = task.dueLabel() {
                        Label(due, systemImage: "calendar")
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(task.isOverdue ? Theme.danger : Theme.textTertiary)
                    }
                    if let est = task.estimateMinutes {
                        Label("~\(Fmt.duration(minutes: est))", systemImage: "timer")
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let first = linkedBlocks.first {
                        Label(
                            "\(Fmt.relativeDay(first.start)) \(Fmt.time.string(from: first.start))",
                            systemImage: "rectangle.stack"
                        )
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    }
                    if !subtasks.isEmpty {
                        Label(
                            "\(subtasks.filter(\.isCompleted).count)/\(subtasks.count)",
                            systemImage: "checklist"
                        )
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(task.color).frame(width: 5, height: 5)
                        Text(task.listName)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            if !task.isCompleted && !selectionMode {
                Button {
                    scheduleNextFree(dayOffset: 0)
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .background(Theme.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Schedule in next free slot")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : Theme.surface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(Rectangle())
        .draggable(task.id)
        .onTapGesture {
            if selectionMode {
                onToggleSelection()
            } else {
                model.taskEditor = service.editorContext(for: task)
            }
        }
        .contextMenu {
            Button {
                model.taskEditor = service.editorContext(for: task)
            } label: { Label("Edit", systemImage: "pencil") }

            Button {
                service.toggleTaskCompletion(id: task.id)
            } label: {
                Label(task.isCompleted ? "Mark Incomplete" : "Complete",
                      systemImage: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }

            if !task.isCompleted {
                Button {
                    model.startFocus(taskID: task.id, title: task.title)
                } label: {
                    Label("Focus on This", systemImage: "timer")
                }

                Menu {
                    Button("Next free slot today") { scheduleNextFree(dayOffset: 0) }
                    Button("Next free slot tomorrow") { scheduleNextFree(dayOffset: 1) }
                } label: {
                    Label("Schedule", systemImage: "calendar.badge.plus")
                }

                Menu {
                    ForEach(TaskPriority.allCases) { priority in
                        Button(priority.label) { setPriority(priority) }
                    }
                } label: {
                    Label("Priority", systemImage: "exclamationmark.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                service.deleteTask(id: task.id)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func scheduleNextFree(dayOffset: Int) {
        let minutes = task.estimateMinutes ?? defaultBlockMinutes
        let from = dayOffset == 0
            ? Date()
            : Date().startOfDay.adding(days: dayOffset).at(minutes: workStartMinutes)
        let start = AutoScheduler.nextFreeSlot(
            after: from,
            minutes: minutes,
            existing: service.blocks,
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            snapMinutes: snapMinutes,
            profile: profileStore.profile
        )
        service.scheduleTask(
            task,
            at: start,
            minutes: minutes,
            calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID
        )
    }

    private func setPriority(_ priority: TaskPriority) {
        var context = service.editorContext(for: task)
        context.draft.priority = priority
        if let id = context.existingID {
            service.updateTask(id: id, with: context.draft)
        }
    }
}

/// Slim indented row for a subtask nested under its parent. Draggable onto
/// any timeline, just like a full task.
struct SubtaskRow: View {
    let task: TaskItem

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)

            Button {
                withAnimation(.snappy) { service.toggleTaskCompletion(id: task.id) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(task.isCompleted ? Theme.success : Theme.textTertiary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 12.5))
                .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.textPrimary)
                .strikethrough(task.isCompleted, color: Theme.textTertiary)
                .lineLimit(1)

            if let est = task.estimateMinutes {
                Text("~\(Fmt.duration(minutes: est))")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            if let first = service.blocksLinked(to: task.id).first {
                Label(Fmt.relativeDay(first.start), systemImage: "rectangle.stack")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .draggable(task.id)
        .onTapGesture {
            model.taskEditor = service.editorContext(for: task)
        }
        .contextMenu {
            Button {
                model.taskEditor = service.editorContext(for: task)
            } label: { Label("Edit", systemImage: "pencil") }
            Button {
                service.toggleTaskCompletion(id: task.id)
            } label: {
                Label(task.isCompleted ? "Mark Incomplete" : "Complete", systemImage: "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) {
                service.deleteTask(id: task.id)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
