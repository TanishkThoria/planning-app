import SwiftUI

// MARK: - Shared calm chrome

/// A soft, unhurried scaffold for the daily rituals. The gradient header and
/// generous spacing are deliberate — the point is to slow you down for two
/// minutes, not to process a form.
private struct RitualScaffold<Content: View>: View {
    let accent: Color
    let icon: String
    let eyebrow: String
    let title: String
    let onDone: () -> Void
    var doneLabel: String = "Done"
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onDone(); dismiss() } label: {
                    Text("Save").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(accent)
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        IconChip(icon: icon, tint: accent, size: 48)
                        Text(eyebrow.uppercased())
                            .font(.system(size: 12, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(accent)
                        Text(title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    content
                    Button { onDone(); dismiss() } label: {
                        Text(doneLabel)
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .background(
            LinearGradient(
                colors: [accent.opacity(0.14), Theme.elevated],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 480, height: 660)
        #else
        .presentationDetents([.large])
        #endif
    }
}

private struct RitualSection<Content: View>: View {
    let title: String
    var subtitle: String?
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle).font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary).lineSpacing(2)
            }
            content
            if let note {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9)).foregroundStyle(Theme.textTertiary).padding(.top, 2)
                    Text(note).font(.system(size: 12)).italic().foregroundStyle(Theme.textTertiary).lineSpacing(1)
                }
            }
        }
    }
}

private struct RitualField: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 54

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14.5)).scrollContentBackground(.hidden)
            .frame(minHeight: minHeight).padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(.system(size: 14.5)).foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 14).padding(.top, 18).allowsHitTesting(false)
                }
            }
    }
}

private func ratingControl(_ label: String, value: Binding<Int?>, symbols: [String]) -> some View {
    HStack {
        Text(label).font(.system(size: 14.5)).foregroundStyle(Theme.textSecondary)
        Spacer()
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { n in
                Button {
                    value.wrappedValue = (value.wrappedValue == n) ? nil : n
                    Haptics.selection()
                } label: {
                    Text(symbols[n - 1]).font(.system(size: 20))
                        .opacity(value.wrappedValue == n ? 1 : 0.3)
                        .scaleEffect(value.wrappedValue == n ? 1.2 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
}

// MARK: - Morning

/// A short morning ritual: arrive, set intentions as implementation
/// intentions, and choose the identity you're reinforcing today.
struct MorningRitualView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var life: LifeStore

    @State private var entry = JournalEntry(dayKey: Fmt.dayKey(Date()))

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
    }

    var body: some View {
        RitualScaffold(
            accent: Theme.warning,
            icon: "sunrise.fill",
            eyebrow: greeting,
            title: "Set your intentions",
            onDone: { life.upsert(entry); Haptics.success() },
            doneLabel: "Start my day"
        ) {
            if let past = pastReflection {
                RitualSection(title: "A line from a past you",
                              subtitle: Fmt.relativeDay(past.date)) {
                    Text("“\(past.text)”")
                        .font(.system(size: 14.5)).foregroundStyle(Theme.textPrimary)
                        .italic().fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            RitualSection(title: "How are you arriving?", subtitle: "A quick honest check-in — no wrong answers.") {
                VStack(spacing: 8) {
                    ratingControl("Mood", value: $entry.mood, symbols: ["😔", "😐", "🙂", "😄", "🤩"])
                    ratingControl("Energy", value: $entry.energy, symbols: ["🪫", "🔋", "⚡️", "🔥", "🚀"])
                    ratingControl("Stress", value: $entry.stress, symbols: ["😌", "🙂", "😐", "😣", "🤯"])
                }
            }

            RitualSection(
                title: "Your top three",
                subtitle: "What would make today a win? Be specific about when and where you'll do each.",
                note: "Implementation intentions — naming the when & where — roughly double follow-through (Gollwitzer)."
            ) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 8) {
                        Text("\(i + 1)").font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(Theme.warning).frame(width: 18)
                        TextField("I will…", text: intentionBinding(i))
                            .textFieldStyle(.plain).font(.system(size: 14.5))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }

            RitualSection(
                title: "Who are you becoming?",
                subtitle: "Name the kind of person today's actions vote for.",
                note: "Every action is a vote for the identity you want (Atomic Habits, James Clear)."
            ) {
                RitualField(placeholder: "Today I am someone who…", text: $entry.notes, minHeight: 60)
            }

            Button {
                life.upsert(entry)
                model.morningRitualPresented = false
                model.afterDismiss { model.morningPlanningPresented = true }
            } label: {
                Label("Now plan the day", systemImage: "wand.and.stars")
                    .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .onAppear { entry = life.entryOrNew(for: Date()) }
    }

    /// A resurfaced line from a previous day's reflection — a small "on this day"
    /// for the journal. Picked deterministically by day so it's stable per open.
    private var pastReflection: (text: String, date: Date)? {
        let todayKey = Fmt.dayKey(Date())
        let candidates: [(String, Date)] = life.journal.compactMap { e in
            guard e.dayKey != todayKey, let d = Fmt.day(fromKey: e.dayKey) else { return nil }
            let line = [e.gratitude, e.wins, e.notes]
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return line.map { ($0, d) }
        }
        guard !candidates.isEmpty else { return nil }
        let seed = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return candidates[seed % candidates.count]
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
}

// MARK: - Evening

/// The evening wind-down: celebrate wins, reflect gently, log gratitude,
/// close your habits, and pre-commit tomorrow's one thing.
struct EveningRitualView: View {
    @EnvironmentObject private var life: LifeStore

    @State private var entry = JournalEntry(dayKey: Fmt.dayKey(Date()))
    @State private var tomorrow = ""
    @State private var evidencePillar: UUID?
    @State private var evidenceText = ""

    private var dueHabits: [Habit] { life.activeHabits.filter { $0.isDue(on: Date()) } }

    var body: some View {
        RitualScaffold(
            accent: Theme.accentChoices[0].color,
            icon: "moon.stars.fill",
            eyebrow: "Wind down",
            title: "Reflect on today",
            onDone: { save() },
            doneLabel: "Rest well"
        ) {
            if !dueHabits.isEmpty {
                RitualSection(title: "Close your habits", subtitle: "Tick off what you did — consistency compounds.") {
                    VStack(spacing: 6) {
                        ForEach(dueHabits) { habit in
                            let done = life.isDone(habit, on: Date())
                            Button {
                                withAnimation(.snappy) { life.toggle(habit, on: Date()) }
                                Haptics.success()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 17)).foregroundStyle(done ? habit.color : Theme.textTertiary)
                                    Text(habit.title).font(.system(size: 14.5, weight: .medium))
                                        .foregroundStyle(done ? Theme.textPrimary : Theme.textSecondary)
                                    Spacer()
                                    if life.streak(habit) > 0 {
                                        Label("\(life.streak(habit))", systemImage: "flame.fill")
                                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.warning)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            RitualSection(
                title: "Where did you act like your future self?",
                subtitle: "Name the wins — the moments you were the person you're becoming.",
                note: "Recalling daily wins measurably lifts wellbeing (Seligman's ‘Three Good Things’)."
            ) {
                RitualField(placeholder: "Today I'm proud that…", text: $entry.wins, minHeight: 64)
            }

            if !life.activePillars.isEmpty { evidenceSection }

            RitualSection(title: "Where did you drift?", subtitle: "Curious, not critical. What pulled you off, and what will you adjust?") {
                RitualField(placeholder: "Next time I'll…", text: $entry.improve)
            }

            RitualSection(
                title: "Grateful for",
                subtitle: "Two or three things you appreciate right now.",
                note: "Regular gratitude journaling improves mood and sleep (Emmons & McCullough)."
            ) {
                RitualField(placeholder: "I'm thankful for…", text: $entry.gratitude)
            }

            RitualSection(
                title: "Tomorrow's one thing",
                subtitle: "Pre-commit the single most important task for tomorrow.",
                note: "Deciding in advance beats deciding in the moment — willpower isn't needed."
            ) {
                TextField("Tomorrow I will…", text: $tomorrow)
                    .textFieldStyle(.plain).font(.system(size: 14.5))
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            RitualSection(title: "How do you feel now?") {
                VStack(spacing: 8) {
                    ratingControl("Mood", value: $entry.mood, symbols: ["😔", "😐", "🙂", "😄", "🤩"])
                    ratingControl("Energy", value: $entry.energy, symbols: ["🪫", "🔋", "⚡️", "🔥", "🚀"])
                }
            }
        }
        .onAppear {
            entry = life.entryOrNew(for: Date())
            tomorrow = firstIntention(for: Date().adding(days: 1))
        }
    }

    private var selectedPillarName: String {
        evidencePillar.flatMap { id in life.activePillars.first { $0.id == id }?.name } ?? "Pick a pillar"
    }

    private var evidenceSection: some View {
        RitualSection(
            title: "What evidence did you create today?",
            subtitle: "One small proof that you're becoming who you want to be — it logs to that pillar.",
            note: "You become an identity through evidence, not intentions."
        ) {
            VStack(spacing: 8) {
                Menu {
                    ForEach(life.activePillars) { p in
                        Button(p.name) { evidencePillar = p.id }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.stand").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                        Text(selectedPillarName).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                HStack(spacing: 8) {
                    TextField("I proved it by…", text: $evidenceText)
                        .textFieldStyle(.plain).font(.system(size: 14.5))
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Button {
                        if let pid = evidencePillar {
                            life.addEvidence(pillarID: pid, text: evidenceText, source: .reflection, strength: 2)
                            evidenceText = ""; Haptics.success()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(Theme.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(evidencePillar == nil || evidenceText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func firstIntention(for day: Date) -> String {
        life.entry(for: day)?.intentions.first ?? ""
    }

    private func save() {
        life.upsert(entry)
        // Seed tomorrow's first intention.
        let text = tomorrow.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            var t = life.entryOrNew(for: Date().adding(days: 1))
            while t.intentions.count < 3 { t.intentions.append("") }
            t.intentions[0] = text
            life.upsert(t)
        }
        Haptics.success()
    }
}
