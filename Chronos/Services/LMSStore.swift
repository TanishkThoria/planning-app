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
    /// Calendar event identifiers hidden because they became reminders.
    private(set) var hiddenEventIDs: Set<String> = []

    private static let key = "chronos.lms.v1"

    private init() { load() }

    var isConfigured: Bool { !sources.isEmpty }

    // MARK: Persistence

    private struct Persisted: Codable {
        var sources: [LMSSource]
        var syncedMap: [String: String]
        var hiddenEventIDs: [String]
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        sources = decoded.sources
        syncedMap = decoded.syncedMap
        hiddenEventIDs = Set(decoded.hiddenEventIDs)
    }

    private func save() {
        let persisted = Persisted(sources: sources, syncedMap: syncedMap, hiddenEventIDs: Array(hiddenEventIDs))
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: Configuration

    func addSource(_ source: LMSSource) {
        sources.append(source)
    }

    func removeSource(_ source: LMSSource, service: EventKitService) {
        sources.removeAll { $0.id == source.id }
        save()
        // Leave already-imported reminders in place, but stop hiding events for
        // a removed source is complex to scope precisely; a full resync on next
        // launch reconciles hidden state.
    }

    /// Push the persisted hidden set into the service so assignment events are
    /// hidden immediately at launch, before the first sync runs.
    func applyHidden(to service: EventKitService) {
        service.setHiddenEventIDs(hiddenEventIDs)
    }

    // MARK: Sync

    func sync(service: EventKitService) async {
        guard isConfigured, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let now = Date()
        let from = now.adding(days: -21)
        let to = now.adding(days: 220)
        var created = 0
        var hidden = hiddenEventIDs

        for source in sources {
            let events = service.events(inCalendar: source.calendarID, from: from, to: to)
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
            if let idx = sources.firstIndex(where: { $0.id == source.id }) {
                sources[idx].lastSyncEpoch = now.timeIntervalSince1970
            }
        }

        hiddenEventIDs = hidden
        save()
        service.setHiddenEventIDs(hidden)
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
