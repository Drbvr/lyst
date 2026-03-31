import SwiftUI
import Core

struct CreateItemView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: ListType? = nil
    @State private var showNoVaultAlert = false

    var body: some View {
        NavigationStack {
            if selectedType == nil {
                typeSelectionView
            } else {
                fieldsView(for: selectedType!)
            }
        }
        .alert("No Folder Selected", isPresented: $showNoVaultAlert) {
            Button("OK") {}
        } message: {
            Text("Please select a vault folder in Settings before creating items.")
        }
    }

    // MARK: - Step 1: Type selection

    private var typeSelectionView: some View {
        List {
            Section {
                ForEach(appState.listTypes, id: \.name) { type in
                    Button {
                        if appState.currentVaultURL == nil {
                            showNoVaultAlert = true
                        } else {
                            selectedType = type
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: iconForType(type.name.lowercased()))
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.name.capitalized)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                let required = type.fields.filter(\.required).map(\.name)
                                if !required.isEmpty {
                                    Text(required.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Choose a type")
            }
        }
        .navigationTitle("New Item")
        .navigationBarTitleInline()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Step 2: Fields form

    @ViewBuilder
    private func fieldsView(for type: ListType) -> some View {
        FieldsFormView(type: type) {
            dismiss()
        }
        .environment(appState)
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "movie":      return "film"
        case "book":       return "book.closed"
        case "todo":       return "checkmark.circle"
        case "restaurant": return "fork.knife"
        case "note":       return "note.text"
        default:           return "doc.text"
        }
    }
}

// MARK: - Fields Form

private struct FieldsFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let type: ListType
    let onSave: () -> Void

    @State private var title: String = ""
    @State private var tagsText: String = ""
    // Dynamic field values keyed by field name
    @State private var textValues: [String: String] = [:]
    @State private var numberValues: [String: String] = [:]   // stored as string, parsed on save
    @State private var dateValues: [String: Date] = [:]
    @State private var dateSwitches: [String: Bool] = [:]

    private var nonTitleFields: [FieldDefinition] {
        type.fields.filter { $0.name.lowercased() != "title" }
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Required", text: $title)
            }

            // Dynamic fields from the type definition
            ForEach(nonTitleFields, id: \.name) { field in
                Section {
                    fieldInput(for: field)
                } header: {
                    HStack(spacing: 4) {
                        Text(field.name.replacingOccurrences(of: "_", with: " ").capitalized)
                        if field.required {
                            Text("*").foregroundStyle(.red)
                        }
                    }
                } footer: {
                    if let min = field.min, let max = field.max {
                        Text("Range: \(min, specifier: "%.0f") – \(max, specifier: "%.0f")")
                    }
                }
            }

            Section {
                TextField("work, project/alpha", text: $tagsText)
                    .autocorrectionDisabled()
                    .noAutocapitalization()
            } header: {
                Text("Tags")
            } footer: {
                Text("Comma-separated. Use / for hierarchy, e.g. work/project")
            }
        }
        .navigationTitle("New \(type.name.capitalized)")
        .navigationBarTitleInline()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { save() }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func fieldInput(for field: FieldDefinition) -> some View {
        switch field.type {
        case .text:
            TextField(field.required ? "Required" : "Optional",
                      text: Binding(
                        get: { textValues[field.name] ?? "" },
                        set: { textValues[field.name] = $0 }
                      ))

        case .number:
            TextField(field.required ? "Required" : "Optional",
                      text: Binding(
                        get: { numberValues[field.name] ?? "" },
                        set: { numberValues[field.name] = $0 }
                      ))
            .keyboardType(.decimalPad)

        case .date:
            let isOn = Binding(
                get: { dateSwitches[field.name] ?? false },
                set: { dateSwitches[field.name] = $0 }
            )
            let date = Binding(
                get: { dateValues[field.name] ?? Date() },
                set: { dateValues[field.name] = $0 }
            )
            Toggle(field.required ? "Set date (required)" : "Set date", isOn: isOn)
            if dateSwitches[field.name] == true {
                DatePicker("", selection: date, displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var properties: [String: PropertyValue] = [:]

        for field in nonTitleFields {
            switch field.type {
            case .text:
                if let v = textValues[field.name], !v.isEmpty {
                    properties[field.name] = .text(v)
                }
            case .number:
                if let s = numberValues[field.name], let d = Double(s) {
                    properties[field.name] = .number(d)
                }
            case .date:
                if dateSwitches[field.name] == true, let d = dateValues[field.name] {
                    properties[field.name] = .date(d)
                }
            }
        }

        let typeName = type.name.lowercased()
        Task {
            if typeName == "todo" {
                await appState.createTodo(title: trimmedTitle, tags: tags, properties: properties)
            } else {
                await appState.createYAMLItem(type: typeName, title: trimmedTitle, tags: tags, properties: properties)
            }
        }
        onSave()
    }
}
