import Foundation
import SwiftUI

/// A logged stretch of focused work — from the Pomodoro / stopwatch timer.
/// Stored locally as JSON; feeds the Insights "focus hours" and "when you
/// actually work" stats. Not an EventKit object (EventKit has nowhere to
/// put this), but deliberately lightweight.
struct FocusSession: Codable, Identifiable, Hashable {
    var id = UUID()
    var taskID: String?
    var taskTitle: String
    var startEpoch: TimeInterval
    var endEpoch: TimeInterval
    var plannedMinutes: Int
    var wasPomodoro: Bool
    var completedFullDuration: Bool
    /// What you were focusing on — set when you tag the session. Optional/
    /// defaulted so older stored sessions decode unchanged.
    var category: ActivityCategory? = nil
    /// A habit or goal this session counts toward.
    var habitID: UUID? = nil
    var goalID: UUID? = nil

    var start: Date { Date(timeIntervalSince1970: startEpoch) }
    var end: Date { Date(timeIntervalSince1970: endEpoch) }
    var actualMinutes: Int { max(0, Int((endEpoch - startEpoch) / 60)) }
}

@MainActor
final class FocusLog: ObservableObject {
    private static let key = "chronos.focusSessions"
    private static let maxStored = 500

    @Published private(set) var sessions: [FocusSession] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([FocusSession].self, from: data) {
            sessions = decoded
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
              let decoded = try? JSONDecoder().decode([FocusSession].self, from: data) else { return }
        sessions = decoded
    }

    func record(_ session: FocusSession) {
        sessions.append(session)
        if sessions.count > Self.maxStored {
            sessions.removeFirst(sessions.count - Self.maxStored)
        }
        save()
    }

    func sessions(inLast days: Int, now: Date = Date()) -> [FocusSession] {
        let cutoff = now.adding(days: -days).timeIntervalSince1970
        return sessions.filter { $0.startEpoch >= cutoff }
    }

    func sessions(on day: Date) -> [FocusSession] {
        sessions.filter { $0.start.isSameDay(as: day) }
    }

    func totalMinutes(inLast days: Int, now: Date = Date()) -> Int {
        sessions(inLast: days, now: now).reduce(0) { $0 + $1.actualMinutes }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
