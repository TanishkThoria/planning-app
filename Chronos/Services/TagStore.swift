import Foundation
import Combine

/// Stores the user's category overrides for events, tasks, and focus sessions.
///
/// Overrides are kept locally (and synced across devices with Chronos+), keyed
/// by the *series-level* event identifier for blocks and the reminder id for
/// tasks. Keying at the series level means tagging one occurrence of a
/// repeating Apple Calendar event tags them all — and it works even for events
/// Chronos can't edit (external / shared / read-only calendars), since nothing
/// is written back into the calendar.
///
/// When there's no explicit override, `category(for:)` falls back to the
/// keyword auto-classifier, so every item is categorised out of the box.
@MainActor
final class TagStore: ObservableObject {
    static let shared = TagStore()

    @Published private var overrides: [String: String] = [:]

    private static let key = "chronos.tags.v1"

    private init() {
        load()
        NotificationCenter.default.addObserver(
            forName: .chronosCloudDidPull, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            overrides = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: Overrides

    func override(forID id: String) -> ActivityCategory? {
        overrides[id].flatMap(ActivityCategory.init(rawValue:))
    }

    func isExplicit(forID id: String) -> Bool { overrides[id] != nil }

    func setCategory(_ category: ActivityCategory?, forID id: String) {
        if let category { overrides[id] = category.rawValue } else { overrides.removeValue(forKey: id) }
        save()
    }

    // MARK: Resolution (override → auto-guess → other)

    func category(for block: TimeBlock) -> ActivityCategory {
        override(forID: block.eventID) ?? ActivityCategory.guess(from: block.title) ?? .other
    }

    func category(for task: TaskItem) -> ActivityCategory {
        override(forID: task.id) ?? ActivityCategory.guess(from: task.title) ?? .other
    }
}
