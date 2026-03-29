import Foundation

/// Error types for view management
public enum ViewError: Error, Equatable {
    case invalidViewDefinition(String)
    case parseError(String)
    case fileError(String)
}

/// Error types for view validation
public enum ValidationError: Error, Equatable {
    case missingRequiredField(String)
    case invalidFilterValue(String)
    case unsupportedFilterType(String)
}

/// Protocol for managing views
public protocol ViewManager {
    func loadViews(from folders: [String]) -> Result<[SavedView], ViewError>
    func applyView(_ view: SavedView, to items: [Item]) -> [Item]
    func validateView(_ view: SavedView) -> Result<Void, ValidationError>
}

/// Default implementation of ViewManager
public class DefaultViewManager: ViewManager {

    private let fileSystem: FileSystemManager
    private let yamlParser = YAMLFrontmatterParser()
    private let filterEngine = ItemFilterEngine()
    private let relativeDateParser = RelativeDateParser()

    public init(fileSystem: FileSystemManager) {
        self.fileSystem = fileSystem
    }

    /// Loads all views from specified folders
    public func loadViews(from folders: [String]) -> Result<[SavedView], ViewError> {
        var views: [SavedView] = []

        for folder in folders {
            // Scan for markdown files
            let scanResult = fileSystem.scanDirectory(at: folder, recursive: false)

            switch scanResult {
            case .success(let files):
                for filePath in files {
                    // Read file
                    let readResult = fileSystem.readFile(at: filePath)

                    switch readResult {
                    case .success(let content):
                        // Parse view
                        if let view = parseViewFromMarkdown(content) {
                            views.append(view)
                        }
                    case .failure:
                        // Skip files that can't be read
                        continue
                    }
                }

            case .failure:
                // Skip folders that can't be scanned
                continue
            }
        }

        return .success(views)
    }

    /// Applies a view's filters to items
    public func applyView(_ view: SavedView, to items: [Item]) -> [Item] {
        return filterEngine.apply(filters: view.filters, to: items)
    }

    /// Validates a view definition
    public func validateView(_ view: SavedView) -> Result<Void, ValidationError> {
        // Check required fields
        if view.name.isEmpty {
            return .failure(.missingRequiredField("name"))
        }

        // Validate display style (already enforced by enum)
        // Validate filters
        if let tags = view.filters.tags {
            for tag in tags {
                if tag.isEmpty {
                    return .failure(.invalidFilterValue("Tag cannot be empty"))
                }
            }
        }

        if let types = view.filters.itemTypes {
            for type in types {
                if type.isEmpty {
                    return .failure(.invalidFilterValue("Item type cannot be empty"))
                }
            }
        }

        if let folders = view.filters.folders {
            for folder in folders {
                if folder.isEmpty {
                    return .failure(.invalidFilterValue("Folder path cannot be empty"))
                }
            }
        }

        return .success(())
    }

    // MARK: - Private Helpers

    private func parseViewFromMarkdown(_ content: String) -> SavedView? {
        // Extract YAML frontmatter
        let (frontmatter, _) = yamlParser.extractFrontmatter(from: content)
        guard let yaml = frontmatter else { return nil }

        // Parse YAML
        return parseViewYAML(yaml)
    }

    private func parseViewYAML(_ yaml: String) -> SavedView? {
        let lines = yaml.components(separatedBy: .newlines)

        var type: String?
        var name: String?
        var displayStyle: DisplayStyle = .list
        var filters: ViewFilters = ViewFilters()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                continue
            }

            // Parse type field
            if trimmed.hasPrefix("type:") {
                let value = String(trimmed.dropFirst("type:".count)).trimmingCharacters(in: .whitespaces)
                type = value
            }

            // Parse name field
            if trimmed.hasPrefix("name:") {
                let value = String(trimmed.dropFirst("name:".count)).trimmingCharacters(in: .whitespaces)
                // Remove quotes if present
                name = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }

            // Parse display_style field
            if trimmed.hasPrefix("display_style:") {
                let value = String(trimmed.dropFirst("display_style:".count)).trimmingCharacters(in: .whitespaces)
                if value == "list" {
                    displayStyle = .list
                } else if value == "card" {
                    displayStyle = .card
                }
            }

            // Parse tags filter
            if trimmed.hasPrefix("tags:") {
                let value = String(trimmed.dropFirst("tags:".count)).trimmingCharacters(in: .whitespaces)
                filters.tags = parseYAMLArray(value)
            }

            // Parse item_types filter
            if trimmed.hasPrefix("item_types:") {
                let value = String(trimmed.dropFirst("item_types:".count)).trimmingCharacters(in: .whitespaces)
                filters.itemTypes = parseYAMLArray(value)
            }

            // Parse due_before filter
            if trimmed.hasPrefix("due_before:") {
                let value = String(trimmed.dropFirst("due_before:".count)).trimmingCharacters(in: .whitespaces)
                filters.dueBefore = parseYAMLDateValue(value)
            }

            // Parse due_after filter
            if trimmed.hasPrefix("due_after:") {
                let value = String(trimmed.dropFirst("due_after:".count)).trimmingCharacters(in: .whitespaces)
                filters.dueAfter = parseYAMLDateValue(value)
            }

            // Parse completed filter
            if trimmed.hasPrefix("completed:") {
                let value = String(trimmed.dropFirst("completed:".count)).trimmingCharacters(in: .whitespaces)
                if value == "true" {
                    filters.completed = true
                } else if value == "false" {
                    filters.completed = false
                }
            }

            // Parse folders filter
            if trimmed.hasPrefix("folders:") {
                let value = String(trimmed.dropFirst("folders:".count)).trimmingCharacters(in: .whitespaces)
                filters.folders = parseYAMLArray(value)
            }
        }

        // Validate that type is "view"
        guard type == "view" else { return nil }
        guard let name = name else { return nil }

        return SavedView(name: name, filters: filters, displayStyle: displayStyle)
    }

    private func parseYAMLArray(_ value: String) -> [String]? {
        // Parse YAML array format: [item1, item2, item3]
        guard value.hasPrefix("[") && value.hasSuffix("]") else { return nil }

        let inner = String(value.dropFirst().dropLast())
        let items = inner.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }

        return items.isEmpty ? nil : items
    }

    private func parseYAMLDateValue(_ value: String) -> Date? {
        let trimmedValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        // Try relative date first
        if trimmedValue.hasPrefix("+") || trimmedValue.hasPrefix("-") {
            return relativeDateParser.parse(trimmedValue)
        }

        // Try ISO8601 date
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: trimmedValue) {
            return date
        }

        return nil
    }
}
