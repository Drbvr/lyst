import SwiftUI
import Core

struct SavedViewsListView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddSheet = false

    var body: some View {
        List {
            ForEach(appState.savedViews) { savedView in
                NavigationLink(value: savedView) {
                    HStack {
                        Image(systemName: savedView.displayStyle == .card
                              ? "square.grid.2x2" : "list.bullet")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(savedView.name)
                                .font(.body)
                            Text(viewSummary(savedView))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(appState.filteredItems(for: savedView).count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .onDelete { indexSet in
                appState.savedViews.remove(atOffsets: indexSet)
                appState.persistSavedViews()
            }
        }
        .navigationTitle("Saved Views")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSavedViewSheet()
                .environment(appState)
        }
        .navigationDestination(for: SavedView.self) { savedView in
            ItemListView(
                title: savedView.name,
                items: appState.filteredItems(for: savedView),
                displayStyle: savedView.displayStyle
            )
        }
    }

    private func viewSummary(_ view: SavedView) -> String {
        var parts: [String] = []
        if let tags = view.filters.tags { parts.append("\(tags.count) tag filter\(tags.count == 1 ? "" : "s")") }
        if let types = view.filters.itemTypes { parts.append(types.joined(separator: ", ")) }
        if view.filters.completed == false { parts.append("incomplete") }
        if view.filters.completed == true { parts.append("completed") }
        return parts.isEmpty ? "No filters" : parts.joined(separator: " · ")
    }
}
