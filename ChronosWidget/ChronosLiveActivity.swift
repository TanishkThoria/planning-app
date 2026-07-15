import ActivityKit
import WidgetKit
import SwiftUI

/// The focus-session Live Activity: a Lock Screen banner and Dynamic Island
/// presentation that count down (Pomodoro) or up (stopwatch) in real time.
/// It reads `FocusActivityAttributes`, shared with the app target.
@available(iOS 16.1, *)
struct ChronosFocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color(rgb: 0x000000))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let accent = Color(rgb: context.attributes.accentHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.phaseLabel, systemImage: "timer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(context, font: .system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.completedPomodoros > 0 {
                        Text("\(context.state.completedPomodoros) pomodoro\(context.state.completedPomodoros == 1 ? "" : "s") done")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(accent)
            } compactTrailing: {
                timerText(context, font: .system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(accent)
            }
            .widgetURL(URL(string: "chronos://focus"))
            .keylineTint(accent)
        }
    }

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        let accent = Color(rgb: context.attributes.accentHex)
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.phaseLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(accent)
                Text(context.state.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
            timerText(context, font: .system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(16)
    }

    /// A live-updating timer when running, a frozen value when paused.
    @ViewBuilder
    private func timerText(_ context: ActivityViewContext<FocusActivityAttributes>, font: Font) -> some View {
        if context.state.isPaused {
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

    private func frozen(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
