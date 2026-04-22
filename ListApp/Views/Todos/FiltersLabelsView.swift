import SwiftUI
import Core

struct FiltersLabelsView: View {
    @Environment(AppState.self) private var appState
    let items: [Item]

    struct SmartFilter: Identifiable { let id = UUID(); let icon: String; let name: String; let predicate: (Item) -> Bool }

    private var filters: [SmartFilter] {
        [
            .init(icon: "flame.fill", name: "Urgent (P1 & overdue)", predicate: { item in
                if let p = TodoPriority.from(item.properties["priority"]), p == .p1,
                   let d = TodoQueries.dueDate(item), d < Date() { return true }
                return false
            }),
            .init(icon: "flag.fill", name: "Priority 1", predicate: {
                TodoPriority.from($0.properties["priority"]) == .p1
            }),
            .init(icon: "calendar", name: "Due today", predicate: { item in
                guard let d = TodoQueries.dueDate(item) else { return false }
                return Calendar.current.isDateInToday(d)
            }),
            .init(icon: "person.crop.circle", name: "Assigned to me", predicate: { _ in true }),
            .init(icon: "clock", name: "Scheduled", predicate: { TodoQueries.dueDate($0) != nil }),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TodoSectionHeader(title: "Smart filters", trailing: "+ Filter")
            TodoGroupCard {
                ForEach(Array(filters.enumerated()), id: \.element.id) { idx, f in
                    let count = items.filter(f.predicate).count
                    NavigationLink {
                        FilteredTodoList(title: f.name, items: items.filter(f.predicate))
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7).fill(TodoToken.fillS)
                                    .frame(width: 26, height: 26)
                                Image(systemName: f.icon).font(.system(size: 13))
                                    .foregroundStyle(TodoToken.fg)
                            }
                            Text(f.name).foregroundStyle(TodoToken.fg)
                                .font(.system(size: 14))
                            Spacer()
                            Text("\(count)").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TodoToken.mute)
                            Image(systemName: "chevron.right").font(.system(size: 12))
                                .foregroundStyle(TodoToken.dim)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if idx < filters.count - 1 { TodoRowDivider() }
                }
            }

            let labels = TodoQueries.labels(items)
            TodoSectionHeader(title: "Labels", trailing: "\(labels.count)")
            TodoGroupCard {
                ForEach(Array(labels.enumerated()), id: \.element.name) { idx, l in
                    HStack(spacing: 12) {
                        Circle().fill(labelColor(l.name)).frame(width: 8, height: 8)
                        Text("@\(l.name)").font(.system(size: 14)).foregroundStyle(TodoToken.fg)
                        Spacer()
                        Text("\(l.count)").font(.system(size: 11)).foregroundStyle(TodoToken.mute)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    if idx < labels.count - 1 { TodoRowDivider() }
                }
            }

            TodoSectionHeader(title: "Filter query")
            Text(verbatim: "(today | overdue) & p1 & #work")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(TodoToken.fg)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(TodoToken.card))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TodoToken.lineS, lineWidth: 0.5))
                .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }

    private func labelColor(_ n: String) -> Color {
        let palette = [TodoToken.red, TodoToken.orange, TodoToken.blue, TodoToken.green, TodoToken.purple]
        return palette[abs(n.hashValue) % palette.count]
    }
}

struct FilteredTodoList: View {
    @Environment(AppState.self) private var appState
    let title: String
    let items: [Item]
    @State private var selection: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TodoSectionHeader(title: title, trailing: "\(items.count)")
                TodoGroupCard {
                    if items.isEmpty {
                        Text("No matches").foregroundStyle(TodoToken.mute).padding(20)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            TodoRowSwipe(item: item, isBulkSelecting: false, selection: $selection)
                            if idx < items.count - 1 { TodoRowDivider() }
                        }
                    }
                }
            }.padding(.top, 12)
        }
        .background(TodoToken.bg.ignoresSafeArea())
        .navigationTitle(title).navigationBarTitleInline()
        .environment(\.colorScheme, .dark)
    }
}
