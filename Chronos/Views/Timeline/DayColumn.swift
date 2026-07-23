import SwiftUI
import Combine

/// One day's worth of timeline: the hour grid, the placed blocks, the now
/// line, double-tap-to-create and task drag-and-drop. Reused by the day
/// planner (full width) and the week planner (7 columns).
struct DayColumn: View {
    let date: Date
    let blocks: [TimeBlock]          // timed blocks touching this day
    let hourHeight: CGFloat
    let snapMinutes: Int
    var compact = false
    var dimPast = true
    /// Calibrated meal/routine windows drawn as ghost bands behind blocks.
    var routineWindows: [PlannerProfile.DayWindow] = []
    /// Time-anchored habits that appear on this day at their set time.
    var anchoredHabits: [Habit] = []
    var isHabitDone: (Habit) -> Bool = { _ in false }
    var onToggleHabit: (Habit) -> Void = { _ in }
    var taskLookup: (String) -> TaskItem? = { _ in nil }

    var onTapBlock: (TimeBlock) -> Void = { _ in }
    var onMoveBlock: (TimeBlock, Date) -> Void = { _, _ in }
    var onResizeBlock: (TimeBlock, Date) -> Void = { _, _ in }
    var onToggleTask: (String) -> Void = { _ in }
    var onDuplicateBlock: (TimeBlock) -> Void = { _ in }
    var onStartBlockNow: (TimeBlock) -> Void = { _ in }
    var onFocusBlock: (TimeBlock) -> Void = { _ in }
    var onDeleteBlock: (TimeBlock) -> Void = { _ in }
    var onCreateAt: (Date) -> Void = { _ in }
    var onCreateRange: (Date, Date) -> Void = { _, _ in }
    var onDropTask: (String, Date) -> Void = { _, _ in }

    @State private var createStartMinutes: Int?
    @State private var createCurrentMinutes: Int?
    /// Block layout is cached and recomputed only when the blocks or day change
    /// — not on every render. Previously `BlockLayout.place` ran inside `body`,
    /// so the now-line timer and drag gestures re-clustered every block each
    /// tick/frame.
    @State private var placed: [BlockLayout.Placed] = []

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                grid

                routineBands(width: geo.size.width)

                // Create layer — double-tap an empty slot to make a block.
                // On macOS you can also long-press and drag to draw an exact
                // duration; that gesture is intentionally NOT attached on iOS,
                // where a full-cover drag gesture starves the ScrollView's pan
                // and breaks vertical scrolling.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, coordinateSpace: .local) { point in
                        onCreateAt(time(atY: point.y).snappedDown(to: snapMinutes))
                    }
                    #if os(macOS)
                    .gesture(dragCreateGesture)
                    #endif

                if let range = createRange {
                    dragCreatePreview(range)
                }

                habitMarkers(width: geo.size.width)

                ForEach(placed) { item in
                    TimeBlockCard(
                        placed: item,
                        day: date,
                        hourHeight: hourHeight,
                        snapMinutes: snapMinutes,
                        columnWidth: geo.size.width,
                        compact: compact,
                        dimPast: dimPast,
                        linkedTask: item.block.linkedTaskID.flatMap(taskLookup),
                        onTap: { onTapBlock(item.block) },
                        onMove: { onMoveBlock(item.block, $0) },
                        onResize: { onResizeBlock(item.block, $0) },
                        onToggleTask: {
                            if let taskID = item.block.linkedTaskID { onToggleTask(taskID) }
                        },
                        onDuplicate: { onDuplicateBlock(item.block) },
                        onStartNow: { onStartBlockNow(item.block) },
                        onFocus: { onFocusBlock(item.block) },
                        onDelete: { onDeleteBlock(item.block) }
                    )
                }

                // Its own subview with its own timer, so the ticking "now" line
                // never invalidates the grid or the blocks.
                if date.isToday {
                    NowLineView(hourHeight: hourHeight)
                }
            }
            .dropDestination(for: String.self) { items, location in
                guard let taskID = items.first else { return false }
                onDropTask(taskID, time(atY: location.y).snappedDown(to: snapMinutes))
                return true
            }
        }
        .frame(height: 24 * hourHeight)
        .onAppear { placed = BlockLayout.place(blocks, on: date) }
        .onChange(of: blocks) { _, newBlocks in placed = BlockLayout.place(newBlocks, on: date) }
        .onChange(of: date) { _, newDate in placed = BlockLayout.place(blocks, on: newDate) }
    }

    private var grid: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<25, id: \.self) { hour in
                Rectangle()
                    .fill(Theme.gridLine)
                    .frame(height: 1)
                    .offset(y: CGFloat(hour) * hourHeight)
            }
        }
        .allowsHitTesting(false)
    }

    /// Striped ghost bands for meals/routines — always-on planning context,
    /// distinct from real calendar blocks. Tap-through so you can still
    /// create blocks over them.
    @ViewBuilder
    private func routineBands(width: CGFloat) -> some View {
        ForEach(routineWindows) { window in
            let start = max(window.start, date.startOfDay)
            let end = min(window.end, date.startOfDay.adding(days: 1))
            // Once a real block sits in this window (e.g. Plan My Day placed
            // the routine as an actual block), drop the ghost so their labels
            // don't overlap.
            if start < end, !isCoveredByBlock(from: start, to: end) {
                let y = CGFloat(start.minutesSinceMidnight) / 60 * hourHeight
                let height = max(CGFloat(end.timeIntervalSince(start) / 60) / 60 * hourHeight, 10)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.textTertiary.opacity(0.07))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.textTertiary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if height >= 22 && !compact {
                        Label(window.title, systemImage: "moon.stars")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.top, 3)
                            .lineLimit(1)
                    }
                }
                .frame(width: width - 4, height: height)
                .offset(x: 2, y: y)
            }
        }
        .allowsHitTesting(false)
    }

    /// Time-anchored habits, drawn as their own compact markers at the set
    /// time — an appointment with yourself, distinct from calendar blocks. Tap
    /// to check off; blocks draw on top where they overlap.
    @ViewBuilder
    private func habitMarkers(width: CGFloat) -> some View {
        ForEach(anchoredHabits) { habit in
            if let minutes = habit.reminderMinutes {
                let done = isHabitDone(habit)
                let y = CGFloat(minutes) / 60 * hourHeight
                let height = max(CGFloat(habit.durationMinutes) / 60 * hourHeight, 22)
                Button {
                    onToggleHabit(habit); Haptics.success()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: done ? "checkmark.circle.fill" : habit.iconName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(done ? Theme.success : habit.color)
                        if height >= 20 {
                            Text(habit.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .strikethrough(done, color: Theme.textTertiary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(Fmt.time.string(from: date.at(minutes: minutes)))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(width: width - 4, height: height, alignment: .leading)
                    .background(habit.color.opacity(done ? 0.08 : 0.14),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(habit.color.opacity(0.5),
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(habit.color)
                            .frame(width: 3)
                            .padding(.vertical, 3)
                    }
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: y)
            }
        }
    }

    /// True when a timed block overlaps the given window, so its ghost band
    /// should be suppressed.
    private func isCoveredByBlock(from start: Date, to end: Date) -> Bool {
        blocks.contains { !$0.isAllDay && $0.start < end && start < $0.end }
    }

    private func time(atY y: CGFloat) -> Date {
        let minutes = max(0, min(Int(y / hourHeight * 60), 24 * 60 - 15))
        return date.at(minutes: minutes)
    }

    private func minutes(atY y: CGFloat) -> Int {
        max(0, min(Int(y / hourHeight * 60), 24 * 60))
    }

    // MARK: Drag-to-create

    /// The snapped (start, end) minutes of the block being drawn, if any.
    private var createRange: (start: Int, end: Int)? {
        guard let s = createStartMinutes, let c = createCurrentMinutes else { return nil }
        let lo = min(s, c), hi = max(s, c)
        let snappedLo = (lo / snapMinutes) * snapMinutes
        let snappedHi = max(snappedLo + snapMinutes, Int(ceil(Double(hi) / Double(snapMinutes))) * snapMinutes)
        return (snappedLo, min(snappedHi, 24 * 60))
    }

    private var dragCreateGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    if createStartMinutes == nil {
                        createStartMinutes = minutes(atY: drag.startLocation.y)
                    }
                    createCurrentMinutes = minutes(atY: drag.location.y)
                }
            }
            .onEnded { value in
                if case .second(true, _) = value, let range = createRange {
                    Haptics.light()
                    onCreateRange(date.at(minutes: range.start), date.at(minutes: range.end))
                }
                createStartMinutes = nil
                createCurrentMinutes = nil
            }
    }

    private func dragCreatePreview(_ range: (start: Int, end: Int)) -> some View {
        let y = CGFloat(range.start) / 60 * hourHeight
        let height = max(CGFloat(range.end - range.start) / 60 * hourHeight, 12)
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Theme.accentColor.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.accentColor, lineWidth: 1.5)
            )
            .overlay(alignment: .topLeading) {
                Text(Fmt.timeRange(date.at(minutes: range.start), date.at(minutes: range.end)))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 6).padding(.top, 3)
            }
            .frame(height: height)
            .offset(y: y)
            .padding(.horizontal, 2)
            .allowsHitTesting(false)
    }
}

/// The "now" indicator, isolated with its own timer so its 30-second ticks
/// only re-render this thin line — never the hour grid or the day's blocks.
private struct NowLineView: View {
    let hourHeight: CGFloat
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NowLine(hourHeight: hourHeight, now: now)
            .onReceive(timer) { now = $0 }
    }
}
