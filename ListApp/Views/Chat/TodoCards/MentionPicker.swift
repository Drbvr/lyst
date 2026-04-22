import SwiftUI
import Core

// Popover shown when the user types `@` in chat input — picks a todo to
// reference. Tapping emits an @{todoId} token that the chat agent can act on.
struct MentionPicker: View {
    @Environment(AppState.self) private var appState
    let query: String
    let onPick: (Item) -> Void

    private var matches: [Item] {
        guard query.hasPrefix("@") else { return [] }
        let needle = query.dropFirst().lowercased()
        let todos = appState.items.filter { $0.type == "todo" && !$0.completed }
        if needle.isEmpty { return Array(todos.prefix(6)) }
        return Array(todos.filter { $0.title.lowercased().contains(needle) }.prefix(6))
    }

    var body: some View {
        if !matches.isEmpty {
            VStack(spacing: 0) {
                ForEach(matches) { item in
                    Button { onPick(item) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "circle").foregroundStyle(TodoToken.mute)
                            Text(item.title).font(.system(size: 13))
                                .foregroundStyle(TodoToken.fg).lineLimit(1)
                            Spacer()
                            if let d = TodoQueries.dueDate(item) {
                                Text(short(d)).font(.system(size: 10))
                                    .foregroundStyle(TodoToken.mute)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                    }.buttonStyle(.plain)
                    if item.id != matches.last?.id {
                        Rectangle().fill(TodoToken.lineS).frame(height: 0.5)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(TodoToken.card2))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TodoToken.line, lineWidth: 0.5))
            .padding(.horizontal, 12)
        }
    }

    private func short(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "E d MMM"; return f.string(from: d)
    }
}
