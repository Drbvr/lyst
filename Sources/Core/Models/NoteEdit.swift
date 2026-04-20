import Foundation

/// A parsed note that the user can review, edit, and optionally save during a batch import.
public struct NoteEdit: Identifiable, Codable, Sendable, Hashable {
    public var id = UUID()
    public var type: String
    public var title: String
    public var properties: [String: PropertyValue]
    public var tags: String        // comma-separated, for inline editing
    public var isIncluded: Bool    // user can toggle to skip saving this note

    public init(type: String, title: String, properties: [String: PropertyValue], tags: [String]) {
        self.type = type
        self.title = title
        self.properties = properties
        self.tags = tags.joined(separator: ", ")
        self.isIncluded = true
    }
}
