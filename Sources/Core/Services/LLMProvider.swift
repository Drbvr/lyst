import Foundation

// MARK: - Message types

/// A message in a chat conversation, serialisable to the API wire format.
public enum LLMChatMessage: Sendable {
    case system(String)
    case user(String)
    case assistant(content: String?)
    /// An assistant turn that ended with tool calls.
    case assistantToolCalls(content: String?, calls: [ToolCallRequest])
    /// The result of a tool call.
    case toolResult(callId: String, content: String)

    public var role: String {
        switch self {
        case .system:                    return "system"
        case .user:                      return "user"
        case .assistant, .assistantToolCalls: return "assistant"
        case .toolResult:                return "tool"
        }
    }
}

// MARK: - Tool definition

public struct LLMToolDefinition: Sendable {
    public let name: String
    public let description: String
    /// JSON Schema string for the tool's parameters object.
    public let parametersJSON: String

    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }

    /// Serialises to the OpenAI /v1/chat/completions `tools` array element.
    public func toOpenAIDict() -> [String: Any] {
        let paramsData = parametersJSON.data(using: .utf8) ?? Data()
        let params = (try? JSONSerialization.jsonObject(with: paramsData)) as? [String: Any] ?? [:]
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": params
            ] as [String: Any]
        ]
    }
}

// MARK: - Stream events

public struct ToolCallRequest: Sendable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public enum FinishReason: Sendable {
    case stop
    case toolCalls([ToolCallRequest])
    case maxTokens
    case cancelled
}

public enum LLMStreamEvent: Sendable {
    case assistantDelta(String)
    case toolCallStart(ToolCallRequest)
    /// Incremental JSON fragment for the arguments of an in-progress tool call.
    case toolCallArgsDelta(id: String, json: String)
    case toolCallComplete(id: String)
    case finish(FinishReason)
}

// MARK: - Protocol

public protocol LLMProvider: Sendable {
    /// True when the provider emits individual token deltas; false when it
    /// emits the full response in a single `.assistantDelta` at the end.
    var supportsNativeTokenStreaming: Bool { get }

    func streamStep(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>

    func cancel()
}
