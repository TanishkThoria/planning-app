import Foundation
import Combine

/// Records the handful of exceptions to the default assumption that a real
/// calendar event (a doctor's appointment, a meeting you didn't create in
/// Chronos) actually happened. By default such events count as attended —
/// "doing and focused" time — with no timer needed; here we only remember the
/// occurrences you explicitly marked as skipped in the day review.
///
/// Keyed by occurrence id (`eventID#startRef`) so a single occurrence of a
/// repeating event can be marked without affecting the rest. Stored locally and
/// synced with Chronos+ like the other side-stores.
@MainActor
final class EventOutcomeStore: ObservableObject {
    static let shared = EventOutcomeStore()

    @Published private var skipped: Set<String> = []

    private static let key = "chronos.eventoutcomes.v1"

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
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            skipped = Set(decoded)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Array(skipped)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Whether this occurrence was marked as not attended.
    func isSkipped(_ occurrenceID: String) -> Bool { skipped.contains(occurrenceID) }

    func setSkipped(_ occurrenceID: String, _ value: Bool) {
        if value { skipped.insert(occurrenceID) } else { skipped.remove(occurrenceID) }
        save()
    }

    func toggle(_ occurrenceID: String) { setSkipped(occurrenceID, !isSkipped(occurrenceID)) }

    /// A real event counts as attended/focused time unless explicitly skipped.
    func countsAsFocused(_ block: TimeBlock) -> Bool {
        block.isRealEvent && !isSkipped(block.id)
    }
}
