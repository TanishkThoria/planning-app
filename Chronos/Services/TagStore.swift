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
    /// Learned word → category vote counts, taught by the categories you set by
    /// hand. Over time this personalises classification for words the built-in
    /// keyword list can't know (a team name, a project, a class nickname).
    @Published private var learned: [String: [String: Int]] = [:]

    private static let key = "chronos.tags.v1"
    private static let learnedKey = "chronos.catlearn.v1"
    /// How many times a word must point at one category before we trust it over
    /// the keyword guess (guards against a single stray tag sticking).
    private static let learnThreshold = 2

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
        if let data = UserDefaults.standard.data(forKey: Self.learnedKey),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            learned = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func saveLearned() {
        if let data = try? JSONEncoder().encode(learned) {
            UserDefaults.standard.set(data, forKey: Self.learnedKey)
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

    // MARK: Learning

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "your", "you",
        "some", "into", "out", "off", "over", "about", "after", "before",
        "get", "got", "day", "week", "time", "app", "new", "old", "pm", "am",
    ]

    /// Significant lowercased words in a title (≥3 letters, no stopwords/numbers).
    private func tokens(_ title: String) -> [String] {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !$0.allSatisfy(\.isNumber) && !Self.stopwords.contains($0) }
    }

    /// Teach the classifier: this title was explicitly filed under `category`.
    func learn(title: String, category: ActivityCategory) {
        var changed = false
        for word in Set(tokens(title)) {
            var votes = learned[word] ?? [:]
            votes[category.rawValue, default: 0] = min(50, (votes[category.rawValue] ?? 0) + 1)
            learned[word] = votes
            changed = true
        }
        if changed { saveLearned() }
    }

    /// The personalised guess from learned words, if confident enough.
    func learnedGuess(from title: String) -> ActivityCategory? {
        var scores: [String: Int] = [:]
        for word in tokens(title) {
            for (cat, count) in learned[word] ?? [:] { scores[cat, default: 0] += count }
        }
        guard let best = scores.max(by: { $0.value < $1.value }), best.value >= Self.learnThreshold
        else { return nil }
        return ActivityCategory(rawValue: best.key)
    }

    // MARK: Resolution (override → learned → keyword guess → other)

    func category(for block: TimeBlock) -> ActivityCategory {
        override(forID: block.eventID) ?? suggestedCategory(forTitle: block.title)
    }

    func category(for task: TaskItem) -> ActivityCategory {
        override(forID: task.id) ?? suggestedCategory(forTitle: task.title)
    }

    /// The best automatic category for a bare title (no explicit override):
    /// learned personalisation first, then the keyword heuristic, then Other.
    /// Used by editors' live preview so it matches what will actually be shown.
    func suggestedCategory(forTitle title: String) -> ActivityCategory {
        learnedGuess(from: title) ?? ActivityCategory.guess(from: title) ?? .other
    }
}
