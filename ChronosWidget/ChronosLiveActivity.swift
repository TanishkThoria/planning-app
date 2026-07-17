import ActivityKit
import WidgetKit
import SwiftUI

/// The Chronos Live Activity — used for both a running focus session (Pomodoro
/// or stopwatch) and the calendar block you're currently in. It shows a live
/// countdown/count-up on the Lock Screen, in the Dynamic Island, and on the
/// CarPlay dashboard and StandBy, all driven from `FocusActivityAttributes`.
///
/// When the timer runs out the content flips to a calm "Done" state (rather
/// than a frozen 0:00); the block activity is also scheduled to remove itself
/// at the block's end, so nothing lingers on the Lock Screen.
@available(iOS 16.1, *)
struct ChronosFocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color(rgb: 0x000000))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let accent = Color(rgb: context.attributes.accentHex)
            let finished = isFinished(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(finished ? "Done" : context.state.phaseLabel, systemImage: leadingIcon(context))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(finished ? Color(rgb: 0x30D158) : accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(context, font: .system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !finished, context.state.completedPomodoros > 0 {
                        Text("\(context.state.completedPomodoros) pomodoro\(context.state.completedPomodoros == 1 ? "" : "s") done")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            } compactLeading: {
                Image(systemName: leadingIcon(context))
                    .foregroundStyle(finished ? Color(rgb: 0x30D158) : accent)
            } compactTrailing: {
                timerText(context, font: .system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: leadingIcon(context))
                    .foregroundStyle(finished ? Color(rgb: 0x30D158) : accent)
            }
            .widgetURL(URL(string: isBlock(context) ? "chronos://today" : "chronos://focus"))
            .keylineTint(accent)
        }
    }

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        let accent = Color(rgb: context.attributes.accentHex)
        let finished = isFinished(context)
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                Image(systemName: finished ? "checkmark" : lockIcon(context))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(finished ? Color(rgb: 0x30D158) : accent)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text((finished ? "Done" : context.state.phaseLabel).uppercased())
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(finished ? Color(rgb: 0x30D158) : accent)
                Text(context.state.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            timerText(context, font: .system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(16)
    }

    /// The live timer while running, a frozen value while paused, and a calm
    /// checkmark once the phase/block is over.
    @ViewBuilder
    private func timerText(_ context: ActivityViewContext<FocusActivityAttributes>, font: Font) -> some View {
        if isFinished(context) {
            Image(systemName: "checkmark.circle.fill")
                .font(font)
                .foregroundStyle(Color(rgb: 0x30D158))
        } else if context.state.isPaused {
            Text(frozen(context.state.frozenSeconds))
                .font(font)
        } else if context.state.isCountdown {
            Text(timerInterval: Date()...context.state.phaseEnd, countsDown: true)
                .font(font)
                .multilineTextAlignment(.trailing)
        } else {
            Text(timerInterval: context.state.phaseStart...Date.distantFuture, countsDown: false)
                .font(font)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Helpers

    /// The block activity reuses these attributes; its phase label is "Now".
    private func isBlock(_ context: ActivityViewContext<FocusActivityAttributes>) -> Bool {
        context.state.phaseLabel == "Now"
    }

    /// Finished when the system has marked the content stale (past its end) or a
    /// countdown has run out.
    private func isFinished(_ context: ActivityViewContext<FocusActivityAttributes>) -> Bool {
        if context.isStale { return true }
        return context.state.isCountdown && !context.state.isPaused
            && context.state.phaseEnd <= Date()
    }

    private func leadingIcon(_ context: ActivityViewContext<FocusActivityAttributes>) -> String {
        if isFinished(context) { return "checkmark.circle.fill" }
        if context.state.isPaused { return "pause.fill" }
        return isBlock(context) ? "calendar" : "timer"
    }

    private func lockIcon(_ context: ActivityViewContext<FocusActivityAttributes>) -> String {
        if context.state.isPaused { return "pause.fill" }
        return isBlock(context) ? "calendar" : "timer"
    }

    private func frozen(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
