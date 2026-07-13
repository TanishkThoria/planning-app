import SwiftUI
#if os(iOS)
import ActivityKit
#endif

/// Starts, updates, and ends the focus-session Live Activity. Wired to
/// `FocusTimerController` so the Lock Screen / Dynamic Island mirror the
/// in-app timer. iOS-only; on macOS every method is a no-op.
@MainActor
final class LiveActivityController: ObservableObject {
    static let shared = LiveActivityController()
    private init() {}

    /// Accent color hex, refreshed from the app so the activity matches the theme.
    var accentHex: UInt32 = 0x7C8CF8

    #if os(iOS)
    private var activity: Activity<FocusActivityAttributes>?

    private var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(_ state: FocusActivityAttributes.ContentState) {
        guard areActivitiesEnabled else { return }
        // Only one focus activity at a time — reuse if present.
        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        let attributes = FocusActivityAttributes(accentHex: accentHex)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func update(_ state: FocusActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        let ending = activity
        self.activity = nil
        Task { await ending.end(nil, dismissalPolicy: .immediate) }
    }
    #else
    func start(_ state: Any) {}
    func update(_ state: Any) {}
    func end() {}
    #endif
}
