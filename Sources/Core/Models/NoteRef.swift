import Foundation

/// A reference to a specific location within a note file, used for citations.
public struct NoteRef: Sendable, Codable, Hashable {
    public let file: String
    public let startLine: Int?
    public let endLine: Int?

    public init(file: String, startLine: Int? = nil, endLine: Int? = nil) {
        self.file = file
        self.startLine = startLine
        self.endLine = endLine
    }

    /// The filename without path, for display.
    public var displayName: String {
        URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
    }
}
