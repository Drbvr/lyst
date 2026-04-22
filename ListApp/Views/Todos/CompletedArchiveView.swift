import SwiftUI
import Core

struct CompletedArchiveView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: Set<UUID> = []

    var body: some View {
        let items = TodoQueries.completed(appState.items)
        let grouped = Dictionary(grouping: items) { item in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: item.updatedAt)
        }
        let keys = grouped.keys.sorted(by: >)
        ScrollView {
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text("No completed todos yet").foregroundStyle(TodoToken.mute).padding(40)
                } else {
                    ForEach(keys, id: \.self) { k in
                        let bucket = grouped[k] ?? []
                        TodoSectionHeader(title: prettyDate(k), trailing: "\(bucket.count)")
                        TodoGroupCard {
                            ForEach(Array(bucket.enumerated()), id: \.element.id) { idx, item in
                                TodoRowSwipe(item: item, isBulkSelecting: false, selection: $selection)
                                if idx < bucket.count - 1 { TodoRowDivider() }
                            }
                        }
                    }
                }
            }.padding(.top, 12)
        }
        .background(TodoToken.bg.ignoresSafeArea())
        .navigationTitle("Completed").navigationBarTitleInline()
        .environment(\.colorScheme, .dark)
    }

    private func prettyDate(_ key: String) -> String {
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: key) else { return key }
        let out = DateFormatter(); out.dateStyle = .medium
        return out.string(from: d)
    }
}
