import SwiftUI
import Core

/// Manual note creation form — type picker + dynamic fields (mirrors CreateItemView pattern).
struct ManualNoteView: View {

    @Bindable var viewModel: ShareViewModel

    var body: some View {
        Form {
            // Type picker
            Section("Note Type") {
                Picker("Type", selection: $viewModel.manualSelectedType) {
                    ForEach(viewModel.listTypes, id: \.name) { listType in
                        Label(listType.name.capitalized, systemImage: iconForType(listType.name))
                            .tag(listType)
                    }
                }
                .pickerStyle(.menu)
            }

            // Dynamic fields
            Section("Fields") {
                ForEach(viewModel.manualSelectedType.fields, id: \.name) { field in
                    fieldRow(for: field)
                }
            }

            // Tags
            Section("Tags") {
                TextField("tag1, tag2", text: $viewModel.manualTagsString)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await viewModel.saveManual() }
                } label: {
                    Label("Save Note", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTitleEmpty)

                Button("Discard") { viewModel.dismiss() }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("New Note")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func fieldRow(for field: FieldDefinition) -> some View {
        let binding = Binding<String>(
            get: { viewModel.manualFieldValues[field.name] ?? "" },
            set: { viewModel.manualFieldValues[field.name] = $0 }
        )

        HStack {
            Text(field.name.replacingOccurrences(of: "_", with: " ").capitalized)
                .frame(width: 100, alignment: .leading)
            TextField(placeholderFor(field), text: binding)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .keyboardType(keyboardType(for: field.type))
        }
    }

    private var isTitleEmpty: Bool {
        (viewModel.manualFieldValues["title"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func placeholderFor(_ field: FieldDefinition) -> String {
        switch field.type {
        case .text:   return "Enter \(field.name)…"
        case .number: return "0"
        case .date:   return "YYYY-MM-DD"
        }
    }

    private func keyboardType(for type: FieldType) -> UIKeyboardType {
        switch type {
        case .number: return .decimalPad
        case .date:   return .numbersAndPunctuation
        case .text:   return .default
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "movie": return "film"
        case "book":  return "book.closed"
        case "todo":  return "checkmark.circle"
        default:      return "doc.text"
        }
    }
}
