import SwiftUI

/// The full-screen reward moment: confetti, a glowing badge, and the title of
/// whatever you just earned. Deliberately a beat you have to tap through — the
/// satisfying counterweight to the app's nudges.
struct CelebrationOverlay: View {
    let celebration: Celebration
    let onDismiss: () -> Void

    @State private var shown = false
    @State private var badgePop = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.6 : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            ConfettiBurst(tint: celebration.color)
                .allowsHitTesting(false)
                .opacity(shown ? 1 : 0)

            card
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            Haptics.success()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { shown = true }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55).delay(0.08)) { badgePop = true }
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            badge
            Text(celebration.eyebrow.uppercased())
                .font(.system(size: 12, weight: .bold)).tracking(1.6)
                .foregroundStyle(celebration.color)
            Text(celebration.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(celebration.subtitle)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: dismiss) {
                Text("Nice!")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(celebration.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .padding(32)
    }

    private var badge: some View {
        ZStack {
            Circle().fill(celebration.color.opacity(0.18)).frame(width: 108, height: 108)
                .scaleEffect(badgePop ? 1 : 0.6)
            Circle().strokeBorder(celebration.color.opacity(0.4), lineWidth: 2).frame(width: 92, height: 92)
            Image(systemName: celebration.icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(celebration.color)
                .scaleEffect(badgePop ? 1 : 0.4)
                .rotationEffect(.degrees(badgePop ? 0 : -20))
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: onDismiss)
    }
}

/// A short burst of falling confetti pieces, mixing the celebration tint with a
/// festive palette. Pure SwiftUI, no assets.
private struct ConfettiBurst: View {
    let tint: Color

    private struct Piece: Identifiable {
        let id = UUID()
        let x: CGFloat        // 0…1 horizontal position
        let delay: Double
        let duration: Double
        let color: Color
        let size: CGFloat
        let rotation: Double
    }

    private let pieces: [Piece]

    init(tint: Color) {
        self.tint = tint
        let palette: [Color] = [tint, Color(hex: 0x7C8CF8), Color(hex: 0xF2C14E),
                                Color(hex: 0x5BD899), Color(hex: 0xF0719B), Color(hex: 0x4FD1C5)]
        pieces = (0..<48).map { i in
            Piece(
                x: CGFloat.random(in: 0...1),
                delay: Double.random(in: 0...0.35),
                duration: Double.random(in: 1.1...2.0),
                color: palette[i % palette.count],
                size: CGFloat.random(in: 6...11),
                rotation: Double.random(in: 0...360)
            )
        }
    }

    @State private var fall = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 1.6)
                        .rotationEffect(.degrees(fall ? p.rotation + 220 : p.rotation))
                        .position(
                            x: p.x * geo.size.width,
                            y: fall ? geo.size.height + 40 : -40
                        )
                        .opacity(fall ? 0 : 1)
                        .animation(.easeIn(duration: p.duration).delay(p.delay), value: fall)
                }
            }
            .onAppear { fall = true }
        }
    }
}
