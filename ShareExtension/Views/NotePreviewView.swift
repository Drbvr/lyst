import SwiftUI
import Core

/// Editable preview of the AI-generated note. The user can tweak fields before saving.
struct NotePreviewView: View {

    @Bindable var viewModel: ShareViewModel

    private var matchedListType: ListType? {
        viewModel.listTypes.first { $0.name.lowercased() == viewModel.draft.type }
    }

    var body: some View {
        Form {
            // Note type (display only — determined by AI)
            Section("Note Type") {
                HStack {
                    Label(viewModel.draft.type.capitalized, systemImage: iconForType(viewModel.draft.type))
                    Spacer()
                    Text("AI selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Title
            Section("Title") {
                TextField("Title", text: $viewModel.draft.title)
            }

            // Dynamic fields from matching ListType
            if let listType = matchedListType {
                Section("Fields") {
                    ForEach(listType.fields.filter { $0.name != "title" }, id: \.name) { field in
                        fieldRow(for: field)
                    }
                }
            }

            // Tags
            Section("Tags") {
                TextField("tag1, tag2", text: $viewModel.draft.tagsString)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
            }

            // Save
            Section {
                Button {
                    Task { await viewModel.savePreview() }
                } label: {
                    Label("Save Note", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.draft.title.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Discard") { viewModel.dismiss() }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Review Note")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func fieldRow(for field: FieldDefinition) -> some View {
        let binding = Binding<String>(
            get: { viewModel.draft.properties[field.name] ?? "" },
            set: { viewModel.draft.properties[field.name] = $0 }
        )

        HStack {
            Text(field.name.replacingOccurrences(of: "_", with: " ").capitalized)
                .frame(width: 100, alignment: .leading)
            TextField(field.type.rawValue, text: binding)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .keyboardType(keyboardType(for: field.type))
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
