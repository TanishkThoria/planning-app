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

    /// One schedulable slice of a task. Chunked tasks expand into several
    /// units (session 1 of 3, …); simple tasks yield exactly one.
    struct WorkUnit {
        let task: TaskItem
        let minutes: Int
        let sessionIndex: Int
        let sessionCount: Int
    }

    /// Breaks a task into work units honouring its per-session length.
    static func workUnits(for task: TaskItem, defaultMinutes: Int) -> [WorkUnit] {
        let total = max(task.estimateMinutes ?? defaultMinutes, 10)
        guard let session = task.effectiveSessionMinutes, session >= 10, session < total else {
            return [WorkUnit(task: task, minutes: total, sessionIndex: 0, sessionCount: 1)]
        }
        var remaining = total
        var lengths: [Int] = []
        while remaining > 0 {
            lengths.append(min(session, remaining))
            remaining -= session
        }
        // Cap the number of sessions to keep proposals sane.
        let capped = Array(lengths.prefix(12))
        return capped.enumerated().map {
            WorkUnit(task: task, minutes: $0.element, sessionIndex: $0.offset, sessionCount: capped.count)
        }
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
        orderByDeadline: Bool = false,
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
            if orderByDeadline {
                // Earliest-deadline-first — used by the deadline work-back
                // planner so the most urgent due date always claims slots.
                switch (a.dueDate, b.dueDate) {
                case let (da?, db?) where da != db: return da < db
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            }
            if a.priority.sortRank != b.priority.sortRank { return a.priority.sortRank < b.priority.sortRank }
            switch (a.dueDate, b.dueDate) {
            case let (da?, db?): return da < db
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }

        // Expand into work units so chunked tasks get multiple sessions.
        let units = ordered.flatMap { workUnits(for: $0, defaultMinutes: defaultMinutes) }

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

        for unit in units {
            let minutes = unit.minutes
            // Deep work and high priority are steered into the focus window.
            let preferFocus = unit.task.priority == .high || unit.task.energy == .deep
            guard let index = gapIndex(fitting: minutes, preferFocus: preferFocus) else { continue }

            var gap = gaps[index]
            let snapped = gap.start.snapped(to: snapMinutes)
            let start = snapped < gap.start ? snapped.adding(minutes: snapMinutes) : snapped
            let end = start.adding(minutes: minutes)
            guard end <= gap.end else {
                // Snapping pushed it past the gap; try the gap unsnapped.
                if gap.start.adding(minutes: minutes) <= gap.end {
                    proposals.append(Proposal(task: unit.task, start: gap.start, minutes: minutes))
                    gap.start = gap.start.adding(minutes: minutes + padding)
                    gaps[index] = gap
                }
                continue
            }

            proposals.append(Proposal(task: unit.task, start: start, minutes: minutes))
            gap.start = end.adding(minutes: padding)
            gaps[index] = gap
        }

        return proposals.sorted { $0.start < $1.start }
    }

    /// Week-level auto-plan: distributes the given tasks across the supplied
    /// days, filling each day before moving on. Chunked tasks naturally
    /// spread their sessions across days as earlier days fill up. Blocks
    /// proposed on one day are treated as busy on the next.
    static func planWeek(
        tasks: [TaskItem],
        existing: [TimeBlock],
        days: [Date],
        workStartMinutes: Int,
        workEndMinutes: Int,
        snapMinutes: Int,
        defaultMinutes: Int,
        gapPaddingMinutes: Int = 0,
        profile: PlannerProfile? = nil,
        now: Date = Date()
    ) -> [Date: [Proposal]] {
        var remaining = tasks
        var byDay: [Date: [Proposal]] = [:]
        // Synthetic blocks representing what we've already proposed, so later
        // days see earlier days' plan as busy.
        var proposedBlocks: [TimeBlock] = []

        for day in days.sorted() {
            guard !remaining.isEmpty else { break }
            let dayExisting = existing + proposedBlocks
            let proposals = plan(
                tasks: remaining,
                existing: dayExisting,
                on: day,
                workStartMinutes: workStartMinutes,
                workEndMinutes: workEndMinutes,
                snapMinutes: snapMinutes,
                defaultMinutes: defaultMinutes,
                gapPaddingMinutes: gapPaddingMinutes,
                profile: profile,
                now: now
            )
            guard !proposals.isEmpty else { continue }
            byDay[day.startOfDay] = proposals

            // Record placed minutes so a task fully scheduled today drops out,
            // and partially-chunked tasks keep only their unscheduled remainder.
            var placedMinutesByTask: [String: Int] = [:]
            for proposal in proposals {
                placedMinutesByTask[proposal.task.id, default: 0] += proposal.minutes
                proposedBlocks.append(syntheticBlock(from: proposal))
            }

            remaining = remaining.compactMap { task in
                guard let placed = placedMinutesByTask[task.id] else { return task }
                let total = max(task.estimateMinutes ?? defaultMinutes, 10)
                let left = total - placed
                guard left >= 10 else { return nil }   // fully (or near-fully) scheduled
                var trimmed = task
                trimmed.estimateMinutes = left
                return trimmed
            }
        }
        return byDay
    }

    /// Deadline work-back: spreads estimated, due-dated work across the days
    /// leading up to each deadline. Earliest deadlines claim slots first, no
    /// session lands after its task's due moment, and a per-day cap keeps the
    /// plan humane instead of frontloading a study marathon.
    static func planDeadlines(
        tasks: [TaskItem],
        existing: [TimeBlock],
        horizonDays: Int,
        maxDailyMinutes: Int,
        workStartMinutes: Int,
        workEndMinutes: Int,
        snapMinutes: Int,
        defaultMinutes: Int,
        gapPaddingMinutes: Int = 0,
        profile: PlannerProfile? = nil,
        now: Date = Date()
    ) -> [Date: [Proposal]] {
        var remaining = tasks.filter { $0.dueDate != nil }
        var byDay: [Date: [Proposal]] = [:]
        var proposedBlocks: [TimeBlock] = []

        for offset in 0..<max(horizonDays, 1) {
            guard !remaining.isEmpty else { break }
            let day = now.startOfDay.adding(days: offset)

            // Only work on tasks whose deadline hasn't passed by this day.
            let eligible = remaining.filter { task in
                guard let due = task.dueDate else { return false }
                return due.startOfDay >= day
            }
            guard !eligible.isEmpty else { continue }

            var proposals = plan(
                tasks: eligible,
                existing: existing + proposedBlocks,
                on: day,
                workStartMinutes: workStartMinutes,
                workEndMinutes: workEndMinutes,
                snapMinutes: snapMinutes,
                defaultMinutes: defaultMinutes,
                gapPaddingMinutes: gapPaddingMinutes,
                profile: profile,
                orderByDeadline: true,
                now: now
            )

            // Never schedule a session past its own due moment.
            proposals = proposals.filter { proposal in
                guard let due = proposal.task.dueDate else { return true }
                let cutoff = proposal.task.dueHasTime ? due : due.endOfDay
                return proposal.end <= cutoff
            }

            // Humane daily cap — trim the latest sessions past the budget.
            var budget = maxDailyMinutes
            proposals = proposals.sorted { $0.start < $1.start }.filter { proposal in
                guard budget >= proposal.minutes else { return false }
                budget -= proposal.minutes
                return true
            }
            guard !proposals.isEmpty else { continue }
            byDay[day] = proposals

            var placedMinutesByTask: [String: Int] = [:]
            for proposal in proposals {
                placedMinutesByTask[proposal.task.id, default: 0] += proposal.minutes
                proposedBlocks.append(syntheticBlock(from: proposal))
            }
            remaining = remaining.compactMap { task in
                guard let placed = placedMinutesByTask[task.id] else { return task }
                let total = max(task.estimateMinutes ?? defaultMinutes, 10)
                let left = total - placed
                guard left >= 10 else { return nil }
                var trimmed = task
                trimmed.estimateMinutes = left
                return trimmed
            }
        }
        return byDay
    }

    private static func syntheticBlock(from proposal: Proposal) -> TimeBlock {
        TimeBlock(
            id: "proposed-\(proposal.task.id)-\(Int(proposal.start.timeIntervalSinceReferenceDate))",
            eventID: "proposed",
            title: proposal.task.title,
            start: proposal.start,
            end: proposal.end,
            isAllDay: false,
            calendarID: "",
            calendarTitle: "",
            color: .clear,
            notes: nil,
            location: nil,
            linkedTaskID: proposal.task.id,
            hasRecurrence: false,
            isEditable: false
        )
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
