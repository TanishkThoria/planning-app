import Foundation
import UserNotifications
import Combine

/// Schedules a local notification at the end of every upcoming timed block
/// so you get nudged to check in ("How did <title> go?"). Tapping through
/// lands you in the app, where the block review flow asks what happened and
/// offers to reschedule. All local — no server, no push tokens.
@MainActor
final class NotificationService: ObservableObject {

    enum Authorization {
        case notDetermined, authorized, denied
    }

    @Published private(set) var authorization: Authorization = .notDetermined
    /// User's master switch (mirrors a preference; notifications are opt-in).
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    private static let enabledKey = "chronos.notificationsEnabled"
    private static let checkInPrefix = "chronos.checkin."
    private let center = UNUserNotificationCenter.current()

    init() {
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: authorization = .notDetermined
        case .denied: authorization = .denied
        default: authorization = .authorized
        }
    }

    /// Ask the system for permission; returns whether it was granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorization = granted ? .authorized : .denied
            return granted
        } catch {
            authorization = .denied
            return false
        }
    }

    /// Rebuild the schedule from the given blocks. Called after every load
    /// so edits in Chronos or the Apple apps stay reflected. Only future,
    /// timed blocks within the next 48h get a nudge (keeps us well under the
    /// 64 pending-notification limit).
    func rescheduleCheckIns(for blocks: [TimeBlock], now: Date = Date()) {
        guard enabled, authorization == .authorized else {
            center.removeAllPendingNotificationRequests()
            return
        }

        center.getPendingNotificationRequests { [weak self] pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.checkInPrefix) }
            self?.center.removePendingNotificationRequests(withIdentifiers: ids)

            let horizon = now.addingTimeInterval(48 * 3600)
            let upcoming = blocks
                .filter { !$0.isAllDay && $0.end > now && $0.end <= horizon && $0.linkedTaskID != nil }
                .sorted { $0.end < $1.end }
                .prefix(48)

            for block in upcoming {
                let content = UNMutableNotificationContent()
                content.title = "How did it go?"
                content.body = "\(block.title) just wrapped up. Tap to check in."
                content.sound = .default
                content.userInfo = ["blockID": block.id]

                let interval = block.end.timeIntervalSince(now)
                guard interval > 1 else { continue }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(Self.checkInPrefix)\(block.id)",
                    content: content,
                    trigger: trigger
                )
                self?.center.add(request)
            }
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
