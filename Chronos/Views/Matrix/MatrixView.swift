import SwiftUI

/// Eisenhower matrix over live Reminders data. Urgency is derived from due
/// dates (overdue or due within 48h) and importance from priority — so
/// dragging a task between quadrants writes real changes back to Apple
/// Reminders: due dates move, priorities change.
struct MatrixView: View {
    var embedded = false

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    enum Quadrant: String, CaseIterable, Identifiable {
        case doFirst = "Do First"
        case schedule = "Schedule"
        case delegate = "Delegate"
        case eliminate = "Eliminate"

        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .doFirst: return "Urgent · Important"
            case .schedule: return "Not urgent · Important"
            case .delegate: return "Urgent · Not important"
            case .eliminate: return "Not urgent · Not important"
            }
        }

        var urgent: Bool { self == .doFirst || self == .delegate }
        var important: Bool { self == .doFirst || self == .schedule }

        var tint: Color {
            switch self {
            case .doFirst: return Theme.danger
            case .schedule: return Theme.success
            case .delegate: return Theme.warning
            case .eliminate: return Theme.textTertiary
            }
        }
    }

    private var openTasks: [TaskItem] {
        service.tasks.filter {
            !$0.isCompleted && !model.hiddenListIDs.contains($0.listID)
        }
    }

    private func tasks(in quadrant: Quadrant) -> [TaskItem] {
        openTasks
            .filter { $0.isUrgent == quadrant.urgent && $0.isImportant == quadrant.important }
            .sorted { a, b in
                if a.priority.sortRank != b.priority.sortRank { return a.priority.sortRank < b.priority.sortRank }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Rectangle().fill(Theme.hairline).frame(height: 1)
            }

            GeometryReader { geo in
                let twoColumns = geo.size.width > 560
                if twoColumns {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            quadrantPanel(.doFirst)
                            quadrantPanel(.schedule)
                        }
                        HStack(spacing: 10) {
                            quadrantPanel(.delegate)
                            quadrantPanel(.eliminate)
                        }
                    }
                    .padding(14)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Quadrant.allCases) { quadrant in
                                quadrantPanel(quadrant)
                                    .frame(minHeight: 200)
                            }
                        }
                        .padding(14)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Matrix")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Drag tasks between quadrants — due dates and priorities update in Reminders")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HeaderIconButton(icon: "plus", prominent: true) {
                model.quickAddPresented = true
            }
        }
    }

    private func quadrantPanel(_ quadrant: Quadrant) -> some View {
        let items = tasks(in: quadrant)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(quadrant.tint).frame(width: 7, height: 7)
                Text(quadrant.rawValue.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(quadrant.tint)
            }
            Text(quadrant.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)

            if items.isEmpty {
                Spacer()
                Text("Drop tasks here")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(items) { task in
                            matrixRow(task)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(quadrant.tint.opacity(0.25), lineWidth: 1)
        )
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            move(taskID: id, to: quadrant)
            return true
        }
    }

    private func matrixRow(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy) { service.toggleTaskCompletion(id: task.id) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(task.priority == .none ? Theme.textTertiary : task.priority.color)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let due = task.dueLabel() {
                    Text(due)
                        .font(.system(size: 9.5))
                        .foregroundStyle(task.isOverdue ? Theme.danger : Theme.textTertiary)
                }
            }

            Spacer(minLength: 2)

            Circle().fill(task.color).frame(width: 5, height: 5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .draggable(task.id)
        .onTapGesture {
            model.taskEditor = service.editorContext(for: task)
        }
        .contextMenu {
            Menu {
                ForEach(Quadrant.allCases) { quadrant in
                    Button(quadrant.rawValue) { move(taskID: task.id, to: quadrant) }
                }
            } label: {
                Label("Move to", systemImage: "square.grid.2x2")
            }
            Button {
                model.taskEditor = service.editorContext(for: task)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                service.toggleTaskCompletion(id: task.id)
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
        }
    }

    /// Rewrites due date + priority so the task lands in the target
    /// quadrant. Urgent → due today; not urgent → due a week out (or keeps
    /// a farther-future due date it already has); important → high
    /// priority; not important → low.
    private func move(taskID: String, to quadrant: Quadrant) {
        guard let task = service.task(withID: taskID) else { return }
        var context = service.editorContext(for: task)

        context.draft.priority = quadrant.important ? .high : .low

        if quadrant.urgent {
            context.draft.hasDue = true
            if task.dueDate == nil || !task.isUrgent {
                context.draft.due = Date().endOfDay
                context.draft.hasTime = false
            }
        } else {
            context.draft.hasDue = true
            if task.isUrgent || task.dueDate == nil {
                context.draft.due = Date().startOfDay.adding(days: 7)
                context.draft.hasTime = false
            }
        }

        if let id = context.existingID {
            service.updateTask(id: id, with: context.draft)
        }
    }
}
