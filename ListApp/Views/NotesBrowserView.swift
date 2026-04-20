import SwiftUI
import Core

/// Single "Notes" tab merging Search + Filter + Tags + SavedViews.
///
/// Layout:
///   - Saved-view shortcuts row (horizontal scroll) at the top.
///   - Type pills (All + per-type).
///   - Segmented status picker (All / Incomplete / Completed).
///   - Collapsible tag groups (top-level + sub-tags).
///   - Results list at the bottom, narrowed by searchable text + filters.
struct NotesBrowserView: View {
    @Environment(AppState.self) private var appState

    @State private var searchText: String = ""
    @State private var selectedTypes: Set<String> = []
    @State private var selectedTags: Set<String> = []
    @State private var completionFilter: CompletionFilter = .all
    @State private var expandedGroups: Set<String> = []
    @State private var showSaveSheet: Bool = false
    @State private var showAddSavedView: Bool = false

    private enum CompletionFilter: String, CaseIterable {
        case all = "All"
        case incomplete = "Incomplete"
        case completed = "Completed"
    }

    // MARK: - Computed filters

    private var currentFilters: ViewFilters {
        ViewFilters(
            tags: selectedTags.isEmpty ? nil : Array(selectedTags),
            itemTypes: selectedTypes.isEmpty ? nil : Array(selectedTypes),
            completed: completionFilter == .all ? nil : completionFilter == .completed
        )
    }

    private var hasActiveFilters: Bool {
        !selectedTags.isEmpty || !selectedTypes.isEmpty || completionFilter != .all
    }

    private var filteredItems: [Item] {
        let base = appState.filteredItems(with: currentFilters)
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let q = trimmed.lowercased()
        return base.filter { item in
            item.title.lowercased().contains(q)
                || item.type.lowercased().contains(q)
                || item.tags.contains { $0.lowercased().contains(q) }
        }
    }

    private var typeStatusFilteredItems: [Item] {
        appState.filteredItems(with: ViewFilters(
            tags: nil,
            itemTypes: selectedTypes.isEmpty ? nil : Array(selectedTypes),
            completed: completionFilter == .all ? nil : completionFilter == .completed
        ))
    }

    private var availableTagGroups: [(tag: String, count: Int, children: [(tag: String, count: Int)])] {
        let items = typeStatusFilteredItems
        var groups: [String: Set<String>] = [:]
        var tagCounts: [String: Int] = [:]
        var topLevelCounts: [String: Int] = [:]

        for item in items {
            let uniqueTags = Set(item.tags.filter { !$0.isEmpty })
            var itemTopLevels: Set<String> = []

            for tag in uniqueTags {
                let topLevel = String(tag.split(separator: "/").first ?? Substring(tag))
                groups[topLevel, default: Set()].insert(tag)
                tagCounts[tag, default: 0] += 1
                itemTopLevels.insert(topLevel)
            }

            for topLevel in itemTopLevels {
                topLevelCounts[topLevel, default: 0] += 1
            }
        }

        return groups.keys.sorted().map { topLevel in
            let allTagsForGroup = groups[topLevel] ?? Set()
            let children = allTagsForGroup
                .filter { $0.contains("/") }
                .sorted()
                .map { childTag in
                    (tag: childTag, count: tagCounts[childTag, default: 0])
                }
            let totalCount = topLevelCounts[topLevel, default: 0]
            return (tag: topLevel, count: totalCount, children: children)
        }
    }

    // MARK: - View

    var body: some View {
        NavigationStack {
            List {
                savedViewsSection
                filtersSection
                tagsSection
                resultsSection
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search notes…")
            .noAutocapitalization()
            .autocorrectionDisabled()
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showAddSavedView = true
                        } label: {
                            Label("New Saved View…", systemImage: "bookmark")
                        }
                        if hasActiveFilters {
                            Button {
                                showSaveSheet = true
                            } label: {
                                Label("Save Current Filters…", systemImage: "square.and.arrow.down")
                            }
                            Button(role: .destructive) {
                                resetFilters()
                            } label: {
                                Label("Reset Filters", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showAddSavedView) {
                AddSavedViewSheet()
                    .environment(appState)
            }
            .sheet(isPresented: $showSaveSheet) {
                AddSavedViewSheet(presetFilters: currentFilters)
                    .environment(appState)
            }
            .navigationDestination(for: SavedView.self) { savedView in
                ItemListView(
                    title: savedView.name,
                    items: appState.filteredItems(for: savedView),
                    displayStyle: savedView.displayStyle
                )
            }
        }
    }

    // MARK: - Saved views

    @ViewBuilder
    private var savedViewsSection: some View {
        if !appState.savedViews.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(appState.savedViews) { savedView in
                            NavigationLink(value: savedView) {
                                savedViewCard(savedView)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("Saved Views")
            }
        }
    }

    private func savedViewCard(_ view: SavedView) -> some View {
        let typeName = view.filters.itemTypes?.first ?? ""
        let accent = color(for: typeName)
        let count = appState.filteredItems(for: view).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon(for: typeName))
                    .foregroundStyle(accent)
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.15))
                    .clipShape(Capsule())
            }
            Text(view.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 150, alignment: .leading)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Filters (type + status)

    @ViewBuilder
    private var filtersSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    TypePill(label: "All", icon: "square.grid.2x2", isSelected: selectedTypes.isEmpty) {
                        selectedTypes = []
                    }
                    ForEach(appState.itemTypeNames, id: \.self) { type in
                        TypePill(
                            label: type.capitalized,
                            icon: icon(for: type),
                            isSelected: selectedTypes.contains(type)
                        ) {
                            if selectedTypes.contains(type) {
                                selectedTypes.remove(type)
                            } else {
                                selectedTypes.insert(type)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            Picker("Status", selection: $completionFilter) {
                ForEach(CompletionFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Filters")
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        if !availableTagGroups.isEmpty {
            Section("Tags") {
                ForEach(availableTagGroups, id: \.tag) { group in
                    tagGroupRow(group)
                }
            }
        }
    }

    @ViewBuilder
    private func tagGroupRow(_ group: (tag: String, count: Int, children: [(tag: String, count: Int)])) -> some View {
        let topIsSelected = selectedTags.contains(group.tag)
            || selectedTags.contains { $0.hasPrefix(group.tag + "/") }

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    toggleTopLevelTag(group.tag, children: group.children)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: topIsSelected ? "tag.fill" : "tag")
                            .foregroundStyle(topIsSelected ? Color.accentColor : .secondary)
                        Text(group.tag)
                            .font(.subheadline.weight(topIsSelected ? .semibold : .regular))
                            .foregroundStyle(topIsSelected ? Color.accentColor : .primary)
                        Text("\(group.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if !group.children.isEmpty {
                    Button {
                        if expandedGroups.contains(group.tag) {
                            expandedGroups.remove(group.tag)
                        } else {
                            expandedGroups.insert(group.tag)
                        }
                    } label: {
                        Image(systemName: expandedGroups.contains(group.tag)
                              ? "chevron.up" : "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !group.children.isEmpty && expandedGroups.contains(group.tag) {
                FlowLayout(spacing: 6) {
                    ForEach(group.children, id: \.tag) { child in
                        FilterTagChip(
                            tag: child.tag,
                            isSelected: selectedTags.contains(child.tag)
                        ) {
                            if selectedTags.contains(child.tag) {
                                selectedTags.remove(child.tag)
                            } else {
                                selectedTags.insert(child.tag)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        Section {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    hasActiveFilters || !searchText.isEmpty ? "No matches" : "No notes",
                    systemImage: "tray",
                    description: Text(hasActiveFilters || !searchText.isEmpty
                                      ? "Try clearing filters or search terms."
                                      : "Create your first note from the Chat tab.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredItems) { item in
                    NavigationLink {
                        ItemDetailView(item: item)
                    } label: {
                        ItemRowView(item: item) {
                            appState.toggleCompletion(for: item)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Results")
                Spacer()
                Text("\(filteredItems.count) of \(appState.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func toggleTopLevelTag(_ tag: String, children: [(tag: String, count: Int)]) {
        let childTags = children.map(\.tag)
        let anySelected = selectedTags.contains(tag) || childTags.contains { selectedTags.contains($0) }
        if anySelected {
            selectedTags.remove(tag)
            childTags.forEach { selectedTags.remove($0) }
        } else {
            // Core tag filtering is exact-match, so selecting a group needs to
            // insert every descendant tag as well — otherwise toggling "work"
            // wouldn't match items only tagged "work/project".
            selectedTags.insert(tag)
            childTags.forEach { selectedTags.insert($0) }
        }
    }

    private func resetFilters() {
        selectedTags = []
        selectedTypes = []
        completionFilter = .all
    }

    private func icon(for typeName: String) -> String {
        switch typeName {
        case "todo":       return "checkmark.circle"
        case "book":       return "book.closed"
        case "movie":      return "film"
        case "restaurant": return "fork.knife"
        default:           return "doc.text"
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
}

// MARK: - Type pill

private struct TypePill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.10))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag chip

private struct FilterTagChip: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("#\(tag)")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
