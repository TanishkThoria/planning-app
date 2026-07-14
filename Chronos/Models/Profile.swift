import Foundation
import SwiftUI

/// The personalization layer: everything the calibration wizard learns
/// about how you live — sleep, meals, routines, when you focus best, and
/// how much Chronos is allowed to bend those rhythms when it plans for you.
/// Stored locally (UserDefaults, JSON); it never leaves the device.

struct MealWindow: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var startMinutes: Int
    var durationMinutes: Int
    var enabled: Bool = true
    /// When on, Plan My Day offers to put this meal on the calendar.
    var autoBlock: Bool = false
}

struct RoutineItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var startMinutes: Int
    var durationMinutes: Int
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday).
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var autoBlock: Bool = false
}

enum FocusPeriod: String, Codable, CaseIterable, Identifiable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .morning: return "Deep work lands before lunch"
        case .afternoon: return "Deep work lands midday"
        case .evening: return "Deep work lands after 5"
        }
    }

    /// Minutes-of-day window the scheduler prefers for high-priority work.
    var windowMinutes: (start: Int, end: Int) {
        switch self {
        case .morning: return (6 * 60, 12 * 60)
        case .afternoon: return (12 * 60, 17 * 60)
        case .evening: return (17 * 60, 22 * 60)
        }
    }
}

enum Flexibility: String, Codable, CaseIterable, Identifiable {
    case strict = "Strict"
    case balanced = "Balanced"
    case flexible = "Flexible"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .strict: return "Meals and routines are untouchable; extra breathing room between blocks"
        case .balanced: return "Meals and routines are protected, scheduling stays within work hours"
        case .flexible: return "Anything between wake-up and bedtime is fair game"
        }
    }

    /// Should meal/routine windows be treated as busy time?
    var protectsRoutines: Bool { self != .flexible }

    /// Extra padding (minutes) enforced between auto-scheduled blocks.
    var minimumGapMinutes: Int {
        switch self {
        case .strict: return 10
        case .balanced: return 5
        case .flexible: return 0
        }
    }
}

struct PlannerProfile: Codable {
    var isCalibrated: Bool = false
    var wakeMinutes: Int = 7 * 60
    var bedMinutes: Int = 23 * 60
    var meals: [MealWindow] = PlannerProfile.defaultMeals
    var routines: [RoutineItem] = []
    var focus: FocusPeriod = .morning
    var flexibility: Flexibility = .balanced

    static let defaultMeals: [MealWindow] = [
        MealWindow(name: "Breakfast", startMinutes: 8 * 60, durationMinutes: 30),
        MealWindow(name: "Lunch", startMinutes: 12 * 60 + 30, durationMinutes: 45),
        MealWindow(name: "Dinner", startMinutes: 19 * 60, durationMinutes: 60),
    ]

    /// A named window on a concrete day (used for busy time and for
    /// Plan My Day's routine-block proposals).
    struct DayWindow: Identifiable, Hashable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let autoBlock: Bool
    }

    /// All enabled meal + routine windows that apply to `day`.
    func routineWindows(on day: Date) -> [DayWindow] {
        guard isCalibrated else { return [] }
        var windows: [DayWindow] = meals.filter(\.enabled).map { meal in
            DayWindow(
                id: "meal-\(meal.id.uuidString)",
                title: meal.name,
                start: day.at(minutes: meal.startMinutes),
                end: day.at(minutes: meal.startMinutes + meal.durationMinutes),
                autoBlock: meal.autoBlock
            )
        }
        let weekday = Calendar.current.component(.weekday, from: day)
        windows += routines.filter { $0.weekdays.contains(weekday) }.map { routine in
            DayWindow(
                id: "routine-\(routine.id.uuidString)",
                title: routine.name,
                start: day.at(minutes: routine.startMinutes),
                end: day.at(minutes: routine.startMinutes + routine.durationMinutes),
                autoBlock: routine.autoBlock
            )
        }
        return windows.sorted { $0.start < $1.start }
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    private static let key = "chronos.plannerProfile"

    @Published var profile: PlannerProfile {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(PlannerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = PlannerProfile()
        }
        NotificationCenter.default.addObserver(
            forName: .chronosCloudDidPull, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadFromDefaults() }
        }
    }

    /// Re-read from UserDefaults after iCloud sync writes a newer copy.
    func reloadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(PlannerProfile.self, from: data) else { return }
        profile = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
