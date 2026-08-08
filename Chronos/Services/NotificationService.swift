import Foundation
import UserNotifications
import Combine

/// Schedules a local notification at the end of every upcoming timed block
/// so you get nudged to check in ("How did <title> go?"). Tapping through
/// lands you in the app, where the block review flow asks what happened and
/// offers to reschedule. All local — no server, no push tokens.
@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    enum Authorization {
        case notDetermined, authorized, denied
    }

    /// Where a tapped notification should take the user. RootView observes
    /// this and navigates, then clears it.
    enum Route: Equatable {
        case checkIn(blockID: String)
        case planMorning
        case reflectEvening
        case weeklyReview
        case grow
        case openToday
    }

    @Published private(set) var authorization: Authorization = .notDetermined
    /// Set when the user taps a notification; consumed by RootView.
    @Published var pendingRoute: Route?
    /// User's master switch (mirrors a preference; notifications are opt-in).
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    private static let enabledKey = "chronos.notificationsEnabled"
    private static let checkInPrefix = "chronos.checkin."
    private static let startPrefix = "chronos.blockstart."
    private static let ritualPrefix = "chronos.ritual."
    private static let weeklyPrefix = "chronos.weekly."
    private static let habitPrefix = "chronos.habit."
    private static let routinePrefix = "chronos.routine."
    private let center = UNUserNotificationCenter.current()

    override init() {
        // On by default — the system permission prompt is the real gate.
        // (This was previously opt-in AND permission-gated, which meant a
        // fresh install never fired a single notification.)
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        super.init()
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    // MARK: Delegate — foreground presentation + tap routing

    /// Show reminders as banners even while Chronos is open, instead of
    /// silently swallowing them (the default).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Route a tapped notification to the matching screen/flow.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        let blockID = response.notification.request.content.userInfo["blockID"] as? String
        Task { @MainActor in
            self.pendingRoute = Self.route(for: id, blockID: blockID)
        }
        completionHandler()
    }

    private static func route(for identifier: String, blockID: String?) -> Route {
        if identifier.hasPrefix(checkInPrefix), let blockID {
            return .checkIn(blockID: blockID)
        }
        if identifier.hasPrefix(startPrefix) { return .openToday }
        if identifier == "\(ritualPrefix)morning" { return .planMorning }
        if identifier == "\(ritualPrefix)evening" { return .reflectEvening }
        if identifier.hasPrefix(weeklyPrefix) { return .weeklyReview }
        return .grow
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

    /// Rebuild the block-driven schedule (start alerts + end-of-block
    /// check-ins) from the given blocks. Called after every load so edits in
    /// Chronos or the Apple apps stay reflected. Only future, timed blocks
    /// within the next 48h are scheduled (keeps us well under the 64
    /// pending-notification limit).
    func rescheduleCheckIns(for blocks: [TimeBlock], startAlerts: Bool = true, now: Date = Date()) {
        guard enabled, authorization == .authorized else {
            // Clear only our block-driven requests — rituals and habit
            // reminders have their own switches and must survive this.
            clear(prefix: Self.checkInPrefix)
            clear(prefix: Self.startPrefix)
            return
        }

        center.getPendingNotificationRequests { [weak self] pending in
            guard let self else { return }
            let ids = pending.map(\.identifier).filter {
                $0.hasPrefix(Self.checkInPrefix) || $0.hasPrefix(Self.startPrefix)
            }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)

            let horizon = now.addingTimeInterval(48 * 3600)
            let timed = blocks.filter { !$0.isAllDay }

            // "Starting in 5 minutes" heads-ups for every upcoming block.
            if startAlerts {
                let starting = timed
                    .filter { $0.start > now.addingTimeInterval(120) && $0.start <= horizon }
                    .sorted { $0.start < $1.start }
                    .prefix(24)
                for block in starting {
                    let lead = min(5 * 60.0, max(60, block.start.timeIntervalSince(now) - 30))
                    let content = UNMutableNotificationContent()
                    content.title = block.title
                    content.body = "Starts at \(Fmt.time.string(from: block.start))."
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(
                        timeInterval: block.start.timeIntervalSince(now) - lead, repeats: false
                    )
                    self.center.add(UNNotificationRequest(
                        identifier: "\(Self.startPrefix)\(block.id)",
                        content: content, trigger: trigger
                    ))
                }
            }

            // "How did it go?" check-ins when a task-linked block wraps up.
            let ending = timed
                .filter { $0.end > now && $0.end <= horizon && $0.linkedTaskID != nil }
                .sorted { $0.end < $1.end }
                .prefix(24)
            for block in ending {
                let content = UNMutableNotificationContent()
                content.title = "How did it go?"
                content.body = "\(block.title) just wrapped up. Tap to check in."
                content.sound = .default
                content.userInfo = ["blockID": block.id]

                let interval = block.end.timeIntervalSince(now)
                guard interval > 1 else { continue }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                self.center.add(UNNotificationRequest(
                    identifier: "\(Self.checkInPrefix)\(block.id)",
                    content: content, trigger: trigger
                ))
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

    /// A weekly review nudge on the given weekday (1 = Sunday … 7 = Saturday)
    /// at a time-of-day. Pass a nil weekday to disable it.
    func scheduleWeeklyReview(weekday: Int?, minutes: Int) {
        clear(prefix: Self.weeklyPrefix)
        guard enabled, authorization == .authorized, let weekday else { return }
        let content = UNMutableNotificationContent()
        content.title = "Weekly review"
        content.body = "Look back on your week and set up the one ahead — it takes five minutes."
        content.sound = .default
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "\(Self.weeklyPrefix)review", content: content, trigger: trigger))
    }

    /// Per-habit reminders at their configured time-of-day. `anchored` habits
    /// happen *at* that moment, so they get an at-the-time "it's time" framing
    /// instead of a loose nudge.
    func scheduleHabitReminders(_ reminders: [(id: String, title: String, minutes: Int, anchored: Bool)]) {
        clear(prefix: Self.habitPrefix)
        guard enabled, authorization == .authorized else { return }
        for r in reminders.prefix(16) {
            scheduleDaily(id: "\(Self.habitPrefix)\(r.id)",
                          title: r.anchored ? r.title : "Habit reminder",
                          body: r.anchored ? "It's time — \(r.title)." : r.title,
                          minutes: r.minutes)
        }
    }

    /// Daily reminders for tracked routines you're establishing.
    func scheduleRoutineReminders(_ reminders: [(id: String, name: String, minutes: Int)]) {
        clear(prefix: Self.routinePrefix)
        guard enabled, authorization == .authorized else { return }
        for r in reminders.prefix(12) {
            scheduleDaily(id: "\(Self.routinePrefix)\(r.id)",
                          title: "Time for \(r.name)",
                          body: "Follow your routine step by step, and keep the streak going.",
                          minutes: r.minutes)
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
