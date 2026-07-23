import Foundation

/// A single, portable snapshot of *everything* Chronos keeps on the device that
/// Apple's own apps don't already sync — goals, milestones, projects, habits,
/// routines, nice-to-haves, personal growth, journals, momentum & XP,
/// achievements, challenges, tags, and every setting.
///
/// Blocks and tasks are deliberately absent: they live in Apple Calendar &
/// Reminders and travel with the user's Apple ID on their own. This file is the
/// belt-and-suspenders for the cases iCloud can't cover on its own — a fresh
/// install, a new phone, or the App Store account transfer — so a user can lift
/// their whole Chronos life onto another device with one file.
///
/// The format is a binary property list so it round-trips the raw UserDefaults
/// values (JSON blobs stored as `Data`, plus the primitive prefs) with no lossy
/// re-encoding. It captures keys by prefix, so any store added later is included
/// automatically without touching this file.
enum ChronosBackup {
    static let fileExtension = "chronosbackup"

    private static let formatTag = "chronos-backup"
    private static let currentVersion = 1

    /// Every key prefix that holds real user data worth carrying over.
    private static let includedPrefixes = ["chronos.", "pref.", "state."]
    /// Per-device sync bookkeeping — a new install should rebuild it from
    /// scratch, so it never travels in a backup.
    private static let excludedPrefixes = ["chronos.cloud."]

    private static func isBackedUp(_ key: String) -> Bool {
        includedPrefixes.contains { key.hasPrefix($0) }
            && !excludedPrefixes.contains { key.hasPrefix($0) }
    }

    // MARK: Export

    /// The keys that will be captured, for display ("N items backed up").
    static func backedUpKeys() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys.filter(isBackedUp)
    }

    /// A stable content hash of everything that would be backed up. `makeData()`
    /// stamps a fresh `created` time on every call, so its bytes can't be
    /// compared to detect real changes — this hashes only the user data, in a
    /// deterministic, cross-launch-stable way (djb2, same as CloudSyncService).
    static func fingerprint() -> Int {
        let defaults = UserDefaults.standard
        var h = 5381
        func mix<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
            for b in bytes { h = (h &* 33) ^ Int(b) }
        }
        for key in backedUpKeys().sorted() {
            mix(key.utf8)
            if let data = defaults.data(forKey: key) {
                mix(data)
            } else if let value = defaults.object(forKey: key) {
                mix(String(describing: value).utf8)
            }
        }
        return h
    }

    /// Serialize the current on-device state into a self-describing binary plist.
    static func makeData() throws -> Data {
        let defaults = UserDefaults.standard
        var payload: [String: Any] = [:]
        for key in backedUpKeys() {
            if let value = defaults.object(forKey: key) { payload[key] = value }
        }
        let wrapper: [String: Any] = [
            "format": formatTag,
            "version": currentVersion,
            "created": Date().timeIntervalSince1970,
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "data": payload,
        ]
        return try PropertyListSerialization.data(fromPropertyList: wrapper, format: .binary, options: 0)
    }

    /// Write the backup to a temp file with a friendly, dated name and return its
    /// URL, ready to hand to a `ShareLink`.
    static func writeTempFile() throws -> URL {
        let data = try makeData()
        let stamp = Self.stampFormatter.string(from: Date())
        let name = "Chronos Backup \(stamp).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: Import

    enum RestoreError: LocalizedError {
        case unreadable
        case notABackup

        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file couldn't be read."
            case .notABackup: return "That doesn't look like a Chronos backup."
            }
        }
    }

    /// Restore from raw backup data: overwrite the stored value for every key in
    /// the backup, drop stale sync bookkeeping so the restored blobs re-upload as
    /// fresh local edits, then post a reload so the live stores adopt it.
    /// Returns the number of keys restored.
    @discardableResult
    static func restore(from data: Data) throws -> Int {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let wrapper = plist as? [String: Any]
        else { throw RestoreError.unreadable }
        guard
            wrapper["format"] as? String == formatTag,
            let payload = wrapper["data"] as? [String: Any]
        else { throw RestoreError.notABackup }

        let defaults = UserDefaults.standard
        // A restored blob is "new" to this device — clear the mod/hash records so
        // Chronos+ sync treats it as a local edit and pushes it, rather than
        // thinking the (empty) cloud copy is newer.
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("chronos.cloud.") {
            defaults.removeObject(forKey: key)
        }
        var restored = 0
        for (key, value) in payload where isBackedUp(key) {
            defaults.set(value, forKey: key)
            restored += 1
        }
        // Wake every store that watches for a cloud pull so the restore shows up
        // without a relaunch. (A relaunch is still the cleanest for stragglers.)
        NotificationCenter.default.post(name: .chronosCloudDidPull, object: nil)
        return restored
    }

    /// Restore from a picked file URL, handling out-of-sandbox security scope.
    @discardableResult
    static func restore(from url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try restore(from: data)
    }
}
