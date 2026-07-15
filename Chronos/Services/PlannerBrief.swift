import SwiftUI

/// Actions the Coach / briefing can trigger. Shared by both the chat and the
/// non-AI briefing screen.
enum QuickAction {
    case planDay, planWeek, reflow, review, focus, overdueSweep, openStats, recalibrate
    case deadlines, availability
}

@MainActor
func performCoachAction(_ action: QuickAction, on model: AppModel) {
    switch action {
    case .planDay: model.planDayPresented = true
    case .planWeek: model.planWeekPresented = true
    case .reflow: model.reflowPresented = true
    case .review: model.reviewPresented = true
    case .focus: model.startFocus(taskID: nil, title: "Focus")
    case .overdueSweep: model.overdueSweepPresented = true
    case .openStats: model.statsPresented = true
    case .recalibrate: model.calibrationPresented = true
    case .deadlines: model.deadlinePlanPresented = true
    case .availability: model.availabilityPresented = true
    }
}

/// Everything the brief needs, gathered by whichever screen is showing.
struct PlannerContext {
    var now: Date
    var todayBlocks: [TimeBlock]          // timed, sorted by start
    var tasks: [TaskItem]
    var taskLookup: (String) -> TaskItem?
    var workStartMinutes: Int
    var workEndMinutes: Int
    var stats: StatsEngine.Stats
}

/// Turns live data into warm, specific, non-canned briefing content. This is
/// the single source of truth so the chat's fallback answers and the briefing
/// cards always say the same thing.
@MainActor
enum PlannerBrief {

    struct Item: Identifiable {
        let id = UUID()
        var icon: String
        var tint: Color
        var title: String
        var message: String
        var action: QuickAction?
        var actionLabel: String?
    }

    // MARK: Greeting

    static func greeting(_ ctx: PlannerContext) -> String {
        let hour = Calendar.current.component(.hour, from: ctx.now)
        let lead: String
        switch hour {
        case 5..<12: lead = ["Good morning.", "Morning!", "A fresh day."].randomElement()!
        case 12..<17: lead = ["Good afternoon.", "Afternoon!", "Midday check-in."].randomElement()!
        case 17..<22: lead = ["Good evening.", "Evening!", "Winding down."].randomElement()!
        default: lead = ["Working late?", "Late one tonight."].randomElement()!
        }
        let blocks = ctx.todayBlocks
        let tail: String
        if let current = blocks.first(where: { $0.start <= ctx.now && ctx.now < $0.end }) {
            tail = "You're in \(current.title) until \(Fmt.time.string(from: current.end))."
        } else if let next = blocks.first(where: { $0.start > ctx.now }) {
            tail = "Next up is \(next.title) at \(Fmt.time.string(from: next.start))."
        } else if blocks.isEmpty {
            tail = "Your timeline's a blank canvas so far."
        } else {
            tail = "Your scheduled blocks are done for today."
        }
        return "\(lead) \(tail)"
    }

    // MARK: Focus

    static func focus(_ ctx: PlannerContext) -> Item {
        if let current = ctx.todayBlocks.first(where: { $0.start <= ctx.now && ctx.now < $0.end }) {
            return Item(icon: "scope", tint: Theme.accentColor, title: "Focus right now",
                        message: "Stay with \(current.title) — it runs until \(Fmt.time.string(from: current.end)).",
                        action: .focus, actionLabel: "Start focus timer")
        }
        if let next = ctx.todayBlocks.first(where: { $0.start > ctx.now }) {
            let mins = max(1, Int(next.start.timeIntervalSince(ctx.now) / 60))
            return Item(icon: "clock.badge", tint: Theme.accentColor, title: "Up next",
                        message: "\(next.title) at \(Fmt.time.string(from: next.start)) — about \(Fmt.duration(minutes: mins)) to wrap loose ends or get set up.",
                        action: nil, actionLabel: nil)
        }
        let top = ctx.tasks
            .filter { !$0.isCompleted && !$0.isSubtask }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .first
        if let top {
            return Item(icon: "scope", tint: Theme.accentColor, title: "What to focus on",
                        message: "Nothing's scheduled right now. Your most pressing task is \(top.title) — want to block time for it?",
                        action: .planDay, actionLabel: "Plan my day")
        }
        return Item(icon: "checkmark.seal", tint: Theme.success, title: "You're clear",
                    message: "Nothing scheduled right now — a good moment to breathe or get ahead on tomorrow.",
                    action: nil, actionLabel: nil)
    }

    // MARK: Load

    static func load(_ ctx: PlannerContext) -> Item {
        let planned = ctx.todayBlocks
            .compactMap { $0.clamped(to: ctx.now.startOfDay) }
            .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        let capacity = max(60, ctx.workEndMinutes - ctx.workStartMinutes)
        let ratio = Double(planned) / Double(capacity)
        let dur = Fmt.duration(minutes: planned)
        if ratio >= 0.9 {
            return Item(icon: "gauge.with.dots.needle.100percent", tint: Theme.warning, title: "Today's load",
                        message: "You've booked \(dur) against a \(Fmt.duration(minutes: capacity)) window — that's packed. If anything's optional, reflow to make room to breathe.",
                        action: .reflow, actionLabel: "Reflow today")
        }
        if ratio >= 0.5 {
            return Item(icon: "gauge.with.dots.needle.67percent", tint: Theme.success, title: "Today's load",
                        message: "\(dur) planned today — a solid, focused load with slack to spare. You're in good shape.",
                        action: nil, actionLabel: nil)
        }
        if planned == 0 {
            return Item(icon: "square.dashed", tint: Theme.accentColor, title: "Today's load",
                        message: "Nothing booked yet. Turn your open tasks into real time blocks whenever you're ready.",
                        action: .planDay, actionLabel: "Plan my day")
        }
        return Item(icon: "gauge.with.dots.needle.33percent", tint: Theme.accentColor, title: "Today's load",
                    message: "Only \(dur) planned today — plenty of room to add a deep-work block or pull tomorrow's work forward.",
                    action: .planDay, actionLabel: "Plan my day")
    }

    // MARK: Loose ends (nil when nothing's slipped)

    static func looseEnds(_ ctx: PlannerContext) -> Item? {
        let overdue = ctx.tasks.filter { $0.isOverdue }.count
        let pastIncomplete = ctx.todayBlocks.filter { block in
            guard block.end < ctx.now, let id = block.linkedTaskID else { return false }
            return ctx.taskLookup(id)?.isCompleted == false
        }.count
        if overdue > 0 {
            return Item(icon: "exclamationmark.arrow.circlepath", tint: Theme.danger, title: "Loose ends",
                        message: "You have \(overdue) overdue task\(overdue == 1 ? "" : "s"). Sweep them onto today in one move.",
                        action: .overdueSweep, actionLabel: "Sweep overdue")
        }
        if pastIncomplete > 0 {
            return Item(icon: "questionmark.circle", tint: Theme.warning, title: "Loose ends",
                        message: "\(pastIncomplete) finished block\(pastIncomplete == 1 ? "" : "s") still have open tasks. Review them and reschedule what slipped.",
                        action: .review, actionLabel: "Review day")
        }
        return nil
    }

    // MARK: Week

    static func week(_ ctx: PlannerContext) -> Item {
        let pct = Int((ctx.stats.completionRate * 100).rounded())
        return Item(icon: "chart.line.uptrend.xyaxis", tint: Theme.accentColor, title: "This week",
                    message: "\(Fmt.duration(minutes: ctx.stats.focusMinutes)) focused, \(ctx.stats.tasksCompleted) task\(ctx.stats.tasksCompleted == 1 ? "" : "s") done, a \(ctx.stats.streakDays)-day streak, and \(pct)% of due tasks complete.",
                    action: .openStats, actionLabel: "See statistics")
    }
}
