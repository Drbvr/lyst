import SwiftUI
import Core

struct BulkSelectBar: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: Set<UUID>
    let allItems: [Item]
    let onDone: () -> Void
    @State private var showReschedule = false

    private var selected: [Item] { allItems.filter { selection.contains($0.id) } }

    var body: some View {
        HStack(spacing: 14) {
            Text("\(selection.count) selected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            bulkButton("checkmark", "Done") {
                for it in selected { appState.toggleCompletion(for: it) }
                finish()
            }
            bulkButton("calendar", "Schedule") { showReschedule = true }
            bulkButton("tag", "Label") { /* would open label picker */ finish() }
            bulkButton("trash", "Delete") {
                for it in selected { appState.deleteItem(it) }
                finish()
            }
            Button { finish() } label: {
                Image(systemName: "xmark").foregroundStyle(.white).padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.14))
                .shadow(radius: 10, y: 4)
        )
        .padding(.horizontal, 16).padding(.bottom, 20)
        .sheet(isPresented: $showReschedule) {
            if let first = selected.first {
                // Simplified: reschedule applied to first selected item;
                // the underlying sheet writes to md via AppState.updateItem.
                RescheduleSheet(item: first)
            }
        }
    }

    private func bulkButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.system(size: 10))
            }.foregroundStyle(.white)
        }.buttonStyle(.plain)
    }

    private func finish() { selection = []; onDone() }
}
