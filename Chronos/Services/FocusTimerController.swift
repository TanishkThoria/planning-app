import SwiftUI
import Combine

/// App-wide focus timer. Runs a Pomodoro cycle or an open stopwatch against
/// an optional task, survives navigation (it's injected at the app root and
/// surfaced as a floating pill), and logs completed focus time to the
/// `FocusLog` for the Insights stats. Time is derived from wall-clock
/// timestamps so it stays correct across backgrounding.
@MainActor
final class FocusTimerController: ObservableObject {

    enum Mode { case pomodoro, stopwatch }
    enum Phase { case focus, rest }

    @Published private(set) var isActive = false
    @Published private(set) var isRunning = false
    @Published private(set) var mode: Mode = .pomodoro
    @Published private(set) var phase: Phase = .focus
    @Published private(set) var taskID: String?
    @Published private(set) var taskTitle: String = "Focus"
    @Published private(set) var completedPomodoros = 0

    /// Seconds counted in the current phase before the latest resume.
    private var accumulated: TimeInterval = 0
    private var lastResumeEpoch: TimeInterval = 0
    /// Wall-clock start of the current focus stretch (for logging).
    private var focusStartEpoch: TimeInterval = 0

    var focusMinutes = 25
    var breakMinutes = 5

    /// Called when a focus stretch ends (finished or stopped) with logged time.
    var onSessionComplete: ((FocusSession) -> Void)?

    /// Elapsed seconds in the current phase.
    func elapsed(at now: Date = Date()) -> TimeInterval {
        accumulated + (isRunning ? now.timeIntervalSince1970 - lastResumeEpoch : 0)
    }

    /// For Pomodoro: seconds remaining in the phase (clamped ≥ 0).
    func remaining(at now: Date = Date()) -> TimeInterval {
        max(0, phaseLength - elapsed(at: now))
    }

    var phaseLength: TimeInterval {
        TimeInterval((phase == .focus ? focusMinutes : breakMinutes) * 60)
    }

    var progress: Double {
        guard mode == .pomodoro, phaseLength > 0 else { return 0 }
        return min(1, elapsed() / phaseLength)
    }

    // MARK: Control

    func start(taskID: String?, title: String, mode: Mode) {
        self.taskID = taskID
        self.taskTitle = title.isEmpty ? "Focus" : title
        self.mode = mode
        phase = .focus
        completedPomodoros = 0
        accumulated = 0
        focusStartEpoch = Date().timeIntervalSince1970
        lastResumeEpoch = focusStartEpoch
        isActive = true
        isRunning = true
    }

    func pause() {
        guard isRunning else { return }
        accumulated = elapsed()
        isRunning = false
    }

    func resume() {
        guard isActive, !isRunning else { return }
        lastResumeEpoch = Date().timeIntervalSince1970
        isRunning = true
    }

    func toggle() { isRunning ? pause() : resume() }

    /// Called by the ticking view when a Pomodoro phase reaches zero.
    func phaseElapsedIfNeeded(at now: Date = Date()) {
        guard mode == .pomodoro, isRunning, elapsed(at: now) >= phaseLength else { return }
        advancePhase()
    }

    /// Move to the next Pomodoro phase, logging a completed focus stretch.
    func advancePhase() {
        if phase == .focus {
            logFocus(completedFull: true)
            completedPomodoros += 1
            phase = .rest
        } else {
            phase = .focus
            focusStartEpoch = Date().timeIntervalSince1970
        }
        accumulated = 0
        lastResumeEpoch = Date().timeIntervalSince1970
        isRunning = true
    }

    /// Stop everything, logging any focus time in progress.
    func stop() {
        if phase == .focus {
            logFocus(completedFull: mode == .pomodoro && elapsed() >= phaseLength)
        }
        isActive = false
        isRunning = false
        taskID = nil
        accumulated = 0
        phase = .focus
    }

    private func logFocus(completedFull: Bool) {
        let now = Date().timeIntervalSince1970
        let minutes = Int((now - focusStartEpoch) / 60)
        guard minutes >= 1 else { return }
        let session = FocusSession(
            taskID: taskID,
            taskTitle: taskTitle,
            startEpoch: focusStartEpoch,
            endEpoch: now,
            plannedMinutes: mode == .pomodoro ? focusMinutes : minutes,
            wasPomodoro: mode == .pomodoro,
            completedFullDuration: completedFull
        )
        onSessionComplete?(session)
        focusStartEpoch = now
    }
}
