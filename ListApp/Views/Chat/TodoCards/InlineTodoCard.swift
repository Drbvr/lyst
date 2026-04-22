import SwiftUI
import Core

// Rendered inside a chat bubble when a tool result references a todo.
// Single source of truth: reads the live Item out of AppState so actions taken
// elsewhere are reflected here too.
struct InlineTodoCard: View {
    @Environment(AppState.self) private var appState
    let itemID: UUID

    private var item: Item? { appState.items.first { $0.id == itemID } }

    var body: some View {
        if let item = item {
            HStack(alignment: .top, spacing: 10) {
                CheckCircle(completed: item.completed, size: 18) {
                    appState.toggleCompletion(for: item)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TodoToken.fg)
                        .strikethrough(item.completed)
                    HStack(spacing: 6) {
                        if let p = TodoPriority.from(item.properties["priority"]) {
                            PriorityFlagView(priority: p, size: 10)
                        }
                        if let d = TodoQueries.dueDate(item) {
                            Text(short(d))
                                .font(.system(size: 10))
                                .foregroundStyle(TodoToken.mute)
                        }
                        ForEach(item.tags.prefix(2), id: \.self) { t in
                            Text("#\(t)").font(.system(size: 10))
                                .foregroundStyle(TodoToken.blue)
                        }
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(TodoToken.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TodoToken.lineS, lineWidth: 0.5))
        } else {
            EmptyView()
        }
    }

    private func short(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "E d MMM"
        return f.string(from: d)
    }
}

struct TodoConfirmCard: View {
    let title: String
    let summary: String
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(summary).font(.system(size: 12)).foregroundStyle(TodoToken.mute)
            HStack {
                Button(role: .cancel) { onCancel() } label: {
                    Text("Cancel").padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(TodoToken.fillS))
                }
                Button { onContinue() } label: {
                    Text("Continue").foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(TodoToken.blue))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(TodoToken.card))
    }
}

struct BriefingCard: View {
    struct Slot: Identifiable { let id = UUID(); let time: String; let title: String; let todoID: UUID? }
    let slots: [Slot]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's plan")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(TodoToken.fg)
            ForEach(slots) { s in
                HStack {
                    Text(s.time).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(TodoToken.mute).frame(width: 50, alignment: .leading)
                    Text(s.title).font(.system(size: 12)).foregroundStyle(TodoToken.fg)
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(TodoToken.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TodoToken.lineS, lineWidth: 0.5))
    }
}
