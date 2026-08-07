import Foundation

// Turns real activity into RPG-style character attributes — Discipline,
// Knowledge, Fitness, Creativity, Relationships, Organization — that level up
// only from evidence (focus time, finished work, showing up), never a slider.
// The character's headline Level/XP stays the app's momentum system; these six
// are its facets, so nothing competes or double-counts.

@MainActor
enum AttributeEngine {

    struct Reading: Identifiable {
        let attribute: Attribute
        let xp: Int
        let level: Int
        let intoLevel: Int          // xp earned inside the current level
        let neededForLevel: Int     // xp span of the current level
        var id: String { attribute.id }
        var progress: Double { neededForLevel <= 0 ? 0 : min(1, Double(intoLevel) / Double(neededForLevel)) }
    }

    /// A sqrt curve: level n starts at 120·(n-1)² xp, so early levels come fast
    /// and later ones ask for more — the classic satisfying ramp.
    static func level(forXP xp: Int) -> Int {
        1 + Int((Double(max(0, xp)) / 120).squareRoot())
    }
    static func xpFloor(forLevel level: Int) -> Int { 120 * (level - 1) * (level - 1) }

    static func readings(
        life: LifeStore, focus: FocusLog, tasks: [TaskItem],
        now: Date = Date(), windowDays: Int = 60
    ) -> [Reading] {
        let since = now.adding(days: -(windowDays - 1)).startOfDay

        // Focus minutes by category, in-window.
        var focusByCat: [ActivityCategory: Int] = [:]
        for s in focus.sessions {
            guard let cat = s.category else { continue }
            guard Date(timeIntervalSince1970: s.endEpoch) >= since else { continue }
            focusByCat[cat, default: 0] += s.actualMinutes
        }
        // Completed tasks by category, in-window.
        var tasksByCat: [ActivityCategory: Int] = [:]
        for t in tasks {
            guard t.isCompleted, let d = t.completionDate, d >= since else { continue }
            tasksByCat[TagStore.shared.category(for: t), default: 0] += 1
        }
        // Habit completions in-window (attributed by the habit's own category guess).
        var habitByCat: [ActivityCategory: Int] = [:]
        for habit in life.activeHabits {
            let cat = ActivityCategory.guess(from: habit.title) ?? .other
            let n = life.completionCount(habit, inLast: windowDays, now: now)
            if n > 0 { habitByCat[cat, default: 0] += n }
        }

        let momentum = MomentumStore.shared
        let planRuns = PlanningMeter.shared.planRuns(inLast: windowDays, now: now)

        return Attribute.allCases.map { attr in
            var xp = 0
            for cat in attr.categories {
                xp += (focusByCat[cat] ?? 0)          // 1 xp / focused minute
                xp += (tasksByCat[cat] ?? 0) * 8      // 8 xp / finished task
                xp += (habitByCat[cat] ?? 0) * 6      // 6 xp / habit day
            }
            switch attr {
            case .discipline:
                xp += momentum.streak() * 25
                xp += min(700, momentum.totalPoints / 5)
            case .organization:
                xp += planRuns * 20
            default:
                break
            }
            let lvl = level(forXP: xp)
            let floor = xpFloor(forLevel: lvl)
            let ceil = xpFloor(forLevel: lvl + 1)
            return Reading(attribute: attr, xp: xp, level: lvl,
                           intoLevel: xp - floor, neededForLevel: ceil - floor)
        }
    }

    /// The strongest and the most-neglected attribute — for coach nudges.
    static func strongest(_ readings: [Reading]) -> Reading? { readings.max { $0.xp < $1.xp } }
    static func weakest(_ readings: [Reading]) -> Reading? { readings.min { $0.xp < $1.xp } }
}
