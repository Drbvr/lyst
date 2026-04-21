import SwiftUI
import Core

// MARK: - Filter state

/// Ad-hoc filter state for the Notes page. Mirrors the structure in the
/// design handoff: single-select type, tri-state completion, multi-select
/// tags, single-select due window.
struct NotesFilterState: Equatable {
    enum Status: String, Equatable, CaseIterable {
        case all
        case open
        case done
    }

    enum Due: Equatable {
        case any
        case today
        case thisWeek
        case overdue
        case custom(start: Date, end: Date)

        var summaryLabel: String? {
            switch self {
            case .any:        return nil
            case .today:      return "Due today"
            case .thisWeek:   return "This week"
            case .overdue:    return "Overdue"
            case .custom(let start, let end):
                let f = DateFormatter()
                f.dateFormat = "MMM d"
                return "\(f.string(from: start))–\(f.string(from: end))"
            }
        }
    }

    var type: String? = nil          // lowercase: "todo", "book", "movie", "restaurant"
    var status: Status = .all
    var tags: Set<String> = []
    var due: Due = .any

    var isDefault: Bool {
        type == nil && status == .all && tags.isEmpty && due == .any
    }

    /// How many non-default sub-filters are applied. Used to badge the
    /// Filter button.
    var activeCount: Int {
        var n = 0
        if type != nil { n += 1 }
        if status != .all { n += 1 }
        n += tags.count
        if due != .any { n += 1 }
        return n
    }
}

// MARK: - Sort mode

enum NotesSortMode: String, CaseIterable, Identifiable {
    case dateAdded
    case dueDate
    case priority
    case titleAZ

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateAdded: return "By date added"
        case .dueDate:   return "By due date"
        case .priority:  return "By priority"
        case .titleAZ:   return "Title A→Z"
        }
    }

    var iconName: String {
        switch self {
        case .dateAdded: return "calendar"
        case .dueDate:   return "clock"
        case .priority:  return "exclamationmark.triangle"
        case .titleAZ:   return "textformat"
        }
    }
}

// MARK: - View

/// Results-first Notes tab.
///
/// Collapses the old stack of filter surfaces (Saved Views, Type pills,
/// Status picker, Tag groups, Search) into a compact top bar + bottom sheet,
/// so the actual list of notes is always visible on first load.
struct NotesBrowserView: View {
    @Environment(AppState.self) private var appState

    @State private var query: String = ""
    @State private var selectedSavedViewID: SavedView.ID? = nil
    @State private var activeFilter: NotesFilterState = .init()
    @State private var sortMode: NotesSortMode = .dateAdded

    @State private var showFilterSheet: Bool = false
    @State private var showAddSavedView: Bool = false
    @State private var showSaveCurrent: Bool = false

    // MARK: - Derived data

    private var matchingItems: [Item] {
        let base = applyFilters(to: appState.items, filters: activeFilter)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let q = trimmed.lowercased()
        return base.filter { item in
            item.title.lowercased().contains(q)
                || item.type.lowercased().contains(q)
                || item.tags.contains { $0.lowercased().contains(q) }
        }
    }

    private var sortedItems: [Item] {
        sort(items: matchingItems, by: sortMode)
    }

    private var groupedSections: [ItemSection] {
        group(items: sortedItems, by: sortMode)
    }

    private var totalNoteCount: Int { appState.items.count }

    private var hasActiveFilters: Bool { !activeFilter.isDefault }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchFilterRow
                savedViewsStrip
                if hasActiveFilters && selectedSavedViewID == nil {
                    activeFiltersCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                resultsList
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Notes")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showFilterSheet) {
                NotesFilterSheet(
                    initialFilter: activeFilter,
                    savedViewID: selectedSavedViewID
                ) { newFilter in
                    applyFromSheet(newFilter)
                }
                .environment(appState)
            }
            .sheet(isPresented: $showAddSavedView) {
                AddSavedViewSheet()
                    .environment(appState)
            }
            .sheet(isPresented: $showSaveCurrent) {
                AddSavedViewSheet(presetFilters: filtersAsViewFilters(activeFilter))
                    .environment(appState)
            }
            .navigationDestination(for: SavedView.self) { savedView in
                ItemListView(
                    title: savedView.name,
                    items: appState.filteredItems(for: savedView),
                    displayStyle: savedView.displayStyle
                )
            }
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort", selection: $sortMode) {
                    ForEach(NotesSortMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.iconName).tag(mode)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    showAddSavedView = true
                } label: {
                    Label("New Saved View…", systemImage: "bookmark")
                }
                if hasActiveFilters {
                    Button {
                        showSaveCurrent = true
                    } label: {
                        Label("Save Current Filters…", systemImage: "square.and.arrow.down")
                    }
                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            resetFilters()
                        }
                    } label: {
                        Label("Reset Filters", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: - Search + filter row

    private var searchFilterRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes", text: $query)
                    .noAutocapitalization()
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemFill))
            )

            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Filters")
                        .font(.system(size: 15, weight: .medium))
                    if activeFilter.activeCount > 0 {
                        Text("\(activeFilter.activeCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filters, \(activeFilter.activeCount) active")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Saved views chip strip

    private var savedViewsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SavedViewChip(
                    icon: "square.grid.2x2",
                    label: "All",
                    count: totalNoteCount,
                    isSelected: selectedSavedViewID == nil && !hasActiveFilters
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedSavedViewID = nil
                        activeFilter = .init()
                    }
                }
                ForEach(appState.savedViews) { view in
                    SavedViewChip(
                        icon: iconForSavedView(view),
                        label: view.name,
                        count: appState.filteredItems(for: view).count,
                        isSelected: selectedSavedViewID == view.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSavedViewID = view.id
                            activeFilter = filtersFromSavedView(view)
                        }
                    }
                    .contextMenu {
                        Button {
                            showAddSavedView = true
                        } label: {
                            Label("Edit Saved Views…", systemImage: "pencil")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Active filters card

    private var activeFiltersCard: some View {
        HStack(spacing: 6) {
            Text("Active")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let type = activeFilter.type {
                FilterPill(label: type.capitalized) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeFilter.type = nil
                        selectedSavedViewID = nil
                    }
                }
            }
            if activeFilter.status != .all {
                FilterPill(label: activeFilter.status == .open ? "Open" : "Done") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeFilter.status = .all
                        selectedSavedViewID = nil
                    }
                }
            }
            ForEach(Array(activeFilter.tags).sorted(), id: \.self) { tag in
                FilterPill(label: "#\(tag)") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeFilter.tags.remove(tag)
                        selectedSavedViewID = nil
                    }
                }
            }
            if let dueLabel = activeFilter.due.summaryLabel {
                FilterPill(label: dueLabel) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeFilter.due = .any
                        selectedSavedViewID = nil
                    }
                }
            }

            Spacer(minLength: 4)

            Text("\(matchingItems.count) results")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Results list

    @ViewBuilder
    private var resultsList: some View {
        if sortedItems.isEmpty {
            ContentUnavailableView(
                hasActiveFilters || !query.isEmpty ? "No matches" : "No notes",
                systemImage: "tray",
                description: Text(hasActiveFilters || !query.isEmpty
                                  ? "Try clearing filters or search terms."
                                  : "Create your first note from the Chat tab.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(groupedSections) { section in
                    Section {
                        ForEach(section.items) { item in
                            let current = appState.items.first(where: { $0.id == item.id }) ?? item
                            NavigationLink(value: current) {
                                ItemRowView(item: current) {
                                    appState.toggleCompletion(for: current)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if current.type == "todo" {
                                    Button {
                                        appState.toggleCompletion(for: current)
                                    } label: {
                                        Label(
                                            current.completed ? "Undo" : "Done",
                                            systemImage: current.completed
                                                ? "arrow.uturn.backward"
                                                : "checkmark"
                                        )
                                    }
                                    .tint(current.completed ? .orange : .green)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    appState.deleteItem(current)
                                } label: {
                                    Label("Delete", systemImage: "archivebox")
                                }
                                .accessibilityLabel("Delete \(current.title)")
                            }
                        }
                    } header: {
                        if let title = section.title {
                            HStack {
                                Text(title)
                                if let trailing = section.trailingLabel {
                                    Spacer()
                                    Text(trailing)
                                        .textCase(nil)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Filter application helpers

    private func applyFilters(to items: [Item], filters: NotesFilterState) -> [Item] {
        NotesFilterEvaluator.apply(filters, to: items)
    }

    private func filtersAsViewFilters(_ f: NotesFilterState) -> ViewFilters {
        NotesFilterEvaluator.viewFilters(for: f)
    }

    private func filtersFromSavedView(_ view: SavedView) -> NotesFilterState {
        var state = NotesFilterState()
        state.type = view.filters.itemTypes?.first
        state.tags = Set(view.filters.tags ?? [])
        if let c = view.filters.completed {
            state.status = c ? .done : .open
        } else {
            state.status = .all
        }
        return state
    }

    private func applyFromSheet(_ newFilter: NotesFilterState) {
        withAnimation(.easeInOut(duration: 0.15)) {
            activeFilter = newFilter
            selectedSavedViewID = nil
        }
    }

    private func resetFilters() {
        activeFilter = .init()
        selectedSavedViewID = nil
    }

    private func iconForSavedView(_ view: SavedView) -> String {
        iconForType(view.filters.itemTypes?.first ?? "")
    }

    private func iconForType(_ typeName: String) -> String {
        switch typeName.lowercased() {
        case "todo":       return "checkmark.circle"
        case "book":       return "book"
        case "movie":      return "film"
        case "restaurant": return "fork.knife"
        default:           return "bookmark"
        }
    }

    // MARK: - Sorting & grouping

    private func sort(items: [Item], by mode: NotesSortMode) -> [Item] {
        switch mode {
        case .dateAdded:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .dueDate:
            return items.sorted { lhs, rhs in
                let lDue = due(for: lhs) ?? .distantFuture
                let rDue = due(for: rhs) ?? .distantFuture
                return lDue < rDue
            }
        case .priority:
            return items.sorted { priorityRank(for: $0) < priorityRank(for: $1) }
        case .titleAZ:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func group(items: [Item], by mode: NotesSortMode) -> [ItemSection] {
        guard !items.isEmpty else { return [] }
        switch mode {
        case .dateAdded:
            return groupByAddedDate(items)
        case .dueDate:
            return groupByDueDate(items)
        case .priority, .titleAZ:
            return [ItemSection(id: "all", title: nil, trailingLabel: nil, items: items)]
        }
    }

    private func groupByAddedDate(_ items: [Item]) -> [ItemSection] {
        let cal = Calendar.current
        let now = Date()
        var buckets: [String: [Item]] = [:]
        var order: [String] = []
        func push(_ key: String, _ item: Item) {
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]!.append(item)
        }

        let startOfToday     = cal.startOfDay(for: now)
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfThisWeek  = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let startOfThisMonth = cal.dateInterval(of: .month, for: now)?.start ?? startOfToday

        for item in items {
            let d = item.createdAt
            if d >= startOfToday          { push("Today", item) }
            else if d >= startOfYesterday { push("Yesterday", item) }
            else if d >= startOfThisWeek  { push("This Week", item) }
            else if d >= startOfThisMonth { push("This Month", item) }
            else                          { push("Earlier", item) }
        }
        let preferred = ["Today", "Yesterday", "This Week", "This Month", "Earlier"]
        let ordered = preferred.filter { order.contains($0) }
        return ordered.map { key in
            ItemSection(id: key, title: key, trailingLabel: nil, items: buckets[key] ?? [])
        }
    }

    private func groupByDueDate(_ items: [Item]) -> [ItemSection] {
        let cal = Calendar.current
        let now = Date()
        var buckets: [String: [Item]] = [:]
        var order: [String] = []
        func push(_ key: String, _ item: Item) {
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]!.append(item)
        }

        let startOfToday = cal.startOfDay(for: now)
        let endOfToday   = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let endOfWeek    = cal.dateInterval(of: .weekOfYear, for: now)?.end ?? endOfToday

        for item in items {
            if item.completed {
                push("Completed", item)
            } else if let d = due(for: item) {
                if d < startOfToday      { push("Overdue",   item) }
                else if d < endOfToday   { push("Today",     item) }
                else if d < endOfWeek    { push("This Week", item) }
                else                     { push("Later",     item) }
            } else {
                push("No due date", item)
            }
        }

        let preferred = ["Overdue", "Today", "This Week", "Later", "No due date", "Completed"]
        let ordered = preferred.filter { order.contains($0) }
        return ordered.map { key in
            ItemSection(id: key, title: key, trailingLabel: nil, items: buckets[key] ?? [])
        }
    }

    private func priorityRank(for item: Item) -> Int {
        if case .text(let p) = item.properties["priority"] {
            switch p.lowercased() {
            case "high":   return 0
            case "medium": return 1
            case "low":    return 2
            default:       return 3
            }
        }
        return 3
    }

    private func due(for item: Item) -> Date? {
        if case .date(let d) = item.properties["dueDate"] { return d }
        return nil
    }
}

// MARK: - Sections & chips

struct ItemSection: Identifiable {
    let id: String
    let title: String?
    let trailingLabel: String?
    let items: [Item]
}

// MARK: - Filter evaluator

/// Pure functions that turn a `NotesFilterState` into a matching `[Item]`
/// using the existing Core filter engine plus a manual pass for due-date
/// windows.
enum NotesFilterEvaluator {
    private static let engine = ItemFilterEngine()

    static func apply(_ filters: NotesFilterState, to items: [Item]) -> [Item] {
        let vf = viewFilters(for: filters)
        var result = engine.apply(filters: vf, to: items)

        switch filters.due {
        case .any:
            break
        case .today:
            let range = dayRange(containing: Date())
            result = result.filter { due(for: $0).map { range.contains($0) } ?? false }
        case .thisWeek:
            let range = weekRange(containing: Date())
            result = result.filter { due(for: $0).map { range.contains($0) } ?? false }
        case .overdue:
            let now = Date()
            result = result.filter {
                guard let d = due(for: $0) else { return false }
                return d < now && !$0.completed
            }
        case .custom(let start, let end):
            let range = start...end
            result = result.filter { due(for: $0).map { range.contains($0) } ?? false }
        }
        return result
    }

    static func viewFilters(for f: NotesFilterState) -> ViewFilters {
        ViewFilters(
            tags: f.tags.isEmpty ? nil : Array(f.tags),
            itemTypes: f.type.map { [$0] },
            completed: {
                switch f.status {
                case .all:  return nil
                case .open: return false
                case .done: return true
                }
            }()
        )
    }

    private static func due(for item: Item) -> Date? {
        if case .date(let d) = item.properties["dueDate"] { return d }
        return nil
    }

    private static func dayRange(containing date: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? date
        return start...end
    }

    private static func weekRange(containing date: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else {
            return dayRange(containing: date)
        }
        return interval.start...interval.end
    }
}

struct SavedViewChip: View {
    let icon: String
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count) items")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FilterPill: View {
    let label: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.accentColor.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove filter \(label)")
    }
}
