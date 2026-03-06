import SwiftUI
import Core

struct ItemListView: View {
    @Environment(AppState.self) private var appState
    let title: String
    let items: [Item]
    let displayStyle: DisplayStyle

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "tray",
                    description: Text("No items match the current filters.")
                )
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            ItemRowView(item: item) {
                                appState.toggleCompletion(for: item)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if item.type == "todo" {
                                Button {
                                    appState.toggleCompletion(for: item)
                                } label: {
                                    Label(
                                        item.completed ? "Undo" : "Done",
                                        systemImage: item.completed
                                            ? "arrow.uturn.backward"
                                            : "checkmark"
                                    )
                                }
                                .tint(item.completed ? .orange : .green)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                appState.deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
        }
    }
}
