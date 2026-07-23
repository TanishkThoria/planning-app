import Foundation
import Combine

/// A whole-snapshot backup of everything Chronos keeps on the device, kept in
/// the user's iCloud **key-value store** — the one place data survives even a
/// delete-and-reinstall or a move to a brand-new phone, with no manual export.
///
/// This is the belt to `CloudSyncService`'s suspenders. Where that service keeps
/// per-key CloudKit records for live multi-device *sync*, this keeps a single
/// compact snapshot (the exact `ChronosBackup` blob) under one iCloud key. On a
/// fresh install it's pulled back automatically, so goals, projects, habits,
/// routines, growth, journals, momentum, achievements and settings all come
/// home on their own — no "did you remember to export?" moment.
///
/// It stays completely dormant on the free account: it only ever touches iCloud
/// when the build actually ships the iCloud entitlement
/// (`AppEntitlements.cloudBuild`, added in Xcode after the App Store transfer,
/// with "Key-value storage" enabled under iCloud). Until then every method
/// returns immediately and the ubiquitous store is never referenced.
///
/// Conflict handling is intentionally coarse: last-writer-wins on the whole
/// snapshot, keyed by a modified-timestamp. That's exactly right for its job —
/// carrying your data across a reinstall — while CloudKit handles fine-grained
/// concurrent edits across live devices.
@MainActor
final class CloudKeyValueBackup: ObservableObject {
    static let shared = CloudKeyValueBackup()

    /// Snapshot blob + its modified time, in the ubiquitous key-value store.
    private let blobKey = "chronos.kv.snapshot.v1"
    private let stampKey = "chronos.kv.snapshot.modified"
    /// Device-local markers (prefixed `chronos.cloud.` so they're never
    /// themselves backed up, and are cleared on restore). They record which
    /// snapshot this device already reflects, so we neither echo our own writes
    /// nor re-upload unchanged data.
    private let appliedStampKey = "chronos.cloud.kv.applied"
    private let pushedFingerprintKey = "chronos.cloud.kv.fingerprint"

    /// Single per-value ceiling for iCloud KVS is ~1 MB; stay comfortably under.
    private let maxSnapshotBytes = 900_000

    private var active: Bool { AppEntitlements.cloudBuild }

    private init() {}

    // MARK: Lifecycle

    /// Observe external iCloud changes and reconcile once. Safe on every launch;
    /// no-ops entirely on the free account.
    func start() {
        guard active else { return }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullIfNewer() }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
        reconcile()
    }

    /// Pull a newer snapshot if iCloud has one, otherwise push local state up.
    func sync() {
        guard active else { return }
        reconcile()
    }

    /// Push the current local state up (e.g. when backgrounding).
    func backUp() {
        guard active else { return }
        push()
    }

    // MARK: Reconcile

    private func reconcile() {
        let store = NSUbiquitousKeyValueStore.default
        let remoteStamp = store.double(forKey: stampKey)
        let hasRemote = store.data(forKey: blobKey) != nil && remoteStamp > 0
        let appliedStamp = UserDefaults.standard.double(forKey: appliedStampKey)

        // A remote snapshot newer than the one we already reflect wins — this is
        // the fresh-install case (appliedStamp is 0, so any snapshot restores).
        if hasRemote && remoteStamp > appliedStamp {
            pull(from: store, stamp: remoteStamp)
        } else {
            push()
        }
    }

    private func pullIfNewer() {
        guard active else { return }
        let store = NSUbiquitousKeyValueStore.default
        let remoteStamp = store.double(forKey: stampKey)
        let appliedStamp = UserDefaults.standard.double(forKey: appliedStampKey)
        if store.data(forKey: blobKey) != nil, remoteStamp > appliedStamp {
            pull(from: store, stamp: remoteStamp)
        }
    }

    private func pull(from store: NSUbiquitousKeyValueStore, stamp: Double) {
        guard let data = store.data(forKey: blobKey) else { return }
        do {
            try ChronosBackup.restore(from: data)
            // restore() wipes chronos.cloud.* markers, so re-stamp *after* it to
            // record that this device now reflects the pulled snapshot.
            let defaults = UserDefaults.standard
            defaults.set(stamp, forKey: appliedStampKey)
            defaults.set(ChronosBackup.fingerprint(), forKey: pushedFingerprintKey)
        } catch {
            // A corrupt snapshot must never clobber good local data — leave it.
        }
    }

    private func push() {
        let defaults = UserDefaults.standard
        let fingerprint = ChronosBackup.fingerprint()
        let lastFingerprint = defaults.object(forKey: pushedFingerprintKey) as? Int
        let store = NSUbiquitousKeyValueStore.default
        // Nothing changed since our last upload, and it's already up there.
        if lastFingerprint == fingerprint, store.data(forKey: blobKey) != nil { return }

        guard let data = try? ChronosBackup.makeData(), data.count < maxSnapshotBytes else {
            // Too big for KVS (rare) — the manual file backup still covers it.
            return
        }
        let stamp = Date().timeIntervalSince1970
        store.set(data, forKey: blobKey)
        store.set(stamp, forKey: stampKey)
        store.synchronize()
        defaults.set(stamp, forKey: appliedStampKey)
        defaults.set(fingerprint, forKey: pushedFingerprintKey)
    }
}
