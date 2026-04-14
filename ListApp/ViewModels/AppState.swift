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

// MARK: - AppState

@Observable
class AppState {
    var items: [Item]
    var savedViews: [SavedView]
    var listTypes: [ListType] = MockData.listTypes
    var isLoadingItems: Bool = false
    var currentVaultURL: URL? = nil
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
    private let fileSystemManager = AppFileSystemManager()

    init() {
        // Initialize with mock data immediately to avoid blocking UI
        self.items = MockData.allItems
        self.savedViews = Self.loadPersistedSavedViews() ?? MockData.savedViews
        self.selectedTheme = UserDefaults.standard.string(forKey: "selectedTheme") ?? "system"
        self.vaultDisplayName = UserDefaults.standard.string(forKey: "vaultDisplayName") ?? "ListAppVault"
        self.llmSettings = LLMSettings.load()

        // Load real files asynchronously in the background
        Task {
            await loadItemsFromVault()
        }
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
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    /// Reload items from a specific vault URL (called when user picks a folder).
    /// Always updates items — nil means scan error; empty array means empty folder.
    func reloadItems(from vaultURL: URL) async {
        isLoadingItems = true
        defer { isLoadingItems = false }

        if let loadedItems = scanItems(at: vaultURL) {
            self.items = loadedItems
        }
        // nil result = scan error; leave existing items untouched
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
                let loadedItems = scanItems(at: url)
                if accessing { url.stopAccessingSecurityScopedResource() }
                if let loadedItems = loadedItems, !loadedItems.isEmpty {
                    currentVaultURL = url
                    self.items = loadedItems
                    return
                }
            }
        }

        // Fall back to default Documents/ListAppVault
        let documentsURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        let vaultURL = documentsURL.appendingPathComponent("ListAppVault")

        guard FileManager.default.fileExists(atPath: vaultURL.path) else { return }

        if let loadedItems = scanItems(at: vaultURL) {
            currentVaultURL = vaultURL
            self.items = loadedItems
        }
    }

    /// Scan a vault URL for markdown items.
    /// Returns nil on scan/directory error, [] for a legitimate empty folder.
    private func scanItems(at url: URL) -> [Item]? {
        let coreFileSystem = DefaultFileSystemManager()
        let todoParser = ObsidianTodoParser()

        guard case .success(let filePaths) = coreFileSystem.scanDirectory(at: url.path, recursive: true) else {
            return nil  // Directory read error — don't wipe existing items
        }

        var loadedItems: [Item] = []
        for filePath in filePaths {
            guard case .success(let content) = coreFileSystem.readFile(at: filePath) else { continue }

            var parsed = todoParser.parseTodos(from: content, sourceFile: filePath)

            // Stamp items with real file-system dates
            let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
            let fsCreated  = (attrs?[.creationDate]     as? Date) ?? Date()
            let fsModified = (attrs?[.modificationDate] as? Date) ?? Date()

            for i in parsed.indices {
                // For todo items, use file creation date (YAML types keep their date_read/date_watched)
                if parsed[i].type == "todo" {
                    parsed[i].createdAt = fsCreated
                }
                // Always stamp updatedAt with file modification date
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

    func toggleCompletion(for item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].completed.toggle()
            items[index].updatedAt = Date()

            Task {
                _ = await fileSystemManager.toggleTodoCompletion(items[index])
            }
        }
    }

    func deleteItem(_ item: Item) {
        items.removeAll { $0.id == item.id }

        Task {
            _ = await fileSystemManager.deleteItem(item)
        }
    }

    func updateItem(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            updated.updatedAt = Date()
            items[index] = updated

            Task {
                _ = await fileSystemManager.writeItem(updated)
            }
        }
    }

    // MARK: - Item Creation

    /// Create a new todo item — appends a checkbox line to Inbox.md in the vault root.
    func createTodo(title: String, tags: [String], properties: [String: PropertyValue]) async {
        guard let vaultURL = currentVaultURL else { return }

        let coreFileSystem = DefaultFileSystemManager()
        let inboxPath = vaultURL.appendingPathComponent("Inbox.md").path

        // Build the markdown line
        var line = "- [ ] \(title)"
        if case .text(let p) = properties["priority"] {
            let emoji: String
            switch p {
            case "high":   emoji = "⏫"
            case "medium": emoji = "🔼"
            case "low":    emoji = "🔽"
            default:       emoji = ""
            }
            if !emoji.isEmpty { line += " \(emoji)" }
        }
        if case .date(let d) = properties["dueDate"] {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withFullDate]
            line += " 📅 \(fmt.string(from: d))"
        }
        for tag in tags { line += " #\(tag)" }

        // Read existing content or start fresh
        let existing: String
        if case .success(let content) = coreFileSystem.readFile(at: inboxPath) {
            existing = content
        } else {
            existing = "# Inbox\n"
        }

        let newContent = existing.hasSuffix("\n") ? existing + line + "\n" : existing + "\n" + line + "\n"
        _ = coreFileSystem.writeFile(at: inboxPath, content: newContent)

        // Create and append in memory
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
    }

    /// Create a new YAML-frontmatter item (book, movie, restaurant, etc.).
    /// Writes a new .md file to {VaultRoot}/{TypeName}s/{sanitizedTitle}.md
    func createYAMLItem(type: String, title: String, tags: [String], properties: [String: PropertyValue]) async {
        guard let vaultURL = currentVaultURL else { return }

        let coreFileSystem = DefaultFileSystemManager()
        let typeFolderName = type.capitalized + "s"
        let typeFolderURL = vaultURL.appendingPathComponent(typeFolderName)

        // Ensure type folder exists
        try? FileManager.default.createDirectory(at: typeFolderURL, withIntermediateDirectories: true)

        let safeName = title
            .components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        let filePath = typeFolderURL.appendingPathComponent("\(safeName).md").path

        // Build YAML frontmatter
        var lines = ["---", "type: \(type)", "title: \(title)"]
        if !tags.isEmpty {
            let tagsStr = tags.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("tags: [\(tagsStr)]")
        }

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withFullDate]

        for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
            switch value {
            case .text(let t):   lines.append("\(key): \(t)")
            case .number(let n): lines.append(n.truncatingRemainder(dividingBy: 1) == 0
                                     ? "\(key): \(Int(n))"
                                     : "\(key): \(n)")
            case .date(let d):   lines.append("\(key): \(isoFull.string(from: d))")
            case .bool(let b):   lines.append("\(key): \(b)")
            }
        }
        lines += ["---", ""]
        _ = coreFileSystem.writeFile(at: filePath, content: lines.joined(separator: "\n"))

        // Create and append in memory
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
}
