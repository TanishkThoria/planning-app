import Foundation
import EventKit

/// Connects school LMS feeds (Canvas, Schoology, …) to Chronos. Assignments
/// from a subscribed .ics calendar become reminders (with due dates, notes,
/// and links), and the original assignment calendar entries are hidden so they
/// don't double up. Real events (lectures, office hours) stay on the calendar.
@MainActor
final class LMSStore: ObservableObject {
    static let shared = LMSStore()

    @Published var sources: [LMSSource] = [] { didSet { save() } }
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSummary: String?

    /// event key → created reminder id, so we never import the same one twice.
    private var syncedMap: [String: String] = [:]
    /// Per-source calendar event identifiers hidden because they became
    /// reminders — kept per source so unlinking can restore exactly its events.
    private var hiddenBySource: [String: Set<String>] = [:]

    private static let key = "chronos.lms.v2"
    private static let legacyKey = "chronos.lms.v1"

    private init() { load() }

    var isConfigured: Bool { !sources.isEmpty }

    /// Every hidden event id across all sources.
    var hiddenEventIDs: Set<String> {
        hiddenBySource.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    /// The oldest last-sync across sources (nil if any source never synced).
    var oldestSyncEpoch: TimeInterval? {
        let epochs = sources.map { $0.lastSyncEpoch ?? 0 }
        return epochs.min()
    }

    // MARK: Persistence

    private struct Persisted: Codable {
        var sources: [LMSSource]
        var syncedMap: [String: String]
        var hiddenBySource: [String: [String]]
    }

    private struct LegacyPersisted: Codable {
        var sources: [LMSSource]
        var syncedMap: [String: String]
        var hiddenEventIDs: [String]
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            sources = decoded.sources
            syncedMap = decoded.syncedMap
            hiddenBySource = decoded.hiddenBySource.mapValues(Set.init)
            return
        }
        // Migrate v1 (single flat hidden set) — attribute it to the first
        // source; a later sync rebuilds precise attribution anyway.
        if let data = UserDefaults.standard.data(forKey: Self.legacyKey),
           let legacy = try? JSONDecoder().decode(LegacyPersisted.self, from: data) {
            sources = legacy.sources
            syncedMap = legacy.syncedMap
            if let first = legacy.sources.first {
                hiddenBySource = [first.id.uuidString: Set(legacy.hiddenEventIDs)]
            }
            save()
            UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        }
    }

    private func save() {
        let persisted = Persisted(
            sources: sources,
            syncedMap: syncedMap,
            hiddenBySource: hiddenBySource.mapValues(Array.init)
        )
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: Configuration

    func addSource(_ source: LMSSource) {
        sources.append(source)
    }

    /// Unlink a school: stop syncing it and unhide its calendar events.
    /// Already-imported reminders stay (they're the user's tasks now).
    func remove(_ source: LMSSource, service: EventKitService) {
        sources.removeAll { $0.id == source.id }
        hiddenBySource[source.id.uuidString] = nil
        let prefix = "\(source.id.uuidString):"
        syncedMap = syncedMap.filter { !$0.key.hasPrefix(prefix) }
        save()
        service.setHiddenEventIDs(hiddenEventIDs)
    }

    /// Push the persisted hidden set into the service so assignment events are
    /// hidden immediately at launch, before the first sync runs.
    func applyHidden(to service: EventKitService) {
        service.setHiddenEventIDs(hiddenEventIDs)
    }

    // MARK: Sync

    /// Re-import if the last sync is older than `minInterval` (default 6h) —
    /// called on launch, on foreground, and when calendar data changes, so a
    /// day never passes without a sync while the app is in use.
    func autoSyncIfStale(service: EventKitService, minInterval: TimeInterval = 6 * 3600, now: Date = Date()) async {
        guard isConfigured, !isSyncing else { return }
        let oldest = oldestSyncEpoch ?? 0
        guard now.timeIntervalSince1970 - oldest >= minInterval else { return }
        await sync(service: service)
    }

    func sync(service: EventKitService) async {
        guard isConfigured, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let now = Date()
        let from = now.adding(days: -21)
        let to = now.adding(days: 220)
        var created = 0

        for source in sources {
            let events = service.events(inCalendar: source.calendarID, from: from, to: to)
            var hidden: Set<String> = []
            for event in events {
                guard let eid = event.eventIdentifier, let start = event.startDate else { continue }
                let end = event.endDate ?? start
                let duration = Int(end.timeIntervalSince(start) / 60)
                let kind = LMSClassifier.classify(
                    title: event.title ?? "",
                    isAllDay: event.isAllDay,
                    durationMinutes: duration
                )
                guard kind == .assignment else { continue }

                hidden.insert(eid)

                let key = "\(source.id.uuidString):\(event.calendarItemExternalIdentifier ?? eid)"
                if let existing = syncedMap[key], service.reminderExists(existing) { continue }

                let rid = service.createAssignmentReminder(
                    title: event.title ?? "Assignment",
                    due: start,
                    hasTime: !event.isAllDay,
                    notes: notes(for: event, source: source),
                    url: event.url,
                    listID: source.listID,
                    commit: false
                )
                if let rid {
                    syncedMap[key] = rid
                    created += 1
                }
            }
            // Union instead of replace: events that scrolled out of the fetch
            // window stay hidden rather than reappearing as calendar noise.
            hiddenBySource[source.id.uuidString, default: []].formUnion(hidden)
            if let idx = sources.firstIndex(where: { $0.id == source.id }) {
                sources[idx].lastSyncEpoch = now.timeIntervalSince1970
            }
        }

        save()
        service.setHiddenEventIDs(hiddenEventIDs)
        service.commitStore()

        lastSummary = created > 0
            ? "Imported \(created) new assignment\(created == 1 ? "" : "s")."
            : "You're all caught up — no new assignments."
    }

    private func notes(for event: EKEvent, source: LMSSource) -> String? {
        var parts: [String] = []
        if let body = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            parts.append(body)
        }
        parts.append("From \(source.name)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: Feed URL → subscription URL

    /// Turn a pasted feed URL into a `webcal://` URL that makes the system
    /// Calendar offer to subscribe.
    static func subscribeURL(from raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("https://") { s = "webcal://" + String(s.dropFirst(8)) }
        else if s.hasPrefix("http://") { s = "webcal://" + String(s.dropFirst(7)) }
        else if !s.hasPrefix("webcal://") { s = "webcal://" + s }
        return URL(string: s)
    }
}
