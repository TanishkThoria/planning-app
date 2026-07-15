import SwiftUI

/// The Chronos design language: one restrained, high-contrast palette that now
/// adapts to light and dark automatically. Every surface, hairline and text
/// tone comes from here so the whole app reads as one system in either mode.
enum Theme {

    /// Builds a color that resolves per appearance — the whole app becomes
    /// light/dark aware just by driving the environment's color scheme.
    static func dynamic(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #else
        return dark
        #endif
    }

    // MARK: Surfaces

    /// App background — a soft off-white by day, near-black (with a whisper of
    /// blue so OLED smear is avoided) by night.
    static let bg = dynamic(light: Color(hex: 0xF4F5F7), dark: Color(hex: 0x0B0C0F))
    /// Cards, rails and sheets.
    static let surface = dynamic(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x131519))
    /// Elevated surfaces: popovers, editors, hovering cards.
    static let elevated = dynamic(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x1A1D22))
    /// Pressed / selected fills.
    static let fill = dynamic(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.06))

    // MARK: Lines

    static let hairline = dynamic(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.07))
    static let hairlineStrong = dynamic(light: Color.black.opacity(0.16), dark: Color.white.opacity(0.14))
    static let gridLine = dynamic(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.05))

    // MARK: Text

    static let textPrimary = dynamic(light: Color(hex: 0x14161A), dark: Color(hex: 0xF2F3F5))
    static let textSecondary = dynamic(light: Color(hex: 0x5B616B), dark: Color(hex: 0x9BA1AA))
    static let textTertiary = dynamic(light: Color(hex: 0x9098A2), dark: Color(hex: 0x5E646D))

    // MARK: Semantic (vivid on both schemes)

    static let nowLine = Color(hex: 0xFF5D5D)
    static let danger = dynamic(light: Color(hex: 0xE5484D), dark: Color(hex: 0xFF6B6B))
    static let success = dynamic(light: Color(hex: 0x30A46C), dark: Color(hex: 0x5BD899))
    static let warning = dynamic(light: Color(hex: 0xD98A2B), dark: Color(hex: 0xF2B95C))

    // MARK: Accent choices (power users pick theirs in Settings)

    struct AccentChoice: Identifiable, Hashable {
        let name: String
        let color: Color
        var id: String { name }
    }

    static let accentChoices: [AccentChoice] = [
        .init(name: "Indigo", color: Color(hex: 0x7C8CF8)),
        .init(name: "Teal", color: Color(hex: 0x4FD1C5)),
        .init(name: "Amber", color: Color(hex: 0xF2B95C)),
        .init(name: "Rose", color: Color(hex: 0xF0719B)),
        .init(name: "Lime", color: Color(hex: 0xA3E06B)),
        .init(name: "Graphite", color: Color(hex: 0xAEB6C2)),
    ]

    static func accent(named name: String) -> Color {
        accentChoices.first(where: { $0.name == name })?.color ?? accentChoices[0].color
    }

    // MARK: Type

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: Metrics — a slightly more generous, iOS-native spacing scale

    enum Metric {
        /// Standard screen edge inset.
        static let screen: CGFloat = 20
        /// Gap between stacked cards.
        static let cardGap: CGFloat = 14
        /// Inner padding for cards / rows.
        static let cardPadding: CGFloat = 16
        /// The house corner radius — soft, Apple-like.
        static let radius: CGFloat = 18
        /// Smaller radius for chips / compact controls.
        static let radiusSmall: CGFloat = 12
    }

    /// A soft shadow for elevated cards (light mode gets a real shadow; dark
    /// leans on the hairline so it stays flat and clean).
    static let cardShadow = dynamic(light: Color.black.opacity(0.06), dark: Color.clear)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Shared component styling

struct PanelModifier: ViewModifier {
    var padding: CGFloat = Theme.Metric.cardPadding
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: Theme.cardShadow, radius: 10, y: 4)
    }
}

extension View {
    func panel(padding: CGFloat = Theme.Metric.cardPadding) -> some View {
        modifier(PanelModifier(padding: padding))
    }
}

/// Drives the whole app's light/dark appearance from a single user preference
/// (System / Light / Dark). Applied wherever a color scheme used to be forced.
struct ChronosAppearance: ViewModifier {
    @AppStorage(Prefs.appearance) private var appearance = "system"
    func body(content: Content) -> some View {
        content.preferredColorScheme(scheme)
    }
    private var scheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil          // follow the system
        }
    }
}

extension View {
    /// Follow the user's chosen appearance (System / Light / Dark).
    func chronosAppearance() -> some View { modifier(ChronosAppearance()) }
}

/// Centralised user preference keys + defaults so every view binds to the
/// same storage.
enum Prefs {
    static let accentName = "pref.accentName"
    static let appearance = "pref.appearance"                   // system | light | dark
    static let workStartMinutes = "pref.workStartMinutes"       // default 9:00
    static let workEndMinutes = "pref.workEndMinutes"           // default 18:00
    static let snapMinutes = "pref.snapMinutes"                 // default 15
    static let defaultBlockMinutes = "pref.defaultBlockMinutes" // default 30
    static let defaultCalendarID = "pref.defaultCalendarID"
    static let defaultListID = "pref.defaultListID"
    static let dimPastBlocks = "pref.dimPastBlocks"
    static let showCompletedInToday = "pref.showCompletedInToday"
    static let hourHeight = "pref.hourHeight"
    static let planDayGapMinutes = "pref.planDayGapMinutes"     // breathing room between auto-scheduled blocks
    static let morningReminderEnabled = "pref.morningReminderEnabled"
    static let morningReminderMinutes = "pref.morningReminderMinutes"
    static let eveningReminderEnabled = "pref.eveningReminderEnabled"
    static let eveningReminderMinutes = "pref.eveningReminderMinutes"
    static let coachEnabled = "pref.coachEnabled"                 // show the AI Coach tab
    static let startAlertsEnabled = "pref.startAlertsEnabled"     // "starting in 5 min" nudges
    static let blockLiveActivities = "pref.blockLiveActivities"   // current-block Live Activity

    // MARK: Chronos+ (paid-account features — all default OFF, all no-op until
    // the underlying Apple capability is present; see PaidFeatures + docs/CHRONOS_PLUS_SETUP.md)

    /// Master switch. When on AND the capabilities are entitled, the paid
    /// layer activates; otherwise everything stays dormant.
    static let chronosPlusEnabled = "pref.chronosPlusEnabled"
    /// Mirror Chronos-only data (Grow, momentum, profile, schools) across the
    /// user's devices via their private iCloud (CloudKit).
    static let cloudSyncEnabled = "pref.cloudSyncEnabled"
    /// Game Center leaderboards + friends presence.
    static let socialEnabled = "pref.socialEnabled"
    /// Live Home/Lock Screen widgets (needs the App Group capability).
    static let liveWidgetsEnabled = "pref.liveWidgetsEnabled"
    /// A short, shareable code other Chronos users add to see your presence.
    static let friendCode = "pref.friendCode"
    /// Display name shown to friends and on the leaderboard.
    static let socialDisplayName = "pref.socialDisplayName"
    /// A custom status emoji + line friends see (e.g. "🎯" · "Deep work till 5").
    static let socialStatusEmoji = "pref.socialStatusEmoji"
    static let socialStatusText = "pref.socialStatusText"
    /// Whether to share live presence with friends at all (privacy switch).
    static let sharePresence = "pref.sharePresence"
}
