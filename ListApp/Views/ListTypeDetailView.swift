import SwiftUI
import Core

struct ListTypeDetailView: View {
    @Environment(AppState.self) private var appState
    let listType: ListType

    var body: some View {
        let items = appState.items.filter { $0.type == listType.name }

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
                if listType.fields.isEmpty {
                    Text("No fields defined")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(listType.fields, id: \.name) { field in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.name.capitalized)
                                    .font(.body)
                                Text(field.type.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if field.required {
                                Text("Required")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            if let prompt = listType.llmExtractionPrompt {
                Section("AI Extraction Prompt") {
                    Text(prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !items.isEmpty {
                Section("Items (\(items.count))") {
                    ForEach(items.prefix(5)) { item in
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            ItemRowView(item: item) {
                                appState.toggleCompletion(for: item)
                            }
                        }
                    }
                    if items.count > 5 {
                        NavigationLink(destination: ItemListView(
                            title: listType.name.capitalized,
                            items: items,
                            displayStyle: .list
                        )) {
                            Text("View all \(items.count) items →")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle(listType.name.capitalized)
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
