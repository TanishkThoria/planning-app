import Foundation

// Anti-perfectionism, quantified. The honest metric isn't "did you never fall
// behind" — it's "how fast did you come back." RecoveryEngine measures returns
// after disruption, so a missed day becomes a comeback story instead of a
// broken streak. Consistency is returning.

struct RecoveryReading {
    let activeToday: Bool
    /// Days since the last active day (0 if active today).
    let currentGapDays: Int
    /// Length of the gap you most recently returned from (0 if none).
    let lastClosedGap: Int
    /// Number of gaps closed (comebacks) within the window.
    let comebacks: Int
    /// Active days within the window.
    let activeDays: Int
    let windowDays: Int
    /// True on the day you return after being away — the moment to celebrate.
    let justReturned: Bool

    var resilience: Double {
        windowDays <= 0 ? 0 : Double(activeDays) / Double(windowDays)
    }

    var headline: String {
        if justReturned { return "Welcome back — you returned" }
        if activeToday && currentGapDays == 0 { return "Still showing up" }
        if currentGapDays >= 1 { return "Ready when you are" }
        return "Showing up"
    }
    var message: String {
        if justReturned {
            return "You were away \(lastClosedGap) day\(lastClosedGap == 1 ? "" : "s") and came back. That's the whole skill. Consistency isn't never falling behind — it's returning."
        }
        if currentGapDays >= 2 {
            return "It's been \(currentGapDays) days. No guilt — the fastest way back is one small win. Pick the smallest thing and start."
        }
        if comebacks > 0 {
            return "You've bounced back \(comebacks) time\(comebacks == 1 ? "" : "s") in the last \(windowDays) days. Returning is a muscle, and yours works."
        }
        return "You've shown up \(activeDays) of the last \(windowDays) days. Keep the chain honest — a missed day is just a comeback waiting."
    }
}

enum RecoveryEngine {
    /// Pure core: `flags[0]` is today, oldest last.
    static func reading(activeFlags flags: [Bool]) -> RecoveryReading {
        let window = flags.count
        guard window > 0 else {
            return RecoveryReading(activeToday: false, currentGapDays: 0, lastClosedGap: 0,
                                   comebacks: 0, activeDays: 0, windowDays: 0, justReturned: false)
        }
        let activeToday = flags[0]
        let activeDays = flags.filter { $0 }.count

        // Current gap: consecutive inactive days from today backward.
        var currentGap = 0
        if !activeToday {
            for f in flags { if f { break }; currentGap += 1 }
        }

        // The gap we just closed (only meaningful if active today, idle yesterday).
        var lastClosedGap = 0
        var justReturned = false
        if activeToday, flags.count > 1, !flags[1] {
            var g = 0
            for i in 1..<flags.count { if flags[i] { break }; g += 1 }
            lastClosedGap = g
            justReturned = g >= 1
        }

        // Comebacks: count inactive-runs that are immediately followed (toward
        // today) by an active day within the window.
        var comebacks = 0
        var inRun = false
        // Walk oldest → newest so "followed by active" is natural.
        for f in flags.reversed() {
            if f {
                if inRun { comebacks += 1; inRun = false }
            } else {
                inRun = true
            }
        }

        return RecoveryReading(
            activeToday: activeToday, currentGapDays: currentGap, lastClosedGap: lastClosedGap,
            comebacks: comebacks, activeDays: activeDays, windowDays: window, justReturned: justReturned)
    }

    /// Builds the flags from live stores. A day is "active" if it earned real
    /// momentum, logged focus, or completed a habit.
    @MainActor
    static func reading(life: LifeStore, focus: FocusLog, now: Date = Date(), windowDays: Int = 30) -> RecoveryReading {
        let flags: [Bool] = (0..<windowDays).map { off in
            let day = now.adding(days: -off)
            if MomentumStore.shared.score(on: day) >= 20 { return true }
            if !focus.sessions(on: day).isEmpty { return true }
            if life.activeHabits.contains(where: { life.isDone($0, on: day) }) { return true }
            return false
        }
        return reading(activeFlags: flags)
    }
}
