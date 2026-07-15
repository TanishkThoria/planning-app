import Foundation

/// The "realistic workload" guardrail — Sunsama's most-loved idea. Compares the
/// time your due-today tasks will actually take against the free time you have
/// left between now and the end of your workday, so over-planning becomes
/// visible instead of a 10pm surprise.
enum DayLoad {
    struct Result {
        var committedMinutes: Int
        var freeMinutes: Int
        var taskCount: Int

        var overcommitted: Bool { committedMinutes > freeMinutes && committedMinutes > 0 }
        /// 0…1+ fill ratio (can exceed 1 when overcommitted).
        var ratio: Double {
            guard committedMinutes > 0 else { return 0 }
            if freeMinutes <= 0 { return 1.6 }
            return Double(committedMinutes) / Double(freeMinutes)
        }
        var overBy: Int { max(0, committedMinutes - freeMinutes) }
    }

    /// `events` should be today's timed blocks; `workStart`/`workEnd` are
    /// minutes-since-midnight. `defaultEstimate` fills in tasks with no estimate.
    static func compute(
        tasks: [TaskItem],
        events: [TimeBlock],
        workStart: Int,
        workEnd: Int,
        now: Date = Date(),
        defaultEstimate: Int = 30
    ) -> Result {
        let due = tasks.filter { !$0.isCompleted && $0.isDueToday }
        let committed = due.reduce(0) { $0 + ($1.estimateMinutes ?? defaultEstimate) }

        let today = now.startOfDay
        let windowStart = max(today.at(minutes: workStart), now)
        let windowEnd = today.at(minutes: workEnd)
        guard windowEnd > windowStart else {
            return Result(committedMinutes: committed, freeMinutes: 0, taskCount: due.count)
        }
        var free = Int(windowEnd.timeIntervalSince(windowStart) / 60)
        for event in events where !event.isAllDay {
            let s = max(event.start, windowStart)
            let e = min(event.end, windowEnd)
            if e > s { free -= Int(e.timeIntervalSince(s) / 60) }
        }
        return Result(committedMinutes: committed, freeMinutes: max(0, free), taskCount: due.count)
    }
}
