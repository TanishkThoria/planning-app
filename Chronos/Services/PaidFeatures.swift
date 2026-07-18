import Foundation
import Combine
#if canImport(CloudKit)
import CloudKit
#endif
#if canImport(GameKit)
import GameKit
#endif

/// The paid-account ("Chronos+") capabilities. Each one is fully implemented in
/// code but stays completely dormant until BOTH of these are true:
///
///   1. The underlying Apple capability is present in the build (the entitlement
///      the user adds in Xcode when they upgrade to a paid Developer account),
///      auto-detected at runtime — nothing crashes on the free account.
///   2. The user has flipped the matching toggle in Settings › Chronos+.
///
/// This mirrors how the App Group and Foundation Models features already behave:
/// compile everywhere, run only when available, otherwise no-op with a clear
/// "available on Chronos+" message. See docs/CHRONOS_PLUS_SETUP.md for the
/// one-click turn-on steps.
enum PaidCapability: String, CaseIterable, Identifiable {
    case cloudSync
    case leaderboards
    case friends
    case liveWidgets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloudSync: return "iCloud Sync"
        case .leaderboards: return "Leaderboards"
        case .friends: return "Friends"
        case .liveWidgets: return "Live Widgets"
        }
    }

    var subtitle: String {
        switch self {
        case .cloudSync: return "Your Grow data, momentum, profile & schools on every device."
        case .leaderboards: return "Weekly focus minutes & momentum, ranked with friends."
        case .friends: return "See what your friends are focusing on right now."
        case .liveWidgets: return "Home & Lock Screen widgets that update live."
        }
    }

    var icon: String {
        switch self {
        case .cloudSync: return "arrow.triangle.2.circlepath.icloud"
        case .leaderboards: return "trophy"
        case .friends: return "person.2"
        case .liveWidgets: return "rectangle.stack.badge.play"
        }
    }

    /// The Apple entitlement this capability rides on.
    var entitlementKey: String {
        switch self {
        case .cloudSync, .friends:
            return "com.apple.developer.icloud-container-identifiers"
        case .leaderboards:
            return "com.apple.developer.game-center"
        case .liveWidgets:
            return "com.apple.security.application-groups"
        }
    }
}

/// Whether this build actually ships the paid Apple capabilities. It's driven
/// by the `CHRONOS_PLUS` compilation condition, which the upgrade guide has you
/// add in Xcode at the same time you add the iCloud, App Group and Game Center
/// capabilities (see docs/CHRONOS_PLUS_SETUP.md).
///
/// This is deliberately a compile-time flag rather than a runtime entitlement
/// probe: it means the free account's binary can *never* reach a `CKContainer`
/// or GameKit call (which would crash without the matching entitlement), while
/// the code itself still compiles everywhere so CI keeps validating it.
enum AppEntitlements {
    /// CloudKit-backed features (iCloud sync + friends/presence). Deliberately a
    /// separate gate so the initial launch can ship *without* CloudKit — which
    /// keeps the app easy to transfer between developer accounts. Enable by
    /// adding `CHRONOS_CLOUD` (or the umbrella `CHRONOS_PLUS`) once you're on your
    /// own account and add the iCloud capability.
    static var cloudBuild: Bool {
        #if CHRONOS_PLUS || CHRONOS_CLOUD
        return true
        #else
        return false
        #endif
    }

    /// Game Center global leaderboards. Transfer-safe, so this can ship before a
    /// transfer. Enable with `CHRONOS_GAMECENTER` (or `CHRONOS_PLUS`) plus the
    /// Game Center capability.
    static var gameCenterBuild: Bool {
        #if CHRONOS_PLUS || CHRONOS_GAMECENTER
        return true
        #else
        return false
        #endif
    }

    /// The umbrella flag turns everything on at once (used post-transfer).
    static var chronosPlusBuild: Bool {
        #if CHRONOS_PLUS
        return true
        #else
        return false
        #endif
    }

    /// Live widgets ride on the App Group — detected at runtime, so no compile
    /// flag is needed, just the App Group capability added in Xcode. Also
    /// transfer-safe.
    static let appGroupConfigured: Bool = {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ChronosShared.appGroupID
        ) != nil
    }()
}

@MainActor
final class PaidFeatures: ObservableObject {
    static let shared = PaidFeatures()

    /// iCloud account reachability (only meaningful when the iCloud entitlement
    /// is present).
    enum ICloudState: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case unavailable
    }

    @Published private(set) var iCloud: ICloudState = .unknown
    @Published private(set) var gameCenterAuthenticated = false

    /// The master toggle. Off by default; flipping it on only matters when at
    /// least one capability is entitled.
    var masterEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Prefs.chronosPlusEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Prefs.chronosPlusEnabled) }
    }

    private init() {}

    // MARK: Entitlement presence (compile-time capability actually shipped)

    func isEntitled(_ capability: PaidCapability) -> Bool {
        // Per-capability so the CloudKit-free features (Game Center leaderboards,
        // live widgets) can ship independently of iCloud/CloudKit — see
        // AppEntitlements. On the free build these are all false and no paid
        // framework is ever touched.
        switch capability {
        case .cloudSync, .friends: return AppEntitlements.cloudBuild
        case .leaderboards:        return AppEntitlements.gameCenterBuild
        case .liveWidgets:         return AppEntitlements.appGroupConfigured
        }
    }

    /// Any paid capability shipped in this build? (false on the free account)
    var anyCapabilityEntitled: Bool {
        PaidCapability.allCases.contains { isEntitled($0) }
    }

    // MARK: Ready = entitled + account-available + user opted-in

    private func userEnabled(_ capability: PaidCapability) -> Bool {
        guard masterEnabled else { return false }
        let defaults = UserDefaults.standard
        switch capability {
        case .cloudSync:
            return defaults.object(forKey: Prefs.cloudSyncEnabled) == nil
                ? true : defaults.bool(forKey: Prefs.cloudSyncEnabled)
        case .leaderboards, .friends:
            return defaults.object(forKey: Prefs.socialEnabled) == nil
                ? true : defaults.bool(forKey: Prefs.socialEnabled)
        case .liveWidgets:
            return defaults.object(forKey: Prefs.liveWidgetsEnabled) == nil
                ? true : defaults.bool(forKey: Prefs.liveWidgetsEnabled)
        }
    }

    /// The one check every paid code path gates on. All three must hold.
    func isReady(_ capability: PaidCapability) -> Bool {
        guard isEntitled(capability), userEnabled(capability) else { return false }
        switch capability {
        case .cloudSync, .friends:
            return iCloud == .available
        case .leaderboards:
            return true   // GameKit auth is handled lazily by SocialService
        case .liveWidgets:
            return true
        }
    }

    /// A human-readable reason a capability isn't active yet, for the UI.
    func status(for capability: PaidCapability) -> String {
        if !isEntitled(capability) {
            return "Add the capability in Xcode after upgrading — see setup guide."
        }
        if !masterEnabled { return "Turn on Chronos+ to enable." }
        if !userEnabled(capability) { return "Turned off." }
        if (capability == .cloudSync || capability == .friends) && iCloud != .available {
            switch iCloud {
            case .noAccount: return "Sign in to iCloud in System Settings."
            case .restricted: return "iCloud is restricted on this device."
            case .unavailable, .unknown: return "iCloud is unavailable right now."
            case .available: break
            }
        }
        return "Active."
    }

    // MARK: Refresh (safe on the free account — never touches CloudKit unless entitled)

    func refresh() {
        refreshICloud()
    }

    private func refreshICloud() {
        #if canImport(CloudKit)
        guard isEntitled(.cloudSync) else { iCloud = .unavailable; return }
        CKContainer.default().accountStatus { [weak self] status, _ in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .available: self.iCloud = .available
                case .noAccount: self.iCloud = .noAccount
                case .restricted: self.iCloud = .restricted
                case .couldNotDetermine, .temporarilyUnavailable: self.iCloud = .unknown
                @unknown default: self.iCloud = .unknown
                }
            }
        }
        #else
        iCloud = .unavailable
        #endif
    }
}
