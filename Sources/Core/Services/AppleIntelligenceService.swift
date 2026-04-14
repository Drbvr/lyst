import Foundation
import FoundationModels

// MARK: - Error

public enum AppleIntelligenceError: LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "Apple Intelligence is not available on this device. " +
        "Enable it in Settings → Apple Intelligence & Siri, or switch to Personal LLM in AI settings."
    }
}

// MARK: - Tools

@available(iOS 26.0, macOS 26.0, *)
private struct WebFetchTool: Tool {
    let name = "web_fetch"
    let description = "Fetch the readable text content of a URL. Use this when the content contains a URL you need to look up to create an accurate note."

    @Generable
    struct Arguments {
        @Guide(description: "The URL to fetch")
        var url: String
    }

    func call(arguments: Arguments) async throws -> String {
        (try? await WebContentFetcher().fetchText(from: arguments.url))
            ?? "Could not fetch content from \(arguments.url)."
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct AskUserTool: Tool {
    let name = "ask_user"
    let description = "Ask the user a short clarifying question when the content is ambiguous and you cannot determine a required field without more information."

    @Generable
    struct Arguments {
        @Guide(description: "The question to show the user")
        var question: String
    }

    let onAsk: @Sendable (String) async -> String

    func call(arguments: Arguments) async throws -> String {
        await onAsk(arguments.question)
    }
}

// MARK: - Service

/// Handles on-device AI note generation using Apple Intelligence (iOS 26+).
@available(iOS 26.0, macOS 26.0, *)
public actor AppleIntelligenceService {

    /// Whether Apple Intelligence is enabled and available on this device.
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public init() {}

    /// Generate a model response using tool calling (web_fetch is always available;
    /// ask_user is enabled when `onAsk` is provided).
    ///
    /// The framework drives the tool loop internally — `respond(to:)` returns only
    /// after all tool calls are complete and the model has produced its final answer.
    ///
    /// If `retryPrompt` is provided, it is called with the first response. When it
    /// returns a non-nil string that string is sent as a second turn on the **same**
    /// session and the retry response is returned instead.
    public func complete(
        systemPrompt: String,
        userMessage: String,
        onAsk: (@Sendable (String) async -> String)? = nil,
        retryPrompt: (@Sendable (String) -> String?)? = nil
    ) async throws -> String {
        var tools: [any Tool] = [WebFetchTool()]
        if let onAsk {
            tools.append(AskUserTool(onAsk: onAsk))
        }
        let session = LanguageModelSession(instructions: systemPrompt, tools: tools)
        let first = try await session.respond(to: userMessage)
        let firstContent = first.content
        if let retryMessage = retryPrompt?(firstContent) {
            let retry = try await session.respond(to: retryMessage)
            return retry.content
        }
        return firstContent
    }
}
