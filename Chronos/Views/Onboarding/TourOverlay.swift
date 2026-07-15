import SwiftUI

/// The interactive tour's floating coach-mark. It sits above the live app —
/// the real screens show and stay tappable underneath — and on each step it
/// navigates the app for you and can trigger the actual feature. A bottom
/// card carries the narration + controls; a slim top bar shows progress + Skip.
struct TourOverlay: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var tour = TourController.shared

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if let step = tour.current {
                callout(step)
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(step.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { apply(tour.current) }
        .onChange(of: tour.index) { _, _ in
            withAnimation(.snappy) { apply(tour.current) }
        }
    }

    /// Clear the iPhone tab bar; sit lower on macOS/iPad where there's a sidebar.
    private var bottomInset: CGFloat {
        #if os(iOS)
        96
        #else
        28
        #endif
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Theme.accentColor)
                        .frame(width: max(6, geo.size.width * tour.progress))
                }
            }
            .frame(height: 5)
            Button("Skip tour") { withAnimation(.snappy) { tour.finish() } }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    // MARK: Callout

    private func callout(_ step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.accentColor.opacity(0.16))
                        .frame(width: 42, height: 42)
                    Image(systemName: step.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(tour.index + 1) of \(tour.steps.count)")
                        .font(.system(size: 11.5, weight: .bold)).tracking(0.8)
                        .foregroundStyle(Theme.textTertiary)
                    Text(step.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
            }

            Text(step.message)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let demoLabel = step.demoLabel, let demo = step.demo {
                Button {
                    runDemo(demo)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "hand.tap.fill").font(.system(size: 13.5, weight: .semibold))
                        Text(demoLabel).font(.system(size: 14.5, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right").font(.system(size: 12.5, weight: .bold))
                    }
                    .foregroundStyle(Theme.accentColor)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                if tour.index > 0 {
                    Button { withAnimation(.snappy) { tour.back() } } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button { withAnimation(.snappy) { tour.next() } } label: {
                    Text(tour.isLast ? "Done" : "Next")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .frame(maxWidth: 460)
    }

    // MARK: Navigation + demos

    private func apply(_ step: TourStep?) {
        guard let step else { return }
        model.screen = step.screen
        if let mode = step.mode { model.plannerMode = mode }
    }

    private func runDemo(_ demo: TourDemo) {
        switch demo {
        case .quickAdd: model.quickAddPresented = true
        case .planDay: model.planDayPresented = true
        case .focusTimer: model.startFocus(taskID: nil, title: "Focus")
        case .morningRitual: model.morningRitualPresented = true
        case .search: model.searchPresented = true
        case .stats: model.statsPresented = true
        case .coach: model.coachPresented = true
        case .commandBar: model.commandBarPresented = true
        }
    }
}
