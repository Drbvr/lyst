import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// Record of a single tool call within an assistant message.
public struct ToolCallRecord: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let argumentsJSON: String
    public var resultJSON: String?
    public var errorMessage: String?
    public var isRunning: Bool

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.isRunning = true
    }
}

/// A single message in a chat conversation.
public struct ChatMessage: Sendable, Identifiable {
    public let id: UUID
    public let role: ChatRole
    public var content: String
    public var toolCalls: [ToolCallRecord]
    public var citations: [NoteRef]
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String = "",
        toolCalls: [ToolCallRecord] = [],
        citations: [NoteRef] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.citations = citations
        self.timestamp = timestamp
    }
}
