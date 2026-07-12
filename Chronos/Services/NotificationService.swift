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
    private static let ritualPrefix = "chronos.ritual."
    private static let habitPrefix = "chronos.habit."
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

    // MARK: Daily rituals + habit nudges

    /// A repeating daily notification at a given minute-of-day.
    private func scheduleDaily(id: String, title: String, body: String, minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func clear(prefix: String) {
        center.getPendingNotificationRequests { [weak self] pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            self?.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Morning planning + evening reflection nudges. Pass nil to disable one.
    func scheduleRituals(morningMinutes: Int?, eveningMinutes: Int?) {
        clear(prefix: Self.ritualPrefix)
        guard enabled, authorization == .authorized else { return }
        if let m = morningMinutes {
            scheduleDaily(id: "\(Self.ritualPrefix)morning",
                          title: "Plan your day",
                          body: "Take two minutes to lay out today before it runs away.",
                          minutes: m)
        }
        if let e = eveningMinutes {
            scheduleDaily(id: "\(Self.ritualPrefix)evening",
                          title: "Reflect on today",
                          body: "How did it go? Review what slipped and set tomorrow's intentions.",
                          minutes: e)
        }
    }

    /// Per-habit reminders at their configured time-of-day.
    func scheduleHabitReminders(_ reminders: [(id: String, title: String, minutes: Int)]) {
        clear(prefix: Self.habitPrefix)
        guard enabled, authorization == .authorized else { return }
        for r in reminders.prefix(16) {
            scheduleDaily(id: "\(Self.habitPrefix)\(r.id)",
                          title: "Habit reminder",
                          body: r.title,
                          minutes: r.minutes)
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
