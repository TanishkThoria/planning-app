import SwiftUI

/// A single block on the timeline. Handles its own drag-to-move and
/// drag-to-resize with live snapping, and exposes everything else through
/// callbacks so it stays platform- and screen-agnostic.
struct TimeBlockCard: View {
    let placed: BlockLayout.Placed
    let day: Date
    let hourHeight: CGFloat
    let snapMinutes: Int
    let columnWidth: CGFloat
    var compact = false
    var dimPast = true
    var linkedTask: TaskItem?

    var onTap: () -> Void = {}
    var onMove: (Date) -> Void = { _ in }
    var onResize: (Date) -> Void = { _ in }
    var onToggleTask: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onStartNow: () -> Void = {}
    var onFocus: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var dragOffset: CGFloat?
    @State private var resizeOffset: CGFloat?
    /// Where the card settled after a drag, held until EventKit's refresh
    /// moves the real block — otherwise the card snaps back to its old slot
    /// for a beat and the whole move feels broken.
    @State private var settleDragOffset: CGFloat?
    @State private var settleResizeOffset: CGFloat?
    /// Last snapped minute-of-day announced with a haptic tick.
    @State private var lastTickMinutes: Int?
    @ObservedObject private var tags = TagStore.shared

    private var block: TimeBlock { placed.block }
    private var category: ActivityCategory { tags.category(for: block) }

    private var clampedInterval: (start: Date, end: Date) {
        block.clamped(to: day) ?? (block.start, block.end)
    }

    // MARK: Geometry

    private var baseY: CGFloat {
        CGFloat(clampedInterval.start.minutesSinceMidnight) / 60 * hourHeight
    }

    private var baseHeight: CGFloat {
        let minutes = clampedInterval.end.timeIntervalSince(clampedInterval.start) / 60
        return max(CGFloat(minutes) / 60 * hourHeight, 18)
    }

    private var laneWidth: CGFloat {
        max((columnWidth - 6) / CGFloat(placed.columnCount), 24)
    }

    private var xOffset: CGFloat {
        CGFloat(placed.column) * laneWidth + 2
    }

    private var displayHeight: CGFloat {
        max(baseHeight + (resizeOffset ?? settleResizeOffset ?? 0), 18)
    }

    private var isInteracting: Bool {
        dragOffset != nil || resizeOffset != nil
    }

    /// Snap a raw finger offset to the grid, in points.
    private func snapY(_ raw: CGFloat) -> CGFloat {
        let snapPts = CGFloat(snapMinutes) / 60 * hourHeight
        return (raw / snapPts).rounded() * snapPts
    }

    // MARK: Proposed times while dragging

    private var proposedStart: Date {
        guard let dragOffset else { return block.start }
        let rawStart = clampedInterval.start.addingTimeInterval(Double(dragOffset / hourHeight) * 3600)
        let snapped = rawStart.snapped(to: snapMinutes)
        let delta = snapped.timeIntervalSince(clampedInterval.start)
        return block.start.addingTimeInterval(delta)
    }

    private var proposedEnd: Date {
        if let resizeOffset {
            let rawEnd = clampedInterval.end.addingTimeInterval(Double(resizeOffset / hourHeight) * 3600)
            return max(rawEnd.snapped(to: snapMinutes), block.start.adding(minutes: 5))
        }
        return proposedStart.addingTimeInterval(block.duration)
    }

    var body: some View {
        content
            .frame(width: laneWidth - 2, height: displayHeight, alignment: .topLeading)
            .scaleEffect(dragOffset != nil ? 1.02 : 1, anchor: .center)
            .shadow(color: .black.opacity(isInteracting ? 0.35 : 0), radius: 10, y: 5)
            // While dragging the card follows the finger 1:1 (no quantized
            // jumps — that's what made moves feel jittery); the time label
            // shows the snapped target and it glides onto the grid on release.
            .offset(x: xOffset, y: baseY + (dragOffset ?? settleDragOffset ?? 0))
            .opacity(dimPast && block.isPast && !isInteracting ? 0.45 : 1)
            .zIndex(isInteracting || settleDragOffset != nil ? 10 : (block.isNow ? 2 : 1))
            .animation(.snappy(duration: 0.18), value: hourHeight)
            // When the store reflects the move, hand positioning back to it.
            .onChange(of: block.start) { _, _ in
                settleDragOffset = nil
                settleResizeOffset = nil
            }
            .onChange(of: block.end) { _, _ in settleResizeOffset = nil }
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(block.color.opacity(isInteracting ? 0.32 : 0.17))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(block.color.opacity(isInteracting ? 0.8 : 0.35), lineWidth: 1)

            HStack(alignment: .top, spacing: 0) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 7, bottomLeadingRadius: 7,
                    bottomTrailingRadius: 0, topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(block.color)
                .frame(width: 3)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .top, spacing: 4) {
                        if linkedTask != nil {
                            taskCheckbox
                        }
                        Text(block.title)
                            .font(.system(size: compact ? 10.5 : 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .strikethrough(linkedTask?.isCompleted == true, color: Theme.textSecondary)
                            .lineLimit(compact ? 2 : 3)
                        Spacer(minLength: 0)
                        if block.hasMeeting && displayHeight >= 26 {
                            Image(systemName: "video.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.accentColor)
                        }
                        if block.hasRecurrence && !compact && displayHeight >= 30 {
                            Image(systemName: "repeat")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        if !compact && displayHeight >= 30 {
                            Image(systemName: category.icon)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(category.color)
                        }
                    }
                    if displayHeight >= 38 && !compact {
                        Text(isInteracting
                             ? Fmt.timeRange(proposedStart, proposedEnd)
                             : Fmt.timeRange(block.start, block.end))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isInteracting ? Color.accentColor : Theme.textSecondary)
                    }
                    if displayHeight >= 66 && !compact, let location = block.location, !location.isEmpty {
                        Label(location, systemImage: "mappin")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, displayHeight < 26 ? 2 : 5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .gesture(moveGesture, including: block.isEditable ? .all : .subviews)
        .overlay(alignment: .bottom) {
            if block.isEditable && !compact {
                resizeHandle
            }
        }
        .contextMenu { contextMenuItems }
    }

    private var taskCheckbox: some View {
        Button(action: onToggleTask) {
            Image(systemName: linkedTask?.isCompleted == true ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(linkedTask?.isCompleted == true ? Theme.success : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if let url = block.meetingURL {
            Link(destination: url) {
                Label("Join \(block.meetingPlatform ?? "Meeting")", systemImage: "video")
            }
        }
        Button { onTap() } label: { Label("Edit", systemImage: "pencil") }
        Button { onFocus() } label: { Label("Focus on This", systemImage: "timer") }
        categorySubmenu
        if block.isEditable {
            Button { onDuplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { onStartNow() } label: { Label("Start Now", systemImage: "play.circle") }
            if let task = linkedTask {
                Button { onToggleTask() } label: {
                    Label(task.isCompleted ? "Mark Task Incomplete" : "Complete Task",
                          systemImage: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
                }
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// Tag the block's category — works for any event, including repeating and
    /// imported Apple Calendar events (tags the whole series, no calendar edit).
    @ViewBuilder
    private var categorySubmenu: some View {
        Menu {
            ForEach(ActivityCategory.allCases) { c in
                Button { tags.setCategory(c, forID: block.eventID); Haptics.light() } label: {
                    Label(c.title, systemImage: c.icon)
                    if category == c { Image(systemName: "checkmark") }
                }
            }
            if tags.isExplicit(forID: block.eventID) {
                Divider()
                Button { tags.setCategory(nil, forID: block.eventID); Haptics.light() } label: {
                    Label("Auto-detect", systemImage: "wand.and.stars")
                }
            }
        } label: {
            Label("Category: \(category.title)", systemImage: category.icon)
        }
    }

    // MARK: Gestures

    #if os(iOS)
    /// Long-press first so vertical drags don't fight the scroll view. The
    /// card then tracks the finger 1:1; a selection tick fires whenever the
    /// snapped landing slot changes, and release glides onto the grid.
    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    if dragOffset == nil { Haptics.medium() } // pickup
                    dragOffset = drag.translation.height
                    tickIfSlotChanged()
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value, abs(drag.translation.height) > 2 {
                    endMove(offset: drag.translation.height)
                } else {
                    dragOffset = nil
                }
                lastTickMinutes = nil
            }
    }
    #else
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                dragOffset = value.translation.height
                tickIfSlotChanged()
            }
            .onEnded { value in
                if abs(value.translation.height) > 2 {
                    endMove(offset: value.translation.height)
                } else {
                    dragOffset = nil
                }
                lastTickMinutes = nil
            }
    }
    #endif

    /// Glide the card onto its snapped slot immediately, then commit. The
    /// settle offset keeps it there until EventKit's refresh catches up.
    private func endMove(offset: CGFloat) {
        let final = proposedStartFor(offset: offset)
        withAnimation(.snappy(duration: 0.2)) {
            settleDragOffset = snapY(offset)
            dragOffset = nil
        }
        Haptics.light()
        onMove(final)
    }

    /// Fire a selection tick when the drag crosses into a new snap slot.
    private func tickIfSlotChanged() {
        let minutes = (resizeOffset != nil ? proposedEnd : proposedStart).minutesSinceMidnight
        if let last = lastTickMinutes, last != minutes {
            Haptics.selection()
        }
        lastTickMinutes = minutes
    }

    private func proposedStartFor(offset: CGFloat) -> Date {
        let rawStart = clampedInterval.start.addingTimeInterval(Double(offset / hourHeight) * 3600)
        let snapped = rawStart.snapped(to: snapMinutes)
        let delta = snapped.timeIntervalSince(clampedInterval.start)
        return block.start.addingTimeInterval(delta)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 10)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        resizeOffset = value.translation.height
                        tickIfSlotChanged()
                    }
                    .onEnded { value in
                        let rawEnd = clampedInterval.end.addingTimeInterval(Double(value.translation.height / hourHeight) * 3600)
                        let newEnd = max(rawEnd.snapped(to: snapMinutes), block.start.adding(minutes: 5))
                        withAnimation(.snappy(duration: 0.2)) {
                            settleResizeOffset = CGFloat(newEnd.timeIntervalSince(clampedInterval.end) / 3600) * hourHeight
                            resizeOffset = nil
                        }
                        Haptics.light()
                        lastTickMinutes = nil
                        onResize(newEnd)
                    }
            )
    }
}
