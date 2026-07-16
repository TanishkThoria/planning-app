import Foundation
import Combine
#if canImport(CloudKit)
import CloudKit
#endif

extension Notification.Name {
    /// Posted after a successful CloudKit pull writes fresh data into
    /// UserDefaults, so the in-memory stores can reload.
    static let chronosCloudDidPull = Notification.Name("chronos.cloudDidPull")
}

/// Mirrors Chronos's *own* data — the pieces Apple Calendar & Reminders can't
/// hold — across the user's devices via their private iCloud database.
///
/// EventKit stays the source of truth for blocks and tasks (already synced by
/// iCloud Calendar/Reminders). This only carries the extra JSON blobs Chronos
/// keeps in UserDefaults: Grow data, momentum history, the planner profile,
/// connected schools, and the focus log.
///
/// The whole thing is dormant until `PaidFeatures.isReady(.cloudSync)` — no
/// iCloud entitlement, no signed-in account, or the toggle off means every
/// method returns immediately. It is written so the free account never touches
/// CloudKit at all.
@MainActor
final class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()

    enum SyncState: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
        case unavailable
    }

    @Published private(set) var state: SyncState = .idle

    /// The UserDefaults keys that get mirrored. EventKit-backed data is
    /// deliberately absent — iCloud already syncs it natively.
    private let mirroredKeys = [
        "chronos.lifeData",         // Grow: goals, habits, journal, templates, budgets
        "chronos.momentum.v1",      // momentum history
        "chronos.plannerProfile",   // calibration profile
        "chronos.lms.v2",           // connected schools
        "chronos.focusSessions",    // focus log
        "chronos.tags.v1",          // category overrides
        "chronos.routines.v1",      // guided routines
        "chronos.personalization.v1", // setup survey + modular layout
    ]

    private static let recordType = "ChronosBlob"
    /// Timestamp of the version we currently hold locally for a key.
    private func modKey(_ key: String) -> String { "chronos.cloud.mod.\(key)" }
    /// Hash of the payload we last synced, so a local edit is detected without
    /// each store having to announce it.
    private func hashKey(_ key: String) -> String { "chronos.cloud.hash.\(key)" }

    private init() {}

    // MARK: Public API (all safely no-op when not ready)

    /// Pull remote → local, then push local → remote. Call on launch and when
    /// coming to the foreground.
    func syncNow() async {
        guard PaidFeatures.shared.isReady(.cloudSync) else {
            state = .unavailable
            return
        }
        #if canImport(CloudKit)
        state = .syncing
        do {
            try await pull()
            try await push()
            state = .synced(Date())
        } catch {
            state = .failed(Self.friendlyError(error))
        }
        #else
        state = .unavailable
        #endif
    }

    /// Push local → remote only (e.g. when backgrounding).
    func pushIfReady() async {
        guard PaidFeatures.shared.isReady(.cloudSync) else { return }
        #if canImport(CloudKit)
        do { try await push() } catch { /* best-effort */ }
        #endif
    }

    #if canImport(CloudKit)
    private var database: CKDatabase { CKContainer.default().privateCloudDatabase }

    /// Fetch each mirrored record; if the remote copy is newer than what we last
    /// wrote locally, adopt it and post a reload.
    private func pull() async throws {
        var changed = false
        for key in mirroredKeys {
            let recordID = CKRecord.ID(recordName: key)
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                continue   // nothing stored remotely yet
            }
            guard
                let payload = record["payload"] as? Data,
                let remoteMod = record["modified"] as? Date
            else { continue }

            let localMod = UserDefaults.standard.object(forKey: modKey(key)) as? Date ?? .distantPast
            if remoteMod > localMod {
                UserDefaults.standard.set(payload, forKey: key)
                UserDefaults.standard.set(remoteMod, forKey: modKey(key))
                // Remember what we just adopted so we don't immediately re-push it.
                UserDefaults.standard.set(Self.hash(payload), forKey: hashKey(key))
                changed = true
            }
        }
        if changed {
            NotificationCenter.default.post(name: .chronosCloudDidPull, object: nil)
        }
    }

    /// Upload any local blob whose content changed since the last sync. Local
    /// edits are detected by comparing a content hash, so the stores don't have
    /// to announce their own changes.
    private func push() async throws {
        for key in mirroredKeys {
            guard let data = UserDefaults.standard.data(forKey: key) else { continue }
            let currentHash = Self.hash(data)
            let lastHash = UserDefaults.standard.integer(forKey: hashKey(key))
            let hasLastHash = UserDefaults.standard.object(forKey: hashKey(key)) != nil
            // Unchanged since the last sync → nothing to upload.
            if hasLastHash && currentHash == lastHash { continue }

            let now = Date()
            let recordID = CKRecord.ID(recordName: key)
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: Self.recordType, recordID: recordID)
            }
            record["payload"] = data as CKRecordValue
            record["modified"] = now as CKRecordValue
            _ = try await database.save(record)

            UserDefaults.standard.set(now, forKey: modKey(key))
            UserDefaults.standard.set(currentHash, forKey: hashKey(key))
        }
    }

    /// A stable content hash for change detection (djb2 over the bytes — order
    /// stability doesn't matter, only that identical data hashes identically).
    private static func hash(_ data: Data) -> Int {
        var h = 5381
        for byte in data { h = (h &* 33) ^ Int(byte) }
        return h
    }

    private static func friendlyError(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated: return "Sign in to iCloud to sync."
            case .networkUnavailable, .networkFailure: return "No network — will retry."
            case .quotaExceeded: return "Your iCloud storage is full."
            default: return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }
    #endif
}
