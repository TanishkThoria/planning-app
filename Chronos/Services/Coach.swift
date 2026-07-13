import SwiftUI

/// The on-device coach. Reads your real stats + calibration profile and
/// produces plain-language, prioritized suggestions for tightening up your
/// planning. Entirely heuristic and offline — no data leaves the device.
/// The engine is deliberately structured as (signal → insight) rules so a
/// richer natural-language model could be layered on top later without
/// changing any callers.
enum Coach {

    enum Tone {
        case positive, neutral, warning

        var color: Color {
            switch self {
            case .positive: return Theme.success
            case .neutral: return Theme.textSecondary
            case .warning: return Theme.warning
            }
        }

        var icon: String {
            switch self {
            case .positive: return "checkmark.seal.fill"
            case .neutral: return "lightbulb"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }

    /// An action the user can take straight from a suggestion, so the coach
    /// is a doorway to doing the thing, not just advice.
    enum Action {
        case recalibrate, planDay, planWeek, reflow, openGrow, addHabit
        case morningRitual, eveningRitual, focusTimer, overdueSweep
    }

    struct Suggestion: Identifiable {
        let id = UUID()
        let tone: Tone
        let title: String
        let detail: String
        /// Sort weight — higher surfaces first.
        let weight: Int
        var action: Action? = nil
        var actionLabel: String? = nil
    }

    /// Personal signals drawn from the lifestyle layer + focus log, so the
    /// coach can reason about habits, mood/energy, and when you actually do
    /// your best work — not just the calendar.
    struct Signals {
        var habitCount = 0
        var bestHabitStreak = 0
        var habitConsistency: Double = 0     // 0…1 over the last 7 due-days
        var journalStreak = 0
        var avgEnergy7: Double?              // 1…5, last 7 journal days
        var avgMood7: Double?                // 1…5
        /// Focus period where the most timer minutes actually landed.
        var observedFocus: FocusPeriod?
        var focusSampleMinutes = 0
    }

    static func suggestions(
        stats: StatsEngine.Stats,
        profile: PlannerProfile,
        tasks: [TaskItem],
        signals: Signals = Signals()
    ) -> [Suggestion] {
        var out: [Suggestion] = []

        // MARK: Personal signals (habits, energy, focus timing)

        // Observed vs. declared focus window — the app *noticing* your rhythm.
        if profile.isCalibrated, signals.focusSampleMinutes >= 120,
           let observed = signals.observedFocus, observed != profile.focus {
            out.append(.init(
                tone: .neutral,
                title: "You focus best in the \(observed.rawValue.lowercased())",
                detail: "Most of your timed work lands in the \(observed.rawValue.lowercased()), but your focus window is set to \(profile.focus.rawValue.lowercased()). Recalibrate and Plan My Day will aim deep work where you're actually sharpest.",
                weight: 86,
                action: .recalibrate, actionLabel: "Recalibrate"
            ))
        }

        // Habit consistency (Atomic Habits: make it easy / the 2-minute rule).
        if signals.habitCount >= 2 {
            let pct = Int((signals.habitConsistency * 100).rounded())
            if signals.habitConsistency < 0.5 {
                out.append(.init(
                    tone: .warning,
                    title: "Habits are slipping (\(pct)%)",
                    detail: "You're completing under half your habits. Shrink them until they're almost too easy — a two-minute version you can't say no to. Consistency first, size later.",
                    weight: 80,
                    action: .openGrow, actionLabel: "Review Habits"
                ))
            } else if signals.habitConsistency >= 0.85 {
                out.append(.init(
                    tone: .positive,
                    title: "Rock-solid habits (\(pct)%)",
                    detail: "You're showing up almost every day. This is where real change compounds. Consider stacking one small new habit onto an existing one.",
                    weight: 58
                ))
            }
        }
        if signals.bestHabitStreak >= 21 {
            out.append(.init(
                tone: .positive,
                title: "\(signals.bestHabitStreak)-day habit streak",
                detail: "Three weeks-plus of consistency — this is becoming part of who you are, not just something you do.",
                weight: 62
            ))
        }

        // Energy-aware load management.
        if let energy = signals.avgEnergy7, energy > 0 {
            if energy <= 2.2 {
                out.append(.init(
                    tone: .warning,
                    title: "Your energy has been low",
                    detail: "The last week's check-ins average low energy. Protect sleep, lighten the plan, and put one genuinely restorative block on the calendar — rest is part of the system, not a reward for finishing it.",
                    weight: 84
                ))
            } else if energy >= 4.2 {
                out.append(.init(
                    tone: .positive,
                    title: "You've been running strong",
                    detail: "High energy all week. A good moment to take a swing at that ambitious goal you've been circling.",
                    weight: 46
                ))
            }
        }

        // Reflection habit.
        if signals.journalStreak == 0 && stats.blockCount >= 3 {
            out.append(.init(
                tone: .neutral,
                title: "Try an evening reflection",
                detail: "Two minutes naming what went well and setting tomorrow's intention meaningfully lifts follow-through — and it's the fastest way to make this coach smarter about you.",
                weight: 52,
                action: .eveningRitual, actionLabel: "Reflect Now"
            ))
        }

        // Plan adherence
        if stats.adherenceEligible >= 3 {
            let pct = Int((stats.adherenceRate * 100).rounded())
            if stats.adherenceRate < 0.5 {
                out.append(.init(
                    tone: .warning,
                    title: "You finish \(pct)% of what you plan",
                    detail: "Fewer than half of your timeblocked tasks got done. Try planning 30–40% fewer blocks per day, or shorten estimates so each block feels achievable.",
                    weight: 95
                ))
            } else if stats.adherenceRate < 0.75 {
                out.append(.init(
                    tone: .neutral,
                    title: "Plan adherence: \(pct)%",
                    detail: "Solid, with room to grow. Protecting a buffer between blocks tends to push this higher — you're at \(profile.flexibility.rawValue.lowercased()) flexibility now.",
                    weight: 70
                ))
            } else {
                out.append(.init(
                    tone: .positive,
                    title: "Plan adherence: \(pct)%",
                    detail: "You're following through on the vast majority of your plan. Consider adding a stretch block — you have the discipline for it.",
                    weight: 55
                ))
            }
        }

        // On-time completion
        if stats.datedCompleted >= 3 {
            let pct = Int((stats.onTimeRate * 100).rounded())
            if stats.onTimeRate < 0.6 {
                out.append(.init(
                    tone: .warning,
                    title: "\(pct)% of dated tasks finished on time",
                    detail: "Deadlines are slipping. The Matrix view can help you triage — or schedule due-soon tasks into your \(profile.focus.rawValue.lowercased()) focus window earlier in the day.",
                    weight: 90
                ))
            } else if stats.onTimeRate >= 0.85 {
                out.append(.init(
                    tone: .positive,
                    title: "\(pct)% on-time completion",
                    detail: "You reliably hit your deadlines. Nicely done.",
                    weight: 40
                ))
            }
        }

        // Overdue backlog
        if stats.overdueNow >= 5 {
            out.append(.init(
                tone: .warning,
                title: "\(stats.overdueNow) tasks are overdue",
                detail: "That's a lot of open loops. Sweep them across the next few days' free time in one move, then bulk-move whatever no longer matters from the Matrix.",
                weight: 88,
                action: .overdueSweep, actionLabel: "Clear Overdue"
            ))
        }

        // Deep-work placement vs focus window
        if stats.deepMinutes > 0 {
            let deepHours = stats.deepMinutes / 60
            out.append(.init(
                tone: .neutral,
                title: "\(Fmt.duration(minutes: stats.deepMinutes)) of deep work logged",
                detail: "Your focus window is set to \(profile.focus.rawValue.lowercased()). Tag your hardest tasks \u{201C}Deep\u{201D} and Plan My Day will aim them there automatically\(deepHours >= 10 ? " — you're clearly putting in the hours." : ".")",
                weight: 50
            ))
        }

        // Focus timer usage
        if stats.focusSessions == 0 && stats.blockCount >= 3 {
            out.append(.init(
                tone: .neutral,
                title: "Try the focus timer",
                detail: "You're planning blocks but not timing your work. Start a Pomodoro from any block to stay on track and unlock deeper stats on where your hours actually go.",
                weight: 45,
                action: .focusTimer, actionLabel: "Start Timer"
            ))
        } else if stats.focusMinutes > 0 {
            out.append(.init(
                tone: .positive,
                title: "\(Fmt.duration(minutes: stats.focusMinutes)) of focused time",
                detail: "Logged across \(stats.focusSessions) session\(stats.focusSessions == 1 ? "" : "s"). Timed work is the most reliable signal of a productive week.",
                weight: 42
            ))
        }

        // Streak
        if stats.streakDays >= 3 {
            out.append(.init(
                tone: .positive,
                title: "\(stats.streakDays)-day streak",
                detail: "You've completed at least one task every day for \(stats.streakDays) days running. Momentum is on your side.",
                weight: 60
            ))
        }

        // Over-packed days relative to waking hours
        if profile.isCalibrated, stats.avgPlannedPerActiveDay > 0 {
            let wakingHours = max(profile.bedMinutes - profile.wakeMinutes, 60) / 60
            if stats.avgPlannedPerActiveDay / 60 >= Int(Double(wakingHours) * 0.7) {
                out.append(.init(
                    tone: .warning,
                    title: "Your days are packed",
                    detail: "You're averaging \(Fmt.duration(minutes: stats.avgPlannedPerActiveDay)) of blocks on active days — most of your waking hours. Leave some white space for the unexpected, or things will keep slipping.",
                    weight: 78
                ))
            }
        }

        // Not calibrated
        if !profile.isCalibrated {
            out.append(.init(
                tone: .neutral,
                title: "Calibrate for smarter plans",
                detail: "Tell Chronos your sleep, meals, routines and focus window (Settings → Calibrate) and every auto-plan will schedule around your real life.",
                weight: 100,
                action: .recalibrate, actionLabel: "Calibrate"
            ))
        }

        // Fallback when there's little data
        if out.isEmpty {
            out.append(.init(
                tone: .neutral,
                title: "Not enough data yet",
                detail: "Plan a few days, complete some tasks, and time a work session or two. Your coach gets sharper as it learns your patterns.",
                weight: 10
            ))
        }

        return out.sorted { $0.weight > $1.weight }
    }
}
