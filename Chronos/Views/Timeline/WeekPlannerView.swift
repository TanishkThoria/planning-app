import SwiftUI
import EventKit

/// Seven side-by-side day columns sharing one hour scale. Blocks can be
/// dragged vertically within a day, tasks can be dropped onto any day, and
/// tapping a day header jumps into the day planner.
struct WeekPlannerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    @AppStorage(Prefs.hourHeight) private var hourHeight = 64.0
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.dimPastBlocks) private var dimPastBlocks = true
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    @State private var pendingDelete: TimeBlock?

    private var weekDays: [Date] {
        let start = model.selectedDate.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

            dayHeaderRow

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        TimeGutter(hourHeight: hourHeight)
                        ForEach(weekDays, id: \.self) { day in
                            column(for: day)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(Theme.gridLine).frame(width: 1)
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    proxy.scrollTo("hour-\(max(workStartMinutes / 60 - 1, 1))", anchor: .top)
                }
            }
        }
        .background(Theme.bg)
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

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.monthTitle.string(from: model.selectedDate))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(weekRangeLabel)
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

    private var weekRangeLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return "\(Fmt.monthDay.string(from: first)) – \(Fmt.monthDay.string(from: last))"
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: TimeGutter.width, height: 1)
            ForEach(weekDays, id: \.self) { day in
                dayHeader(day)
            }
        }
        .padding(.bottom, 8)
    }

    private func dayHeader(_ day: Date) -> some View {
        let hasAllDay = service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs)
            .contains(where: \.isAllDay)
        return Button {
            model.selectedDate = day
            model.screen = .day
        } label: {
            VStack(spacing: 3) {
                Text(Fmt.weekdayShort.string(from: day).uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(day.isToday ? Color.accentColor : Theme.textTertiary)
                Text(Fmt.dayNumber.string(from: day))
                    .font(.system(size: 15, weight: day.isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(day.isToday ? Color.accentColor : Theme.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(
                        day.isSameDay(as: model.selectedDate) ? Theme.fill : Color.clear,
                        in: Circle()
                    )
                Circle()
                    .fill(hasAllDay ? Theme.textTertiary : Color.clear)
                    .frame(width: 3, height: 3)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func column(for day: Date) -> some View {
        let blocks = service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs)
            .filter { !$0.isAllDay }
        return DayColumn(
            date: day,
            blocks: blocks,
            hourHeight: hourHeight,
            snapMinutes: snapMinutes,
            compact: true,
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
