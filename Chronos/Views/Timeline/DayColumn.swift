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
    var onDropTask: (String, Date) -> Void = { _, _ in }

    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                grid

                routineBands(width: geo.size.width)

                // Create layer — double tap/click an empty slot.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, coordinateSpace: .local) { point in
                        onCreateAt(time(atY: point.y).snappedDown(to: snapMinutes))
                    }

                ForEach(BlockLayout.place(blocks, on: date)) { placed in
                    TimeBlockCard(
                        placed: placed,
                        day: date,
                        hourHeight: hourHeight,
                        snapMinutes: snapMinutes,
                        columnWidth: geo.size.width,
                        compact: compact,
                        dimPast: dimPast,
                        linkedTask: placed.block.linkedTaskID.flatMap(taskLookup),
                        onTap: { onTapBlock(placed.block) },
                        onMove: { onMoveBlock(placed.block, $0) },
                        onResize: { onResizeBlock(placed.block, $0) },
                        onToggleTask: {
                            if let taskID = placed.block.linkedTaskID { onToggleTask(taskID) }
                        },
                        onDuplicate: { onDuplicateBlock(placed.block) },
                        onStartNow: { onStartBlockNow(placed.block) },
                        onFocus: { onFocusBlock(placed.block) },
                        onDelete: { onDeleteBlock(placed.block) }
                    )
                }

                if date.isToday {
                    NowLine(hourHeight: hourHeight, now: now)
                }
            }
            .dropDestination(for: String.self) { items, location in
                guard let taskID = items.first else { return false }
                onDropTask(taskID, time(atY: location.y).snappedDown(to: snapMinutes))
                return true
            }
        }
        .frame(height: 24 * hourHeight)
        .onReceive(timer) { now = $0 }
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
            if start < end {
                let y = CGFloat(start.minutesSinceMidnight) / 60 * hourHeight
                let height = max(CGFloat(end.timeIntervalSince(start) / 60) / 60 * hourHeight, 10)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.textTertiary.opacity(0.07))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.textTertiary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if height >= 22 && !compact {
                        Label(window.title, systemImage: "moon.stars")
                            .font(.system(size: 9, weight: .medium))
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

    private func time(atY y: CGFloat) -> Date {
        let minutes = max(0, min(Int(y / hourHeight * 60), 24 * 60 - 15))
        return date.at(minutes: minutes)
    }
}
