import SwiftUI

/// Rolling agenda: the next two weeks as one scannable list — each day's
/// all-day events, time blocks, and due tasks interleaved chronologically.
/// Built for the "what does my life look like" read-through.
struct AgendaView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30

    private let daysShown = 14

    private var days: [Date] {
        (0..<daysShown).map { model.selectedDate.startOfDay.adding(days: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.selectedDate.isToday && !overdueTasks.isEmpty {
                        overdueSection
                    }
                    ForEach(days, id: \.self) { day in
                        daySection(day)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Agenda")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Next \(daysShown) days from \(Fmt.relativeDay(model.selectedDate).lowercased())")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            DateNavigator()
            HeaderIconButton(icon: "plus", prominent: true) {
                model.quickAddPresented = true
            }
        }
    }

    // MARK: Data per day

    private var overdueTasks: [TaskItem] {
        service.tasks.filter {
            !$0.isCompleted && $0.isOverdue && !$0.isDueToday && !model.hiddenListIDs.contains($0.listID)
        }
    }

    private func blocks(on day: Date) -> [TimeBlock] {
        service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs)
    }

    private func tasksDue(on day: Date) -> [TaskItem] {
        service.tasks.filter { task in
            guard !model.hiddenListIDs.contains(task.listID),
                  let due = task.dueDate, due.isSameDay(as: day) else { return false }
            return !task.isCompleted || day.isToday
        }
        .sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            if a.dueHasTime != b.dueHasTime { return !a.dueHasTime }
            if let da = a.dueDate, let db = b.dueDate, da != db { return da < db }
            return a.priority.sortRank < b.priority.sortRank
        }
    }

    // MARK: Sections

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.danger)
                Text("OVERDUE")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.danger)
                Spacer()
                Text("\(overdueTasks.count)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.danger)
            }
            .padding(.top, 16)

            ForEach(overdueTasks) { task in
                AgendaTaskRow(task: task)
            }
        }
    }

    private func daySection(_ day: Date) -> some View {
        let dayBlocks = blocks(on: day)
        let allDay = dayBlocks.filter(\.isAllDay)
        let timed = dayBlocks.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        let due = tasksDue(on: day)
        let plannedMinutes = timed
            .compactMap { $0.clamped(to: day) }
            .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }

        return VStack(alignment: .leading, spacing: 6) {
            // Day header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.relativeDay(day))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(day.isToday ? Color.accentColor : Theme.textPrimary)
                Text(Fmt.monthDay.string(from: day))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if plannedMinutes > 0 {
                    Text(Fmt.duration(minutes: plannedMinutes))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
                Button {
                    model.selectedDate = day
                    model.screen = .day
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Open in day planner")
            }
            .padding(.top, 18)

            if allDay.isEmpty && timed.isEmpty && due.isEmpty {
                Text("Nothing planned")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                if !allDay.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(allDay) { block in
                            Button {
                                model.blockEditor = service.editorContext(for: block)
                            } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(block.color).frame(width: 5, height: 5)
                                    Text(block.title)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(block.color.opacity(0.14), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }

                // Dateless-time tasks first, then the timed spine.
                ForEach(due.filter { !$0.dueHasTime }) { task in
                    AgendaTaskRow(task: task)
                }
                ForEach(agendaSpine(timed: timed, timedTasks: due.filter(\.dueHasTime)), id: \.id) { item in
                    switch item {
                    case .block(let block):
                        AgendaBlockRow(block: block, day: day)
                    case .task(let task):
                        AgendaTaskRow(task: task)
                    }
                }
            }
        }
    }

    private enum SpineItem {
        case block(TimeBlock)
        case task(TaskItem)

        var id: String {
            switch self {
            case .block(let block): return "b-\(block.id)"
            case .task(let task): return "t-\(task.id)"
            }
        }

        var sortDate: Date {
            switch self {
            case .block(let block): return block.start
            case .task(let task): return task.dueDate ?? .distantFuture
            }
        }
    }

    private func agendaSpine(timed: [TimeBlock], timedTasks: [TaskItem]) -> [SpineItem] {
        (timed.map(SpineItem.block) + timedTasks.map(SpineItem.task))
            .sorted { $0.sortDate < $1.sortDate }
    }
}

// MARK: - Rows

private struct AgendaBlockRow: View {
    let block: TimeBlock
    let day: Date

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    var body: some View {
        Button {
            model.blockEditor = service.editorContext(for: block)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.time.string(from: block.start))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Text(Fmt.time.string(from: block.end))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(width: 58, alignment: .trailing)

                RoundedRectangle(cornerRadius: 2)
                    .fill(block.color)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(block.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if block.hasRecurrence {
                            Image(systemName: "repeat")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    HStack(spacing: 5) {
                        Text(block.calendarTitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textTertiary)
                        if let location = block.location, !location.isEmpty {
                            Text("· \(location)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                if let taskID = block.linkedTaskID, let task = service.task(withID: taskID) {
                    Button {
                        service.toggleTaskCompletion(id: taskID)
                    } label: {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(task.isCompleted ? Theme.success : Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(block.isPast && !day.isToday ? 1 : (block.isPast ? 0.55 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AgendaTaskRow: View {
    let task: TaskItem

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    var body: some View {
        HStack(spacing: 10) {
            Text(task.dueHasTime ? Fmt.time.string(from: task.dueDate ?? Date()) : "to do")
                .font(.system(size: 10.5, weight: task.dueHasTime ? .semibold : .regular, design: .rounded))
                .foregroundStyle(task.isOverdue ? Theme.danger : Theme.textTertiary)
                .frame(width: 58, alignment: .trailing)

            Button {
                withAnimation(.snappy) { service.toggleTaskCompletion(id: task.id) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        task.isCompleted
                            ? Theme.success
                            : (task.priority == .none ? Theme.textTertiary : task.priority.color)
                    )
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 13))
                .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.textPrimary)
                .strikethrough(task.isCompleted, color: Theme.textTertiary)
                .lineLimit(1)

            if task.isSubtask {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            Circle().fill(task.color).frame(width: 5, height: 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .draggable(task.id)
        .onTapGesture {
            model.taskEditor = service.editorContext(for: task)
        }
    }
}
