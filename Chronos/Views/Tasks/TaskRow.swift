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
    @ObservedObject private var tags = TagStore.shared

    private var category: ActivityCategory { tags.category(for: task) }

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
                    .foregroundStyle(isSelected ? Theme.accentColor : Theme.textTertiary)
                    .padding(.top, 1)
            } else {
                Button {
                    if !task.isCompleted { Haptics.success() }
                    withAnimation(.snappy) { service.toggleTaskCompletion(id: task.id) }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(
                            task.isCompleted
                                ? Theme.success
                                : (task.priority == .none ? Theme.textTertiary : task.priority.color)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.textPrimary)
                        .strikethrough(task.isCompleted, color: Theme.textTertiary)
                        .lineLimit(2)
                    if task.priority != .none {
                        Text(task.priority.badge)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(task.priority.color)
                    }
                    if task.energy != .none {
                        Image(systemName: task.energy.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(task.energy.color)
                    }
                }

                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                // Metadata reflows across as many lines as it needs — the
                // category leads, followed by timing and context chips.
                FlowLayout(spacing: 7, lineSpacing: 6) {
                    CategoryBadge(category: category, showsLabel: true, size: 9)
                    if let due = task.dueLabel() {
                        metaChip(due, icon: "calendar",
                                 tint: task.isOverdue ? Theme.danger : Theme.textSecondary)
                    }
                    if task.daysOverdue >= 2 {
                        Text("\(task.daysOverdue)d late")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.danger.opacity(task.daysOverdue >= 7 ? 0.22 : 0.12), in: Capsule())
                    }
                    if task.puntCount >= 2 && !task.isCompleted {
                        Label("moved \(task.puntCount)×", systemImage: "arrow.uturn.forward")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(task.puntCount >= 4 ? Theme.danger : Theme.warning)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background((task.puntCount >= 4 ? Theme.danger : Theme.warning).opacity(0.12), in: Capsule())
                            .help("This task has been rescheduled \(task.puntCount) times — consider splitting it or dropping it.")
                    }
                    if let est = task.estimateMinutes {
                        metaChip("~\(Fmt.duration(minutes: est))", icon: "timer", tint: Theme.textSecondary)
                    }
                    if let first = linkedBlocks.first {
                        metaChip("\(Fmt.relativeDay(first.start)) \(Fmt.time.string(from: first.start))",
                                 icon: "rectangle.stack", tint: Theme.accentColor)
                    }
                    if !subtasks.isEmpty {
                        metaChip("\(subtasks.filter(\.isCompleted).count)/\(subtasks.count)",
                                 icon: "checklist", tint: Theme.textSecondary)
                    }
                    metaChip(task.listName, dot: task.color, tint: Theme.textSecondary)
                }
            }

            Spacer(minLength: 6)

            if !task.isCompleted && !selectionMode {
                Button {
                    scheduleNextFree(dayOffset: 0)
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Theme.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Schedule in next free slot")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            isSelected ? Theme.accentColor.opacity(0.12) : Theme.surface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
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

            categorySubmenu

            Divider()

            Button(role: .destructive) {
                service.deleteTask(id: task.id)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// A neutral, capsule-backed metadata chip. Optional leading icon or color
    /// dot; text always. Uniform styling keeps the reflowing meta line calm.
    @ViewBuilder
    private func metaChip(_ text: String, icon: String? = nil, dot: Color? = nil, tint: Color) -> some View {
        HStack(spacing: 4) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .medium)) }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.fill, in: Capsule())
    }

    /// Tag the task's category (or return it to auto-detect).
    @ViewBuilder
    private var categorySubmenu: some View {
        Menu {
            ForEach(ActivityCategory.allCases) { c in
                Button { tags.setCategory(c, forID: task.id); Haptics.light() } label: {
                    Label(c.title, systemImage: c.icon)
                    if category == c { Image(systemName: "checkmark") }
                }
            }
            if tags.isExplicit(forID: task.id) {
                Divider()
                Button { tags.setCategory(nil, forID: task.id); Haptics.light() } label: {
                    Label("Auto-detect", systemImage: "wand.and.stars")
                }
            }
        } label: {
            Label("Category: \(category.title)", systemImage: category.icon)
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
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }

            if let first = service.blocksLinked(to: task.id).first {
                Label(Fmt.relativeDay(first.start), systemImage: "rectangle.stack")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accentColor)
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
