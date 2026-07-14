import SwiftUI

/// The Coach screen for devices without on-device AI: a warm daily briefing
/// (greeting, what to focus on, today's load, loose ends, suggestions,
/// planning shortcuts, week glance) — grounded in live data, not a chatbot.
struct CoachBriefingView: View {
    @EnvironmentObject private var model: AppModel

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
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.16)).frame(width: 34, height: 34)
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Coach")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your daily briefing")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            OverflowMenu { InsightsMenu() }
            HeaderIconButton(icon: "chart.bar.xaxis", prominent: true) { model.statsPresented = true }
        }
    }
}
