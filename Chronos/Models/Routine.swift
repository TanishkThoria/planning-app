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

    var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }
    var totalMinutes: Int { max(1, totalSeconds / 60) }
}

/// Persists the user's routines (defaults seeded on first run) to UserDefaults.
@MainActor
final class RoutineStore: ObservableObject {
    static let shared = RoutineStore()

    @Published var routines: [Routine] { didSet { save() } }

    private static let key = "chronos.routines.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Routine].self, from: data) {
            routines = decoded
        } else {
            routines = Self.defaults
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
    }

    private func save() {
        if let data = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
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
    func delete(_ routine: Routine) { routines.removeAll { $0.id == routine.id } }

    private static func step(_ title: String, _ minutes: Int) -> RoutineStep {
        RoutineStep(title: title, seconds: minutes * 60)
    }

    static let defaults: [Routine] = [
        Routine(name: "Morning Launch", emoji: "☀️", steps: [
            step("Water & wake up", 2),
            step("Stretch", 3),
            step("Shower", 10),
            step("Get dressed", 5),
            step("Plan today", 5),
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
