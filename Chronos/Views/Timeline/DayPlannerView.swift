import SwiftUI
import EventKit
import Combine

/// The main screen: a full-day timeline with an optional backlog rail for
/// dragging unscheduled tasks straight onto the day.
struct DayPlannerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    @AppStorage(Prefs.hourHeight) private var hourHeight = 64.0
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.dimPastBlocks) private var dimPastBlocks = true
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    @State private var pendingDelete: TimeBlock?
    @State private var now = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var dayBlocks: [TimeBlock] {
        service.blocks(on: model.selectedDate, hiddenCalendars: model.hiddenCalendarIDs)
    }

    private var allDayBlocks: [TimeBlock] { dayBlocks.filter(\.isAllDay) }
    private var timedBlocks: [TimeBlock] { dayBlocks.filter { !$0.isAllDay } }

    var body: some View {
        GeometryReader { geo in
            let showRail = geo.size.width > 720 && model.backlogVisible

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                if model.selectedDate.isToday {
                    UpNextStrip(blocks: dayBlocks, now: now)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                }

                if !allDayBlocks.isEmpty {
                    allDayRow
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                }

                Rectangle().fill(Theme.hairline).frame(height: 1)

                HStack(spacing: 0) {
                    timeline
                    if showRail {
                        Rectangle().fill(Theme.hairline).frame(width: 1)
                        BacklogRail(day: model.selectedDate)
                            .frame(width: 270)
                    }
                }
            }
        }
        .background(Theme.bg)
        .onReceive(timer) { now = $0 }
        .confirmationDialog(
            "Delete \u{201C}\(pendingDelete?.title ?? "")\u{201D}?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if pendingDelete?.hasRecurrence == true {
                Button("Delete This Occurrence", role: .destructive) { confirmDelete(span: .thisEvent) }
                Button("Delete This and Future", role: .destructive) { confirmDelete(span: .futureEvents) }
            } else {
                Button("Delete", role: .destructive) { confirmDelete(span: .thisEvent) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func confirmDelete(span: EKSpan) {
        if let block = pendingDelete {
            service.deleteBlock(id: block.id, span: span)
        }
        pendingDelete = nil
    }

    // MARK: Header

    private var plannedMinutes: Int {
        timedBlocks
            .compactMap { $0.clamped(to: model.selectedDate) }
            .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.weekdayFull.string(from: model.selectedDate))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    Text(Fmt.monthDayYear.string(from: model.selectedDate))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    if !dayBlocks.isEmpty {
                        Text("·")
                            .foregroundStyle(Theme.textTertiary)
                        Text("\(timedBlocks.count) blocks · \(Fmt.duration(minutes: plannedMinutes)) planned")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            Spacer()

            DateNavigator()

            HeaderIconButton(icon: "minus.magnifyingglass") {
                hourHeight = max(40, hourHeight - 8)
            }
            HeaderIconButton(icon: "plus.magnifyingglass") {
                hourHeight = min(128, hourHeight + 8)
            }
            HeaderIconButton(icon: "wand.and.stars", label: "Plan") {
                model.planDayPresented = true
            }
            HeaderIconButton(icon: "sidebar.right") {
                withAnimation(.snappy) { model.backlogVisible.toggle() }
            }
            HeaderIconButton(icon: "plus", prominent: true) {
                model.quickAddPresented = true
            }
            .keyboardShortcut("k", modifiers: .command)
        }
    }

    private var allDayRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("ALL DAY")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.textTertiary)
                ForEach(allDayBlocks) { block in
                    Button {
                        model.blockEditor = service.editorContext(for: block)
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(block.color).frame(width: 6, height: 6)
                            Text(block.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(block.color.opacity(0.14), in: Capsule())
                        .overlay(Capsule().strokeBorder(block.color.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    TimeGutter(hourHeight: hourHeight)
                    dayColumn
                        .padding(.trailing, 12)
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                let anchor = model.selectedDate.isToday
                    ? max(Date().minutesSinceMidnight / 60 - 1, 0)
                    : max(workStartMinutes / 60 - 1, 0)
                proxy.scrollTo("hour-\(min(max(anchor, 1), 23))", anchor: .top)
            }
        }
    }

    private var dayColumn: some View {
        DayColumn(
            date: model.selectedDate,
            blocks: timedBlocks,
            hourHeight: hourHeight,
            snapMinutes: snapMinutes,
            dimPast: dimPastBlocks,
            taskLookup: { service.task(withID: $0) },
            onTapBlock: { model.blockEditor = service.editorContext(for: $0) },
            onMoveBlock: { block, newStart in service.moveBlock(id: block.id, to: newStart) },
            onResizeBlock: { block, newEnd in service.resizeBlock(id: block.id, newEnd: newEnd) },
            onToggleTask: { service.toggleTaskCompletion(id: $0) },
            onDuplicateBlock: { service.duplicateBlock(id: $0.id) },
            onStartBlockNow: { service.startBlockNow(id: $0.id, snap: snapMinutes) },
            onDeleteBlock: { pendingDelete = $0 },
            onCreateAt: { start in
                model.newBlock(
                    at: start,
                    defaultMinutes: defaultBlockMinutes,
                    calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID
                )
            },
            onDropTask: { taskID, start in
                guard let task = service.task(withID: taskID) else { return }
                service.scheduleTask(
                    task,
                    at: start,
                    minutes: task.estimateMinutes ?? defaultBlockMinutes,
                    calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID
                )
            }
        )
    }
}

/// Unscheduled tasks for the selected day — drag them onto the timeline or
/// tap the bolt to auto-place them in the next free slot.
struct BacklogRail: View {
    let day: Date

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore

    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    /// Incomplete tasks relevant to this day (due, overdue, or dateless)
    /// that don't already have a block on the day.
    private var backlog: [TaskItem] {
        let scheduled = Set(service.blocks(on: day).compactMap(\.linkedTaskID))
        return service.tasks.filter { task in
            guard !task.isCompleted, !scheduled.contains(task.id),
                  !model.hiddenListIDs.contains(task.listID) else { return false }
            guard let due = task.dueDate else { return true }
            return due.startOfDay <= day.startOfDay
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionHeader(title: "Backlog", trailing: "\(backlog.count)")
                Spacer(minLength: 8)
                Button {
                    model.planDayPresented = true
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Plan My Day")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if backlog.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Backlog clear",
                    message: "Every task for this day is either done or already on the timeline."
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(backlog) { task in
                            BacklogTaskRow(task: task) {
                                scheduleAtNextFreeSlot(task)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Theme.bg)
    }

    private func scheduleAtNextFreeSlot(_ task: TaskItem) {
        let minutes = task.estimateMinutes ?? defaultBlockMinutes
        let searchFrom = day.isToday ? Date() : day.at(minutes: workStartMinutes)
        let start = AutoScheduler.nextFreeSlot(
            after: searchFrom,
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
}

private struct BacklogTaskRow: View {
    let task: TaskItem
    let onSchedule: () -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    var body: some View {
        HStack(spacing: 9) {
            Button {
                service.toggleTaskCompletion(id: task.id)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(task.priority == .none ? Theme.textTertiary : task.priority.color)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let due = task.dueLabel() {
                        Text(due)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(task.isOverdue ? Theme.danger : Theme.textTertiary)
                    }
                    if let est = task.estimateMinutes {
                        Text("~\(Fmt.duration(minutes: est))")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Circle().fill(task.color).frame(width: 5, height: 5)
                }
            }

            Spacer(minLength: 4)

            Button(action: onSchedule) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background(Theme.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Schedule in next free slot")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .draggable(task.id)
        .contextMenu {
            Button { model.taskEditor = service.editorContext(for: task) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button { onSchedule() } label: {
                Label("Schedule Next Free Slot", systemImage: "bolt")
            }
            Button { service.toggleTaskCompletion(id: task.id) } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
        }
        .onTapGesture(count: 2) {
            model.taskEditor = service.editorContext(for: task)
        }
    }
}
