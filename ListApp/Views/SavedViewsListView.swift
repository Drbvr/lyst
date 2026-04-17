import SwiftUI
import Core

private struct TypeFilter: Hashable {
    let typeName: String
    let displayTitle: String
}

private struct ViewGroup {
    let header: String
    let views: [SavedView]
}

struct SavedViewsListView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddSheet = false

    var body: some View {
        List {
            Section {
                // Intentionally empty — type cards live in the header
            } header: {
                typeShortcutsScrollView
                    .textCase(nil)
                    .padding(.bottom, 4)
            }

            ForEach(groupedViews, id: \.header) { group in
                Section(group.header) {
                    ForEach(group.views) { savedView in
                        NavigationLink(value: savedView) {
                            viewRow(savedView)
                        }
                    }
                    .onDelete { indexSet in
                        let globalIndexSet = IndexSet(indexSet.compactMap { i in
                            appState.savedViews.firstIndex(of: group.views[i])
                        })
                        appState.savedViews.remove(atOffsets: globalIndexSet)
                        appState.persistSavedViews()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSavedViewSheet()
                .environment(appState)
        }
        .navigationDestination(for: SavedView.self) { savedView in
            ItemListView(
                title: savedView.name,
                items: appState.filteredItems(for: savedView),
                displayStyle: savedView.displayStyle
            )
        }
        .navigationDestination(for: TypeFilter.self) { filter in
            ItemListView(
                title: filter.displayTitle,
                items: appState.items.filter { $0.type == filter.typeName && !$0.completed },
                displayStyle: .list
            )
        }
    }

    // MARK: - Type Shortcut Cards

    private var typeShortcutsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(appState.itemTypeNames, id: \.self) { typeName in
                    let count = appState.items.filter { $0.type == typeName && !$0.completed }.count
                    NavigationLink(value: TypeFilter(typeName: typeName, displayTitle: displayName(for: typeName))) {
                        typeCard(typeName: typeName, count: count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    private func typeCard(typeName: String, count: Int) -> some View {
        let accent = color(for: typeName)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon(for: typeName))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.15))
                    .clipShape(Capsule())
            }
            Text(displayName(for: typeName))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text(count == 1 ? "1 item" : "\(count) items")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 130)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Saved View Rows

    private func viewRow(_ view: SavedView) -> some View {
        let typeName = view.filters.itemTypes?.first ?? ""
        let accent = color(for: typeName)
        let count = appState.filteredItems(for: view).count
        return HStack(spacing: 12) {
            Image(systemName: icon(for: typeName))
                .foregroundStyle(accent)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(view.name)
                    .font(.body)
                Text(friendlyDescription(view))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(count > 0 ? accent : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((count > 0 ? accent : Color.secondary).opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - Grouping

    private var groupedViews: [ViewGroup] {
        var buckets: [String: [SavedView]] = [:]
        var general: [SavedView] = []
        for view in appState.savedViews {
            if let types = view.filters.itemTypes, types.count == 1 {
                buckets[types[0], default: []].append(view)
            } else {
                general.append(view)
            }
        }
        var result: [ViewGroup] = []
        for t in ["todo", "book", "movie", "restaurant"] {
            if let views = buckets.removeValue(forKey: t) {
                result.append(ViewGroup(header: displayName(for: t), views: views))
            }
        }
        for (t, views) in buckets.sorted(by: { $0.key < $1.key }) {
            result.append(ViewGroup(header: displayName(for: t), views: views))
        }
        if !general.isEmpty {
            result.append(ViewGroup(header: "General", views: general))
        }
        return result
    }

    // MARK: - Helpers

    private func icon(for typeName: String) -> String {
        switch typeName {
        case "todo":       return "checkmark.circle"
        case "book":       return "book.closed"
        case "movie":      return "film"
        case "restaurant": return "fork.knife"
        default:           return "square.stack"
        }
    }

    private func color(for typeName: String) -> Color {
        switch typeName {
        case "todo":       return .blue
        case "book":       return .orange
        case "movie":      return .purple
        case "restaurant": return .red
        default:           return .teal
        }
    }

    private func displayName(for typeName: String) -> String {
        if typeName == "todo" { return "Tasks" }
        return typeName.capitalized + "s"
    }

    private func friendlyDescription(_ view: SavedView) -> String {
        var parts: [String] = []
        if view.filters.completed == false { parts.append("Incomplete") }
        if view.filters.completed == true  { parts.append("Completed") }
        if let types = view.filters.itemTypes, !types.isEmpty {
            parts.append(types.map { displayName(for: $0) }.joined(separator: ", "))
        }
        if let tags = view.filters.tags, !tags.isEmpty {
            let tagLabel = tags.prefix(2)
                .map { $0.split(separator: "/").last.map(String.init) ?? $0 }
                .joined(separator: ", ")
            parts.append("tagged \(tagLabel)\(tags.count > 2 ? "…" : "")")
        }
        return parts.isEmpty ? "All items" : parts.joined(separator: " · ")
    }
}
