import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// The Live Activity shown on the Lock Screen / Dynamic Island while a focus
/// session (Pomodoro or stopwatch) is running. The app drives it through
/// `LiveActivityController`; the widget extension renders it.
///
/// IMPORTANT: this file must be a member of BOTH the Chronos app target and
/// the ChronosWidget target (tick both in the File Inspector). ActivityKit is
/// iOS-only, so everything here is guarded by `#if canImport(ActivityKit)` and
/// simply drops out of the macOS build.
struct FocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// What's being focused on.
        var title: String
        /// Wall-clock epoch the current phase ends at (for Pomodoro) — lets the
        /// widget render a live countdown with `Text(timerInterval:)` without
        /// the app pushing every second.
        var phaseEndEpoch: TimeInterval
        /// Wall-clock epoch the current phase began (for stopwatch count-up).
        var phaseStartEpoch: TimeInterval
        /// "Focus" or "Break".
        var phaseLabel: String
        /// Countdown (Pomodoro) vs. count-up (stopwatch).
        var isCountdown: Bool
        /// Paused shows a static time instead of a running timer.
        var isPaused: Bool
        /// Frozen elapsed/remaining seconds to display while paused.
        var frozenSeconds: TimeInterval
        /// Completed Pomodoro count, for a subtle progress row.
        var completedPomodoros: Int

        var phaseStart: Date { Date(timeIntervalSince1970: phaseStartEpoch) }
        var phaseEnd: Date { Date(timeIntervalSince1970: phaseEndEpoch) }
    }

    /// Static for the life of the activity — the accent color as a hex so the
    /// widget can tint itself to match the app.
    var accentHex: UInt32
}
#endif
