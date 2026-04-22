import SwiftUI
import Core

struct TodoDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID
    @State private var showReschedule = false

    private var item: Item? { appState.items.first { $0.id == itemID } }

    var body: some View {
        ScrollView {
            if let item = item {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        CheckCircle(completed: item.completed, size: 26) {
                            appState.toggleCompletion(for: item)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(TodoToken.fg)
                                .strikethrough(item.completed)
                            HStack(spacing: 10) {
                                if let p = TodoPriority.from(item.properties["priority"]) {
                                    PriorityFlagView(priority: p)
                                    Text(p.label).foregroundStyle(TodoToken.mute).font(.system(size: 13))
                                }
                                if let d = TodoQueries.dueDate(item) {
                                    Label(dateLabel(d), systemImage: "calendar")
                                        .foregroundStyle(TodoToken.mute).font(.system(size: 13))
                                }
                            }
                        }
                    }.padding(.horizontal, 20).padding(.top, 16)

                    if !item.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(item.tags, id: \.self) { t in
                                    Text("#\(t)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(TodoToken.blue)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().fill(TodoToken.blue.opacity(0.14)))
                                }
                            }.padding(.horizontal, 20)
                        }
                    }

                    if case .text(let notes) = item.properties["notes"], !notes.isEmpty {
                        TodoSectionHeader(title: "Notes")
                        Text(notes)
                            .font(.system(size: 14)).foregroundStyle(TodoToken.fg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(TodoToken.card))
                            .padding(.horizontal, 16)
                    }

                    if case .text(let sub) = item.properties["subtaskList"], !sub.isEmpty {
                        let subs = sub.components(separatedBy: "\n")
                        TodoSectionHeader(title: "Subtasks", trailing: "\(subs.count)")
                        TodoGroupCard {
                            ForEach(Array(subs.enumerated()), id: \.offset) { idx, s in
                                HStack(spacing: 12) {
                                    Image(systemName: "circle")
                                        .foregroundStyle(TodoToken.mute)
                                    Text(s).foregroundStyle(TodoToken.fg)
                                    Spacer()
                                }
                                .padding(.horizontal, 18).padding(.vertical, 11)
                                if idx < subs.count - 1 { TodoRowDivider() }
                            }
                        }
                    }

                    if case .text(let link) = item.properties["linkedNote"], !link.isEmpty {
                        TodoSectionHeader(title: "Linked note")
                        HStack {
                            Image(systemName: "arrow.up.forward").foregroundStyle(TodoToken.blue)
                            Text(link).font(.system(size: 13))
                                .foregroundStyle(TodoToken.fg).lineLimit(1)
                            Spacer()
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(TodoToken.card))
                        .padding(.horizontal, 16)
                    }

                    TodoSectionHeader(title: "Activity")
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Created \(item.createdAt.formatted(date: .abbreviated, time: .shortened))",
                              systemImage: "plus.circle")
                        Label("Updated \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))",
                              systemImage: "pencil")
                        Label("Source: \(URL(fileURLWithPath: item.sourceFile).lastPathComponent)",
                              systemImage: "doc.text")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(TodoToken.mute)
                    .padding(.horizontal, 20).padding(.bottom, 40)
                }
            } else {
                Text("Todo not found").foregroundStyle(TodoToken.mute).padding()
            }
        }
        .background(TodoToken.bg.ignoresSafeArea())
        .navigationTitle("").navigationBarTitleInline()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Reschedule…") { showReschedule = true }
                    if let item = item {
                        Button(role: .destructive) {
                            appState.deleteItem(item); dismiss()
                        } label: { Text("Delete") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showReschedule) {
            if let item = item { RescheduleSheet(item: item) }
        }
        .environment(\.colorScheme, .dark)
    }

    private func dateLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }
}
