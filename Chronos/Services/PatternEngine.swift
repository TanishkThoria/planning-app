import Foundation

// Emotional intelligence, quantified over time. PatternEngine correlates the
// self-reported signals (mood, energy, stress) and the clock with what actually
// got done, and surfaces the handful of patterns that are real — "you focus best
// 9–11am", "you struggle after low-energy days". On-device, honest, and only
// spoken once there's enough data to mean something.

struct PatternInsight: Identifiable {
    let id = UUID()
    let icon: String
    let tintHex: UInt32
    let title: String
    let detail: String
}

@MainActor
enum PatternEngine {

    static func insights(life: LifeStore, focus: FocusLog,
                         now: Date = Date(), windowDays: Int = 90) -> [PatternInsight] {
        var out: [PatternInsight] = []
        let since = now.adding(days: -(windowDays - 1)).startOfDay

        let sessions = focus.sessions.filter { Date(timeIntervalSince1970: $0.endEpoch) >= since }

        // 1. Best focus window (hour of day).
        if sessions.count >= 8 {
            var byHour = [Int](repeating: 0, count: 24)
            for s in sessions {
                let h = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: s.startEpoch))
                byHour[h] += s.actualMinutes
            }
            // Best 3-hour window.
            var bestStart = 0, bestSum = -1
            for start in 0...21 {
                let sum = byHour[start] + byHour[start + 1] + byHour[start + 2]
                if sum > bestSum { bestSum = sum; bestStart = start }
            }
            if bestSum > 0 {
                out.append(PatternInsight(
                    icon: "sun.max.fill", tintHex: 0xFFB23E,
                    title: "You focus best \(hourLabel(bestStart))–\(hourLabel(bestStart + 3))",
                    detail: "Most of your deep work lands in this window. Protect it for your hardest task."))
            }

            // 2. Best weekday.
            var byWeekday = [Int](repeating: 0, count: 8)   // 1…7
            for s in sessions {
                let wd = Calendar.current.component(.weekday, from: Date(timeIntervalSince1970: s.startEpoch))
                byWeekday[wd] += s.actualMinutes
            }
            if let best = (1...7).max(by: { byWeekday[$0] < byWeekday[$1] }), byWeekday[best] > 0 {
                out.append(PatternInsight(
                    icon: "calendar", tintHex: 0x5B6CF0,
                    title: "\(Fmt.weekdayFull.string(from: weekdayDate(best))) is your strongest day",
                    detail: "You consistently do the most focused work then — plan your biggest push around it."))
            }
        }

        // Focus minutes per day, for correlation with self-reports.
        var focusByDay: [String: Int] = [:]
        for s in sessions {
            focusByDay[Fmt.dayKey(Date(timeIntervalSince1970: s.startEpoch)), default: 0] += s.actualMinutes
        }
        let entries = life.journal.filter { (Fmt.day(fromKey: $0.dayKey) ?? .distantPast) >= since }

        // 3. Energy ↔ focus.
        if let line = correlationLine(
            entries: entries, focusByDay: focusByDay,
            value: { $0.energy }, highIsGood: true,
            highWord: "high-energy", lowWord: "low-energy") {
            out.append(PatternInsight(icon: "bolt.fill", tintHex: 0x3FC97A,
                title: "Energy shapes your output", detail: line))
        }

        // 4. Stress ↔ focus (higher stress → less focus).
        if let line = correlationLine(
            entries: entries, focusByDay: focusByDay,
            value: { $0.stress }, highIsGood: false,
            highWord: "high-stress", lowWord: "calm") {
            out.append(PatternInsight(icon: "wind", tintHex: 0x22C3C9,
                title: "Stress costs you focus", detail: line))
        }

        // 5. Mood trend.
        let moodLast7 = avgMood(entries, since: now.adding(days: -6).startOfDay, to: now)
        let moodPrev7 = avgMood(entries, since: now.adding(days: -13).startOfDay, to: now.adding(days: -7))
        if let a = moodLast7, let b = moodPrev7, abs(a - b) >= 0.6 {
            let up = a > b
            out.append(PatternInsight(
                icon: up ? "arrow.up.right" : "arrow.down.right",
                tintHex: up ? 0x5BD899 : 0xF2B95C,
                title: up ? "Your mood is trending up" : "Your mood has dipped",
                detail: up
                    ? "This week felt better than last. Whatever you changed, keep doing it."
                    : "This week felt heavier than last. Be gentle — protect sleep and one small win a day."))
        }

        return out
    }

    // MARK: Helpers

    private static func correlationLine(
        entries: [JournalEntry], focusByDay: [String: Int],
        value: (JournalEntry) -> Int?, highIsGood: Bool,
        highWord: String, lowWord: String
    ) -> String? {
        var highMinutes: [Int] = [], lowMinutes: [Int] = []
        for e in entries {
            guard let v = value(e) else { continue }
            let m = focusByDay[e.dayKey] ?? 0
            if v >= 4 { highMinutes.append(m) } else if v <= 2 { lowMinutes.append(m) }
        }
        guard highMinutes.count >= 3, lowMinutes.count >= 3 else { return nil }
        let highAvg = Double(highMinutes.reduce(0, +)) / Double(highMinutes.count)
        let lowAvg = Double(lowMinutes.reduce(0, +)) / Double(lowMinutes.count)
        let better = highIsGood ? highAvg : lowAvg
        let worse = highIsGood ? lowAvg : highAvg
        guard better - worse >= 20 else { return nil }   // needs a real gap (≥20 min)
        let goodWord = highIsGood ? highWord : lowWord
        return "On your \(goodWord) days you focus about \(Fmt.duration(minutes: Int(better - worse))) more than on \(highIsGood ? lowWord : highWord) days."
    }

    private static func avgMood(_ entries: [JournalEntry], since: Date, to: Date) -> Double? {
        let vals = entries.compactMap { e -> Int? in
            guard let d = Fmt.day(fromKey: e.dayKey), d >= since, d <= to else { return nil }
            return e.mood
        }
        guard !vals.isEmpty else { return nil }
        return Double(vals.reduce(0, +)) / Double(vals.count)
    }

    private static func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12am" }
        if h == 12 { return "12pm" }
        return h < 12 ? "\(h)am" : "\(h - 12)pm"
    }
    private static func weekdayDate(_ weekday: Int) -> Date {
        // Any date with the given weekday, for formatting the name.
        var comps = DateComponents(); comps.weekday = weekday; comps.year = 2024; comps.month = 1
        // Jan 2024: find first matching weekday.
        let cal = Calendar.current
        for day in 1...7 {
            var c = DateComponents(); c.year = 2024; c.month = 1; c.day = day
            if let date = cal.date(from: c), cal.component(.weekday, from: date) == weekday { return date }
        }
        return Date()
    }
}
