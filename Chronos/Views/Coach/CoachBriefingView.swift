import SwiftUI

/// The Coach screen for devices without on-device AI: a warm daily briefing
/// (greeting, what to focus on, today's load, loose ends, suggestions,
/// planning shortcuts, week glance) — grounded in live data, not a chatbot.
struct CoachBriefingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                BriefingContent()
                    .padding(18)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconChip(icon: "sun.horizon.fill", tint: Color(hex: 0xFFB23E), size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Coach")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your daily briefing")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HeaderIconButton(icon: "slider.horizontal.3") { model.calibrationPresented = true }
            if isPresented {
                HeaderIconButton(icon: "xmark") { dismiss() }
            }
        }
    }
}
