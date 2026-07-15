import SwiftUI

/// Runs a routine hands-free: each step counts down, auto-advances, and (if
/// voice is on) is announced aloud — so you can just do the thing instead of
/// managing a timer. Built for time-blindness (Routinery's core idea).
struct RoutineRunnerView: View {
    let routine: Routine
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.routineVoiceEnabled) private var voiceEnabled = true

    @State private var stepIndex = 0
    @State private var running = true
    @State private var finished = false
    @State private var stepEndDate = Date()
    @State private var pausedRemaining = 0
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let speaker = RoutineSpeaker.shared

    private var steps: [RoutineStep] { routine.steps }
    private var current: RoutineStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    private var next: RoutineStep? { steps.indices.contains(stepIndex + 1) ? steps[stepIndex + 1] : nil }

    private var remaining: Int {
        running ? max(0, Int(stepEndDate.timeIntervalSince(now).rounded(.up))) : pausedRemaining
    }
    private var stepProgress: Double {
        guard let current, current.seconds > 0 else { return 0 }
        return 1 - Double(remaining) / Double(current.seconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            if finished { finishedView } else { runnerView }
        }
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 420, height: 560)
        #else
        .presentationDetents([.large])
        #endif
        .onAppear { begin(0) }
        .onDisappear { speaker.stop() }
        .onReceive(tick) { value in
            now = value
            if running, !finished, remaining <= 0 { advance() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("\(routine.emoji) \(routine.name)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { voiceEnabled.toggle(); if !voiceEnabled { speaker.stop() } } label: {
                Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(voiceEnabled ? Theme.accentColor : Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Runner

    private var runnerView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("STEP \(stepIndex + 1) OF \(steps.count)")
                .font(.system(size: 12.5, weight: .bold)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            Text(current?.title ?? "")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            ZStack {
                Circle().stroke(Theme.fill, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: stepProgress)
                    .stroke(Theme.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: stepProgress)
                Text(timeText(remaining))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            .frame(width: 220, height: 220)

            if let next {
                Text("Next: \(next.title) · \(next.minutes) min")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Last step — you're almost there.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.success)
            }

            Spacer()
            progressDots
            controls.padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressDots: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { idx, _ in
                Capsule()
                    .fill(idx < stepIndex ? Theme.accentColor
                          : idx == stepIndex ? Theme.accentColor.opacity(0.55) : Theme.fill)
                    .frame(height: 4)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            control("backward.fill", "Back", Theme.textSecondary) { begin(max(0, stepIndex - 1)) }
            control(running ? "pause.fill" : "play.fill", running ? "Pause" : "Resume", Theme.accentColor, prominent: true) {
                running ? pause() : resume()
            }
            control("forward.fill", "Skip", Theme.textSecondary) { advance() }
        }
    }

    private func control(_ icon: String, _ label: String, _ tint: Color, prominent: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: prominent ? 22 : 17, weight: .semibold))
                    .foregroundStyle(prominent ? Theme.bg : tint)
                    .frame(width: prominent ? 64 : 52, height: prominent ? 64 : 52)
                    .background(prominent ? tint : Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(prominent ? Color.clear : Theme.hairline, lineWidth: 1))
                Text(label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Finished

    private var finishedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(routine.emoji).font(.system(size: 56))
            Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(Theme.success)
            Text("\(routine.name) complete")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(steps.count) steps · \(routine.totalMinutes) min. Nicely done.")
                .font(.system(size: 14.5)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { dismiss() } label: {
                Text("Done").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Flow

    private func begin(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        stepIndex = index
        let seconds = steps[index].seconds
        now = Date()
        stepEndDate = now.addingTimeInterval(TimeInterval(seconds))
        pausedRemaining = seconds
        running = true
        announce(steps[index])
    }

    private func advance() {
        if stepIndex + 1 < steps.count {
            begin(stepIndex + 1)
        } else {
            finish()
        }
    }

    private func pause() {
        pausedRemaining = remaining
        running = false
        speaker.stop()
    }

    private func resume() {
        now = Date()
        stepEndDate = now.addingTimeInterval(TimeInterval(pausedRemaining))
        running = true
    }

    private func finish() {
        running = false
        finished = true
        Haptics.success()
        if voiceEnabled { speaker.speak("\(routine.name) complete. Nice work.") }
    }

    private func announce(_ step: RoutineStep) {
        Haptics.light()
        guard voiceEnabled else { return }
        speaker.speak("Now: \(step.title). \(step.minutes) minute\(step.minutes == 1 ? "" : "s").")
    }

    private func timeText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
