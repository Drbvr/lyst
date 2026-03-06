import SwiftUI
import Core

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    private var searchResults: [Item] {
        appState.searchItems(query: searchText)
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                ContentUnavailableView(
                    "Search Items",
                    systemImage: "magnifyingglass",
                    description: Text("Search across all items by title, tags, or type.")
                )
            } else if searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(searchResults) { item in
                    NavigationLink {
                        ItemDetailView(item: item)
                    } label: {
                        ItemRowView(item: item) {
                            appState.toggleCompletion(for: item)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search items...")
        .navigationTitle("Search")
    }
}
