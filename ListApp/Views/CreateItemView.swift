import SwiftUI
import Core
import PhotosUI

struct CreateItemView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: ListType? = nil
    @State private var showNoVaultAlert = false
    @State private var showURLInput = false
    @State private var showTextInput = false
    @State private var pendingImportOnDismiss: PendingImport? = nil
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var isLoadingPhoto = false

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
        .sheet(isPresented: $showURLInput, onDismiss: {
            if pendingImportOnDismiss != nil { dismiss() }
        }) {
            URLInputView { url in
                pendingImportOnDismiss = PendingImport(webURL: url)
            }
        }
        .sheet(isPresented: $showTextInput, onDismiss: {
            if pendingImportOnDismiss != nil { dismiss() }
        }) {
            TextImportView { text in
                pendingImportOnDismiss = PendingImport(text: text)
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            selectedPhoto = nil
            isLoadingPhoto = true
            Task { await loadAndImportPhoto(newItem) }
        }
        .onDisappear {
            if let pending = pendingImportOnDismiss {
                appState.pendingImport = pending
            }
        }
    }

    // MARK: - Photo import helper

    private func loadAndImportPhoto(_ item: PhotosPickerItem) async {
        defer { Task { @MainActor in isLoadingPhoto = false } }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        guard (try? data.write(to: tempURL)) != nil else { return }
        await MainActor.run {
            pendingImportOnDismiss = PendingImport(image: tempURL)
            dismiss()
        }
    }

    // MARK: - Step 1: Type selection

    private var typeSelectionView: some View {
        List {
            Section {
                Button {
                    if appState.currentVaultURL == nil {
                        showNoVaultAlert = true
                    } else {
                        showURLInput = true
                    }
                } label: {
                    Label("From URL", systemImage: "link")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                if appState.currentVaultURL == nil {
                    Button {
                        showNoVaultAlert = true
                    } label: {
                        Label("From Photo", systemImage: "photo")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                } else if isLoadingPhoto {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading photo…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("From Photo", systemImage: "photo")
                            .foregroundStyle(.primary)
                    }
                }

                Button {
                    if appState.currentVaultURL == nil {
                        showNoVaultAlert = true
                    } else {
                        showTextInput = true
                    }
                } label: {
                    Label("From Text", systemImage: "text.alignleft")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            } header: {
                Label("Generate with AI", systemImage: "sparkles")
            }

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
                        .contentShape(Rectangle())
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
            // Priority gets a segmented picker matching the edit form
            if field.name.lowercased() == "priority" {
                let binding = Binding<String>(
                    get: { textValues[field.name] ?? "" },
                    set: { textValues[field.name] = $0 }
                )
                Picker("Priority", selection: binding) {
                    Text("None").tag("")
                    Text("🔴 High").tag("high")
                    Text("🟠 Medium").tag("medium")
                    Text("🔵 Low").tag("low")
                }
                .pickerStyle(.segmented)
            } else {
            TextField(field.required ? "Required" : "Optional",
                      text: Binding(
                        get: { textValues[field.name] ?? "" },
                        set: { textValues[field.name] = $0 }
                      ))
            }

        case .number:
            TextField(field.required ? "Required" : "Optional",
                      text: Binding(
                        get: { numberValues[field.name] ?? "" },
                        set: { numberValues[field.name] = $0 }
                      ))
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif

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

// MARK: - URL Input

private struct URLInputView: View {
    let onImport: (URL) -> Void
    @State private var urlText = ""
    @State private var isInvalid = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com", text: $urlText)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit { submit() }
                } footer: {
                    if isInvalid {
                        Text("Please enter a valid https:// or http:// URL.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { submit() }
                        .fontWeight(.semibold)
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func submit() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed),
              url.scheme == "https" || url.scheme == "http" else {
            isInvalid = true
            return
        }
        onImport(url)
        dismiss()
    }
}

// MARK: - Text Import

private struct TextImportView: View {
    let onImport: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                } header: {
                    Text("Paste or type your content")
                } footer: {
                    Text("The AI will read this text and create notes from it.")
                }
            }
            .navigationTitle("Import from Text")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
