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
                        // Always resolve the latest state from appState so completion
                        // changes made in ItemDetailView are reflected when popping back.
                        let current = appState.items.first(where: { $0.id == item.id }) ?? item
                        NavigationLink(value: current) {
                            ItemRowView(item: current) {
                                appState.toggleCompletion(for: current)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if current.type == "todo" {
                                Button {
                                    appState.toggleCompletion(for: current)
                                } label: {
                                    Label(
                                        current.completed ? "Undo" : "Done",
                                        systemImage: current.completed
                                            ? "arrow.uturn.backward"
                                            : "checkmark"
                                    )
                                }
                                .tint(current.completed ? .orange : .green)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                appState.deleteItem(current)
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
