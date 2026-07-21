import Foundation

/// Pure analytics over EventKit snapshots + the focus log. Everything the
/// Insights screen and the Coach read comes from here, so the numbers are
/// consistent and testable.
enum StatsEngine {

    struct DayStat: Identifiable {
        let day: Date
        var plannedMinutes: Int
        var focusMinutes: Int
        var completedTasks: Int
        var id: Date { day }
    }

    struct Stats {
        var range: DateInterval
        var plannedMinutes = 0
        var blockCount = 0
        var tasksCompleted = 0
        var tasksDue = 0
        var tasksDueCompleted = 0
        var onTimeCompleted = 0        // completed on/before due
        var datedCompleted = 0         // completed tasks that had a due date
        var adherenceEligible = 0      // past task-linked blocks
        var adherenceMet = 0           // …whose task got completed
        var focusMinutes = 0
        var focusSessions = 0
        var deepMinutes = 0
        var shallowMinutes = 0
        var avgBlockMinutes = 0
        var longestBlockTitle: String?
        var longestBlockMinutes = 0
        var linkedBlocks = 0
        var streakDays = 0
        var overdueNow = 0
        var perDay: [DayStat] = []

        var completionRate: Double { tasksDue == 0 ? 0 : Double(tasksDueCompleted) / Double(tasksDue) }
        var onTimeRate: Double { datedCompleted == 0 ? 0 : Double(onTimeCompleted) / Double(datedCompleted) }
        var adherenceRate: Double { adherenceEligible == 0 ? 0 : Double(adherenceMet) / Double(adherenceEligible) }
        var busiestDay: DayStat? { perDay.max { $0.plannedMinutes < $1.plannedMinutes } }
        var avgPlannedPerActiveDay: Int {
            let active = perDay.filter { $0.plannedMinutes > 0 }
            guard !active.isEmpty else { return 0 }
            return active.reduce(0) { $0 + $1.plannedMinutes } / active.count
        }
    }

    static func compute(
        days: [Date],
        blocks: (Date) -> [TimeBlock],
        allTasks: [TaskItem],
        taskLookup: (String) -> TaskItem?,
        sessions: [FocusSession],
        now: Date = Date(),
        // Real external events (not Chronos timeblocks) auto-count as attended,
        // focused time — unless the day review marked the occurrence skipped.
        isEventSkipped: (TimeBlock) -> Bool = { _ in false }
    ) -> Stats {
        let sortedDays = days.sorted()
        let start = (sortedDays.first ?? now).startOfDay
        let end = (sortedDays.last ?? now).endOfDay
        var stats = Stats(range: DateInterval(start: start, end: end))

        var blockMinutes: [Int] = []

        for day in sortedDays {
            let dayBlocks = blocks(day).filter { !$0.isAllDay }
            var dayPlanned = 0
            for block in dayBlocks {
                guard let clamped = block.clamped(to: day) else { continue }
                let minutes = Int(clamped.end.timeIntervalSince(clamped.start) / 60)
                dayPlanned += minutes

                // Count each occurrence once (on its starting day) for totals.
                if block.start.isSameDay(as: day) {
                    stats.blockCount += 1
                    blockMinutes.append(block.durationMinutes)
                    if block.durationMinutes > stats.longestBlockMinutes {
                        stats.longestBlockMinutes = block.durationMinutes
                        stats.longestBlockTitle = block.title
                    }
                    if let taskID = block.linkedTaskID {
                        stats.linkedBlocks += 1
                        let energy = taskLookup(taskID)?.energy ?? .none
                        switch energy {
                        case .deep: stats.deepMinutes += block.durationMinutes
                        case .shallow: stats.shallowMinutes += block.durationMinutes
                        case .none: break
                        }
                        // Adherence: a past block linked to a task.
                        if block.end < now {
                            stats.adherenceEligible += 1
                            if taskLookup(taskID)?.isCompleted == true { stats.adherenceMet += 1 }
                        }
                    }
                }
            }
            stats.plannedMinutes += dayPlanned

            let daySessions = sessions.filter { $0.start.isSameDay(as: day) }
            // Attended real events on their start day count as focused time.
            let attendedEventMinutes = dayBlocks
                .filter { $0.isRealEvent && $0.start.isSameDay(as: day) && $0.end < now && !isEventSkipped($0) }
                .reduce(0) { $0 + $1.durationMinutes }
            let dayFocus = daySessions.reduce(0) { $0 + $1.actualMinutes } + attendedEventMinutes
            stats.focusMinutes += dayFocus
            stats.focusSessions += daySessions.count

            let dayCompleted = allTasks.filter {
                $0.isCompleted && ($0.completionDate?.isSameDay(as: day) ?? false)
            }.count
            stats.tasksCompleted += dayCompleted

            stats.perDay.append(DayStat(
                day: day,
                plannedMinutes: dayPlanned,
                focusMinutes: dayFocus,
                completedTasks: dayCompleted
            ))
        }

        if !blockMinutes.isEmpty {
            stats.avgBlockMinutes = blockMinutes.reduce(0, +) / blockMinutes.count
        }

        // Tasks due within the range + on-time behaviour.
        for task in allTasks {
            if let due = task.dueDate, due >= start, due <= end {
                stats.tasksDue += 1
                if task.isCompleted { stats.tasksDueCompleted += 1 }
            }
            if task.isCompleted, let due = task.dueDate, let done = task.completionDate,
               done >= start, done <= end {
                stats.datedCompleted += 1
                if done <= due.endOfDay { stats.onTimeCompleted += 1 }
            }
        }

        stats.overdueNow = allTasks.filter { !$0.isCompleted && $0.isOverdue }.count
        stats.streakDays = completionStreak(tasks: allTasks, now: now)
        return stats
    }

    /// Consecutive days ending today on which at least one task was
    /// completed. Today not yet counted doesn't break the streak.
    static func completionStreak(tasks: [TaskItem], now: Date = Date()) -> Int {
        let completedDays = Set(
            tasks.compactMap { $0.isCompleted ? $0.completionDate?.startOfDay : nil }
        )
        guard !completedDays.isEmpty else { return 0 }
        var streak = 0
        var cursor = now.startOfDay
        // Grace: if nothing done yet today, start counting from yesterday.
        if !completedDays.contains(cursor) { cursor = cursor.adding(days: -1) }
        while completedDays.contains(cursor) {
            streak += 1
            cursor = cursor.adding(days: -1)
        }
        return streak
    }
}
