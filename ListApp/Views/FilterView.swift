import SwiftUI
import Core

struct FilterView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTags: Set<String> = []
    @State private var selectedTypes: Set<String> = []
    @State private var completionFilter: CompletionFilter = .all
    @State private var navigateToResults = false

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
        VStack(spacing: 0) {
            // Sticky result bar at top
            NavigationLink(destination: ItemListView(
                title: filterTitle,
                items: filteredItems,
                displayStyle: .list
            )) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(filterTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(hasActiveFilters
                             ? "\(filteredItems.count) of \(appState.items.count) items"
                             : "All \(appState.items.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(hasActiveFilters ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(hasActiveFilters ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Filters below
            Form {
                // Reset button when filters are active
                if hasActiveFilters {
                    Section {
                        Button(role: .destructive) {
                            selectedTags = []
                            selectedTypes = []
                            completionFilter = .all
                        } label: {
                            Label("Reset All Filters", systemImage: "xmark.circle")
                        }
                    }
                }

                Section("Type") {
                    ForEach(appState.itemTypeNames, id: \.self) { type in
                        Toggle(isOn: Binding(
                            get: { selectedTypes.contains(type) },
                            set: { if $0 { selectedTypes.insert(type) } else { selectedTypes.remove(type) } }
                        )) {
                            Label(type.capitalized, systemImage: iconForType(type))
                        }
                    }
                }

                Section("Status") {
                    Picker("Completion", selection: $completionFilter) {
                        ForEach(CompletionFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Tags") {
                    FlowLayout(spacing: 8) {
                        ForEach(appState.allTags, id: \.self) { tag in
                            FilterTagChip(
                                tag: tag,
                                isSelected: selectedTags.contains(tag)
                            ) {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Filter")
    }

    private var filterTitle: String {
        if !hasActiveFilters { return "All Items" }
        var parts: [String] = []
        if !selectedTypes.isEmpty { parts.append(selectedTypes.map(\.capitalized).joined(separator: ", ")) }
        if completionFilter != .all { parts.append(completionFilter.rawValue) }
        if !selectedTags.isEmpty { parts.append("\(selectedTags.count) tag\(selectedTags.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "movie": return "film"
        case "book": return "book.closed"
        case "todo": return "checkmark.circle"
        default: return "doc.text"
        }
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
