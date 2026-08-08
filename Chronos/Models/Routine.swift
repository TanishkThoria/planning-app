import Foundation
import Combine

/// A single step in a guided routine — a named micro-task. Usually timed (it
/// counts down), but a step can be marked `untimed` for things that aren't about
/// a clock — "no phone", "make the bed" — where you just tap Done to move on.
struct RoutineStep: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var seconds: Int
    /// A check-off step with no countdown. Optional/defaulted so older saved
    /// routines decode unchanged.
    var untimed: Bool = false
    var minutes: Int { max(1, seconds / 60) }
}

/// An ordered routine you can run hands-free — Routinery's core idea, built for
/// time-blindness: each step counts down and (optionally) is announced aloud so
/// you never have to look at the screen or decide what's next.
struct Routine: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var emoji: String
    var steps: [RoutineStep]
    /// When true, this is a routine you're *establishing*: it's tracked like a
    /// habit — you log it each day, build a streak, and (optionally) get a
    /// reminder. Optional/defaulted so older saved routines decode unchanged.
    var tracked: Bool = false
    var cadence: HabitCadence = .daily
    var reminderMinutes: Int?

    /// Total timed duration — untimed check-off steps don't add clock time.
    var totalSeconds: Int { steps.filter { !$0.untimed }.reduce(0) { $0 + $1.seconds } }
    var totalMinutes: Int { max(1, totalSeconds / 60) }
    var hasUntimedSteps: Bool { steps.contains { $0.untimed } }

    /// Wall-clock minutes to reserve when laying the routine on the calendar —
    /// every step counts (each at least a minute), including check-off steps.
    var plannedMinutes: Int { max(1, steps.reduce(0) { $0 + max(1, $1.minutes) }) }

    /// Is this tracked routine expected on the given weekday? Routines only use
    /// the simple cadences (daily / weekdays / weekly); the richer habit-only
    /// cadences fall back to "every day" here.
    func isDue(on day: Date) -> Bool {
        switch cadence {
        case .weekdays:
            let wd = Calendar.current.component(.weekday, from: day)
            return (2...6).contains(wd)
        case .daily, .weekly, .everyNDays, .customDays, .monthly:
            return true
        }
    }
}

/// Persists the user's routines (defaults seeded on first run) to UserDefaults.
@MainActor
final class RoutineStore: ObservableObject {
    static let shared = RoutineStore()

    @Published var routines: [Routine] { didSet { save() } }
    /// "routineID#yyyy-MM-dd" days a tracked routine was completed.
    @Published private(set) var completions: Set<String> { didSet { saveCompletions() } }

    private static let key = "chronos.routines.v1"
    private static let completionsKey = "chronos.routines.completions.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Routine].self, from: data) {
            routines = decoded
        } else {
            routines = Self.defaults
        }
        if let data = UserDefaults.standard.data(forKey: Self.completionsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            completions = Set(decoded)
        } else {
            completions = []
        }
        NotificationCenter.default.addObserver(
            forName: .chronosCloudDidPull, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private func reload() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Routine].self, from: data) {
            routines = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.completionsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            completions = Set(decoded)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func saveCompletions() {
        if let data = try? JSONEncoder().encode(Array(completions)) {
            UserDefaults.standard.set(data, forKey: Self.completionsKey)
        }
    }

    // MARK: Tracking (completions + streaks, for `tracked` routines)

    var trackedRoutines: [Routine] { routines.filter(\.tracked) }

    private func token(_ id: UUID, _ day: Date) -> String { "\(id)#\(Fmt.dayKey(day))" }

    func isDone(_ routine: Routine, on day: Date) -> Bool {
        completions.contains(token(routine.id, day))
    }
    /// Mark done for the day (used when a run finishes); idempotent.
    func markDone(_ routine: Routine, on day: Date = Date()) {
        completions.insert(token(routine.id, day))
    }
    func toggle(_ routine: Routine, on day: Date) {
        let t = token(routine.id, day)
        if completions.contains(t) { completions.remove(t) } else { completions.insert(t) }
    }

    /// Consecutive due-days completed, ending today (today-not-yet-done is grace).
    func streak(_ routine: Routine, now: Date = Date()) -> Int {
        var streak = 0
        var cursor = now.startOfDay
        if routine.isDue(on: cursor) && !isDone(routine, on: cursor) { cursor = cursor.adding(days: -1) }
        var guardCount = 0
        while guardCount < 400 {
            guardCount += 1
            if routine.isDue(on: cursor) {
                if isDone(routine, on: cursor) { streak += 1 } else { break }
            }
            cursor = cursor.adding(days: -1)
        }
        return streak
    }

    func completionCount(_ routine: Routine, inLast days: Int, now: Date = Date()) -> Int {
        (0..<days).reduce(0) { $0 + (isDone(routine, on: now.adding(days: -$1)) ? 1 : 0) }
    }

    func add(_ routine: Routine) { routines.append(routine) }
    func update(_ routine: Routine) {
        if let i = routines.firstIndex(where: { $0.id == routine.id }) { routines[i] = routine }
    }
    /// Update in place if it exists, otherwise append.
    func upsert(_ routine: Routine) {
        if let i = routines.firstIndex(where: { $0.id == routine.id }) { routines[i] = routine }
        else { routines.append(routine) }
    }
    func delete(_ routine: Routine) {
        routines.removeAll { $0.id == routine.id }
        completions = completions.filter { !$0.hasPrefix("\(routine.id)#") }
    }

    private static func step(_ title: String, _ minutes: Int) -> RoutineStep {
        RoutineStep(title: title, seconds: minutes * 60)
    }

    static let defaults: [Routine] = [
        Routine(name: "Morning Launch", emoji: "☀️", steps: [
            step("Wake up & water", 2),
            RoutineStep(title: "No phone", seconds: 60, untimed: true),
            step("Wash your face", 3),
            step("Healthy breakfast", 15),
            step("Shower", 10),
            step("Get dressed & go", 5),
        ]),
        Routine(name: "Study Sprint", emoji: "📚", steps: [
            step("Clear your desk", 2),
            step("Phone on Do Not Disturb", 1),
            step("Deep focus", 25),
            step("Stretch & water", 5),
        ]),
        Routine(name: "Wind Down", emoji: "🌙", steps: [
            step("Tidy your space", 5),
            step("Tomorrow's top 3", 3),
            step("Screens off", 1),
            step("Read", 15),
        ]),
    ]
}
