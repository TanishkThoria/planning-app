import Foundation

// Turns the real things a user already does — kept habits, finished tasks, focus
// sessions, shipped milestones, plus any evidence they note by hand — into a
// per-pillar reading of how much they're *becoming* that identity. Pure,
// on-device, honest: auto-evidence is computed live and never stored, so the
// number always reflects the actual recent record and can't be inflated.

/// A completed task reduced to just what the engine needs (so the engine never
/// touches EventKit). Built by the view from `service.tasks` + `TagStore`.
struct TaskEvidence {
    let date: Date
    let category: ActivityCategory?
    let title: String
}

enum EvidenceTrend {
    case fresh, rising, steady, quiet
    var label: String {
        switch self {
        case .fresh: return "Just started"
        case .rising: return "Building"
        case .steady: return "Holding steady"
        case .quiet: return "Gone quiet"
        }
    }
    var icon: String {
        switch self {
        case .fresh: return "sparkle"
        case .rising: return "arrow.up.right"
        case .steady: return "equal"
        case .quiet: return "moon.zzz.fill"
        }
    }
}

/// The computed state of one pillar over a trailing window.
struct PillarReading: Identifiable {
    let pillar: IdentityPillar
    let score: Double            // 0…1 "becoming"
    let evidenceCount: Int       // events in the window
    let trend: EvidenceTrend
    let recent: [IdentityEvidence]   // newest first, auto + manual merged
    var id: UUID { pillar.id }
}

@MainActor
enum EvidenceEngine {

    /// Full-score target: this many strength-points over the window reads as
    /// "fully living it." ~1.5 points/day.
    private static let dailyTarget = 1.5

    static func readings(
        pillars: [IdentityPillar],
        life: LifeStore,
        focus: FocusLog,
        taskEvidence: [TaskEvidence],
        goalProgress: [UUID: Double],
        now: Date = Date(),
        windowDays: Int = 14
    ) -> [PillarReading] {
        pillars.map {
            reading(for: $0, life: life, focus: focus, taskEvidence: taskEvidence,
                    goalProgress: goalProgress, now: now, windowDays: windowDays)
        }
    }

    static func reading(
        for pillar: IdentityPillar,
        life: LifeStore,
        focus: FocusLog,
        taskEvidence: [TaskEvidence],
        goalProgress: [UUID: Double],
        now: Date = Date(),
        windowDays: Int = 14
    ) -> PillarReading {
        let windowStart = now.adding(days: -(windowDays - 1)).startOfDay
        var events = evidence(for: pillar, life: life, focus: focus,
                              taskEvidence: taskEvidence, since: windowStart, now: now)
        events.sort { $0.epoch > $1.epoch }

        // Evidence score: normalized strength density over the window.
        let totalStrength = events.reduce(0) { $0 + $1.strength }
        let target = Double(windowDays) * dailyTarget
        let evidenceScore = target <= 0 ? 0 : min(1, Double(totalStrength) / target)

        // Blend in linked-goal progress, if any.
        let linkedGoals = (pillar.linkedGoalIDs ?? []).compactMap { goalProgress[$0] }
        let score: Double
        if linkedGoals.isEmpty {
            score = evidenceScore
        } else {
            let goalAvg = linkedGoals.reduce(0, +) / Double(linkedGoals.count)
            score = min(1, evidenceScore * 0.75 + goalAvg * 0.25)
        }

        // Trend: last 7 days vs the 7 before.
        let sevenAgo = now.adding(days: -6).startOfDay
        let fourteenAgo = now.adding(days: -13).startOfDay
        let last7 = events.filter { $0.date >= sevenAgo }.count
        let prev7 = events.filter { $0.date >= fourteenAgo && $0.date < sevenAgo }.count
        let ageDays = pillar.createdEpoch > 0
            ? Calendar.current.dateComponents([.day], from: Date(timeIntervalSince1970: pillar.createdEpoch), to: now).day ?? 99
            : 99
        let trend: EvidenceTrend
        if events.isEmpty {
            trend = ageDays < 4 ? .fresh : .quiet
        } else if last7 == 0 {
            trend = .quiet
        } else if last7 >= 2 && Double(last7) > Double(prev7) * 1.2 {
            trend = .rising
        } else {
            trend = .steady
        }

        return PillarReading(pillar: pillar, score: score, evidenceCount: events.count,
                             trend: trend, recent: Array(events.prefix(12)))
    }

    /// All evidence (auto + manual) attributable to a pillar since `since`.
    static func evidence(
        for pillar: IdentityPillar,
        life: LifeStore,
        focus: FocusLog,
        taskEvidence: [TaskEvidence],
        since: Date,
        now: Date = Date()
    ) -> [IdentityEvidence] {
        var out: [IdentityEvidence] = []
        let cats = Set(pillar.categoryList)

        // Manual + reflection evidence the user noted.
        out += life.identityEvidence.filter { $0.pillarID == pillar.id && $0.date >= since }

        // Linked habits: each due-and-kept day is a small proof.
        let linkedHabits = pillar.linkedHabitIDs ?? []
        for hid in linkedHabits {
            guard let habit = life.habits.first(where: { $0.id == hid }) else { continue }
            var day = since.startOfDay
            while day <= now.startOfDay {
                if habit.isDue(on: day) && life.isDone(habit, on: day) {
                    out.append(IdentityEvidence(
                        epoch: day.at(minutes: 12 * 60).timeIntervalSince1970,
                        pillarID: pillar.id, source: .habit,
                        text: "Showed up: \(habit.title.isEmpty ? "habit" : habit.title)",
                        strength: 1))
                }
                day = day.adding(days: 1)
            }
        }

        // Linked projects: logged time and milestones hit.
        let linkedProjects = pillar.linkedProjectIDs ?? []
        for pid in linkedProjects {
            guard let project = life.projects.first(where: { $0.id == pid }) else { continue }
            for entry in project.timeEntries where entry.date >= since {
                out.append(IdentityEvidence(
                    epoch: entry.epoch, pillarID: pillar.id, source: .focus,
                    text: "\(entry.minutes)m on \(project.title.isEmpty ? "project" : project.title)",
                    strength: entry.minutes >= 45 ? 2 : 1))
            }
            for m in project.milestones where m.isDone {
                if let done = m.doneDate, done >= since {
                    out.append(IdentityEvidence(
                        epoch: done.timeIntervalSince1970, pillarID: pillar.id, source: .milestone,
                        text: "Hit a milestone: \(m.title.isEmpty ? "milestone" : m.title)",
                        strength: 2))
                }
            }
        }

        // Focus sessions in a matching category.
        if !cats.isEmpty {
            for s in focus.sessions {
                guard let cat = s.category, cats.contains(cat) else { continue }
                let end = Date(timeIntervalSince1970: s.endEpoch)
                guard end >= since else { continue }
                out.append(IdentityEvidence(
                    epoch: s.endEpoch, pillarID: pillar.id, source: .focus,
                    text: "Focused \(s.actualMinutes)m · \(cat.title)",
                    strength: s.actualMinutes >= 50 ? 2 : 1))
            }
            // Completed tasks in a matching category.
            for t in taskEvidence {
                guard let cat = t.category, cats.contains(cat), t.date >= since else { continue }
                out.append(IdentityEvidence(
                    epoch: t.date.timeIntervalSince1970, pillarID: pillar.id, source: .task,
                    text: "Finished: \(t.title)", strength: 1))
            }
        }

        return out
    }
}
