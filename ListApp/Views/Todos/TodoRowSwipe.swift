import SwiftUI
import Core

// Wraps TodoRowView with swipe actions, priority context menu, navigation
// into detail, and optional bulk-select mode. In bulk mode, taps toggle
// selection; otherwise they push the detail view.
struct TodoRowSwipe: View {
    @Environment(AppState.self) private var appState
    let item: Item
    let isBulkSelecting: Bool
    @Binding var selection: Set<UUID>
    @State private var showReschedule = false
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 8) {
            if isBulkSelecting {
                Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.contains(item.id) ? TodoToken.blue : TodoToken.mute)
                    .font(.system(size: 20))
                    .padding(.leading, 14)
                    .onTapGesture { toggleSelect() }
            }
            TodoRowView(
                item: item,
                onToggle: { appState.toggleCompletion(for: item) },
                onTap: {
                    if isBulkSelecting { toggleSelect() }
                    else { showDetail = true }
                }
            )
        }
        .navigationDestination(isPresented: $showDetail) {
            TodoDetailView(itemID: item.id)
        }
        .contextMenu {
            Menu("Priority") {
                ForEach(TodoPriority.allCases) { p in
                    Button(p.label) { setPriority(p) }
                }
                Button("Clear") { setPriority(nil) }
            }
            Button("Reschedule…") { showReschedule = true }
            Button(role: .destructive) { appState.deleteItem(item) } label: { Text("Delete") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                appState.toggleCompletion(for: item)
            } label: {
                Label(item.completed ? "Undo" : "Done",
                      systemImage: item.completed ? "arrow.uturn.backward" : "checkmark")
            }.tint(item.completed ? .orange : .green)
            Button { showReschedule = true } label: {
                Label("Schedule", systemImage: "calendar")
            }.tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { appState.deleteItem(item) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showReschedule) {
            RescheduleSheet(item: item)
        }
    }

    private func toggleSelect() {
        if selection.contains(item.id) { selection.remove(item.id) }
        else { selection.insert(item.id) }
    }

    private func setPriority(_ p: TodoPriority?) {
        var updated = item
        if let p = p { updated.properties["priority"] = .text(p.storageValue) }
        else { updated.properties.removeValue(forKey: "priority") }
        appState.updateItem(updated)
    }
}
