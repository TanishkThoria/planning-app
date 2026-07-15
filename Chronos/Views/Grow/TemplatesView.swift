import SwiftUI

/// Day templates: capture a day's block layout once (your "ideal day"),
/// then stamp it onto any future day in a tap. Perfect for a repeating ideal
/// week or a standard workday.
struct TemplatesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    @State private var namingTemplate = false
    @State private var newName = ""
    @State private var applyTarget: DayTemplate?
    @State private var importing = false
    @State private var importCode = ""
    @State private var importError = false

    private var day: Date { model.selectedDate }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    saveCard

                    if life.templates.isEmpty {
                        EmptyStateView(
                            icon: "square.grid.3x3",
                            title: "No templates yet",
                            message: "Lay out an ideal day on the calendar, then save it here to reuse any time."
                        )
                    } else {
                        SectionHeader(title: "Your templates", trailing: "\(life.templates.count)")
                        ForEach(life.templates) { template in
                            templateRow(template)
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 460, height: 560)
        #else
        .presentationDetents([.large])
        #endif
        .alert("Name this template", isPresented: $namingTemplate) {
            TextField("e.g. Ideal Workday", text: $newName)
            Button("Save") { saveTemplate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saving \(service.templateBlocks(for: day).count) blocks from \(Fmt.relativeDay(day)).")
        }
        .confirmationDialog(
            "Apply \u{201C}\(applyTarget?.name ?? "")\u{201D} to \(Fmt.relativeDay(day))?",
            isPresented: Binding(get: { applyTarget != nil }, set: { if !$0 { applyTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Add \(applyTarget?.blocks.count ?? 0) blocks") {
                if let t = applyTarget {
                    service.applyTemplate(t, to: day, fallbackCalendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID)
                }
                applyTarget = nil
                dismiss()
            }
            Button("Cancel", role: .cancel) { applyTarget = nil }
        }
        .alert("Import a template", isPresented: $importing) {
            TextField("Paste a chronos-tpl: code", text: $importCode)
            Button("Import") {
                if let template = DayTemplate.fromShareCode(importCode) {
                    life.addTemplate(template)
                    Haptics.success()
                } else {
                    importError = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste a template code someone shared with you.")
        }
        .alert("That code didn't work", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Make sure you copied the whole code, starting with \u{201C}chronos-tpl:\u{201D}.")
        }
    }

    private var headerBar: some View {
        HStack {
            Button("Close") { dismiss() }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("Templates").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Import") { importCode = ""; importing = true }
                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentColor)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var saveCard: some View {
        let count = service.templateBlocks(for: day).count
        return Button {
            newName = ""
            namingTemplate = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 15)).foregroundStyle(Theme.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Save \(Fmt.relativeDay(day)) as a template")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(count == 0 ? "No blocks on this day yet" : "\(count) blocks")
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .panel(padding: 12)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.5 : 1)
    }

    private func templateRow(_ template: DayTemplate) -> some View {
        let span = templateSpan(template)
        return Button {
            applyTarget = template
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 15)).foregroundStyle(Theme.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text("\(template.blocks.count) blocks\(span.isEmpty ? "" : " · \(span)")")
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text("Apply")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.bg)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accentColor, in: Capsule())
            }
            .panel(padding: 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let code = template.shareCode {
                ShareLink(item: code) {
                    Label("Share Template Code", systemImage: "square.and.arrow.up")
                }
            }
            Button(role: .destructive) { life.deleteTemplate(template.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func templateSpan(_ template: DayTemplate) -> String {
        guard let first = template.blocks.map(\.startMinutes).min(),
              let last = template.blocks.map({ $0.startMinutes + $0.durationMinutes }).max()
        else { return "" }
        let base = Date().startOfDay
        return Fmt.timeRange(base.at(minutes: first), base.at(minutes: last))
    }

    private func saveTemplate() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let blocks = service.templateBlocks(for: day)
        guard !blocks.isEmpty else { return }
        life.addTemplate(DayTemplate(name: name.isEmpty ? Fmt.relativeDay(day) : name, blocks: blocks))
    }
}
