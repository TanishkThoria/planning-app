import SwiftUI

/// The reflection journal: morning intentions (your top three), a mood +
/// energy check-in, and evening reflection prompts. One entry per day,
/// navigable back through history.
struct JournalView: View {
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var day = Date().startOfDay
    @State private var entry = JournalEntry(dayKey: Fmt.dayKey(Date()))

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intentionsSection
                    checkInSection
                    reflectionSection
                    if Calendar.current.isDateInToday(day) { onThisDaySection }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 480, height: 640)
        #else
        .presentationDetents([.large])
        #endif
        .onAppear { load() }
        .onChange(of: day) { _, _ in load() }
    }

    private func load() { entry = life.entryOrNew(for: day) }
    private func persist() { life.upsert(entry) }

    // MARK: On This Day — resurface past reflections (Day One's beloved feature)

    @ViewBuilder
    private var onThisDaySection: some View {
        let memories = memories
        if !memories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "On this day")
                ForEach(memories, id: \.entry.id) { memory in
                    Button { persist(); day = Fmt.day(fromKey: memory.entry.dayKey) ?? day } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(memory.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Text(snippet(memory.entry))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var memories: [(label: String, entry: JournalEntry)] {
        let cal = Calendar.current
        var dates: [Date] = [7, 30, 90, 180, 365].map { day.adding(days: -$0) }
        for y in 1...3 {
            if let past = cal.date(byAdding: .year, value: -y, to: day) { dates.append(past.startOfDay) }
        }
        var seen = Set<String>([Fmt.dayKey(day)])
        var out: [(String, JournalEntry)] = []
        for date in dates.sorted(by: >) {
            let key = Fmt.dayKey(date)
            if seen.contains(key) { continue }
            seen.insert(key)
            if let e = life.entry(for: date), e.hasEvening || e.hasMorning {
                out.append((memoryLabel(from: date), e))
            }
        }
        return out
    }

    private func memoryLabel(from date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date.startOfDay, to: day).day ?? 0
        switch days {
        case 7: return "1 week ago"
        case 30: return "1 month ago"
        case 90: return "3 months ago"
        case 180: return "6 months ago"
        case 365...370: return "1 year ago"
        case 730...740: return "2 years ago"
        default:
            if days >= 365 { return "\(days / 365) years ago" }
            return "\(days) days ago"
        }
    }

    private func snippet(_ entry: JournalEntry) -> String {
        let candidates = [entry.wins, entry.gratitude, entry.intentions.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "", entry.notes, entry.improve]
        return candidates.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "You reflected on this day."
    }

    private var headerBar: some View {
        HStack {
            Button("Done") { persist(); dismiss() }
                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accentColor)
                .keyboardShortcut(.defaultAction)
            Spacer()
            VStack(spacing: 1) {
                Text("Journal").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(Fmt.relativeDay(day)).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            HStack(spacing: 4) {
                Button { persist(); day = day.adding(days: -1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                Button { persist(); if day < Date().startOfDay { day = day.adding(days: 1) } } label: {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(day < Date().startOfDay ? Theme.textSecondary : Theme.textTertiary)
                .disabled(day >= Date().startOfDay)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var intentionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today's intentions", systemImage: "sunrise.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text("The three things that would make today a win.")
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 8) {
                    Text("\(i + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 18)
                    TextField("Priority \(i + 1)", text: intentionBinding(i))
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .onSubmit(persist)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private func intentionBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < entry.intentions.count ? entry.intentions[i] : "" },
            set: {
                while entry.intentions.count < 3 { entry.intentions.append("") }
                entry.intentions[i] = $0
            }
        )
    }

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Check-in", systemImage: "heart.text.square")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            ratingRow("Mood", value: $entry.mood, symbols: ["😔", "😐", "🙂", "😄", "🤩"])
            ratingRow("Energy", value: $entry.energy, symbols: ["🪫", "🔋", "⚡️", "🔥", "🚀"])
        }
    }

    private func ratingRow(_ label: String, value: Binding<Int?>, symbols: [String]) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        value.wrappedValue = (value.wrappedValue == n) ? nil : n
                        persist()
                    } label: {
                        Text(symbols[n - 1])
                            .font(.system(size: 18))
                            .opacity(value.wrappedValue == n ? 1 : 0.35)
                            .scaleEffect(value.wrappedValue == n ? 1.15 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Evening reflection", systemImage: "moon.stars.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            promptField("What went well?", text: $entry.wins)
            promptField("What could be better?", text: $entry.improve)
            promptField("Grateful for…", text: $entry.gratitude)
        }
    }

    private func promptField(_ prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prompt.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(1)
                .foregroundStyle(Theme.textTertiary)
            TextEditor(text: text)
                .font(.system(size: 12.5)).scrollContentBackground(.hidden)
                .frame(minHeight: 52)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}
