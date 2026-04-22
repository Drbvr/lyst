import SwiftUI
import Core

struct TodoRowView: View {
    let item: Item
    var indent: CGFloat = 0
    var showNoteLink: Bool = true
    var onToggle: () -> Void
    var onTap: (() -> Void)? = nil

    private var priority: TodoPriority? { TodoPriority.from(item.properties["priority"]) }
    private var dueDate: Date? {
        if case .date(let d) = item.properties["dueDate"] { return d }
        return nil
    }
    private var isOverdue: Bool {
        guard let d = dueDate, !item.completed else { return false }
        return d < Calendar.current.startOfDay(for: Date())
    }
    private var subtaskCount: (done: Int, total: Int)? {
        if case .text(let s) = item.properties["subtasks"] {
            let parts = s.split(separator: "/").compactMap { Int($0) }
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        return nil
    }

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .top, spacing: 12) {
                CheckCircle(completed: item.completed, action: onToggle)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .regular))
                            .strikethrough(item.completed)
                            .foregroundStyle(item.completed ? TodoToken.mute : TodoToken.fg)
                            .lineLimit(2)
                        if let p = priority {
                            PriorityFlagView(priority: p, size: 12)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        if let d = dueDate {
                            Label(formattedDue(d), systemImage: "calendar")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isOverdue ? TodoToken.red : TodoToken.mute)
                        }
                        ForEach(item.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(TodoToken.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(TodoToken.blue.opacity(0.12)))
                        }
                        if let st = subtaskCount {
                            Label("\(st.done)/\(st.total)", systemImage: "circle.grid.2x1")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 11))
                                .foregroundStyle(TodoToken.mute)
                        }
                        if showNoteLink && item.sourceFile.hasSuffix(".md") && !item.sourceFile.hasSuffix("/Inbox.md") {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.forward")
                                Text("note")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(TodoToken.mute)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4).strokeBorder(TodoToken.line, lineWidth: 0.5)
                            )
                        }
                    }
                }
                .padding(.leading, indent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formattedDue(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            let df = DateFormatter(); df.dateFormat = "HH:mm"
            let s = df.string(from: d)
            return s == "00:00" ? "Today" : "Today \(s)"
        }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        let df = DateFormatter(); df.dateFormat = "d MMM"
        return df.string(from: d)
    }
}
