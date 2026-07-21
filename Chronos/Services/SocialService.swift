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

    var icon: String {
        switch self {
        case .free: return "circle"
        case .light: return "circle.lefthalf.filled"
        case .busy: return "circle.fill"
        case .headsDown: return "moon.fill"
        }
    }
}

/// The stats bundled into a presence update (computed by the app each tick).
struct SocialStats: Hashable {
    var momentumToday: Int = 0
    var streakDays: Int = 0
    var level: Int = 1
    var focusToday: Int = 0
    var tasksToday: Int = 0
    var weeklyFocus: Int = 0
}

/// A snapshot a user publishes about themselves for friends to see. Only ever
/// shared when the user opts into Friends; carries no calendar detail beyond
/// the current block's title (which the user can keep vague) and an optional
/// custom status.
struct FriendPresence: Codable, Hashable {
    var code: String
    var displayName: String
    var statusEmoji: String = ""
    var statusText: String = ""
    /// Optional contact handle (phone or Apple ID) the friend chose to share.
    var contactHandle: String = ""
    var currentBlockTitle: String?
    var busy: BusyLevel = .free
    var momentum: Int = 0
    var streakDays: Int = 0
    var level: Int = 1
    var focusToday: Int = 0
    var tasksToday: Int = 0
    var weeklyFocus: Int = 0
    var updatedEpoch: TimeInterval = 0

    var updated: Date { Date(timeIntervalSince1970: updatedEpoch) }
    var levelTitle: String { MomentumStore.levelTitle(for: level) }
}

/// What we render for each friend.
struct FriendStatus: Identifiable, Hashable {
    var id: String { presence.code }
    var presence: FriendPresence
    var isStale: Bool { Date().timeIntervalSince1970 - presence.updatedEpoch > 60 * 60 }
    /// "Active now" if updated in the last few minutes.
    var isLive: Bool { Date().timeIntervalSince1970 - presence.updatedEpoch < 8 * 60 }
}

/// A little congratulations a friend sends you (👏🔥💪🎯).
struct Cheer: Codable, Hashable, Identifiable {
    var fromCode: String
    var fromName: String
    var emoji: String
    var epoch: TimeInterval
    var id: String { "\(fromCode)-\(epoch)" }
    var date: Date { Date(timeIntervalSince1970: epoch) }
}

// MARK: - Leaderboard

/// The friend-leaderboard boards (computed locally from presence — always
/// works, no Game Center required).
enum LeaderboardBoard: String, CaseIterable, Identifiable {
    case focusWeek, momentum, streak
    var id: String { rawValue }
    var title: String {
        switch self {
        case .focusWeek: return "Focus"
        case .momentum: return "Momentum"
        case .streak: return "Streak"
        }
    }
    var icon: String {
        switch self {
        case .focusWeek: return "timer"
        case .momentum: return "bolt.fill"
        case .streak: return "flame.fill"
        }
    }
    func value(_ p: FriendPresence) -> Int {
        switch self {
        case .focusWeek: return p.weeklyFocus
        case .momentum: return p.momentum
        case .streak: return p.streakDays
        }
    }
    func display(_ v: Int) -> String {
        switch self {
        case .focusWeek: return Fmt.duration(minutes: v)
        case .momentum: return "\(v)"
        case .streak: return "\(v)d"
        }
    }
}

struct LeaderboardRow: Identifiable, Hashable {
    var rank: Int
    var presence: FriendPresence
    var value: Int
    var isYou: Bool
    var id: String { presence.code }
}

/// A derived "moment" for the activity feed (synthesised from presence — no
/// server-side event log needed).
struct ActivityMoment: Identifiable, Hashable {
    var id: String
    var icon: String
    var tint: UInt32
    var name: String
    var text: String
    var code: String
    var isYou: Bool
}

// MARK: - Duels (head-to-head friend challenges)

/// A head-to-head challenge between two friends over a metric and a window.
/// Scores are read live from each side's published presence, so there's no
/// separate score to sync — the leaderboard values already flowing are the
/// duel's scoreboard. Rides the same `.friends` capability, so it's completely
/// dormant until Chronos+ (post-transfer).
struct Duel: Codable, Hashable, Identifiable {
    var challengerCode: String
    var challengerName: String
    var opponentCode: String
    var opponentName: String
    /// LeaderboardBoard.rawValue — reuses the existing ranking metrics.
    var metricRaw: String
    var startEpoch: TimeInterval
    var endEpoch: TimeInterval
    var accepted: Bool = false

    var id: String { "\(challengerCode)-\(opponentCode)-\(Int(startEpoch))" }
    var metric: LeaderboardBoard { LeaderboardBoard(rawValue: metricRaw) ?? .focusWeek }
    var startDate: Date { Date(timeIntervalSince1970: startEpoch) }
    var endDate: Date { Date(timeIntervalSince1970: endEpoch) }
    var isFinished: Bool { Date().timeIntervalSince1970 >= endEpoch }
    var isPending: Bool { !accepted && !isFinished }
}

// MARK: - Friends backend abstraction

/// A pluggable source of friend presence + cheers. The live backend is
/// CloudKit's public database; the default is a no-op so the free account (and
/// any build without the iCloud entitlement) behaves cleanly.
protocol FriendsBackend {
    func publish(_ presence: FriendPresence) async throws
    func fetch(codes: [String]) async throws -> [FriendPresence]
    func sendCheer(_ cheer: Cheer, to code: String) async throws
    func fetchCheers(for code: String) async throws -> [Cheer]
    func postDuel(_ duel: Duel, to code: String) async throws
    func fetchDuels(for code: String) async throws -> [Duel]
}

struct DisabledFriendsBackend: FriendsBackend {
    func publish(_ presence: FriendPresence) async throws {}
    func fetch(codes: [String]) async throws -> [FriendPresence] { [] }
    func sendCheer(_ cheer: Cheer, to code: String) async throws {}
    func fetchCheers(for code: String) async throws -> [Cheer] { [] }
    func postDuel(_ duel: Duel, to code: String) async throws {}
    func fetchDuels(for code: String) async throws -> [Duel] { [] }
}

#if canImport(CloudKit)
/// Presence + cheers exchanged through the app's *public* CloudKit database,
/// keyed by a short friend code. Server-free: everyone reads/writes their own
/// record and looks up friends by code. Requires the iCloud entitlement.
struct CloudKitFriendsBackend: FriendsBackend {
    static let presenceType = "FriendPresence"
    static let inboxType = "CheerInbox"
    private var database: CKDatabase { CKContainer.default().publicCloudDatabase }

    func publish(_ p: FriendPresence) async throws {
        let id = CKRecord.ID(recordName: "friend-\(p.code)")
        let record: CKRecord
        do {
            record = try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.presenceType, recordID: id)
        }
        if let data = try? JSONEncoder().encode(p) {
            record["payload"] = data as CKRecordValue
        }
        record["updatedEpoch"] = p.updatedEpoch as CKRecordValue
        _ = try await database.save(record)
    }

    func fetch(codes: [String]) async throws -> [FriendPresence] {
        var out: [FriendPresence] = []
        for code in codes {
            let id = CKRecord.ID(recordName: "friend-\(code)")
            do {
                let record = try await database.record(for: id)
                if let data = record["payload"] as? Data,
                   let p = try? JSONDecoder().decode(FriendPresence.self, from: data) {
                    out.append(p)
                }
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
        return out
    }

    /// Cheers land in the recipient's inbox record as an appended JSON list, so
    /// no queryable index is required.
    func sendCheer(_ cheer: Cheer, to code: String) async throws {
        let id = CKRecord.ID(recordName: "cheers-\(code)")
        let record: CKRecord
        var existing: [Cheer] = []
        do {
            record = try await database.record(for: id)
            if let data = record["payload"] as? Data,
               let list = try? JSONDecoder().decode([Cheer].self, from: data) {
                existing = list
            }
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.inboxType, recordID: id)
        }
        existing.append(cheer)
        existing = Array(existing.suffix(50))
        if let data = try? JSONEncoder().encode(existing) {
            record["payload"] = data as CKRecordValue
        }
        _ = try await database.save(record)
    }

    func fetchCheers(for code: String) async throws -> [Cheer] {
        let id = CKRecord.ID(recordName: "cheers-\(code)")
        do {
            let record = try await database.record(for: id)
            if let data = record["payload"] as? Data,
               let list = try? JSONDecoder().decode([Cheer].self, from: data) {
                return list
            }
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
        return []
    }

    static let duelInboxType = "DuelInbox"

    /// Duels append to a per-user inbox (same pattern as cheers) — the
    /// challenger writes to both participants' inboxes so each side sees it.
    func postDuel(_ duel: Duel, to code: String) async throws {
        let id = CKRecord.ID(recordName: "duels-\(code)")
        let record: CKRecord
        var existing: [Duel] = []
        do {
            record = try await database.record(for: id)
            if let data = record["payload"] as? Data,
               let list = try? JSONDecoder().decode([Duel].self, from: data) {
                existing = list
            }
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.duelInboxType, recordID: id)
        }
        existing.append(duel)
        existing = Array(existing.suffix(50))
        if let data = try? JSONEncoder().encode(existing) {
            record["payload"] = data as CKRecordValue
        }
        _ = try await database.save(record)
    }

    func fetchDuels(for code: String) async throws -> [Duel] {
        let id = CKRecord.ID(recordName: "duels-\(code)")
        do {
            let record = try await database.record(for: id)
            if let data = record["payload"] as? Data,
               let list = try? JSONDecoder().decode([Duel].self, from: data) {
                return list
            }
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
        return []
    }
}
#endif

// MARK: - SocialService

/// Owns Game Center leaderboards and the full Friends layer — presence, a
/// computed friends leaderboard, an activity feed, and cheers. Every network
/// path is gated on `PaidFeatures.isReady(...)`, so on the free account it
/// holds empty state and does nothing.
@MainActor
final class SocialService: ObservableObject {
    static let shared = SocialService()

    enum GameCenterLeaderboard {
        static let weeklyFocus = "chronos.focus.weekly"
        static let momentumAllTime = "chronos.momentum.alltime"
    }

    @Published private(set) var gameCenterAuthenticated = false
    @Published private(set) var friends: [FriendStatus] = []
    @Published private(set) var duels: [Duel] = []
    @Published private(set) var receivedCheers: [Cheer] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefreshed: Date?

    /// Codes of friends the user has added (persisted).
    @Published var friendCodes: [String] {
        didSet { UserDefaults.standard.set(friendCodes, forKey: "chronos.friendCodes") }
    }

    /// The latest stats the app handed us, so presence publishes stay rich even
    /// when only the block changes.
    private var latestStats = SocialStats()

    private var backend: FriendsBackend {
        #if canImport(CloudKit)
        if PaidFeatures.shared.isReady(.friends) { return CloudKitFriendsBackend() }
        #endif
        return DisabledFriendsBackend()
    }

    private init() {
        friendCodes = UserDefaults.standard.stringArray(forKey: "chronos.friendCodes") ?? []
    }

    // MARK: Your identity + status

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

    var sharesPresence: Bool {
        UserDefaults.standard.object(forKey: Prefs.sharePresence) == nil
            ? true : UserDefaults.standard.bool(forKey: Prefs.sharePresence)
    }

    /// A presence snapshot for the local user, used to seed leaderboards + feed
    /// even before the first network round-trip.
    var myPresence: FriendPresence {
        FriendPresence(
            code: myFriendCode,
            displayName: myDisplayName,
            statusEmoji: UserDefaults.standard.string(forKey: Prefs.socialStatusEmoji) ?? "",
            statusText: UserDefaults.standard.string(forKey: Prefs.socialStatusText) ?? "",
            contactHandle: UserDefaults.standard.string(forKey: Prefs.socialContactHandle) ?? "",
            currentBlockTitle: nil,
            busy: .free,
            momentum: latestStats.momentumToday,
            streakDays: latestStats.streakDays,
            level: latestStats.level,
            focusToday: latestStats.focusToday,
            tasksToday: latestStats.tasksToday,
            weeklyFocus: latestStats.weeklyFocus,
            updatedEpoch: Date().timeIntervalSince1970
        )
    }

    private static func generateCode() -> String {
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

    // MARK: Leaderboard (computed from presence — always available)

    func leaderboard(_ board: LeaderboardBoard) -> [LeaderboardRow] {
        var people = friends.map(\.presence)
        people.append(myPresence)
        let sorted = people.sorted { board.value($0) > board.value($1) }
        return sorted.enumerated().map { idx, p in
            LeaderboardRow(rank: idx + 1, presence: p, value: board.value(p), isYou: p.code == myFriendCode)
        }
    }

    var myRank: Int? {
        leaderboard(.focusWeek).first { $0.isYou }?.rank
    }

    // MARK: Activity feed (derived moments)

    func activityMoments() -> [ActivityMoment] {
        var out: [ActivityMoment] = []
        for status in friends.sorted(by: { $0.presence.updatedEpoch > $1.presence.updatedEpoch }) {
            let p = status.presence
            if !status.isStale, p.busy == .headsDown, let block = p.currentBlockTitle, !block.isEmpty {
                out.append(.init(id: "\(p.code)-focus", icon: "moon.fill", tint: 0xFF6B6B,
                                 name: p.displayName, text: "is heads-down on \(block)", code: p.code, isYou: false))
            } else if !status.isStale, let block = p.currentBlockTitle, !block.isEmpty {
                out.append(.init(id: "\(p.code)-now", icon: "circle.fill", tint: p.busy.colorHex,
                                 name: p.displayName, text: "is on \(block)", code: p.code, isYou: false))
            }
            if p.streakDays >= 3 {
                out.append(.init(id: "\(p.code)-streak", icon: "flame.fill", tint: 0xF2B95C,
                                 name: p.displayName, text: "is on a \(p.streakDays)-day streak", code: p.code, isYou: false))
            }
            if p.tasksToday >= 3 {
                out.append(.init(id: "\(p.code)-tasks", icon: "checkmark.circle.fill", tint: 0x5BD899,
                                 name: p.displayName, text: "finished \(p.tasksToday) tasks today", code: p.code, isYou: false))
            }
        }
        return out
    }

    // MARK: Cheers

    func sendCheer(to code: String, emoji: String) {
        guard PaidFeatures.shared.isReady(.friends) else { return }
        let cheer = Cheer(fromCode: myFriendCode, fromName: myDisplayName, emoji: emoji,
                          epoch: Date().timeIntervalSince1970)
        let backend = backend
        Task {
            do { try await backend.sendCheer(cheer, to: code) }
            catch { await MainActor.run { self.lastError = error.localizedDescription } }
        }
    }

    func refreshCheers() async {
        guard PaidFeatures.shared.isReady(.friends) else { receivedCheers = []; return }
        do {
            let cheers = try await backend.fetchCheers(for: myFriendCode)
            receivedCheers = cheers.sorted { $0.epoch > $1.epoch }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Presence

    /// Store the latest computed stats so every presence publish is rich.
    func updateStats(_ stats: SocialStats) { latestStats = stats }

    func publishPresence(blockTitle: String?, busy: BusyLevel, stats: SocialStats) {
        latestStats = stats
        guard PaidFeatures.shared.isReady(.friends), sharesPresence else { return }
        let presence = FriendPresence(
            code: myFriendCode,
            displayName: myDisplayName,
            statusEmoji: UserDefaults.standard.string(forKey: Prefs.socialStatusEmoji) ?? "",
            statusText: UserDefaults.standard.string(forKey: Prefs.socialStatusText) ?? "",
            contactHandle: UserDefaults.standard.string(forKey: Prefs.socialContactHandle) ?? "",
            currentBlockTitle: blockTitle,
            busy: busy,
            momentum: stats.momentumToday,
            streakDays: stats.streakDays,
            level: stats.level,
            focusToday: stats.focusToday,
            tasksToday: stats.tasksToday,
            weeklyFocus: stats.weeklyFocus,
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
            duels = []
            return
        }
        do {
            let presences = try await backend.fetch(codes: friendCodes)
            friends = presences
                .map(FriendStatus.init)
                .sorted { $0.presence.updatedEpoch > $1.presence.updatedEpoch }
            lastRefreshed = Date()
            await refreshCheers()
            await refreshDuels()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Duels (head-to-head — dormant until .friends is ready)

    /// Challenge a friend to a head-to-head over a metric for `days` days.
    func sendDuel(to code: String, metric: LeaderboardBoard, days: Int = 7) {
        guard PaidFeatures.shared.isReady(.friends) else { return }
        let now = Date().timeIntervalSince1970
        let opponentName = friends.first { $0.presence.code == code }?.presence.displayName ?? code
        let duel = Duel(
            challengerCode: myFriendCode, challengerName: myDisplayName,
            opponentCode: code, opponentName: opponentName,
            metricRaw: metric.rawValue, startEpoch: now, endEpoch: now + Double(days) * 86_400,
            accepted: false
        )
        let backend = backend
        let myCode = myFriendCode
        Task {
            do {
                try await backend.postDuel(duel, to: code)
                try await backend.postDuel(duel, to: myCode)
                await refreshDuels()
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    func acceptDuel(_ duel: Duel) {
        guard PaidFeatures.shared.isReady(.friends) else { return }
        var accepted = duel
        accepted.accepted = true
        let backend = backend
        let myCode = myFriendCode
        Task {
            do {
                try await backend.postDuel(accepted, to: duel.challengerCode)
                try await backend.postDuel(accepted, to: myCode)
                await refreshDuels()
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    func refreshDuels() async {
        guard PaidFeatures.shared.isReady(.friends) else { duels = []; return }
        do {
            let raw = try await backend.fetchDuels(for: myFriendCode)
            // Both participants may have posted (invite + accept); keep the most
            // resolved copy of each duel id.
            var map: [String: Duel] = [:]
            for d in raw {
                if let existing = map[d.id] {
                    if d.accepted && !existing.accepted { map[d.id] = d }
                } else {
                    map[d.id] = d
                }
            }
            let recent = Date().timeIntervalSince1970 - 3 * 86_400
            duels = map.values
                .filter { !$0.isFinished || $0.endEpoch > recent }
                .sorted { $0.startEpoch > $1.startEpoch }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// (your score, their score) for a duel, read live from presence.
    func duelScores(_ duel: Duel) -> (mine: Int, theirs: Int) {
        let mine = duel.metric.value(myPresence)
        let theirCode = duel.challengerCode == myFriendCode ? duel.opponentCode : duel.challengerCode
        let theirs = friends.first { $0.presence.code == theirCode }.map { duel.metric.value($0.presence) } ?? 0
        return (mine, theirs)
    }

    func opponentName(_ duel: Duel) -> String {
        duel.challengerCode == myFriendCode ? duel.opponentName : duel.challengerName
    }

    /// A duel that arrived for me and I haven't accepted yet.
    func isIncoming(_ duel: Duel) -> Bool {
        duel.opponentCode == myFriendCode && !duel.accepted
    }

    // MARK: Game Center (optional extra)

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

    func submitWeeklyFocus(minutes: Int) { submit(minutes, to: GameCenterLeaderboard.weeklyFocus) }
    func submitMomentum(_ points: Int) { submit(points, to: GameCenterLeaderboard.momentumAllTime) }

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
}
