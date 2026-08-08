import SwiftUI

/// A proposed block in the Plan-My-Day preview — a hypothetical event the user
/// can drag and resize before committing. Times are minutes-since-midnight on
/// the plan's day, so snapping and drag math stay integer-clean.
struct PlanDraftBlock: Identifiable, Equatable {
    enum Source: Equatable {
        case task(String)      // reminder id → scheduleTask
        case ritual(String)    // routine-window title
        case project(UUID)
    }

    let id = UUID()
    var title: String
    var emoji: String?
    var startMinutes: Int
    var minutes: Int
    /// Colour used to render the draft on the timeline.
    var color: Color
    /// Palette hex to stamp on the created block (projects); nil = leave default.
    var colorHex: UInt32?
    var source: Source

    var endMinutes: Int { startMinutes + minutes }
}

/// The interactive hour-by-hour canvas: existing blocks shown faded for
/// context, each draft block draggable (move) and resizable (bottom handle),
/// snapping to the grid. Purpose-built for the preview so it stays independent
/// of the live EventKit timeline.
struct PlanPreviewTimeline: View {
    let day: Date
    let existing: [TimeBlock]
    @Binding var drafts: [PlanDraftBlock]
    var snapMinutes: Int = 15
    /// The hour to scroll into view on appear (e.g. the workday start).
    var focusHour: Int = 8

    private let hourHeight: CGFloat = 58
    private let gutter: CGFloat = 52
    private var totalHeight: CGFloat { hourHeight * 24 }

    // Context blocks clamped to this day, timed only.
    private var contextBlocks: [(id: String, title: String, start: Int, minutes: Int, color: Color)] {
        existing.filter { !$0.isAllDay }.compactMap { block in
            guard let clamped = block.clamped(to: day) else { return nil }
            let start = max(0, clamped.start.minutesSinceMidnight)
            let mins = max(15, Int(clamped.end.timeIntervalSince(clamped.start) / 60))
            return (block.id, block.title, start, mins, block.color)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    hourGutter
                    ZStack(alignment: .topLeading) {
                        gridLines
                        ForEach(contextBlocks, id: \.id) { block in
                            contextBlockView(block)
                        }
                        ForEach($drafts) { $draft in
                            DraftBlockView(
                                draft: $draft,
                                hourHeight: hourHeight,
                                snapMinutes: snapMinutes,
                                onRemove: { drafts.removeAll { $0.id == draft.id } }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.trailing, 10)
                }
                .frame(height: totalHeight, alignment: .top)
                .overlay(alignment: .topLeading) { scrollAnchors }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("plan-hour-\(min(max(focusHour, 1), 22))", anchor: .top)
                }
            }
        }
    }

    private var hourGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(height: hourHeight, alignment: .top)
                    .frame(width: gutter, alignment: .trailing)
                    .padding(.trailing, 8)
                    .offset(y: -6)
            }
        }
    }

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight)
            }
        }
    }

    private var scrollAnchors: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Color.clear.frame(height: hourHeight).id("plan-hour-\(hour)")
            }
        }
    }

    private func contextBlockView(_ block: (id: String, title: String, start: Int, minutes: Int, color: Color)) -> some View {
        let h = max(18, CGFloat(block.minutes) / 60 * hourHeight)
        return HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(block.color.opacity(0.5)).frame(width: 3)
            Text(block.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: h, alignment: .top)
        .background(Theme.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .offset(y: CGFloat(block.start) / 60 * hourHeight)
        .allowsHitTesting(false)
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return Fmt.hourLabel.string(from: date)
    }
}

/// A single draggable / resizable draft block. Drag the body to move it; drag
/// the bottom handle to change its length. Both snap to the grid on release.
private struct DraftBlockView: View {
    @Binding var draft: PlanDraftBlock
    let hourHeight: CGFloat
    let snapMinutes: Int
    let onRemove: () -> Void

    @GestureState private var moveBy: CGFloat = 0
    @GestureState private var resizeBy: CGFloat = 0

    private var baseY: CGFloat { CGFloat(draft.startMinutes) / 60 * hourHeight }
    private var baseHeight: CGFloat { max(22, CGFloat(draft.minutes) / 60 * hourHeight) }

    var body: some View {
        let liveHeight = max(22, baseHeight + resizeBy)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let emoji = draft.emoji { Text(emoji).font(.system(size: 12)) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(draft.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if liveHeight > 34 {
                        Text(timeRangeLabel)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(draft.color.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            Spacer(minLength: 0)
            // Resize handle
            HStack {
                Spacer()
                Capsule().fill(draft.color.opacity(0.7)).frame(width: 26, height: 4)
                Spacer()
            }
            .frame(height: 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($resizeBy) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        let deltaMin = snapped(Int((value.translation.height / hourHeight * 60).rounded()))
                        draft.minutes = max(snapMinutes, min(24 * 60 - draft.startMinutes, draft.minutes + deltaMin))
                        Haptics.light()
                    }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: liveHeight, alignment: .top)
        .background(draft.color.opacity(0.20), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(draft.color, lineWidth: 1.5))
        .offset(y: baseY + moveBy)
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($moveBy) { value, state, _ in state = value.translation.height }
                .onEnded { value in
                    let deltaMin = snapped(Int((value.translation.height / hourHeight * 60).rounded()))
                    let newStart = max(0, min(24 * 60 - draft.minutes, draft.startMinutes + deltaMin))
                    draft.startMinutes = newStart
                    Haptics.light()
                }
        )
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove from plan", systemImage: "trash")
            }
        }
        .animation(.snappy(duration: 0.18), value: draft.startMinutes)
        .animation(.snappy(duration: 0.18), value: draft.minutes)
        .zIndex(1)
    }

    private func snapped(_ minutes: Int) -> Int {
        let s = max(1, snapMinutes)
        return Int((Double(minutes) / Double(s)).rounded()) * s
    }

    private var timeRangeLabel: String {
        let start = day0.at(minutes: draft.startMinutes)
        let end = day0.at(minutes: draft.endMinutes)
        return Fmt.timeRange(start, end)
    }

    // A neutral day base for formatting times (date component is irrelevant).
    private var day0: Date { Date().startOfDay }
}
