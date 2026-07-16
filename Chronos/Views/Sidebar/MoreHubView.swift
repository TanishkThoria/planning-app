import SwiftUI

/// The iPhone "More" tab: a tidy launcher for everything that isn't one of the
/// person's primary tabs. Secondary feature screens push in place; tools open
/// their usual sheets. Keeps the tab bar focused while nothing is ever more
/// than a tap away.
struct MoreHubView: View {
    /// Optional feature screens (Grow / Insights / Coach) not promoted to tabs.
    let secondary: [AppModel.Screen]

    @EnvironmentObject private var model: AppModel
    @ObservedObject private var personalization = PersonalizationStore.shared
    @State private var path: [AppModel.Screen] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !secondary.isEmpty {
                    Section("Features") {
                        ForEach(secondary) { screen in
                            NavigationLink(value: screen) {
                                row(screen.title, subtitle: moduleBlurb(screen),
                                    icon: screen.iconFilled, tint: Theme.accentColor)
                            }
                        }
                    }
                }

                Section("Tools") {
                    toolRow("Focus timer", "timer") { model.startFocus(taskID: nil, title: "Focus") }
                    toolRow("Guided routines", "figure.walk.motion") { model.routinesPresented = true }
                    toolRow("Templates", "square.grid.3x3") { model.templatesPresented = true }
                    toolRow("Journal", "book.closed") { model.journalPresented = true }
                    toolRow("Search", "magnifyingglass") { model.searchPresented = true }
                }

                Section {
                    NavigationLink(value: AppModel.Screen.settings) {
                        row("Settings", subtitle: nil, icon: "gearshape.fill", tint: Theme.textSecondary)
                    }
                    Button {
                        model.personalizePresented = true
                    } label: {
                        row("Personalize", subtitle: "Re-arrange your tabs", icon: "slider.horizontal.3", tint: Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: AppModel.Screen.self) { destination($0) }
        }
        // Programmatic navigation (e.g. the ⌘K command bar) to a secondary
        // screen selects this tab; push the screen so it actually shows.
        .onChange(of: model.screen) { _, new in
            if new != .more, secondary.contains(new), path.last != new {
                path = [new]
            }
        }
        .onChange(of: path) { _, new in
            if new.isEmpty, model.screen != .more, secondary.contains(model.screen) {
                model.screen = .more
            }
        }
    }

    @ViewBuilder
    private func destination(_ screen: AppModel.Screen) -> some View {
        switch screen {
        case .grow: GrowView()
        case .insights: InsightsView()
        case .coach: CoachView()
        case .settings: SettingsView()
        default: EmptyView()
        }
    }

    private func moduleBlurb(_ screen: AppModel.Screen) -> String? {
        PersonalModule.allCases.first { $0.screen == screen }?.blurb
    }

    private func toolRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row(title, subtitle: nil, icon: icon, tint: Theme.accentColor)
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, subtitle: String?, icon: String, tint: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
