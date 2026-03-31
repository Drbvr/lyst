import SwiftUI
import Core

struct FilterView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTags: Set<String> = []
    @State private var selectedTypes: Set<String> = []
    @State private var completionFilter: CompletionFilter = .all
    @State private var expandedGroups: Set<String> = []
    @State private var showSaveSheet = false

    private enum CompletionFilter: String, CaseIterable {
        case all = "All"
        case incomplete = "Incomplete"
        case completed = "Completed"
    }

    private var currentFilters: ViewFilters {
        ViewFilters(
            tags: selectedTags.isEmpty ? nil : Array(selectedTags),
            itemTypes: selectedTypes.isEmpty ? nil : Array(selectedTypes),
            completed: completionFilter == .all ? nil : completionFilter == .completed
        )
    }

    private var filteredItems: [Item] {
        appState.filteredItems(with: currentFilters)
    }

    private var hasActiveFilters: Bool {
        !selectedTags.isEmpty || !selectedTypes.isEmpty || completionFilter != .all
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── TYPE ──────────────────────────────────────────────
                    filterSectionHeader("Type")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            TypePill(
                                label: "All",
                                icon: "square.grid.2x2",
                                isSelected: selectedTypes.isEmpty
                            ) {
                                selectedTypes = []
                            }
                            ForEach(appState.itemTypeNames, id: \.self) { type in
                                TypePill(
                                    label: type.capitalized,
                                    icon: iconForType(type),
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    Divider().padding(.horizontal, 16).padding(.top, 4)

                    // ── STATUS ────────────────────────────────────────────
                    filterSectionHeader("Status")

                    Picker("", selection: $completionFilter) {
                        ForEach(CompletionFilter.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    Divider().padding(.horizontal, 16)

                    // ── TAGS ──────────────────────────────────────────────
                    filterSectionHeader("Tags")

                    if appState.tagGroups.isEmpty {
                        Text("No tags found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(appState.tagGroups, id: \.tag) { group in
                                tagGroupRow(group)
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    // ── RESET ─────────────────────────────────────────────
                    if hasActiveFilters {
                        Button(role: .destructive) {
                            selectedTags = []
                            selectedTypes = []
                            completionFilter = .all
                        } label: {
                            Label("Reset All Filters", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    // Spacer so content isn't hidden behind the sticky footer
                    Spacer().frame(height: 90)
                }
            }

            // ── STICKY FOOTER ─────────────────────────────────────────────
            VStack(spacing: 8) {
                NavigationLink(value: FilterResult(title: filterTitle, items: filteredItems)) {
                    HStack {
                        Text(hasActiveFilters
                             ? "Show \(filteredItems.count) of \(appState.items.count) results"
                             : "Show all \(appState.items.count) items")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showSaveSheet = true
                } label: {
                    Text("Save as View…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(.regularMaterial)
        }
        .navigationTitle("Filter")
        .navigationDestination(for: FilterResult.self) { result in
            ItemListView(title: result.title, items: result.items, displayStyle: .list)
        }
        .sheet(isPresented: $showSaveSheet) {
            AddSavedViewSheet(presetFilters: currentFilters)
                .environment(appState)
        }
    }

    // MARK: - Tag group row

    @ViewBuilder
    private func tagGroupRow(_ group: (tag: String, count: Int, children: [(tag: String, count: Int)])) -> some View {
        let topIsSelected = selectedTags.contains(group.tag) ||
                            selectedTags.contains { $0.hasPrefix(group.tag + "/") }

        VStack(spacing: 0) {
            // Top-level row
            HStack(spacing: 10) {
                // Select / deselect the entire top-level group
                Button {
                    toggleTopLevelTag(group.tag, children: group.children)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: topIsSelected ? "tag.fill" : "tag")
                            .foregroundStyle(topIsSelected ? Color.accentColor : .secondary)
                            .font(.subheadline)
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

                // Expand/collapse button (only when there are subtags)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Subtag chips (visible when expanded)
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
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            Divider().padding(.leading, 16)
        }
    }

    private func toggleTopLevelTag(_ tag: String, children: [(tag: String, count: Int)]) {
        let childTags = children.map(\.tag)
        let anySelected = selectedTags.contains(tag) || childTags.contains { selectedTags.contains($0) }
        if anySelected {
            selectedTags.remove(tag)
            childTags.forEach { selectedTags.remove($0) }
        } else {
            selectedTags.insert(tag)
        }
    }

    // MARK: - Helpers

    private var filterTitle: String {
        if !hasActiveFilters { return "All Items" }
        var parts: [String] = []
        if !selectedTypes.isEmpty { parts.append(selectedTypes.map(\.capitalized).joined(separator: ", ")) }
        if completionFilter != .all { parts.append(completionFilter.rawValue) }
        if !selectedTags.isEmpty { parts.append("\(selectedTags.count) tag\(selectedTags.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func filterSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "movie":      return "film"
        case "book":       return "book.closed"
        case "todo":       return "checkmark.circle"
        case "restaurant": return "fork.knife"
        default:           return "doc.text"
        }
    }
}

// MARK: - Type Pill

private struct TypePill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.10))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Tag Chip

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
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Result (navigation value)

private struct FilterResult: Hashable {
    let title: String
    let items: [Item]
}
