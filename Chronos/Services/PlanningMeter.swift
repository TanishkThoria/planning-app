import Foundation

// Measures how much time goes into *planning* vs *doing*, so Chronos can catch
// the power-user failure mode: using the planner to procrastinate. Planning time
// is sampled from how long the planning surfaces stay open; execution time comes
// from the focus log. The ratio drives an honest coach nudge — "you've designed
// enough, time to build" — never a punishment.

@MainActor
final class PlanningMeter: ObservableObject {
    static let shared = PlanningMeter()

    private static let secondsKey = "chronos.planning.seconds.v1"   // [dayKey: Int]
    private static let runsKey = "chronos.planning.runs.v1"         // [dayKey: Int]
    /// A single open surface can't count for more than this (guards a sheet left
    /// open in the background from inflating the tally).
    private static let maxSessionSeconds: TimeInterval = 25 * 60

    @Published private(set) var seconds: [String: Int]
    @Published private(set) var runs: [String: Int]
    /// Active planning surfaces → the epoch they opened.
    private var openTags: [String: TimeInterval] = [:]

    private init() {
        seconds = (UserDefaults.standard.dictionary(forKey: Self.secondsKey) as? [String: Int]) ?? [:]
        runs = (UserDefaults.standard.dictionary(forKey: Self.runsKey) as? [String: Int]) ?? [:]
        NotificationCenter.default.addObserver(
            forName: .chronosCloudDidPull, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.reload() } }
    }

    private func reload() {
        seconds = (UserDefaults.standard.dictionary(forKey: Self.secondsKey) as? [String: Int]) ?? [:]
        runs = (UserDefaults.standard.dictionary(forKey: Self.runsKey) as? [String: Int]) ?? [:]
    }

    // MARK: Surface open / close

    /// A planning surface appeared. Safe to call repeatedly.
    func begin(_ tag: String) {
        openTags[tag] = Date().timeIntervalSince1970
    }

    /// A planning surface closed — bank the elapsed time (capped).
    func end(_ tag: String) {
        guard let start = openTags.removeValue(forKey: tag) else { return }
        let elapsed = min(Self.maxSessionSeconds, max(0, Date().timeIntervalSince1970 - start))
        guard elapsed >= 1 else { return }
        let key = Fmt.dayKey(Date())
        seconds[key, default: 0] += Int(elapsed)
        UserDefaults.standard.set(seconds, forKey: Self.secondsKey)
    }

    /// A plan was actually committed (Plan My Day/Week/Deadline applied). Used to
    /// tell "designing" apart from "executing a plan."
    func recordPlanRun() {
        let key = Fmt.dayKey(Date())
        runs[key, default: 0] += 1
        UserDefaults.standard.set(runs, forKey: Self.runsKey)
    }

    // MARK: Rollups

    /// Planning minutes over the trailing `days` days (including today).
    func planningMinutes(inLast days: Int, now: Date = Date()) -> Int {
        totalMinutes(seconds, inLast: days, now: now)
    }
    func planRuns(inLast days: Int, now: Date = Date()) -> Int {
        (0..<days).reduce(0) { $0 + (runs[Fmt.dayKey(now.adding(days: -$1))] ?? 0) }
    }

    private func totalMinutes(_ map: [String: Int], inLast days: Int, now: Date) -> Int {
        let secs = (0..<days).reduce(0) { $0 + (map[Fmt.dayKey(now.adding(days: -$1))] ?? 0) }
        return secs / 60
    }
}

/// The computed planning-vs-execution reading.
struct ActionRatio {
    let planningMinutes: Int
    let executionMinutes: Int
    /// Planning as a share of all deliberate time, 0…1.
    let ratio: Double
    let rescheduleCount: Int      // number of tasks punted 2+ times (real churn)
    let planRuns: Int

    /// Enough signal to judge? (Avoids scolding on a quiet week.)
    var hasSignal: Bool { planningMinutes + executionMinutes >= 30 }
    /// Tilted too far into designing rather than doing.
    var overPlanning: Bool { hasSignal && ratio >= 0.4 }
    /// Several distinct tasks keep slipping — moving work around, not doing it.
    var churning: Bool { rescheduleCount >= 3 }

    var headline: String {
        if overPlanning { return "You've designed enough — time to build" }
        if churning { return "Lots of reshuffling lately" }
        return "Healthy balance of planning and doing"
    }
    var detail: String {
        if overPlanning {
            return "Planning is \(Int((ratio * 100).rounded()))% of your deliberate time this week. Your system is good enough. Your next upgrade is execution — start the smallest block now."
        }
        if churning {
            return "\(rescheduleCount) tasks keep slipping. When something won't stick, the fix is usually a smaller first step, not a better time."
        }
        return "Planning \(Fmt.duration(minutes: planningMinutes)), doing \(Fmt.duration(minutes: executionMinutes)) this week. Keep it up."
    }
}

@MainActor
enum ActionRatioEngine {
    static func reading(meter: PlanningMeter, focus: FocusLog, tasks: [TaskItem],
                        days: Int = 7, now: Date = Date()) -> ActionRatio {
        let planning = meter.planningMinutes(inLast: days, now: now)
        let execution = focus.totalMinutes(inLast: days)
        let total = planning + execution
        let ratio = total <= 0 ? 0 : Double(planning) / Double(total)
        // Real churn = distinct tasks that keep being moved, not one busy backlog.
        let reschedules = tasks.filter { !$0.isCompleted && $0.puntCount >= 2 }.count
        return ActionRatio(planningMinutes: planning, executionMinutes: execution,
                           ratio: ratio, rescheduleCount: reschedules,
                           planRuns: meter.planRuns(inLast: days, now: now))
    }
}
