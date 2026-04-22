import SwiftUI
import Core

struct TodosHomeView: View {
    @Environment(AppState.self) private var appState
    @State private var scope: TodoScope = .today
    @State private var query: String = ""
    @State private var showCreateSheet: Bool = false
    @State private var showCompleted: Bool = false
    @State private var editingSelection: Set<UUID> = []
    @State private var isBulkSelecting: Bool = false

    private var todos: [Item] { appState.items.filter { $0.type == "todo" } }
    private var openCount: Int { TodoQueries.openTodos(appState.items).count }
    private var overdueCount: Int { TodoQueries.overdueCount(appState.items) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        header
                        searchField
                        scopePicker
                        QuickAddBar { title in
                            let result = QuickAddParser.parse(title)
                            Task {
                                try? await createFromQuickAdd(result)
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 14)

                        scopeBody
                    }
                    .padding(.bottom, 80)
                }
                .background(TodoToken.bg.ignoresSafeArea())
                if isBulkSelecting && !editingSelection.isEmpty {
                    BulkSelectBar(
                        selection: $editingSelection,
                        allItems: todos,
                        onDone: { isBulkSelecting = false; editingSelection = [] }
                    )
                    .transition(.move(edge: .bottom))
                }
            }
            .navigationTitle("Todos").navigationBarTitleInline().toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Bulk select") { isBulkSelecting.toggle() }
                        Button("Completed archive") { showCompleted = true }
                        Button("New Todo…") { showCreateSheet = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                TodoCreateSheet().environment(appState)
            }
            .sheet(isPresented: $showCompleted) {
                NavigationStack { CompletedArchiveView() }
                    .environment(appState)
            }
            .navigationDestination(for: String.self) { project in
                ProjectDetailView(project: project)
            }
            .environment(\.colorScheme, .dark)
        }
    }

    // MARK: - Top elements

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(scope.label.capitalized)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(TodoToken.fg)
            Text("\(openCount) open · \(overdueCount) overdue")
                .font(.system(size: 14))
                .foregroundStyle(TodoToken.mute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(TodoToken.mute)
            TextField("Search todos", text: $query)
                .textFieldStyle(.plain).foregroundStyle(TodoToken.fg)
                .noAutocapitalization()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(TodoToken.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TodoToken.lineS, lineWidth: 0.5))
        .padding(.horizontal, 20).padding(.bottom, 10)
    }

    private var scopePicker: some View {
        SegmentedScopePicker(
            items: TodoScope.allCases.map { ($0, $0.label) },
            selection: $scope
        )
        .padding(.bottom, 12)
    }

    @ViewBuilder private var scopeBody: some View {
        let filtered = searchFilter(todos)
        switch scope {
        case .today:    TodayScopeView(items: filtered, selection: $editingSelection, isBulkSelecting: $isBulkSelecting)
        case .upcoming: UpcomingScopeView(items: filtered)
        case .inbox:    InboxScopeView(items: filtered)
        case .projects: ProjectsScopeView(items: filtered)
        case .labels:   FiltersLabelsView(items: filtered)
        }
    }

    private func searchFilter(_ items: [Item]) -> [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    private func createFromQuickAdd(_ r: QuickAddResult) async throws {
        guard !r.title.isEmpty else { return }
        var props: [String: PropertyValue] = [:]
        if let d = r.dueDate { props["dueDate"] = .date(d) }
        if let p = r.priority { props["priority"] = .text(p) }
        var tags: [String] = []
        if let pr = r.project { tags.append(pr) }
        tags.append(contentsOf: r.labels)
        _ = try await appState.createTodo(title: r.title, tags: tags, properties: props)
    }
}
