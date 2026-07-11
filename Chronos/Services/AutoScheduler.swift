import Foundation

/// Greedy gap-filling scheduler behind "Plan My Day": takes the tasks you
/// choose, finds the free stretches between existing calendar blocks inside
/// your working hours, and proposes a slot for each task — highest priority
/// and earliest due date first.
enum AutoScheduler {

    struct Proposal: Identifiable, Hashable {
        let task: TaskItem
        var start: Date
        var minutes: Int
        var id: String { task.id }
        var end: Date { start.adding(minutes: minutes) }
    }

    struct Gap {
        var start: Date
        var end: Date
        var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
    }

    /// Free stretches on `day` between `workStartMinutes` and
    /// `workEndMinutes`, excluding existing (non-all-day) blocks. When the
    /// day is today, time already gone is not offered.
    static func freeGaps(
        on day: Date,
        existing: [TimeBlock],
        workStartMinutes: Int,
        workEndMinutes: Int,
        now: Date = Date()
    ) -> [Gap] {
        var windowStart = day.at(minutes: workStartMinutes)
        let windowEnd = day.at(minutes: max(workEndMinutes, workStartMinutes + 30))
        if day.isSameDay(as: now) {
            windowStart = max(windowStart, now.snapped(to: 5))
        }
        guard windowStart < windowEnd else { return [] }

        let busy = existing
            .filter { !$0.isAllDay }
            .compactMap { $0.clamped(to: day) }
            .sorted { $0.start < $1.start }

        var gaps: [Gap] = []
        var cursor = windowStart
        for interval in busy {
            if interval.start > cursor {
                gaps.append(Gap(start: cursor, end: min(interval.start, windowEnd)))
            }
            cursor = max(cursor, interval.end)
            if cursor >= windowEnd { break }
        }
        if cursor < windowEnd {
            gaps.append(Gap(start: cursor, end: windowEnd))
        }
        return gaps.filter { $0.minutes >= 10 }
    }

    /// First-fit proposal set. Tasks that don't fit are simply omitted —
    /// the UI reports how many were left out.
    static func plan(
        tasks: [TaskItem],
        existing: [TimeBlock],
        on day: Date,
        workStartMinutes: Int,
        workEndMinutes: Int,
        snapMinutes: Int,
        defaultMinutes: Int,
        gapPaddingMinutes: Int = 0,
        now: Date = Date()
    ) -> [Proposal] {
        var gaps = freeGaps(
            on: day,
            existing: existing,
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            now: now
        )

        let ordered = tasks.sorted { a, b in
            if a.priority.sortRank != b.priority.sortRank { return a.priority.sortRank < b.priority.sortRank }
            switch (a.dueDate, b.dueDate) {
            case let (da?, db?): return da < db
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }

        var proposals: [Proposal] = []
        for task in ordered {
            let minutes = max(task.estimateMinutes ?? defaultMinutes, 10)
            guard let index = gaps.firstIndex(where: { $0.minutes >= minutes }) else { continue }

            var gap = gaps[index]
            let start = gap.start.snapped(to: snapMinutes) < gap.start
                ? gap.start.snapped(to: snapMinutes).adding(minutes: snapMinutes)
                : gap.start.snapped(to: snapMinutes)
            let end = start.adding(minutes: minutes)
            guard end <= gap.end else {
                // Snapping pushed it past the gap; try the gap unsnapped.
                if gap.start.adding(minutes: minutes) <= gap.end {
                    proposals.append(Proposal(task: task, start: gap.start, minutes: minutes))
                    gap.start = gap.start.adding(minutes: minutes + gapPaddingMinutes)
                    gaps[index] = gap
                }
                continue
            }

            proposals.append(Proposal(task: task, start: start, minutes: minutes))
            gap.start = end.adding(minutes: gapPaddingMinutes)
            gaps[index] = gap
        }

        return proposals.sorted { $0.start < $1.start }
    }

    /// The next open slot of at least `minutes` starting from `after` —
    /// used by "Schedule" buttons and untimed quick-adds. Looks up to a
    /// week ahead so it always finds something.
    static func nextFreeSlot(
        after: Date,
        minutes: Int,
        existing: [TimeBlock],
        workStartMinutes: Int,
        workEndMinutes: Int,
        snapMinutes: Int
    ) -> Date {
        for offset in 0..<7 {
            let day = after.startOfDay.adding(days: offset)
            let gaps = freeGaps(
                on: day,
                existing: existing.filter { $0.clamped(to: day) != nil },
                workStartMinutes: workStartMinutes,
                workEndMinutes: workEndMinutes,
                now: max(after, Date())
            )
            for gap in gaps where gap.minutes >= minutes {
                let snapped = gap.start.snapped(to: snapMinutes)
                let start = snapped < gap.start ? snapped.adding(minutes: snapMinutes) : snapped
                if start.adding(minutes: minutes) <= gap.end { return start }
                if gap.start.adding(minutes: minutes) <= gap.end { return gap.start }
            }
        }
        return max(after, Date()).snapped(to: snapMinutes)
    }
}
