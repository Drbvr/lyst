import Foundation

/// Protocol for filtering items
public protocol FilterEngine {
    func apply(filters: ViewFilters, to items: [Item]) -> [Item]
}

/// Default implementation of filter engine
public class ItemFilterEngine: FilterEngine {

    private let tagHierarchy = TagHierarchy()

    public init() {}

    /// Applies filters to items using AND logic (all filters must match)
    public func apply(filters: ViewFilters, to items: [Item]) -> [Item] {
        var filtered = items

        // Apply tag filter
        if let tags = filters.tags, !tags.isEmpty {
            filtered = filterByTags(filtered, tags: tags)
        }

        // Apply item type filter
        if let types = filters.itemTypes, !types.isEmpty {
            let normalizedTypes = Set(types.map { $0.lowercased() })
            filtered = filtered.filter { normalizedTypes.contains($0.type.lowercased()) }
        }

        // Apply completion status filter
        if let completed = filters.completed {
            filtered = filtered.filter { $0.completed == completed }
        }

        // Apply due date filters
        if let dueBefore = filters.dueBefore {
            filtered = filterByDueDate(filtered, before: dueBefore)
        }

        if let dueAfter = filters.dueAfter {
            filtered = filterByDueDate(filtered, after: dueAfter)
        }

        // Apply folder filter
        if let folders = filters.folders, !folders.isEmpty {
            filtered = filterByFolders(filtered, folders: folders)
        }

        return filtered
    }

    // MARK: - Private Filter Methods

    private func filterByTags(_ items: [Item], tags: [String]) -> [Item] {
        // Collect all tags from all items
        let allItemTags = Set(items.flatMap { $0.tags })

        // Expand wildcards in filter tags
        var expandedTags = Set<String>()
        for tag in tags {
            if tag.contains("*") {
                let matched = tagHierarchy.expandWildcard(tag: tag, in: allItemTags)
                expandedTags.formUnion(matched)
            } else {
                expandedTags.insert(tag)
            }
        }

        // Filter items that have at least one matching tag (OR logic between tags)
        return items.filter { item in
            item.tags.contains { tag in expandedTags.contains(tag) }
        }
    }

    private func filterByDueDate(_ items: [Item], before: Date) -> [Item] {
        return items.filter { item in
            if case .date(let dueDate) = item.properties["dueDate"] {
                return dueDate < before
            }
            return false
        }
    }

    private func filterByDueDate(_ items: [Item], after: Date) -> [Item] {
        return items.filter { item in
            if case .date(let dueDate) = item.properties["dueDate"] {
                return dueDate > after
            }
            return false
        }
    }

    private func filterByFolders(_ items: [Item], folders: [String]) -> [Item] {
        return items.filter { item in
            let pathComponents = item.sourceFile.components(separatedBy: "/")
            return folders.contains { folderName in
                pathComponents.contains(folderName)
            }
        }
    }
}
