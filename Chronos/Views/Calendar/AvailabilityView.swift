import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Turns your actual free time into pasteable text — "Mon: 2–4 PM, Wed:
/// 10 AM–12 PM" — for the eternal "when are you free?" message. Computed from
/// your real calendar inside your working hours, so you never offer a slot
/// you don't have.
struct AvailabilityView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60

    @State private var daysAhead = 5
    @State private var minSlotMinutes = 30
    @State private var skipWeekends = true
    @State private var copied = false
    @State private var showQR = false

    private struct DaySlots: Identifiable {
        let day: Date
        let gaps: [AutoScheduler.Gap]
        var id: Date { day }
    }

    private var slots: [DaySlots] {
        (0..<daysAhead).compactMap { offset in
            let day = Date().startOfDay.adding(days: offset)
            if skipWeekends {
                let weekday = Calendar.current.component(.weekday, from: day)
                if weekday == 1 || weekday == 7 { return nil }
            }
            let gaps = AutoScheduler.freeGaps(
                on: day,
                existing: service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs),
                workStartMinutes: workStartMinutes,
                workEndMinutes: workEndMinutes
            ).filter { $0.minutes >= minSlotMinutes }
            guard !gaps.isEmpty else { return nil }
            return DaySlots(day: day, gaps: gaps)
        }
    }

    private var composedText: String {
        slots.map { entry in
            let day = Fmt.weekdayShort.string(from: entry.day) + " " + Fmt.monthDay.string(from: entry.day)
            let times = entry.gaps
                .map { "\(Fmt.time.string(from: $0.start))–\(Fmt.time.string(from: $0.end))" }
                .joined(separator: ", ")
            return "\(day): \(times)"
        }
        .joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    controls
                    preview
                    if showQR, !slots.isEmpty, let qr = QRCode.image(from: composedText) {
                        VStack(spacing: 8) {
                            qr.interpolation(.none).resizable()
                                .frame(width: 160, height: 160)
                                .padding(10)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text("Have someone scan this to grab your free slots.")
                                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .background(Theme.bg)
        .chronosAppearance()
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 480)
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Share Availability")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your real free slots, ready to paste")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NEXT")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                Picker("", selection: $daysAhead) {
                    Text("3 days").tag(3)
                    Text("5 days").tag(5)
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MIN SLOT")
                        .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(Theme.textTertiary)
                    Picker("", selection: $minSlotMinutes) {
                        Text("30m").tag(30)
                        Text("45m").tag(45)
                        Text("1h").tag(60)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                Toggle(isOn: $skipWeekends) {
                    Text("Skip weekends")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.switch)
                .fixedSize()
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Preview")
            if slots.isEmpty {
                Text("No free slots of at least \(minSlotMinutes) minutes in that window — a badge of honor or a warning sign, you decide.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(slots) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(Fmt.weekdayShort.string(from: entry.day))
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(entry.day.isToday ? Color.accentColor : Theme.textSecondary)
                                .frame(width: 34, alignment: .leading)
                            Text(entry.gaps
                                .map { "\(Fmt.time.string(from: $0.start))–\(Fmt.time.string(from: $0.end))" }
                                .joined(separator: "  ·  "))
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                copyText()
            } label: {
                Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(copied ? Theme.success : Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(copied ? Theme.success.opacity(0.15) : Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(slots.isEmpty)

            Button { withAnimation(.snappy) { showQR.toggle() } } label: {
                Image(systemName: showQR ? "qrcode.viewfinder" : "qrcode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(showQR ? Theme.bg : Color.accentColor)
                    .frame(width: 46, height: 44)
                    .background(showQR ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.12)),
                               in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(slots.isEmpty)

            ShareLink(item: composedText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(slots.isEmpty)
        }
        .padding(14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func copyText() {
        #if os(iOS)
        UIPasteboard.general.string = composedText
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(composedText, forType: .string)
        #endif
        Haptics.success()
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.snappy) { copied = false }
        }
    }
}
