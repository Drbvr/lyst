import SwiftUI
import Core

/// Navigation destination for ItemListView
private struct ItemListViewDestination: Hashable {
    let title: String
    let items: [Item]
    let displayStyle: DisplayStyle
}

struct ListTypeDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let listType: ListType
    @State private var fields: [EditableField]
    @State private var extractionPrompt: String
    @State private var showFieldValidation = false

    init(listType: ListType) {
        self.listType = listType
        _fields = State(initialValue: listType.fields.map { EditableField(name: $0.name, type: $0.type, required: $0.required) })
        _extractionPrompt = State(initialValue: listType.llmExtractionPrompt ?? "")
    }

    var body: some View {
        let items = appState.items.filter { $0.type.lowercased() == listType.name.lowercased() }

        List {
            Section {
                HStack {
                    Image(systemName: iconForType(listType.name))
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listType.name.capitalized)
                            .font(.headline)
                        Text("\(items.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Fields") {
                if fields.isEmpty {
                    Text("No fields defined")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach($fields) { $field in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Field name", text: $field.name)
                            Picker("Type", selection: $field.type) {
                                Text("Text").tag(FieldType.text)
                                Text("Number").tag(FieldType.number)
                                Text("Date").tag(FieldType.date)
                            }
                            .pickerStyle(.segmented)
                            Toggle("Required", isOn: $field.required)
                        }
                    }
                    .onDelete { fields.remove(atOffsets: $0) }
                }
                Button {
                    fields.append(EditableField(name: "", type: .text, required: false))
                } label: {
                    Label("Add field", systemImage: "plus")
                }
            }

            Section("AI Extraction Prompt") {
                TextEditor(text: $extractionPrompt)
                    .frame(minHeight: 120)
            }

            if !items.isEmpty {
                Section("Items (\(items.count))") {
                    ForEach(items.prefix(5)) { item in
                        NavigationLink(value: item) {
                            ItemRowView(item: item) {
                                appState.toggleCompletion(for: item)
                            }
                        }
                    }
                    if items.count > 5 {
                        NavigationLink(value: ItemListViewDestination(
                            title: listType.name.capitalized,
                            items: items,
                            displayStyle: .list
                        )) {
                            Text("View all \(items.count) items →")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .navigationDestination(for: Item.self) { item in
                    ItemDetailView(item: item)
                }
                .navigationDestination(for: ItemListViewDestination.self) { dest in
                    ItemListView(title: dest.title, items: dest.items, displayStyle: dest.displayStyle)
                }
            }
        }
        .navigationTitle(listType.name.capitalized)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { save() }
            }
        }
        .alert("Field names required", isPresented: $showFieldValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please provide a name for each field before saving.")
        }
    }

    private func save() {
        let hasEmptyFieldNames = fields.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if hasEmptyFieldNames {
            showFieldValidation = true
            return
        }
        let cleanedFields = fields.map { $0.asFieldDefinition }
        let updated = ListType(
            name: listType.name,
            fields: cleanedFields,
            llmExtractionPrompt: extractionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : extractionPrompt
        )
        appState.upsertListType(updated)
        dismiss()
    }

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "movie": return "film"
        case "book": return "book.closed"
        case "todo": return "checkmark.circle"
        default: return "doc.text"
        }
    }
}

private struct EditableField: Identifiable {
    var id = UUID()
    var name: String
    var type: FieldType
    var required: Bool

    var asFieldDefinition: FieldDefinition {
        FieldDefinition(name: name.trimmingCharacters(in: .whitespacesAndNewlines), type: type, required: required)
    }
}
