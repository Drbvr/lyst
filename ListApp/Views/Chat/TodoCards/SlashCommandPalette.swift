import SwiftUI

struct SlashCommand: Identifiable, Hashable {
    let id = UUID()
    let command: String
    let description: String
    static let all: [SlashCommand] = [
        .init(command: "/todo",     description: "Create a new todo"),
        .init(command: "/today",    description: "What's due today?"),
        .init(command: "/overdue",  description: "List overdue todos"),
        .init(command: "/plan",     description: "Plan my day (time-boxed)"),
        .init(command: "/extract",  description: "Extract todos from the current note"),
    ]
}

// Popover-style palette shown below the chat input when the user types `/`.
// Filters live as the user continues typing after the slash.
struct SlashCommandPalette: View {
    let query: String
    let onPick: (SlashCommand) -> Void

    private var matches: [SlashCommand] {
        guard query.hasPrefix("/") else { return [] }
        let needle = query.dropFirst().lowercased()
        return SlashCommand.all.filter { $0.command.dropFirst().lowercased().hasPrefix(needle) }
    }

    var body: some View {
        if !matches.isEmpty {
            VStack(spacing: 0) {
                ForEach(matches) { cmd in
                    Button { onPick(cmd) } label: {
                        HStack {
                            Text(cmd.command)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(TodoToken.blue)
                            Text(cmd.description)
                                .font(.system(size: 12))
                                .foregroundStyle(TodoToken.mute)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if cmd.id != matches.last?.id {
                        Rectangle().fill(TodoToken.lineS).frame(height: 0.5)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(TodoToken.card2))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TodoToken.line, lineWidth: 0.5))
            .padding(.horizontal, 12)
        }
    }
}
