import SwiftUI

/// The first-run (and re-runnable) questionnaire. Asks what the person is using
/// Chronos for and what they want to achieve, then adapts the layout so the
/// features they care about are primary tabs and the rest tuck into "More".
struct PersonalizeView: View {
    /// First-run copy differs slightly from the Settings re-run.
    var isFirstRun = true
    var onDone: () -> Void = {}

    @ObservedObject private var store = PersonalizationStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.accentName) private var accentName = "Blue"

    @State private var role: UserRole?
    @State private var goals: Set<UserGoal> = []

    init(isFirstRun: Bool = true, onDone: @escaping () -> Void = {}) {
        self.isFirstRun = isFirstRun
        self.onDone = onDone
        _role = State(initialValue: PersonalizationStore.shared.role)
        _goals = State(initialValue: PersonalizationStore.shared.goals)
    }

    private let roleColumns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    /// Live preview of the tabs this survey would produce.
    private var previewPrimary: [PersonalModule] {
        PersonalizationStore.recommend(for: goals)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    roleSection
                    goalsSection
                    previewSection
                }
                .padding(20)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(Theme.bg)
        .chronosAppearance()
        .tint(Theme.accent(named: accentName))
        #if os(macOS)
        .frame(width: 520, height: 680)
        #endif
    }

    // MARK: Header / footer

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(isFirstRun ? "Let's set up your Chronos" : "Personalize")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Answer two quick things and we'll arrange the app around you.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if !isFirstRun {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 12) {
                if isFirstRun {
                    Button("Skip") { skip() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .buttonStyle(.plain)
                }
                Spacer()
                Button { apply() } label: {
                    Text(isFirstRun ? "Build my setup" : "Apply")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Theme.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(goals.isEmpty && role == nil)
                .opacity(goals.isEmpty && role == nil ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .padding(.top, 2)
        }
    }

    // MARK: Sections

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("What are you mainly using Chronos for?", "Pick the closest fit.")
            LazyVGrid(columns: roleColumns, spacing: 10) {
                ForEach(UserRole.allCases) { r in
                    roleCard(r)
                }
            }
        }
    }

    private func roleCard(_ r: UserRole) -> some View {
        let selected = role == r
        return Button {
            withAnimation(.snappy) { role = selected ? nil : r }
            Haptics.light()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: r.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accentColor : Theme.textSecondary)
                    .frame(width: 24)
                Text(r.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(selected ? Theme.accentColor.opacity(0.12) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Theme.accentColor.opacity(0.5) : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("What do you want to achieve?", "Choose any that matter to you.")
            FlowLayout(spacing: 9, lineSpacing: 9) {
                ForEach(UserGoal.allCases) { goal in
                    goalChip(goal)
                }
            }
        }
    }

    private func goalChip(_ goal: UserGoal) -> some View {
        let selected = goals.contains(goal)
        return Button {
            withAnimation(.snappy) {
                if selected { goals.remove(goal) } else { goals.insert(goal) }
            }
            Haptics.light()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: goal.icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selected ? Theme.bg : Theme.accentColor)
                Text(goal.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? Theme.bg : Theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(selected ? AnyShapeStyle(Theme.accentColor) : AnyShapeStyle(Theme.surface),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Your setup", "You can fine-tune this later in Settings.")
            VStack(alignment: .leading, spacing: 14) {
                layoutRow(
                    "Primary tabs",
                    modules: [] ,
                    coreLabels: ["Today", "Calendar", "Tasks"],
                    extra: Array(previewPrimary.prefix(PersonalizationStore.maxPrimaryOnPhone))
                )
                let inMore = PersonalModule.allCases.filter {
                    !previewPrimary.prefix(PersonalizationStore.maxPrimaryOnPhone).contains($0)
                }
                if !inMore.isEmpty {
                    layoutRow("A tap away in \u{201C}More\u{201D}", modules: inMore, coreLabels: [], extra: [])
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    private func layoutRow(_ label: String, modules: [PersonalModule], coreLabels: [String], extra: [PersonalModule]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textTertiary)
            FlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(coreLabels, id: \.self) { name in
                    pill(name, icon: coreIcon(name), muted: true)
                }
                ForEach(extra + modules) { m in
                    pill(m.title, icon: m.icon, muted: false)
                }
            }
        }
    }

    private func coreIcon(_ name: String) -> String {
        switch name {
        case "Today": return "sun.max.fill"
        case "Calendar": return "calendar"
        case "Tasks": return "checklist"
        default: return "square"
        }
    }

    private func pill(_ title: String, icon: String, muted: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(title).font(.system(size: 12.5, weight: .medium))
        }
        .foregroundStyle(muted ? Theme.textSecondary : Theme.accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((muted ? Theme.fill : Theme.accentColor.opacity(0.12)), in: Capsule())
    }

    private func sectionTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Actions

    private func apply() {
        store.completeSurvey(role: role, goals: goals)
        Haptics.success()
        onDone()
        dismiss()
    }

    private func skip() {
        store.markSeen()
        onDone()
        dismiss()
    }
}
