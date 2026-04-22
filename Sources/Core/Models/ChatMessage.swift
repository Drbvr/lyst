import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// Approval state for a tool call that requires the user's explicit consent
/// before it runs (e.g. creating a note, fetching an external URL).
public enum ToolApprovalState: String, Sendable, Codable {
    case notRequired
    case pending
    case approved
    case denied
}

/// Record of a single tool call within an assistant message.
public struct ToolCallRecord: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let argumentsJSON: String
    public var resultJSON: String?
    public var errorMessage: String?
    public var isRunning: Bool
    public var approvalState: ToolApprovalState
    public var approvalSummary: String?

    public init(
        id: String,
        name: String,
        argumentsJSON: String,
        approvalState: ToolApprovalState = .notRequired,
        approvalSummary: String? = nil
    ) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.isRunning = true
        self.approvalState = approvalState
        self.approvalSummary = approvalSummary
    }
}

/// Names of tools that require user approval before execution.
public enum GatedChatTools {
    public static let names: Set<String> = ["web_fetch", "update_todos", "break_down_task"]

    public static func requiresApproval(_ name: String) -> Bool {
        names.contains(name)
    }
}

/// A collection of note drafts proposed by the assistant in a single turn,
/// to be reviewed and optionally saved by the user.
public struct DraftBundle: Sendable, Identifiable {
    public let id: UUID
    public var drafts: [NoteEdit]
    public var isSaved: Bool

    public init(id: UUID = UUID(), drafts: [NoteEdit], isSaved: Bool = false) {
        self.id = id
        self.drafts = drafts
        self.isSaved = isSaved
    }
}

/// A single message in a chat conversation.
public struct ChatMessage: Sendable, Identifiable {
    public let id: UUID
    public let role: ChatRole
    public var content: String
    public var toolCalls: [ToolCallRecord]
    public var citations: [NoteRef]
    public var draftBundle: DraftBundle?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String = "",
        toolCalls: [ToolCallRecord] = [],
        citations: [NoteRef] = [],
        draftBundle: DraftBundle? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.citations = citations
        self.draftBundle = draftBundle
        self.timestamp = timestamp
    }
}
