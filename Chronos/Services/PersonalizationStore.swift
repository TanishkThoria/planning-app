import SwiftUI
import Combine

/// Holds the first-run questionnaire answers and the resulting modular layout —
/// which optional modules are promoted to primary tabs vs. tucked into "More".
/// Persisted locally (and mirrored via Chronos+ sync). Everything degrades
/// gracefully: with no survey done, the layout is the historical default
/// (Grow + Insights primary), so nothing changes for people who skip it.
@MainActor
final class PersonalizationStore: ObservableObject {
    static let shared = PersonalizationStore()

    @Published var role: UserRole?
    @Published var goals: Set<UserGoal> = []
    /// Ordered optional modules the user has promoted to primary tabs.
    @Published private(set) var primaryModules: [PersonalModule] = [.grow, .insights]
    @Published private(set) var hasCompletedSurvey = false

    /// How many optional modules can sit on the iPhone tab bar alongside the
    /// three core tabs before things get cramped (3 core + 2 + More = 6).
    static let maxPrimaryOnPhone = 2

    private struct Payload: Codable {
        var role: UserRole?
        var goals: [UserGoal]
        var primary: [PersonalModule]
        var completed: Bool
    }

    private static let key = "chronos.personalization.v1"

    private init() {
        load()
        NotificationCenter.default.addObserver(
            forName: .chronosCloudDidPull, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        role = payload.role
        goals = Set(payload.goals)
        primaryModules = payload.primary
        hasCompletedSurvey = payload.completed
    }

    private func save() {
        let payload = Payload(role: role, goals: Array(goals), primary: primaryModules, completed: hasCompletedSurvey)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: Derivation

    /// The modules the current goals most strongly point to, ranked by how many
    /// selected goals nominate each. Falls back to the sensible default so the
    /// layout is never empty.
    func recommendedModules() -> [PersonalModule] { Self.recommend(for: goals) }

    /// Rank the optional modules for a goal set — usable before the survey is
    /// saved (e.g. the live preview) — highest first, sensible default if empty.
    nonisolated static func recommend(for goals: Set<UserGoal>) -> [PersonalModule] {
        var score: [PersonalModule: Int] = [:]
        for goal in goals {
            for module in goal.suggests { score[module, default: 0] += 1 }
        }
        func order(_ m: PersonalModule) -> Int {
            switch m {
            case .grow: return 3
            case .insights: return 2
            case .coach: return 1
            }
        }
        let ranked = PersonalModule.allCases
            .filter { score[$0, default: 0] > 0 }
            .sorted { (score[$0] ?? 0, order($0)) > (score[$1] ?? 0, order($1)) }
        return ranked.isEmpty ? [.grow, .insights] : ranked
    }

    // MARK: Mutations

    /// Save the survey and adopt its recommendation as the layout.
    func completeSurvey(role: UserRole?, goals: Set<UserGoal>) {
        self.role = role
        self.goals = goals
        self.primaryModules = recommendedModules()
        self.hasCompletedSurvey = true
        save()
    }

    func isPrimary(_ module: PersonalModule) -> Bool { primaryModules.contains(module) }

    /// Toggle a module between primary (a tab) and secondary (in More).
    func togglePrimary(_ module: PersonalModule) {
        if let idx = primaryModules.firstIndex(of: module) {
            primaryModules.remove(at: idx)
        } else {
            primaryModules.append(module)
        }
        save()
    }

    func setPrimary(_ modules: [PersonalModule]) {
        primaryModules = modules
        save()
    }

    /// Mark the survey seen without changing anything (used when it's skipped).
    func markSeen() {
        hasCompletedSurvey = true
        save()
    }

    // MARK: Layout queries (consumed by the navigation)

    /// Optional modules shown as primary tabs, in order. Coach only counts when
    /// the on-device model is actually available and the user hasn't hidden it.
    func primaryScreens(coachAvailable: Bool) -> [AppModel.Screen] {
        primaryModules
            .filter { $0 != .coach || coachAvailable }
            .map(\.screen)
    }

    /// Optional modules NOT promoted — they live in the More tab.
    func secondaryScreens(coachAvailable: Bool) -> [AppModel.Screen] {
        PersonalModule.allCases
            .filter { !primaryModules.contains($0) }
            .filter { $0 != .coach || coachAvailable }
            .map(\.screen)
    }
}
