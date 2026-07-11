import SwiftUI

/// The Chronos design language: a restrained, high-contrast dark palette
/// built for long planning sessions. Every surface, hairline and text tone
/// comes from here so the whole app reads as one system.
enum Theme {

    // MARK: Surfaces

    /// App background — near-black with a whisper of blue so pure-black OLED
    /// smear is avoided and hairlines stay visible.
    static let bg = Color(hex: 0x0B0C0F)
    /// Cards, rails and sheets.
    static let surface = Color(hex: 0x131519)
    /// Elevated surfaces: popovers, editors, hovering cards.
    static let elevated = Color(hex: 0x1A1D22)
    /// Pressed / selected fills.
    static let fill = Color.white.opacity(0.06)

    // MARK: Lines

    static let hairline = Color.white.opacity(0.07)
    static let hairlineStrong = Color.white.opacity(0.14)
    static let gridLine = Color.white.opacity(0.05)

    // MARK: Text

    static let textPrimary = Color(hex: 0xF2F3F5)
    static let textSecondary = Color(hex: 0x9BA1AA)
    static let textTertiary = Color(hex: 0x5E646D)

    // MARK: Semantic

    static let nowLine = Color(hex: 0xFF5D5D)
    static let danger = Color(hex: 0xFF6B6B)
    static let success = Color(hex: 0x5BD899)
    static let warning = Color(hex: 0xF2B95C)

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
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func panel(padding: CGFloat = 14) -> some View {
        modifier(PanelModifier(padding: padding))
    }
}

/// Centralised user preference keys + defaults so every view binds to the
/// same storage.
enum Prefs {
    static let accentName = "pref.accentName"
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
}
