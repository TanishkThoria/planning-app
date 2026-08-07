import Foundation

// The identity-aware half of the coach. Where `Coach` reasons about the
// calendar and tasks, `GrowthCoach` reasons about who the user is trying to
// become: which pillars have gone quiet, whether they're planning instead of
// doing, how to reframe a miss, and what patterns they've noted about
// themselves. It speaks the app's core language — evidence and returning, never
// shame — and hands back the same `Coach.Suggestion` type so it merges cleanly.

@MainActor
enum GrowthCoach {
    static func suggestions(life: LifeStore, focus: FocusLog, tasks: [TaskItem],
                            now: Date = Date()) -> [Coach.Suggestion] {
        var out: [Coach.Suggestion] = []

        // 1. Planning addiction — the power-user failure mode.
        let ratio = ActionRatioEngine.reading(meter: PlanningMeter.shared, focus: focus, tasks: tasks)
        if ratio.overPlanning {
            out.append(.init(tone: .warning,
                title: "You've designed enough — time to build",
                detail: ratio.detail, weight: 86,
                action: .focusTimer, actionLabel: "Start a focus block"))
        } else if ratio.churning {
            out.append(.init(tone: .warning,
                title: "Lots of reshuffling lately",
                detail: ratio.detail, weight: 73,
                action: .focusTimer, actionLabel: "Just start the smallest one"))
        }

        // 2. A pillar that's gone quiet. Build the SAME evidence inputs the
        // Future Self screen uses (completed-task categories + non-time goal
        // progress) so the coach never contradicts what the user sees there.
        if !life.activePillars.isEmpty {
            let since = now.adding(days: -13).startOfDay
            let taskEvidence: [TaskEvidence] = tasks.compactMap { t in
                guard t.isCompleted, let d = t.completionDate, d >= since else { return nil }
                return TaskEvidence(date: d, category: TagStore.shared.category(for: t), title: t.title)
            }
            var goalProgress: [UUID: Double] = [:]
            for g in life.activeGoals {
                switch g.kind {
                case .milestone: goalProgress[g.id] = g.milestoneProgress
                case .habitLink:
                    if let hid = g.linkedHabitID, let h = life.habits.first(where: { $0.id == hid }) {
                        goalProgress[g.id] = min(1, Double(life.completionCount(h, inLast: 7)) / 7)
                    }
                case .time: break   // needs the calendar, which the coach can't see here
                }
            }
            let readings = EvidenceEngine.readings(
                pillars: life.activePillars, life: life, focus: focus,
                taskEvidence: taskEvidence, goalProgress: goalProgress)
            if let quiet = readings
                .filter({ $0.trend == .quiet || $0.score < 0.2 })
                .min(by: { $0.score < $1.score }) {
                out.append(.init(tone: .neutral,
                    title: "\(quiet.pillar.name) has gone quiet",
                    detail: "You haven't built much evidence for becoming \(quiet.pillar.name.lowercased()) lately. One small proof today restarts the momentum — it doesn't have to be big.",
                    weight: 66, action: .openFutureSelf, actionLabel: "Open Future Self"))
            }
        }

        // 3. Recovery reframe — celebrate the return, soften the gap.
        let recovery = RecoveryEngine.reading(life: life, focus: focus)
        if recovery.justReturned {
            out.append(.init(tone: .positive,
                title: "You came back",
                detail: recovery.message, weight: 71,
                action: .dayIntent, actionLabel: "Set today's minimum"))
        } else if recovery.currentGapDays >= 2 {
            out.append(.init(tone: .neutral,
                title: "Ready when you are",
                detail: recovery.message, weight: 69,
                action: .focusTimer, actionLabel: "Start with 10 minutes"))
        }

        // 4. Anti-perfectionism reframe on the best-kept habit.
        if let habit = life.activeHabits.max(by: {
            life.completionCount($0, inLast: 28) < life.completionCount($1, inLast: 28)
        }) {
            let kept = life.completionCount(habit, inLast: 28)
            if kept >= 18, habit.isDue(on: now), !life.isDone(habit, on: now) {
                out.append(.init(tone: .positive,
                    title: "One miss won't undo this",
                    detail: "You kept \"\(habit.title)\" \(kept) of the last 28 days. A single missed day doesn't change the pattern — just don't miss twice.",
                    weight: 57, action: .openGrow, actionLabel: "Open habits"))
            }
        }

        // 5. Surface a self-pattern from My Manual when work is stuck.
        let overdue = tasks.filter { !$0.isCompleted && $0.isOverdue }.count
        if overdue >= 3, let pattern = life.notes(.pattern).first {
            let detail: String
            if let solution = life.notes(.solution).first {
                detail = "You noted a pattern: \"\(pattern.text)\" And a fix that works for you: \"\(solution.text)\" Try it on the oldest task."
            } else {
                detail = "You noted a pattern about yourself: \"\(pattern.text)\" Name the first physical step for the oldest task and start there."
            }
            out.append(.init(tone: .neutral, title: "A pattern you spotted",
                detail: detail, weight: 64,
                action: .overdueSweep, actionLabel: "Clear the backlog"))
        }

        return out
    }
}
