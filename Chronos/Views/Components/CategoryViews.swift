import SwiftUI

/// A small colored category chip (icon, optionally a label).
struct CategoryBadge: View {
    let category: ActivityCategory
    var showsLabel = false
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(category.color)
            if showsLabel {
                Text(category.title)
                    .font(.system(size: size + 2, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, showsLabel ? 7 : 5)
        .padding(.vertical, showsLabel ? 3 : 4)
        .background(category.color.opacity(0.14), in: Capsule())
    }
}

/// A menu that sets/clears the category override for an item id (event series
/// id or reminder id). "Auto" clears the override so the keyword classifier
/// takes over again.
struct CategoryMenu<Trigger: View>: View {
    let id: String
    let current: ActivityCategory
    @ViewBuilder var label: () -> Trigger
    @ObservedObject private var tags = TagStore.shared

    var body: some View {
        Menu {
            Section("Category") {
                ForEach(ActivityCategory.allCases) { category in
                    Button {
                        tags.setCategory(category, forID: id)
                        Haptics.light()
                    } label: {
                        Label(category.title, systemImage: category.icon)
                        if current == category { Image(systemName: "checkmark") }
                    }
                }
            }
            if tags.isExplicit(forID: id) {
                Divider()
                Button { tags.setCategory(nil, forID: id); Haptics.light() } label: {
                    Label("Auto-detect", systemImage: "wand.and.stars")
                }
            }
        } label: {
            label()
        }
    }
}

extension CategoryMenu where Trigger == CategoryBadge {
    init(id: String, current: ActivityCategory, showsLabel: Bool = false) {
        self.id = id
        self.current = current
        self.label = { CategoryBadge(category: current, showsLabel: showsLabel) }
    }
}

/// An editor field (matching `CalendarPickerRow`) for choosing an item's
/// category. Binds to an optional override — nil means "auto-detect from the
/// title", and the field then previews what the classifier picked, live, as
/// you type. Used in the block and task editors.
struct CategoryField: View {
    /// The item's title — drives the live auto-detected preview.
    let title: String
    @Binding var override: ActivityCategory?

    private var resolved: ActivityCategory {
        override ?? ActivityCategory.guess(from: title) ?? .other
    }

    var body: some View {
        FieldRow(label: "Category") {
            Menu {
                ForEach(ActivityCategory.allCases) { category in
                    Button {
                        override = category
                        Haptics.light()
                    } label: {
                        Label(category.title, systemImage: category.icon)
                        if resolved == category { Image(systemName: "checkmark") }
                    }
                }
                Divider()
                Button {
                    override = nil
                    Haptics.light()
                } label: {
                    Label("Auto-detect", systemImage: "wand.and.stars")
                    if override == nil { Image(systemName: "checkmark") }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: resolved.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(resolved.color)
                    Text(resolved.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if override == nil {
                        Text("Auto")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.fill, in: Capsule())
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .fixedSize()
        }
    }
}

/// A wrap-friendly legend of every category with its color and icon — used in
/// Settings so the palette (and what each tag means) is discoverable at a glance.
struct CategoryLegend: View {
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(ActivityCategory.allCases) { category in
                HStack(spacing: 5) {
                    Image(systemName: category.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(category.color)
                    Text(category.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(category.color.opacity(0.13), in: Capsule())
            }
        }
    }
}
