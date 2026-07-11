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
    var taskLookup: (String) -> TaskItem? = { _ in nil }

    var onTapBlock: (TimeBlock) -> Void = { _ in }
    var onMoveBlock: (TimeBlock, Date) -> Void = { _, _ in }
    var onResizeBlock: (TimeBlock, Date) -> Void = { _, _ in }
    var onToggleTask: (String) -> Void = { _ in }
    var onDuplicateBlock: (TimeBlock) -> Void = { _ in }
    var onStartBlockNow: (TimeBlock) -> Void = { _ in }
    var onDeleteBlock: (TimeBlock) -> Void = { _ in }
    var onCreateAt: (Date) -> Void = { _ in }
    var onDropTask: (String, Date) -> Void = { _, _ in }

    @State private var now = Date()
    @State private var dropIndicatorMinutes: Int?

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                grid

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
                        onDelete: { onDeleteBlock(placed.block) }
                    )
                }

                if let minutes = dropIndicatorMinutes {
                    dropIndicator(minutes: minutes)
                }

                if date.isToday {
                    NowLine(hourHeight: hourHeight, now: now)
                }
            }
            .dropDestination(for: String.self) { items, location in
                dropIndicatorMinutes = nil
                guard let taskID = items.first else { return false }
                onDropTask(taskID, time(atY: location.y).snappedDown(to: snapMinutes))
                return true
            } isTargeted: { targeted in
                if !targeted { dropIndicatorMinutes = nil }
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

    private func dropIndicator(minutes: Int) -> some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .offset(y: CGFloat(minutes) / 60 * hourHeight)
            .allowsHitTesting(false)
    }

    private func time(atY y: CGFloat) -> Date {
        let minutes = max(0, min(Int(y / hourHeight * 60), 24 * 60 - 15))
        return date.at(minutes: minutes)
    }
}
