import Foundation

/// Represents a saved view configuration
public struct SavedView: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let name: String
    public var filters: ViewFilters
    public var displayStyle: DisplayStyle

    public init(
        id: UUID = UUID(),
        name: String,
        filters: ViewFilters = ViewFilters(),
        displayStyle: DisplayStyle = .list
    ) {
        self.id = id
        self.name = name
        self.filters = filters
        self.displayStyle = displayStyle
    }
}

/// Represents filters for viewing items
public struct ViewFilters: Codable, Equatable, Hashable {
    public var tags: [String]?  // Support wildcards like "work/*"
    public var itemTypes: [String]?
    public var dueBefore: Date?
    public var dueAfter: Date?
    public var completed: Bool?
    public var folders: [String]?

    public init(
        tags: [String]? = nil,
        itemTypes: [String]? = nil,
        dueBefore: Date? = nil,
        dueAfter: Date? = nil,
        completed: Bool? = nil,
        folders: [String]? = nil
    ) {
        self.tags = tags
        self.itemTypes = itemTypes
        self.dueBefore = dueBefore
        self.dueAfter = dueAfter
        self.completed = completed
        self.folders = folders
    }
}

/// Represents how a view should be displayed
public enum DisplayStyle: String, Codable, Hashable {
    case list
    case card
}
