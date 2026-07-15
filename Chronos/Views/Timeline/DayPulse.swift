import SwiftUI

/// A quick health-check of a day's shape: back-to-back marathons, overbooking,
/// deep work drifting outside your focus window, a squeezed lunch. The score
/// chip lives in the day header; tapping it explains exactly what to fix.
enum DayPulse {

    struct Finding: Identifiable {
        let id = UUID()
        var icon: String
        var tint: Color
        var title: String
        var detail: String
    }

    struct Result {
        var score: Int
        var findings: [Finding]
        var tint: Color {
            score >= 80 ? Theme.success : (score >= 55 ? Theme.warning : Theme.danger)
        }
    }

    static func analyze(
        blocks: [TimeBlock],
        day: Date,
        workStartMinutes: Int,
        workEndMinutes: Int,
        profile: PlannerProfile?,
        taskLookup: (String) -> TaskItem?
    ) -> Result {
        let timed = blocks
            .filter { !$0.isAllDay }
            .compactMap { block in block.clamped(to: day).map { (block: block, start: $0.start, end: $0.end) } }
            .sorted { $0.start < $1.start }

        var score = 100
        var findings: [Finding] = []

        guard !timed.isEmpty else {
            return Result(score: 100, findings: [Finding(
                icon: "square.dashed", tint: Theme.textTertiary,
                title: "Open canvas",
                detail: "Nothing scheduled — plan the day to give it a shape."
            )])
        }

        // 1. Longest back-to-back stretch (gaps under 10 minutes don't count
        //    as breaks).
        var runStart = timed[0].start
        var runEnd = timed[0].end
        var longestRun: TimeInterval = 0
        for item in timed.dropFirst() {
            if item.start.timeIntervalSince(runEnd) < 10 * 60 {
                runEnd = max(runEnd, item.end)
            } else {
                longestRun = max(longestRun, runEnd.timeIntervalSince(runStart))
                runStart = item.start
                runEnd = item.end
            }
        }
        longestRun = max(longestRun, runEnd.timeIntervalSince(runStart))
        if longestRun >= 150 * 60 {
            score -= 25
            findings.append(Finding(
                icon: "figure.run", tint: Theme.warning,
                title: "\(Fmt.duration(longestRun)) back-to-back",
                detail: "That's a long stretch with no real break. Even 10 minutes between blocks protects the later hours from the earlier ones."
            ))
        }

        // 2. Booked ratio inside the working window.
        let window = max(workEndMinutes - workStartMinutes, 60)
        let planned = timed.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        let ratio = Double(planned) / Double(window)
        if ratio >= 0.85 {
            score -= 20
            findings.append(Finding(
                icon: "gauge.with.dots.needle.100percent", tint: Theme.danger,
                title: "\(Int((ratio * 100).rounded()))% booked",
                detail: "There's almost no slack. One overrun cascades into everything after it — consider reflowing something to tomorrow."
            ))
        }

        // 3. Deep work outside the calibrated focus window.
        if let profile, profile.isCalibrated {
            let focus = profile.focus.windowMinutes
            let focusStart = day.at(minutes: focus.start)
            let focusEnd = day.at(minutes: focus.end)
            let misplaced = timed.filter { item in
                guard let taskID = item.block.linkedTaskID,
                      taskLookup(taskID)?.energy == .deep else { return false }
                return item.end <= focusStart || item.start >= focusEnd
            }
            if !misplaced.isEmpty {
                score -= 15
                findings.append(Finding(
                    icon: "brain.head.profile", tint: Theme.warning,
                    title: "Deep work outside your focus window",
                    detail: "\(misplaced.count == 1 ? "A deep-work block sits" : "\(misplaced.count) deep-work blocks sit") outside your \(profile.focus.rawValue.lowercased()) focus window. Moving \(misplaced.count == 1 ? "it" : "them") there buys the same work for less effort."
                ))
            }
        }

        // 4. Midday squeeze — no 20-minute opening between 11:30 and 14:00.
        let lunchStart = day.at(minutes: 11 * 60 + 30)
        let lunchEnd = day.at(minutes: 14 * 60)
        var cursor = lunchStart
        var lunchGap: TimeInterval = 0
        for item in timed where item.end > lunchStart && item.start < lunchEnd {
            lunchGap = max(lunchGap, item.start.timeIntervalSince(cursor))
            cursor = max(cursor, item.end)
        }
        lunchGap = max(lunchGap, lunchEnd.timeIntervalSince(cursor))
        if lunchGap < 20 * 60 && timed.contains(where: { $0.end > lunchStart && $0.start < lunchEnd }) {
            score -= 15
            findings.append(Finding(
                icon: "fork.knife", tint: Theme.warning,
                title: "No room at lunch",
                detail: "Midday is wall-to-wall. Protect at least 20 minutes — afternoons run on it."
            ))
        }

        if findings.isEmpty {
            findings.append(Finding(
                icon: "checkmark.seal.fill", tint: Theme.success,
                title: "Well-shaped day",
                detail: "Breaks where you need them, a sane load, and work in the right places. Go live it."
            ))
        }
        return Result(score: max(score, 0), findings: findings)
    }
}

/// The header chip + explanatory sheet.
struct DayPulseChip: View {
    let result: DayPulse.Result
    @State private var showDetail = false
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 5) {
                Circle().fill(result.tint).frame(width: 7, height: 7)
                Text("\(result.score)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Day pulse — how healthy is this day's shape?")
        .sheet(isPresented: $showDetail) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(Theme.fill, lineWidth: 6).frame(width: 52, height: 52)
                        Circle()
                            .trim(from: 0, to: Double(result.score) / 100)
                            .stroke(result.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 52, height: 52)
                        Text("\(result.score)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Day pulse")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("The shape of this day, honestly")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }

                ForEach(result.findings) { finding in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: finding.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(finding.tint)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(finding.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(finding.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                if result.score < 80 {
                    Button {
                        showDetail = false
                        model.reflowPresented = true
                    } label: {
                        Label("Reflow the day", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.accentColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(Theme.bg)
            .chronosAppearance()
            #if os(iOS)
            .presentationDetents([.medium])
            #else
            .frame(minWidth: 380, minHeight: 380)
            #endif
        }
    }
}
