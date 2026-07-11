import Foundation

/// Greedy gap-filling scheduler behind "Plan My Day" and every
/// "next free slot" button. Once a `PlannerProfile` is calibrated it gets
/// opinionated: meal and routine windows become protected time (unless the
/// profile is fully flexible), the scheduling window can widen to
/// wake-to-bed, high-priority tasks are steered into the user's focus
/// window, and the flexibility level enforces breathing room.
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

    /// The effective scheduling window for a day, given prefs + profile.
    static func schedulingWindow(
        on day: Date,
        workStartMinutes: Int,
        workEndMinutes: Int,
        profile: PlannerProfile?
    ) -> (start: Date, end: Date) {
        guard let profile, profile.isCalibrated else {
            return (day.at(minutes: workStartMinutes), day.at(minutes: max(workEndMinutes, workStartMinutes + 30)))
        }
        switch profile.flexibility {
        case .flexible:
            // Anything awake is fair game.
            return (day.at(minutes: profile.wakeMinutes),
                    day.at(minutes: max(profile.bedMinutes, profile.wakeMinutes + 60)))
        case .strict, .balanced:
            // Work hours, clamped inside the waking day.
            let start = max(workStartMinutes, profile.wakeMinutes)
            let end = min(max(workEndMinutes, start + 30), profile.bedMinutes)
            return (day.at(minutes: start), day.at(minutes: max(end, start + 30)))
        }
    }

    /// Free stretches on `day` inside the scheduling window, minus existing
    /// (non-all-day) blocks and any protected routine windows. When the day
    /// is today, time already gone is not offered.
    static func freeGaps(
        on day: Date,
        existing: [TimeBlock],
        workStartMinutes: Int,
        workEndMinutes: Int,
        profile: PlannerProfile? = nil,
        now: Date = Date()
    ) -> [Gap] {
        let window = schedulingWindow(
            on: day,
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            profile: profile
        )
        var windowStart = window.start
        let windowEnd = window.end
        if day.isSameDay(as: now) {
            windowStart = max(windowStart, now.snapped(to: 5))
        }
        guard windowStart < windowEnd else { return [] }

        var busy: [(start: Date, end: Date)] = existing
            .filter { !$0.isAllDay }
            .compactMap { $0.clamped(to: day) }

        if let profile, profile.isCalibrated, profile.flexibility.protectsRoutines {
            busy += profile.routineWindows(on: day).map { ($0.start, $0.end) }
        }
        busy.sort { $0.start < $1.start }

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

    /// First-fit proposal set. High-priority tasks are offered focus-window
    /// gaps first; tasks that don't fit anywhere are omitted (the UI reports
    /// how many were left out).
    static func plan(
        tasks: [TaskItem],
        existing: [TimeBlock],
        on day: Date,
        workStartMinutes: Int,
        workEndMinutes: Int,
        snapMinutes: Int,
        defaultMinutes: Int,
        gapPaddingMinutes: Int = 0,
        profile: PlannerProfile? = nil,
        now: Date = Date()
    ) -> [Proposal] {
        var gaps = freeGaps(
            on: day,
            existing: existing,
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            profile: profile,
            now: now
        )

        let padding: Int = {
            guard let profile, profile.isCalibrated else { return gapPaddingMinutes }
            return max(gapPaddingMinutes, profile.flexibility.minimumGapMinutes)
        }()

        let focusWindow: (start: Date, end: Date)? = {
            guard let profile, profile.isCalibrated else { return nil }
            let minutes = profile.focus.windowMinutes
            return (day.at(minutes: minutes.start), day.at(minutes: minutes.end))
        }()

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

        func gapIndex(fitting minutes: Int, preferFocus: Bool) -> Int? {
            if preferFocus, let focus = focusWindow {
                if let index = gaps.firstIndex(where: {
                    $0.minutes >= minutes && $0.start < focus.end && $0.end > focus.start
                }) {
                    return index
                }
            }
            return gaps.firstIndex(where: { $0.minutes >= minutes })
        }

        for task in ordered {
            let minutes = max(task.estimateMinutes ?? defaultMinutes, 10)
            let preferFocus = task.priority == .high
            guard let index = gapIndex(fitting: minutes, preferFocus: preferFocus) else { continue }

            var gap = gaps[index]
            let snapped = gap.start.snapped(to: snapMinutes)
            let start = snapped < gap.start ? snapped.adding(minutes: snapMinutes) : snapped
            let end = start.adding(minutes: minutes)
            guard end <= gap.end else {
                // Snapping pushed it past the gap; try the gap unsnapped.
                if gap.start.adding(minutes: minutes) <= gap.end {
                    proposals.append(Proposal(task: task, start: gap.start, minutes: minutes))
                    gap.start = gap.start.adding(minutes: minutes + padding)
                    gaps[index] = gap
                }
                continue
            }

            proposals.append(Proposal(task: task, start: start, minutes: minutes))
            gap.start = end.adding(minutes: padding)
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
        snapMinutes: Int,
        profile: PlannerProfile? = nil
    ) -> Date {
        for offset in 0..<7 {
            let day = after.startOfDay.adding(days: offset)
            let gaps = freeGaps(
                on: day,
                existing: existing.filter { $0.clamped(to: day) != nil },
                workStartMinutes: workStartMinutes,
                workEndMinutes: workEndMinutes,
                profile: profile,
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
