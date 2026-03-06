import Foundation

/// Represents a single item in the list system
public struct Item: Identifiable, Codable, Hashable {
    public static func == (lhs: Item, rhs: Item) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public let id: UUID
    public var type: String  // "todo", "book", "movie", etc.
    public var title: String
    public var properties: [String: PropertyValue]  // Flexible property storage
    public var tags: [String]  // Hierarchical tags like "work/linear/backend"
    public var completed: Bool
    public var sourceFile: String  // Path to source markdown file
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        type: String,
        title: String,
        properties: [String: PropertyValue] = [:],
        tags: [String] = [],
        completed: Bool = false,
        sourceFile: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.properties = properties
        self.tags = tags
        self.completed = completed
        self.sourceFile = sourceFile
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
