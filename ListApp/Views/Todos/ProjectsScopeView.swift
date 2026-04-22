import SwiftUI
import Core

struct ProjectsScopeView: View {
    @Environment(AppState.self) private var appState
    let items: [Item]

    var body: some View {
        let projects = TodoQueries.projects(items)
        VStack(spacing: 0) {
            TodoSectionHeader(title: "All projects", trailing: "\(projects.count)")
            TodoGroupCard {
                ForEach(Array(projects.enumerated()), id: \.element.name) { idx, p in
                    NavigationLink(value: p.name) {
                        HStack(spacing: 14) {
                            Circle().fill(projectColor(p.name)).frame(width: 10, height: 10)
                            Text("#\(p.name)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(TodoToken.fg)
                            Spacer()
                            Text("\(p.open)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TodoToken.mute)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(TodoToken.dim)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if idx < projects.count - 1 { TodoRowDivider() }
                }
            }
        }
    }

    private func projectColor(_ name: String) -> Color {
        let palette = [TodoToken.blue, TodoToken.red, TodoToken.orange,
                       TodoToken.green, TodoToken.purple]
        let idx = abs(name.hashValue) % palette.count
        return palette[idx]
    }
}
