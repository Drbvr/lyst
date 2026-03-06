import SwiftUI
import Core

@Observable
class AppState {
    var items: [Item]
    var savedViews: [SavedView] = MockData.savedViews
    var listTypes: [ListType] = MockData.listTypes
    var isLoadingItems: Bool = false

    private let filterEngine = ItemFilterEngine()
    private let searchEngine = FullTextSearchEngine()
    private let tagHierarchyHelper = TagHierarchy()
    private let fileSystemManager = AppFileSystemManager()

    init() {
        // Initialize with mock data immediately to avoid blocking UI
        self.items = MockData.allItems

        // Load real files asynchronously in the background
        Task {
            await loadItemsFromVault()
        }
    }

    /// Reload items from a specific vault URL (called when user picks a folder)
    func reloadItems(from vaultURL: URL) async {
        isLoadingItems = true
        defer { isLoadingItems = false }

        var loadedItems: [Item] = []
        let coreFileSystem = DefaultFileSystemManager()
        let todoParser = ObsidianTodoParser()

        if case .success(let filePaths) = coreFileSystem.scanDirectory(at: vaultURL.path, recursive: true) {
            for filePath in filePaths {
                if case .success(let content) = coreFileSystem.readFile(at: filePath) {
                    let parsedItems = todoParser.parseTodos(from: content, sourceFile: filePath)
                    loadedItems.append(contentsOf: parsedItems)
                }
            }
        }

        if !loadedItems.isEmpty {
            self.items = loadedItems
        }
    }

    /// Load items from vault asynchronously to avoid blocking UI thread
    private func loadItemsFromVault() async {
        isLoadingItems = true
        defer { isLoadingItems = false }

        let documentsURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        let vaultURL = documentsURL.appendingPathComponent("ListAppVault")

        // Check if vault exists
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            // No vault folder, keep using mock data
            return
        }

        // Try to load real files asynchronously
        var loadedItems: [Item] = []
        let coreFileSystem = DefaultFileSystemManager()
        let todoParser = ObsidianTodoParser()

        if case .success(let filePaths) = coreFileSystem.scanDirectory(at: vaultURL.path, recursive: true) {
            for filePath in filePaths {
                if case .success(let content) = coreFileSystem.readFile(at: filePath) {
                    let parsedItems = todoParser.parseTodos(from: content, sourceFile: filePath)
                    loadedItems.append(contentsOf: parsedItems)
                }
            }
        }

        // Update items if we found any
        if !loadedItems.isEmpty {
            self.items = loadedItems
        }
    }

    // MARK: - Computed Properties

    var allTags: [String] {
        Array(Set(items.flatMap { $0.tags })).sorted()
    }

    /// Top-level tag groups with their children and item counts
    var tagGroups: [(tag: String, count: Int, children: [(tag: String, count: Int)])] {
        var groups: [String: Set<String>] = [:]

        for item in items {
            for tag in item.tags {
                guard !tag.isEmpty else { continue }
                let parts = tag.split(separator: "/")
                guard let firstPart = parts.first else { continue }
                let topLevel = String(firstPart)
                groups[topLevel, default: Set()].insert(tag)
            }
        }

        return groups.keys.sorted().map { topLevel in
            let childrenSet = groups[topLevel] ?? Set()
            let children = childrenSet.sorted().map { childTag in
                let count = items.filter { $0.tags.contains(childTag) }.count
                return (tag: childTag, count: count)
            }
            let totalCount = items.filter { item in
                item.tags.contains { $0.hasPrefix(topLevel) }
            }.count
            return (tag: topLevel, count: totalCount, children: children)
        }
    }

    var itemTypeNames: [String] {
        Array(Set(items.map { $0.type })).sorted()
    }

    // MARK: - Actions

    func toggleCompletion(for item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].completed.toggle()
            items[index].updatedAt = Date()

            // Persist change to file asynchronously
            Task {
                _ = await fileSystemManager.toggleTodoCompletion(items[index])
            }
        }
    }

    func deleteItem(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    /// Update an item's properties in memory (title, tags, due date, priority, etc.)
    func updateItem(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            updated.updatedAt = Date()
            items[index] = updated
        }
    }

    // MARK: - Filtering

    func filteredItems(for view: SavedView) -> [Item] {
        filterEngine.apply(filters: view.filters, to: items)
    }

    func filteredItems(with filters: ViewFilters) -> [Item] {
        filterEngine.apply(filters: filters, to: items)
    }

    // MARK: - Search

    func searchItems(query: String) -> [Item] {
        guard !query.isEmpty else { return items }  // Return all items when search is empty
        let results = searchEngine.search(query: query, in: items)
        return results.map { $0.item }
    }
}
