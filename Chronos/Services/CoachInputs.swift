import Foundation

/// Builds the behavioural `Coach.Signals` from the lifestyle + focus layers.
/// Shared by the Coach tab and the Statistics screen so the two never drift.
enum CoachInputs {
    @MainActor
    static func signals(life: LifeStore, focusLog: FocusLog, now: Date = Date()) -> Coach.Signals {
        var s = Coach.Signals()
        let habits = life.activeHabits
        s.habitCount = habits.count
        s.bestHabitStreak = habits.map { life.streak($0) }.max() ?? 0

        // Habit consistency: completed ÷ due over the last 7 days.
        var due = 0, done = 0
        for offset in 0..<7 {
            let day = now.adding(days: -offset)
            for habit in habits where habit.isDue(on: day) {
                due += 1
                if life.isDone(habit, on: day) { done += 1 }
            }
        }
        s.habitConsistency = due == 0 ? 0 : Double(done) / Double(due)

        // Where timed focus actually lands, bucketed by period.
        var byPeriod: [FocusPeriod: Int] = [:]
        for session in focusLog.sessions(inLast: 21) {
            let hour = Calendar.current.component(.hour, from: session.start)
            let period: FocusPeriod = hour < 12 ? .morning : (hour < 17 ? .afternoon : .evening)
            byPeriod[period, default: 0] += session.actualMinutes
            s.focusSampleMinutes += session.actualMinutes
        }
        s.observedFocus = byPeriod.max { $0.value < $1.value }?.key
        return s
    }
}
