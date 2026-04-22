import SwiftUI
import Core

struct InboxScopeView: View {
    @Environment(AppState.self) private var appState
    let items: [Item]
    @State private var selection: Set<UUID> = []

    var body: some View {
        let list = TodoQueries.inbox(items)
        VStack(spacing: 0) {
            TodoSectionHeader(title: "Inbox", trailing: "\(list.count)")
            TodoGroupCard {
                if list.isEmpty {
                    Text("Inbox is empty").foregroundStyle(TodoToken.mute)
                        .padding(20)
                } else {
                    ForEach(Array(list.enumerated()), id: \.element.id) { idx, item in
                        TodoRowSwipe(item: item, isBulkSelecting: false, selection: $selection)
                        if idx < list.count - 1 { TodoRowDivider() }
                    }
                }
            }
        }
    }
}
