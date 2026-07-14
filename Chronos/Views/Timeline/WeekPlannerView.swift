import SwiftUI
import EventKit

/// Tracks the horizontal scroll offset of the week body so the frozen day
/// header can mirror it.
private struct WeekHScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Seven day columns on one hour scale. On roomy widths (Mac / iPad) all
/// seven fit; on iPhone each column keeps a comfortable minimum width and
/// the grid scrolls horizontally — with the day header frozen at the top and
/// the time gutter frozen at the left, exactly like a proper calendar grid.
/// This keeps event names readable instead of crushing them into 50-pt lanes.
struct WeekPlannerView: View {
    var embedded = false

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore

    @AppStorage(Prefs.hourHeight) private var hourHeight = 64.0
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.dimPastBlocks) private var dimPastBlocks = true
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    @State private var pendingDelete: TimeBlock?
    @State private var hOffset: CGFloat = 0

    /// Comfortable minimum column width; below this we scroll horizontally.
    private let minColumnWidth: CGFloat = 116
    private let headerHeight: CGFloat = 52

    private var weekDays: [Date] {
        let start = model.selectedDate.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    var body: some View {
        GeometryReader { geo in
            let bodyWidth = max(geo.size.width - TimeGutter.width, 220)
            let columnWidth = max(minColumnWidth, bodyWidth / 7)
            let columnsWidth = columnWidth * 7

            VStack(spacing: 0) {
                if !embedded {
                    header
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                }

                frozenHeader(columnWidth: columnWidth, columnsWidth: columnsWidth, bodyWidth: bodyWidth)

                Rectangle().fill(Theme.hairline).frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            TimeGutter(hourHeight: hourHeight)
                            weekBody(columnWidth: columnWidth, columnsWidth: columnsWidth, bodyWidth: bodyWidth)
                        }
                        .padding(.top, 8)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        proxy.scrollTo("hour-\(max(workStartMinutes / 60 - 1, 1))", anchor: .top)
                    }
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
            HeaderIconButton(icon: "square.and.arrow.up") {
                model.availabilityPresented = true
            }
            .help("Share availability — copy your free slots as text")
            HeaderIconButton(icon: "wand.and.stars", label: "Plan Week") {
                model.planWeekPresented = true
            }
            HeaderIconButton(icon: "plus", prominent: true) {
                model.quickAddPresented = true
            }
        }
    }

    private var weekRangeLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return "\(Fmt.monthDay.string(from: first)) – \(Fmt.monthDay.string(from: last))"
    }

    // MARK: Frozen day header (mirrors the body's horizontal scroll)

    private func frozenHeader(columnWidth: CGFloat, columnsWidth: CGFloat, bodyWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: TimeGutter.width, height: headerHeight)
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    dayHeader(day).frame(width: columnWidth)
                }
            }
            .frame(width: columnsWidth, alignment: .leading)
            .offset(x: hOffset)
            .frame(width: bodyWidth, alignment: .leading)
            .clipped()
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        let hasAllDay = service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs)
            .contains(where: \.isAllDay)
        return Button {
            model.openDay(day)
        } label: {
            HStack(spacing: 6) {
                Text(Fmt.weekdayShort.string(from: day).uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(day.isToday ? Color.accentColor : Theme.textTertiary)
                Text(Fmt.dayNumber.string(from: day))
                    .font(.system(size: 15, weight: day.isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(day.isToday ? Color.accentColor : Theme.textPrimary)
                    .frame(width: 27, height: 27)
                    .background(
                        day.isToday ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                            : (day.isSameDay(as: model.selectedDate) ? AnyShapeStyle(Theme.fill) : AnyShapeStyle(Color.clear)),
                        in: Circle()
                    )
                if hasAllDay {
                    Circle().fill(Theme.textTertiary).frame(width: 3, height: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: headerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Body (horizontally scrollable columns)

    private func weekBody(columnWidth: CGFloat, columnsWidth: CGFloat, bodyWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    column(for: day)
                        .frame(width: columnWidth)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.gridLine).frame(width: 1)
                        }
                }
            }
            .frame(width: columnsWidth)
            .background(
                GeometryReader { g in
                    Color.clear.preference(
                        key: WeekHScrollKey.self,
                        value: g.frame(in: .named("weekH")).minX
                    )
                }
            )
        }
        .frame(width: bodyWidth)
        .coordinateSpace(name: "weekH")
        .onPreferenceChange(WeekHScrollKey.self) { hOffset = $0 }
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
            routineWindows: profileStore.profile.routineWindows(on: day),
            taskLookup: { service.task(withID: $0) },
            onTapBlock: { model.blockEditor = service.editorContext(for: $0) },
            onMoveBlock: { block, newStart in service.moveBlock(id: block.id, to: newStart) },
            onResizeBlock: { block, newEnd in service.resizeBlock(id: block.id, newEnd: newEnd) },
            onToggleTask: { service.toggleTaskCompletion(id: $0) },
            onDuplicateBlock: { service.duplicateBlock(id: $0.id) },
            onStartBlockNow: { service.startBlockNow(id: $0.id, snap: snapMinutes) },
            onFocusBlock: { model.startFocus(taskID: $0.linkedTaskID, title: $0.title) },
            onDeleteBlock: { pendingDelete = $0 },
            onCreateAt: { start in
                model.newBlock(
                    at: start,
                    defaultMinutes: defaultBlockMinutes,
                    calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID
                )
            },
            onCreateRange: { start, end in
                model.newBlock(
                    at: start,
                    defaultMinutes: max(5, Int(end.timeIntervalSince(start) / 60)),
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
