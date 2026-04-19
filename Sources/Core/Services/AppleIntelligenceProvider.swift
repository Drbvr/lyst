import Foundation
#if canImport(FoundationModels)
import FoundationModels

// MARK: - Chat Tool wrappers for FoundationModels

@available(iOS 26.0, *)
private struct FMSearchNotesTool: Tool {
    let name = "search_notes"
    let description = "Search notes by text using full-text search. Use for specific terms or phrases."

    @Generable struct Arguments {
        @Guide(description: "Search query or FTS5 MATCH expression")
        var query: String
        @Guide(description: "Maximum results to return (default 20, max 50)")
        var maxResults: Int?
    }

    let runner: ChatToolRunner
    func call(arguments: Arguments) async throws -> String {
        let args = SearchNotesArgs(query: arguments.query, maxResults: arguments.maxResults)
        return await runner.runRaw(name: name, args: args)
    }
}

@available(iOS 26.0, *)
private struct FMListNotesTool: Tool {
    let name = "list_notes"
    let description = "List notes by folder, tags, or date range. Returns metadata without content."

    @Generable struct Arguments {
        @Guide(description: "Filter to a specific folder name")
        var folder: String?
        @Guide(description: "Filter by tag (single tag only for Apple Intelligence)")
        var tag: String?
        @Guide(description: "Maximum number of notes to return (default 50, max 200)")
        var limit: Int?
    }

    let runner: ChatToolRunner
    func call(arguments: Arguments) async throws -> String {
        let args = ListNotesArgs(folder: arguments.folder, tag: arguments.tag, limit: arguments.limit)
        return await runner.runRaw(name: name, args: args)
    }
}

@available(iOS 26.0, *)
private struct FMReadNoteTool: Tool {
    let name = "read_note"
    let description = "Read the content of a note by its file path, with optional pagination."

    @Generable struct Arguments {
        @Guide(description: "Absolute file path of the note (from list_notes or search_notes results)")
        var noteFile: String
        @Guide(description: "Character offset to start reading from (default 0)")
        var offset: Int?
        @Guide(description: "Maximum characters to return (default 4000)")
        var limit: Int?
    }

    let runner: ChatToolRunner
    func call(arguments: Arguments) async throws -> String {
        let args = ReadNoteArgs(noteFile: arguments.noteFile, offset: arguments.offset, limit: arguments.limit)
        return await runner.runRaw(name: name, args: args)
    }
}

@available(iOS 26.0, *)
private struct FMOutlineNoteTool: Tool {
    let name = "outline_note"
    let description = "Get the heading structure and word count of a note without its body."

    @Generable struct Arguments {
        @Guide(description: "Absolute file path of the note")
        var noteFile: String
    }

    let runner: ChatToolRunner
    func call(arguments: Arguments) async throws -> String {
        let args = OutlineNoteArgs(noteFile: arguments.noteFile)
        return await runner.runRaw(name: name, args: args)
    }
}

@available(iOS 26.0, *)
private struct FMListRecentNotesTool: Tool {
    let name = "list_recent_notes"
    let description = "List recently modified notes. Use for temporal queries like 'what did I write yesterday'."

    @Generable struct Arguments {
        @Guide(description: "How many hours back to look (default 168 = 7 days)")
        var withinHours: Int?
        @Guide(description: "Maximum results (default 20)")
        var limit: Int?
    }

    let runner: ChatToolRunner
    func call(arguments: Arguments) async throws -> String {
        let args = ListRecentNotesArgs(withinHours: arguments.withinHours, limit: arguments.limit)
        return await runner.runRaw(name: name, args: args)
    }
}

// MARK: - Provider

/// LLMProvider backed by Apple Intelligence (FoundationModels).
/// The framework drives its own tool loop; we emit synthetic stream events.
@available(iOS 26.0, *)
public final class AppleIntelligenceProvider: LLMProvider, @unchecked Sendable {

    public let supportsNativeTokenStreaming = false

    private let toolRunner: ChatToolRunner
    private var session: LanguageModelSession?
    private let lock = NSLock()
    private var activeTask: Task<Void, Never>?

    public init(toolRunner: ChatToolRunner) {
        self.toolRunner = toolRunner
    }

    public func cancel() {
        lock.lock()
        let t = activeTask
        lock.unlock()
        t?.cancel()
    }

    public func streamStep(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            let task = Task {
                do {
                    try await self.executeSession(messages: messages, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            lock.lock()
            activeTask = task
            lock.unlock()
        }
    }

    private func executeSession(
        messages: [LLMChatMessage],
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        guard SystemLanguageModel.default.isAvailable else {
            throw AppleIntelligenceError.unavailable
        }

        let systemPrompt = messages.compactMap {
            if case .system(let t) = $0 { return t } else { return nil }
        }.joined(separator: "\n")

        let userMessages = messages.filter {
            if case .user = $0 { return true }
            if case .assistant = $0 { return true }
            if case .assistantToolCalls = $0 { return true }
            if case .toolResult = $0 { return true }
            return false
        }

        // Build or reuse session
        let fmTools: [any Tool] = [
            FMSearchNotesTool(runner: toolRunner),
            FMListNotesTool(runner: toolRunner),
            FMReadNoteTool(runner: toolRunner),
            FMOutlineNoteTool(runner: toolRunner),
            FMListRecentNotesTool(runner: toolRunner)
        ]

        if session == nil {
            session = LanguageModelSession(tools: fmTools, instructions: systemPrompt)
        }
        guard let sess = session else { return }

        // Extract the last user message
        let lastUserText: String
        if case .user(let t) = userMessages.last {
            lastUserText = t
        } else {
            lastUserText = "Please help."
        }

        let response = try await sess.respond(to: lastUserText)
        let text = response.content

        continuation.yield(.assistantDelta(text))
        continuation.yield(.finish(.stop))
        continuation.finish()
    }
}

#endif
