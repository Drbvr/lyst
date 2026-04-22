import SwiftUI
import Core

struct ProjectDetailView: View {
    @Environment(AppState.self) private var appState
    let project: String
    @State private var viewMode: Int = 0   // 0 list, 1 board, 2 calendar
    @State private var selection: Set<UUID> = []

    private var items: [Item] { TodoQueries.inProject(appState.items, project: project) }
    private var subProjects: [(String, Int)] {
        var counts: [String: Int] = [:]
        for it in items {
            for tag in it.tags where tag.hasPrefix("\(project)/") {
                counts[tag, default: 0] += 1
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Circle().fill(TodoToken.blue).frame(width: 14, height: 14)
                    Text("#\(project)")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(TodoToken.fg)
                }.padding(.horizontal, 20).padding(.top, 4)

                Text("\(items.count) open · \(completedCount) completed · \(subProjects.count) sub-projects")
                    .font(.system(size: 13))
                    .foregroundStyle(TodoToken.mute)
                    .padding(.horizontal, 20).padding(.bottom, 14)

                HStack(spacing: 6) {
                    ForEach(Array(["List","Board","Calendar"].enumerated()), id: \.offset) { idx, label in
                        let sel = idx == viewMode
                        Button { viewMode = idx } label: {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(sel ? Color.black : TodoToken.fg)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(sel ? TodoToken.fg : Color.clear))
                                .overlay(Capsule().strokeBorder(sel ? Color.clear : TodoToken.line, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(.horizontal, 20).padding(.bottom, 12)

                if !subProjects.isEmpty {
                    TodoSectionHeader(title: "Sub-projects")
                    TodoGroupCard {
                        ForEach(Array(subProjects.enumerated()), id: \.element.0) { idx, sp in
                            HStack {
                                Text("#").foregroundStyle(TodoToken.dim).font(.system(size: 12))
                                Text(sp.0).font(.system(size: 14)).foregroundStyle(TodoToken.fg)
                                Spacer()
                                Text("\(sp.1)").font(.system(size: 11)).foregroundStyle(TodoToken.mute)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            if idx < subProjects.count - 1 { TodoRowDivider() }
                        }
                    }
                }

                TodoSectionHeader(title: "Tasks", trailing: "\(items.count) open")
                TodoGroupCard {
                    if viewMode == 0 {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            TodoRowSwipe(item: item, isBulkSelecting: false, selection: $selection)
                            if idx < items.count - 1 { TodoRowDivider() }
                        }
                    } else {
                        Text(viewMode == 1 ? "Board view (coming soon)" : "Calendar view (coming soon)")
                            .foregroundStyle(TodoToken.mute).padding(20)
                    }
                }
            }
            .padding(.top, 8)
        }
        .background(TodoToken.bg.ignoresSafeArea())
        .navigationTitle("").navigationBarTitleInline()
        .environment(\.colorScheme, .dark)
    }

    private var completedCount: Int {
        appState.items.filter { $0.type == "todo" && $0.completed
            && $0.tags.contains { $0 == project || $0.hasPrefix("\(project)/") } }.count
    }
}
