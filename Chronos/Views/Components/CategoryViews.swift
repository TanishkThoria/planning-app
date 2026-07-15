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
