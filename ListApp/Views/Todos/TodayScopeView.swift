import SwiftUI
import Core

struct TodayScopeView: View {
    @Environment(AppState.self) private var appState
    let items: [Item]
    @Binding var selection: Set<UUID>
    @Binding var isBulkSelecting: Bool

    var body: some View {
        let split = TodoQueries.forToday(items)
        VStack(spacing: 0) {
            if !split.overdue.isEmpty {
                TodoSectionHeader(title: "Overdue", trailing: "\(split.overdue.count)")
                TodoGroupCard { forEach(split.overdue) }
            }
            TodoSectionHeader(title: "Today · \(todayLabel())", trailing: "\(split.today.count)")
            TodoGroupCard {
                if split.today.isEmpty {
                    Text("No todos for today").foregroundStyle(TodoToken.mute)
                        .padding(20)
                } else {
                    forEach(split.today)
                }
            }
            if !split.noDate.isEmpty {
                TodoSectionHeader(title: "No date", trailing: "\(split.noDate.count)")
                TodoGroupCard { forEach(split.noDate) }
            }
        }
    }

    @ViewBuilder
    private func forEach(_ items: [Item]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
            TodoRowSwipe(item: item,
                         isBulkSelecting: isBulkSelecting,
                         selection: $selection)
            if idx < items.count - 1 { TodoRowDivider() }
        }
    }

    private func todayLabel() -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return f.string(from: Date())
    }
}
