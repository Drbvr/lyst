import SwiftUI
import Core

struct AddSavedViewSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var presetFilters: ViewFilters = ViewFilters()

    @State private var name: String = ""
    @State private var displayStyle: DisplayStyle = .list
    @State private var selectedTypes: Set<String> = []
    @State private var selectedTags: Set<String> = []
    @State private var completionFilter: CompletionFilter = .all
    @State private var expandedGroups: Set<String> = []

    private enum CompletionFilter: String, CaseIterable {
        case all = "All"
        case incomplete = "Incomplete"
        case completed = "Completed"
    }

    private var builtFilters: ViewFilters {
        ViewFilters(
            tags: selectedTags.isEmpty ? nil : Array(selectedTags),
            itemTypes: selectedTypes.isEmpty ? nil : Array(selectedTypes),
            completed: completionFilter == .all ? nil : completionFilter == .completed
        )
    }

    private var previewCount: Int {
        appState.filteredItems(with: builtFilters).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("My View", text: $name)
                }

                Section("Display") {
                    Picker("Style", selection: $displayStyle) {
                        Label("List", systemImage: "list.bullet").tag(DisplayStyle.list)
                        Label("Card", systemImage: "square.grid.2x2").tag(DisplayStyle.card)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            TypePill(label: "All", icon: "square.grid.2x2", isSelected: selectedTypes.isEmpty) {
                                selectedTypes = []
                            }
                            ForEach(appState.itemTypeNames, id: \.self) { type in
                                TypePill(
                                    label: type.capitalized,
                                    icon: iconForType(type),
                                    isSelected: selectedTypes.contains(type)
                                ) {
                                    if selectedTypes.contains(type) { selectedTypes.remove(type) }
                                    else { selectedTypes.insert(type) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: { Text("Type") }

                Section {
                    Picker("", selection: $completionFilter) {
                        ForEach(CompletionFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: { Text("Status") }

                Section {
                    if appState.tagGroups.isEmpty {
                        Text("No tags found").foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.tagGroups, id: \.tag) { group in
                            tagGroupRow(group)
                        }
                    }
                } header: { Text("Tags") }

                Section {
                    HStack {
                        Text("Preview")
                        Spacer()
                        Text("\(previewCount) item\(previewCount == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Saved View")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { applyPreset() }
    }

    private func applyPreset() {
        selectedTags = Set(presetFilters.tags ?? [])
        selectedTypes = Set(presetFilters.itemTypes ?? [])
        if let completed = presetFilters.completed {
            completionFilter = completed ? .completed : .incomplete
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let view = SavedView(name: trimmed, filters: builtFilters, displayStyle: displayStyle)
        appState.savedViews.append(view)
        appState.persistSavedViews()
        dismiss()
    }

    // MARK: - Tag group row

    @ViewBuilder
    private func tagGroupRow(_ group: (tag: String, count: Int, children: [(tag: String, count: Int)])) -> some View {
        let childTags = group.children.map(\.tag)
        let anySelected = selectedTags.contains(group.tag) || childTags.contains { selectedTags.contains($0) }

        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedGroups.contains(group.tag) },
                set: { if $0 { expandedGroups.insert(group.tag) } else { expandedGroups.remove(group.tag) } }
            )
        ) {
            if !group.children.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(group.children, id: \.tag) { child in
                        tagChip(tag: child.tag, selected: selectedTags.contains(child.tag)) {
                            if selectedTags.contains(child.tag) { selectedTags.remove(child.tag) }
                            else { selectedTags.insert(child.tag) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Button {
                if anySelected {
                    selectedTags.remove(group.tag)
                    childTags.forEach { selectedTags.remove($0) }
                } else {
                    selectedTags.insert(group.tag)
                }
            } label: {
                HStack {
                    Image(systemName: anySelected ? "tag.fill" : "tag")
                        .foregroundStyle(anySelected ? Color.accentColor : .secondary)
                    Text(group.tag)
                        .foregroundStyle(anySelected ? Color.accentColor : .primary)
                    Spacer()
                    Text("\(group.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func tagChip(tag: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("#\(tag)")
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(selected ? .white : Color.secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

// MARK: - Shared Type Pill (internal to AddSavedViewSheet module)

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
