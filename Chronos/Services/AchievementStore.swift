import SwiftUI

/// One thing worth celebrating — an unlocked achievement, a level-up, or a
/// momentum milestone. Drives the full-screen celebration popup.
struct Celebration: Identifiable, Equatable {
    enum Kind { case achievement, levelUp, milestone, challenge }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let icon: String
    let colorHex: UInt32
    var color: Color { Color(hex: colorHex) }
    var eyebrow: String {
        switch kind {
        case .achievement: return "Achievement unlocked"
        case .levelUp: return "Level up"
        case .milestone: return "Milestone"
        case .challenge: return "Challenge complete"
        }
    }

    init(challengeTitle: String, xp: Int, icon: String, colorHex: UInt32) {
        id = "chal-\(challengeTitle)-\(xp)"
        kind = .challenge
        title = challengeTitle
        subtitle = "+\(xp) XP earned"
        self.icon = icon
        self.colorHex = colorHex
    }

    init(_ achievement: Achievement) {
        id = "achv-\(achievement.id)"
        kind = .achievement
        title = achievement.title
        subtitle = achievement.detail
        icon = achievement.icon
        colorHex = achievement.tier.colorHex
    }

    init(levelUp level: Int, title levelTitle: String) {
        id = "level-\(level)"
        kind = .levelUp
        title = "Level \(level)"
        subtitle = levelTitle
        icon = "bolt.fill"
        colorHex = 0x7C8CF8
    }

    init(milestone id: String, title: String, subtitle: String, icon: String, colorHex: UInt32) {
        self.id = "ms-\(id)"
        kind = .milestone
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.colorHex = colorHex
    }
}

/// Tracks which achievements and levels have already been celebrated, and holds
/// a queue of celebrations for the UI to pop one at a time. On first run it
/// silently baselines whatever is already unlocked, so upgrading doesn't dump a
/// pile of old badges on screen — only genuinely new wins celebrate.
@MainActor
final class AchievementStore: ObservableObject {
    static let shared = AchievementStore()

    /// The next celebration to show (nil = nothing pending).
    @Published private(set) var queue: [Celebration] = []

    private var celebrated: Set<String> = []
    private var baselined = false
    private var lastLevel = 0
    private var celebratedMilestones: Set<String> = []

    private static let celebratedKey = "chronos.achv.celebrated"
    private static let baselineKey = "chronos.achv.baselined"
    private static let levelKey = "chronos.achv.level"
    private static let milestonesKey = "chronos.achv.milestones"

    private init() {
        celebrated = Set(UserDefaults.standard.stringArray(forKey: Self.celebratedKey) ?? [])
        baselined = UserDefaults.standard.bool(forKey: Self.baselineKey)
        lastLevel = UserDefaults.standard.integer(forKey: Self.levelKey)
        celebratedMilestones = Set(UserDefaults.standard.stringArray(forKey: Self.milestonesKey) ?? [])
    }

    private func save() {
        UserDefaults.standard.set(Array(celebrated), forKey: Self.celebratedKey)
        UserDefaults.standard.set(baselined, forKey: Self.baselineKey)
        UserDefaults.standard.set(lastLevel, forKey: Self.levelKey)
        UserDefaults.standard.set(Array(celebratedMilestones), forKey: Self.milestonesKey)
    }

    var current: Celebration? { queue.first }

    func dismissCurrent() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
    }

    /// Enqueue a celebration directly (the caller owns de-duplication).
    func enqueue(_ celebration: Celebration) {
        queue.append(celebration)
    }

    /// Check the freshly-computed achievements; enqueue any newly unlocked.
    func register(_ achievements: [Achievement]) {
        let unlockedIDs = achievements.filter(\.unlocked).map(\.id)
        if !baselined {
            celebrated.formUnion(unlockedIDs)
            baselined = true
            save()
            return
        }
        let fresh = achievements.filter { $0.unlocked && !celebrated.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for a in fresh { celebrated.insert(a.id) }
        // Celebrate the rarer tiers last so the gold badge is the one you land on.
        let ordered = fresh.sorted { tierRank($0.tier) < tierRank($1.tier) }
        queue.append(contentsOf: ordered.map(Celebration.init))
        save()
    }

    private func tierRank(_ tier: AchievementTier) -> Int {
        switch tier { case .bronze: return 0; case .silver: return 1; case .gold: return 2 }
    }

    /// Celebrate each new momentum level reached since last time.
    func registerLevel(_ level: Int, title: String) {
        if lastLevel == 0 { lastLevel = max(1, level); save(); return }
        guard level > lastLevel else { return }
        for lv in (lastLevel + 1)...level {
            queue.append(Celebration(levelUp: lv, title: MomentumStore.levelTitle(for: lv)))
        }
        lastLevel = level
        save()
    }

    /// Celebrate a one-off milestone (e.g. a perfect day) at most once.
    func registerMilestone(id: String, title: String, subtitle: String, icon: String, colorHex: UInt32) {
        guard baselined, !celebratedMilestones.contains(id) else {
            if !baselined { celebratedMilestones.insert(id); save() }
            return
        }
        celebratedMilestones.insert(id)
        queue.append(Celebration(milestone: id, title: title, subtitle: subtitle, icon: icon, colorHex: colorHex))
        save()
    }
}
