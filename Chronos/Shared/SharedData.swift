import Foundation

/// Data shared between the Chronos app and its widget extension. The app
/// writes a small `TodaySnapshot` to a shared App Group container whenever
/// things change; the widget reads it. Nothing here imports SwiftUI or
/// EventKit, so it compiles cleanly into both targets.
///
/// IMPORTANT: this file must be a member of BOTH the Chronos app target and
/// the ChronosWidget target (tick both in the File Inspector).

enum ChronosShared {
    /// Must match the App Group id added to both targets' capabilities.
    static let appGroupID = "group.app.chronos.planner"
}

struct SnapshotBlock: Codable, Hashable {
    var title: String
    var startEpoch: TimeInterval
    var endEpoch: TimeInterval
    var colorHex: UInt32

    var start: Date { Date(timeIntervalSince1970: startEpoch) }
    var end: Date { Date(timeIntervalSince1970: endEpoch) }
}

struct SnapshotHabit: Codable, Hashable {
    var name: String
    var colorHex: UInt32
    var done: Bool
}

/// Everything the widgets need for "today", captured at a moment in time.
struct TodaySnapshot: Codable {
    var generatedEpoch: TimeInterval
    var current: SnapshotBlock?
    var next: SnapshotBlock?
    var blockCount: Int
    var plannedMinutes: Int
    var elapsedPlannedMinutes: Int
    var habits: [SnapshotHabit]
    var tasksDueToday: Int
    var tasksDoneToday: Int

    var habitsDone: Int { habits.filter(\.done).count }

    static var placeholder: TodaySnapshot {
        TodaySnapshot(
            generatedEpoch: Date().timeIntervalSince1970,
            current: nil,
            next: SnapshotBlock(
                title: "Deep Work",
                startEpoch: Date().addingTimeInterval(1800).timeIntervalSince1970,
                endEpoch: Date().addingTimeInterval(1800 + 5400).timeIntervalSince1970,
                colorHex: 0x7C8CF8
            ),
            blockCount: 5,
            plannedMinutes: 360,
            elapsedPlannedMinutes: 90,
            habits: [
                SnapshotHabit(name: "Read", colorHex: 0x4FD1C5, done: true),
                SnapshotHabit(name: "Move", colorHex: 0xF2B95C, done: false),
                SnapshotHabit(name: "Meditate", colorHex: 0xA3E06B, done: true),
            ],
            tasksDueToday: 6,
            tasksDoneToday: 2
        )
    }
}

/// Reads/writes the snapshot in the shared App Group. Returns nil safely if
/// the App Group isn't configured yet (e.g. before capabilities are added),
/// so the app degrades gracefully and widgets simply show placeholders.
enum SnapshotStore {
    private static let key = "chronos.todaySnapshot"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: ChronosShared.appGroupID) }

    static func write(_ snapshot: TodaySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func read() -> TodaySnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TodaySnapshot.self, from: data)
    }
}
