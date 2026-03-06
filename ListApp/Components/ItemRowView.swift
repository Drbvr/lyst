import SwiftUI
import Core

struct ItemRowView: View {
    let item: Item
    var onToggleComplete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if item.type == "todo" {
                Button(action: { onToggleComplete?() }) {
                    Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.completed ? .green : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.body)
                        .strikethrough(item.completed)
                        .foregroundStyle(item.completed ? .secondary : .primary)

                    Spacer()

                    if case .text(let priority) = item.properties["priority"] {
                        priorityBadge(priority)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        TagChipView(tag: tag)
                    }
                    if item.tags.count > 3 {
                        Text("+\(item.tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if case .date(let date) = item.properties["dueDate"] {
                        dueDateLabel(date)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func priorityBadge(_ priority: String) -> some View {
        switch priority {
        case "high":
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case "medium":
            Image(systemName: "arrow.up")
                .foregroundStyle(.orange)
                .font(.caption)
        case "low":
            Image(systemName: "arrow.down")
                .foregroundStyle(.blue)
                .font(.caption)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func dueDateLabel(_ date: Date) -> some View {
        let isOverdue = date < Date() && !item.completed
        HStack(spacing: 2) {
            Image(systemName: "calendar")
            Text(date, style: .date)
        }
        .font(.caption)
        .foregroundStyle(isOverdue ? .red : .secondary)
    }
}
