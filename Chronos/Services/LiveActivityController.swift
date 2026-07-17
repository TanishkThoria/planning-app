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
            Task { await activity.update(content(for: state)) }
            return
        }
        let attributes = FocusActivityAttributes(accentHex: accentHex)
        activity = try? Activity.request(
            attributes: attributes,
            content: content(for: state),
            pushType: nil
        )
    }

    func update(_ state: FocusActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(content(for: state)) }
    }

    /// A running countdown goes stale exactly when the phase ends, so the widget
    /// can flip to a calm "Done" state instead of a frozen 0:00 if the app isn't
    /// around to push the next phase.
    private func content(for state: FocusActivityAttributes.ContentState) -> ActivityContent<FocusActivityAttributes.ContentState> {
        let staleDate: Date? = (state.isCountdown && !state.isPaused) ? state.phaseEnd : nil
        return ActivityContent(state: state, staleDate: staleDate)
    }

    func end() {
        guard let activity else { return }
        let ending = activity
        self.activity = nil
        Task { await ending.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: Current-block activity

    /// A second Live Activity that mirrors whatever calendar block you're in
    /// right now (countdown to its end). Reuses the focus attributes so the
    /// widget extension needs no new shared files. The focus timer's activity
    /// always takes priority.
    private var blockActivity: Activity<FocusActivityAttributes>?
    private var blockActivityID: String?
    private var blockActivityEnd: Date?

    func syncBlock(_ block: TimeBlock?, focusActive: Bool) {
        guard areActivitiesEnabled else { return }

        // Focus session running, no current block, or the block already
        // finished → tear down.
        guard let block, !focusActive, block.end > Date() else {
            endBlockActivity()
            return
        }

        // Already showing exactly this block (same occurrence + end time) —
        // nothing to do; it's scheduled to remove itself when the block ends.
        if blockActivityID == block.id, blockActivityEnd == block.end { return }

        endBlockActivity()

        let state = FocusActivityAttributes.ContentState(
            title: block.title,
            phaseEndEpoch: block.end.timeIntervalSince1970,
            phaseStartEpoch: block.start.timeIntervalSince1970,
            phaseLabel: "Now",
            isCountdown: true,
            isPaused: false,
            frozenSeconds: 0,
            completedPomodoros: 0
        )
        let requested = try? Activity.request(
            attributes: FocusActivityAttributes(accentHex: accentHex),
            content: ActivityContent(state: state, staleDate: block.end),
            pushType: nil
        )
        blockActivity = requested
        blockActivityID = requested != nil ? block.id : nil
        blockActivityEnd = requested != nil ? block.end : nil

        // Chronos has no push server to end this remotely, so ask the system to
        // remove it exactly when the block ends — even if the app never runs
        // again before then (locked phone, backgrounded). The countdown keeps
        // ticking until that moment because it's rendered from the time
        // interval, not pushed updates. This is what stops it lingering at 0:00.
        if let requested {
            Task { await requested.end(nil, dismissalPolicy: .after(block.end)) }
        }
    }

    private func endBlockActivity() {
        guard let blockActivity else { return }
        let ending = blockActivity
        self.blockActivity = nil
        blockActivityID = nil
        blockActivityEnd = nil
        Task { await ending.end(nil, dismissalPolicy: .immediate) }
    }
    #else
    func start(_ state: Any) {}
    func update(_ state: Any) {}
    func end() {}
    func syncBlock(_ block: TimeBlock?, focusActive: Bool) {}
    #endif
}
