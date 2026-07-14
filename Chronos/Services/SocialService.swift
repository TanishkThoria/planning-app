import Foundation
import Combine
#if canImport(GameKit)
import GameKit
#endif
#if canImport(CloudKit)
import CloudKit
#endif
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

// MARK: - Presence model (platform-agnostic)

/// How heads-down a friend is right now, derived from their current block.
enum BusyLevel: String, Codable, CaseIterable {
    case free, light, busy, headsDown

    var label: String {
        switch self {
        case .free: return "Free"
        case .light: return "Around"
        case .busy: return "Busy"
        case .headsDown: return "Heads down"
        }
    }

    var colorHex: UInt32 {
        switch self {
        case .free: return 0x5BD899
        case .light: return 0x7C8CF8
        case .busy: return 0xF2B95C
        case .headsDown: return 0xFF6B6B
        }
    }
}

/// A snapshot a user publishes about themselves for friends to see. Only ever
/// shared when the user opts into Friends; carries no calendar detail beyond
/// the current block's title (which the user can keep vague).
struct FriendPresence: Codable, Hashable {
    var code: String
    var displayName: String
    var currentBlockTitle: String?
    var busy: BusyLevel
    var momentum: Int
    var updatedEpoch: TimeInterval

    var updated: Date { Date(timeIntervalSince1970: updatedEpoch) }
}

/// What we render for each friend.
struct FriendStatus: Identifiable, Hashable {
    var id: String { presence.code }
    var presence: FriendPresence
    var isStale: Bool { Date().timeIntervalSince1970 - presence.updatedEpoch > 60 * 60 }
}

struct LeaderboardEntry: Identifiable, Hashable {
    var id: String { code }
    var code: String
    var displayName: String
    var value: Int
    var rank: Int
    var isYou: Bool
}

// MARK: - Friends backend abstraction

/// A pluggable source of friend presence. The live backend is CloudKit's public
/// database; the default is a no-op so the free account (and any build without
/// the iCloud entitlement) behaves cleanly.
protocol FriendsBackend {
    func publish(_ presence: FriendPresence) async throws
    func fetch(codes: [String]) async throws -> [FriendPresence]
}

struct DisabledFriendsBackend: FriendsBackend {
    func publish(_ presence: FriendPresence) async throws {}
    func fetch(codes: [String]) async throws -> [FriendPresence] { [] }
}

#if canImport(CloudKit)
/// Presence exchanged through the app's *public* CloudKit database, keyed by a
/// short friend code. Server-free: everyone reads/writes their own record and
/// looks up friends by code. Requires the iCloud entitlement (paid account).
struct CloudKitFriendsBackend: FriendsBackend {
    static let recordType = "FriendPresence"
    private var database: CKDatabase { CKContainer.default().publicCloudDatabase }

    func publish(_ presence: FriendPresence) async throws {
        let id = CKRecord.ID(recordName: "friend-\(presence.code)")
        let record: CKRecord
        do {
            record = try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        record["code"] = presence.code as CKRecordValue
        record["displayName"] = presence.displayName as CKRecordValue
        record["currentBlockTitle"] = (presence.currentBlockTitle ?? "") as CKRecordValue
        record["busy"] = presence.busy.rawValue as CKRecordValue
        record["momentum"] = presence.momentum as CKRecordValue
        record["updatedEpoch"] = presence.updatedEpoch as CKRecordValue
        _ = try await database.save(record)
    }

    func fetch(codes: [String]) async throws -> [FriendPresence] {
        var out: [FriendPresence] = []
        for code in codes {
            let id = CKRecord.ID(recordName: "friend-\(code)")
            do {
                let record = try await database.record(for: id)
                let title = record["currentBlockTitle"] as? String
                out.append(FriendPresence(
                    code: record["code"] as? String ?? code,
                    displayName: record["displayName"] as? String ?? "Friend",
                    currentBlockTitle: (title?.isEmpty ?? true) ? nil : title,
                    busy: BusyLevel(rawValue: record["busy"] as? String ?? "") ?? .free,
                    momentum: record["momentum"] as? Int ?? 0,
                    updatedEpoch: record["updatedEpoch"] as? TimeInterval ?? 0
                ))
            } catch let error as CKError where error.code == .unknownItem {
                continue   // code not found — silently skip
            }
        }
        return out
    }
}
#endif

// MARK: - SocialService

/// Owns Game Center leaderboards and the Friends presence feature. Every method
/// is gated on `PaidFeatures.isReady(...)`, so on the free account it holds
/// empty state and does nothing.
@MainActor
final class SocialService: ObservableObject {
    static let shared = SocialService()

    /// Leaderboard IDs to create in App Store Connect (documented in the setup
    /// guide). Submitting to an unconfigured ID simply fails silently.
    enum Leaderboard {
        static let weeklyFocus = "chronos.focus.weekly"
        static let momentumAllTime = "chronos.momentum.alltime"
    }

    @Published private(set) var gameCenterAuthenticated = false
    @Published private(set) var friends: [FriendStatus] = []
    @Published private(set) var lastError: String?

    /// Codes of friends the user has added (persisted).
    @Published var friendCodes: [String] {
        didSet { UserDefaults.standard.set(friendCodes, forKey: "chronos.friendCodes") }
    }

    private var backend: FriendsBackend {
        #if canImport(CloudKit)
        if PaidFeatures.shared.isReady(.friends) { return CloudKitFriendsBackend() }
        #endif
        return DisabledFriendsBackend()
    }

    private init() {
        friendCodes = UserDefaults.standard.stringArray(forKey: "chronos.friendCodes") ?? []
    }

    // MARK: Your identity

    /// A stable, shareable code. Generated once and kept in preferences.
    var myFriendCode: String {
        if let existing = UserDefaults.standard.string(forKey: Prefs.friendCode), !existing.isEmpty {
            return existing
        }
        let code = Self.generateCode()
        UserDefaults.standard.set(code, forKey: Prefs.friendCode)
        return code
    }

    var myDisplayName: String {
        get { UserDefaults.standard.string(forKey: Prefs.socialDisplayName) ?? "Me" }
        set { UserDefaults.standard.set(newValue, forKey: Prefs.socialDisplayName) }
    }

    private static func generateCode() -> String {
        // Ambiguous characters removed; grouped for readability (e.g. K7P-3QW).
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        func chunk() -> String { String((0..<3).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] }) }
        return "\(chunk())-\(chunk())"
    }

    func addFriend(code raw: String) {
        let code = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code != myFriendCode, !friendCodes.contains(code) else { return }
        friendCodes.append(code)
        Task { await refreshFriends() }
    }

    func removeFriend(code: String) {
        friendCodes.removeAll { $0 == code }
        friends.removeAll { $0.presence.code == code }
    }

    // MARK: Game Center

    func authenticateGameCenter() {
        guard PaidFeatures.shared.isEntitled(.leaderboards) else { return }
        #if canImport(GameKit)
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.lastError = error.localizedDescription }
                self.gameCenterAuthenticated = GKLocalPlayer.local.isAuthenticated
                #if os(iOS)
                if let viewController { Self.present(viewController) }
                #endif
            }
        }
        #endif
    }

    func submitWeeklyFocus(minutes: Int) {
        submit(minutes, to: Leaderboard.weeklyFocus)
    }

    func submitMomentum(_ points: Int) {
        submit(points, to: Leaderboard.momentumAllTime)
    }

    private func submit(_ value: Int, to leaderboardID: String) {
        guard PaidFeatures.shared.isReady(.leaderboards), gameCenterAuthenticated else { return }
        #if canImport(GameKit)
        GKLeaderboard.submitScore(
            value, context: 0, player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        ) { [weak self] error in
            if let error { Task { @MainActor in self?.lastError = error.localizedDescription } }
        }
        #endif
    }

    #if os(iOS) && canImport(GameKit) && canImport(UIKit)
    private static func present(_ viewController: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(viewController, animated: true)
    }
    #endif

    // MARK: Friends presence

    /// Share the user's current status with their friends. Called from the app
    /// whenever the current block or momentum changes.
    func publishPresence(currentBlockTitle: String?, busy: BusyLevel, momentum: Int) {
        guard PaidFeatures.shared.isReady(.friends) else { return }
        let presence = FriendPresence(
            code: myFriendCode,
            displayName: myDisplayName,
            currentBlockTitle: currentBlockTitle,
            busy: busy,
            momentum: momentum,
            updatedEpoch: Date().timeIntervalSince1970
        )
        let backend = backend
        Task {
            do { try await backend.publish(presence) }
            catch { await MainActor.run { self.lastError = error.localizedDescription } }
        }
    }

    func refreshFriends() async {
        guard PaidFeatures.shared.isReady(.friends), !friendCodes.isEmpty else {
            friends = []
            return
        }
        do {
            let presences = try await backend.fetch(codes: friendCodes)
            friends = presences
                .map(FriendStatus.init)
                .sorted { $0.presence.momentum > $1.presence.momentum }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
