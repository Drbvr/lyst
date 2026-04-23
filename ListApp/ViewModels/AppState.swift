import SwiftUI
import Core

// MARK: - Pending Import

struct PendingImport: Identifiable {
    var id = UUID()
    var texts: [String] = []
    var imageURLs: [URL] = []
    var webURLs: [URL] = []

    init() {}
    init(text: String)   { texts     = [text] }
    init(image: URL)     { imageURLs = [image] }
    init(webURL: URL)    { webURLs   = [webURL] }
}

// MARK: - Errors

enum AppStateCreateError: LocalizedError {
    case noVault
    case invalidFilename
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVault:         return "No vault folder is selected. Pick one in Settings."
        case .invalidFilename: return "Could not derive a valid filename from the title."
        case .writeFailed(let detail): return "Failed to write \(detail)"
        }
    }
}

// MARK: - AppState

@Observable
class AppState {
    var items: [Item]
    var savedViews: [SavedView]
    var listTypes: [ListType] {
        didSet { persistListTypes() }
    }
    var isLoadingItems: Bool = false
    var currentVaultURL: URL? = nil
    var errorMessage: String? = nil
    var selectedTheme: String {
        didSet { UserDefaults.standard.set(selectedTheme, forKey: "selectedTheme") }
    }
    var vaultDisplayName: String {
        didSet { UserDefaults.standard.set(vaultDisplayName, forKey: "vaultDisplayName") }
    }
    var llmSettings: LLMSettings {
        didSet { llmSettings.save() }
    }
    var pendingImport: PendingImport? = nil

    private let filterEngine = ItemFilterEngine()
    private let searchEngine = FullTextSearchEngine()
    private let tagHierarchyHelper = TagHierarchy()
    private let coreFileSystem: FileSystemManager
    private let fileSystemManager: AppFileSystemManager
    var noteIndex: NoteIndex = NoteIndex(dbURL: AppState.defaultIndexURL())
    private var noteIndexer: NoteIndexer?

    private static func defaultIndexURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ListAppVault/.listapp/index.sqlite")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("index.sqlite")
    }

    init(fileSystem: FileSystemManager = DefaultFileSystemManager()) {
        self.coreFileSystem = fileSystem
        self.fileSystemManager = AppFileSystemManager(fileSystem: fileSystem)

        // Initialize with mock data immediately to avoid blocking UI
        self.items = MockData.allItems
        self.savedViews = Self.loadPersistedSavedViews() ?? MockData.savedViews
        self.listTypes = Self.loadPersistedListTypes() ?? MockData.listTypes
        self.selectedTheme = UserDefaults.standard.string(forKey: "selectedTheme") ?? "system"
        self.vaultDisplayName = UserDefaults.standard.string(forKey: "vaultDisplayName") ?? "ListAppVault"
        self.llmSettings = LLMSettings.load()
        ensureListTypesCoverLoadedItems()

        // Load vault items first so currentVaultURL is set before the index
        // is built on top of it — otherwise the cold-start index is empty.
        Task {
            await loadItemsFromVault()
            await openIndex()
        }
    }

    private func openIndex() async {
        try? await noteIndex.open()
        let indexer = NoteIndexer(index: noteIndex)
        noteIndexer = indexer
        fileSystemManager.noteIndexer = indexer
        if let vault = currentVaultURL {
            await indexer.buildInitialIndex(vaultURL: vault, fileSystem: coreFileSystem)
        }
    }

    /// Rebuild the index for a new vault URL.
    func rebuildIndex(for vaultURL: URL) async {
        await noteIndex.close()
        let newURL = vaultURL.appendingPathComponent(".listapp/index.sqlite")
        noteIndex = NoteIndex(dbURL: newURL)
        try? await noteIndex.open()
        let indexer = NoteIndexer(index: noteIndex)
        noteIndexer = indexer
        fileSystemManager.noteIndexer = indexer
        await indexer.buildInitialIndex(vaultURL: vaultURL, fileSystem: coreFileSystem)
    }

    /// Load from a security-scoped URL (iCloud Drive or external folder picker).
    /// Saves a bookmark so the vault persists across launches.
    func setVaultFromSecurityScopedURL(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()

        if let bookmarkData = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmarkData, forKey: "vaultBookmarkData")
            // Share bookmark with the extension via App Group container
            UserDefaults(suiteName: LLMSettings.appGroupID)?
                .set(bookmarkData, forKey: LLMSettings.vaultBookmarkKey)
        }

        vaultDisplayName = url.lastPathComponent
        currentVaultURL = url

        Task {
            await reloadItems(from: url)
            await rebuildIndex(for: url)
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    /// Reload items from a specific vault URL (called when user picks a folder).
    /// Scan errors leave existing items untouched. An empty scan result on a
    /// previously-populated vault is surfaced as a warning rather than silently
    /// wiping memory — a missing vault folder should not delete the user's view
    /// of their items.
    func reloadItems(from vaultURL: URL) async {
        isLoadingItems = true
        defer { isLoadingItems = false }

        let scanned = await Task.detached(priority: .userInitiated) { [coreFileSystem] in
            Self.scanItems(at: vaultURL, coreFileSystem: coreFileSystem)
        }.value

        guard let loadedItems = scanned else { return }

        if loadedItems.isEmpty && !self.items.isEmpty {
            errorMessage = "Vault scan returned no items — keeping current list."
            return
        }
        self.items = loadedItems
        ensureListTypesCoverLoadedItems()
    }

    /// Load items from vault asynchronously to avoid blocking UI thread
    private func loadItemsFromVault() async {
        isLoadingItems = true
        defer { isLoadingItems = false }

        // Try to restore from a saved security-scoped bookmark first (iCloud Drive etc.)
        if let bookmarkData = UserDefaults.standard.data(forKey: "vaultBookmarkData") {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                let accessing = url.startAccessingSecurityScopedResource()
                let loadedItems = await Task.detached(priority: .userInitiated) { [coreFileSystem] in
                    Self.scanItems(at: url, coreFileSystem: coreFileSystem)
                }.value
                if accessing { url.stopAccessingSecurityScopedResource() }
                if let loadedItems = loadedItems, !loadedItems.isEmpty {
                    currentVaultURL = url
                    self.items = loadedItems
                    ensureListTypesCoverLoadedItems()
                    return
                }
            }
        }

        // Fall back to default Documents/ListAppVault
        guard let documentsURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let vaultURL = documentsURL.appendingPathComponent("ListAppVault")

        guard FileManager.default.fileExists(atPath: vaultURL.path) else { return }

        let loadedItems = await Task.detached(priority: .userInitiated) { [coreFileSystem] in
            Self.scanItems(at: vaultURL, coreFileSystem: coreFileSystem)
        }.value
        if let loadedItems = loadedItems {
            currentVaultURL = vaultURL
            self.items = loadedItems
            ensureListTypesCoverLoadedItems()
        }
    }

    /// Scan a vault URL for markdown items. Runs on a background queue.
    /// Returns nil on directory error, [] on a legitimately empty folder.
    nonisolated private static func scanItems(at url: URL, coreFileSystem: FileSystemManager) -> [Item]? {
        let todoParser = ObsidianTodoParser()

        guard case .success(let filePaths) = coreFileSystem.scanDirectory(at: url.path, recursive: true) else {
            return nil
        }

        var loadedItems: [Item] = []
        for filePath in filePaths {
            guard case .success(let content) = coreFileSystem.readFile(at: filePath) else { continue }

            var parsed = todoParser.parseTodos(from: content, sourceFile: filePath)

            let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
            let fsCreated  = (attrs?[.creationDate]     as? Date) ?? Date()
            let fsModified = (attrs?[.modificationDate] as? Date) ?? Date()

            for i in parsed.indices {
                if parsed[i].type == "todo" {
                    parsed[i].createdAt = fsCreated
                }
                parsed[i].updatedAt = fsModified
            }

            loadedItems.append(contentsOf: parsed)
        }
        return loadedItems
    }

    // MARK: - Computed Properties

    var allTags: [String] {
        Array(Set(items.flatMap { $0.tags })).sorted()
    }

    /// Top-level tag groups with their real subtag children and item counts.
    /// A tag only appears as a "child" if it contains a "/" (is a subtag).
    /// Flat tags (no subtags) have an empty children array.
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
            let allTagsForGroup = groups[topLevel] ?? Set()
            // Only real subtags (contain "/") are shown as children
            let children = allTagsForGroup
                .filter { $0.contains("/") }
                .sorted()
                .map { childTag in
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
        Array(Set(items.map { $0.type.lowercased() })).sorted()
    }

    // MARK: - Actions

    /// Toggle completion. Updates UI state optimistically, then persists.
    /// On persist failure the UI state is reverted and `errorMessage` is set.
    func toggleCompletion(for item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let original = items[index]
        items[index].completed.toggle()
        items[index].updatedAt = Date()
        let updatedItem = items[index]

        Task { @MainActor in
            let ok = await fileSystemManager.toggleTodoCompletion(updatedItem)
            if !ok {
                if let idx = self.items.firstIndex(where: { $0.id == original.id }) {
                    self.items[idx] = original
                }
                self.errorMessage = fileSystemManager.error ?? "Could not persist change."
            }
        }
    }

    func deleteItem(_ item: Item) {
        let original = items
        items.removeAll { $0.id == item.id }

        Task { @MainActor in
            let ok = await fileSystemManager.deleteItem(item)
            if !ok {
                self.items = original
                self.errorMessage = fileSystemManager.error ?? "Could not delete item."
            }
        }
    }

    func updateItem(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let original = items[index]
        var updated = item
        updated.updatedAt = Date()
        items[index] = updated

        Task { @MainActor in
            let ok = await fileSystemManager.writeItem(updated, originalTitle: original.title)
            if !ok {
                if let idx = self.items.firstIndex(where: { $0.id == original.id }) {
                    self.items[idx] = original
                }
                self.errorMessage = fileSystemManager.error ?? "Could not update item."
            }
        }
    }

    // MARK: - Item Creation

    /// Create a new todo item — appends a checkbox line to Inbox.md in the vault
    /// root. Returns the absolute file path of Inbox.md on success; throws on
    /// write failure. Also appends the new item to `items`.
    func createTodo(title: String, tags: [String], properties: [String: PropertyValue]) async throws -> String {
        guard let vaultURL = currentVaultURL else { throw AppStateCreateError.noVault }

        let inboxPath = vaultURL.appendingPathComponent("Inbox.md").path
        let line = AppStateLogic.buildTodoLine(title: title, tags: tags, properties: properties)

        let existing: String
        if case .success(let content) = coreFileSystem.readFile(at: inboxPath) {
            existing = content
        } else {
            existing = "# Inbox\n"
        }
        let newContent = AppStateLogic.appendTodoToInbox(existingContent: existing, line: line)

        switch coreFileSystem.writeFile(at: inboxPath, content: newContent) {
        case .success:
            break
        case .failure(let e):
            errorMessage = "Failed to write Inbox.md: \(e)"
            throw AppStateCreateError.writeFailed("Inbox.md: \(e)")
        }

        var newItem = Item(
            type: "todo",
            title: title,
            properties: properties,
            tags: tags,
            completed: false,
            sourceFile: inboxPath
        )
        let attrs = try? FileManager.default.attributesOfItem(atPath: inboxPath)
        newItem.createdAt = (attrs?[.creationDate] as? Date) ?? Date()
        newItem.updatedAt = Date()
        items.append(newItem)
        return inboxPath
    }

    /// Create a new YAML-frontmatter item (book, movie, restaurant, etc.).
    /// Writes a new .md file to {VaultRoot}/{TypeName}s/{sanitizedTitle}.md.
    /// Returns the absolute file path on success; throws on invalid title or
    /// write failure.
    func createYAMLItem(type: String, title: String, tags: [String], properties: [String: PropertyValue]) async throws -> String {
        guard let vaultURL = currentVaultURL else { throw AppStateCreateError.noVault }
        guard let safeName = AppStateLogic.sanitizedFilename(from: title) else {
            errorMessage = "Invalid title for filename."
            throw AppStateCreateError.invalidFilename
        }

        let typeFolderName = type.capitalized + "s"
        let typeFolderURL = vaultURL.appendingPathComponent(typeFolderName)
        try? FileManager.default.createDirectory(at: typeFolderURL, withIntermediateDirectories: true)

        let filePath = typeFolderURL.appendingPathComponent("\(safeName).md").path
        let contents = AppStateLogic.serializeYAMLItem(
            type: type, title: title, tags: tags, properties: properties
        )

        switch coreFileSystem.writeFile(at: filePath, content: contents) {
        case .success:
            break
        case .failure(let e):
            errorMessage = "Failed to write \(safeName).md: \(e)"
            throw AppStateCreateError.writeFailed("\(safeName).md: \(e)")
        }

        var newItem = Item(
            type: type,
            title: title,
            properties: properties,
            tags: tags,
            completed: false,
            sourceFile: filePath
        )
        newItem.updatedAt = Date()
        items.append(newItem)
        return filePath
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
        guard !query.isEmpty else { return items }
        let results = searchEngine.search(query: query, in: items)
        return results.map { $0.item }
    }

    // MARK: - Saved Views Persistence

    func persistSavedViews() {
        if let data = try? JSONEncoder().encode(savedViews) {
            UserDefaults.standard.set(data, forKey: "savedViews")
        }
    }

    private static func loadPersistedSavedViews() -> [SavedView]? {
        guard let data = UserDefaults.standard.data(forKey: "savedViews"),
              let views = try? JSONDecoder().decode([SavedView].self, from: data)
        else { return nil }
        return views
    }

    private func persistListTypes() {
        if let data = try? JSONEncoder().encode(listTypes) {
            UserDefaults.standard.set(data, forKey: "listTypes")
        }
    }

    private static func loadPersistedListTypes() -> [ListType]? {
        guard let data = UserDefaults.standard.data(forKey: "listTypes"),
              let types = try? JSONDecoder().decode([ListType].self, from: data)
        else { return nil }
        return types
    }

    private func ensureListTypesCoverLoadedItems() {
        var byName: [String: ListType] = [:]
        for lt in listTypes {
            byName[lt.name.lowercased()] = lt
        }
        for typeName in itemTypeNames {
            if byName[typeName.lowercased()] == nil {
                let generated = ListType(name: typeName.capitalized)
                byName[typeName.lowercased()] = generated
            }
        }
        let merged = byName.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        if merged != listTypes {
            listTypes = merged
        }
    }

    func upsertListType(_ listType: ListType) {
        let key = listType.name.lowercased()
        if let index = listTypes.firstIndex(where: { $0.name.lowercased() == key }) {
            listTypes[index] = listType
        } else {
            listTypes.append(listType)
            listTypes.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
    }
}
