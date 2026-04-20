import Foundation
#if canImport(FoundationModels)
import FoundationModels

// MARK: - Draft collector

/// Thread-safe collector for drafts produced by `FMProposeNoteTool` during a
/// single `sess.respond(to:)` call. The provider drains it and yields a
/// `.draftsProposed` stream event once the session finishes.
@available(iOS 26.0, *)
private actor DraftCollector {
    private var drafts: [NoteEdit] = []
    func append(_ items: [NoteEdit]) { drafts.append(contentsOf: items) }
    func drain() -> [NoteEdit] {
        let out = drafts
        drafts.removeAll()
        return out
    }
}

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
        return await runner.runRaw(name: name, args: args).result
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
        return await runner.runRaw(name: name, args: args).result
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
        return await runner.runRaw(name: name, args: args).result
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
        return await runner.runRaw(name: name, args: args).result
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
        return await runner.runRaw(name: name, args: args).result
    }
}

/// `propose_note` has no side effects — it hands a draft to the UI via the
/// shared `DraftCollector`. The model is told (in the system prompt) that
/// it must not save notes directly; the user saves drafts from the review card.
///
/// `properties` is intentionally omitted from `@Generable` args because
/// FoundationModels' schema cannot represent `[String: String]`; users can
/// add arbitrary properties via the draft card UI.
@available(iOS 26.0, *)
private struct FMProposeNoteTool: Tool {
    let name = "propose_note"
    let description = "Propose a draft note for the user to review, edit, and save. Call once per proposed note; call multiple times in one response to propose several."

    @Generable struct Arguments {
        @Guide(description: "Item type: 'todo', 'book', 'movie', 'restaurant', 'note', etc.")
        var type: String
        @Guide(description: "Required title of the note")
        var title: String
        @Guide(description: "Optional tags, e.g. ['work', 'project/alpha']")
        var tags: [String]?
    }

    let runner: ChatToolRunner
    let collector: DraftCollector
    func call(arguments: Arguments) async throws -> String {
        let args = ProposeNoteArgs(
            type: arguments.type,
            title: arguments.title,
            tags: arguments.tags ?? [],
            properties: [:]
        )
        let out = await runner.runRaw(name: name, args: args)
        await collector.append(out.drafts)
        return out.result
    }
}

@available(iOS 26.0, *)
private struct FMWebFetchTool: Tool {
    let name = "web_fetch"
    let description = "Fetch the readable text of a public http or https URL."

    @Generable struct Arguments {
        @Guide(description: "Public http or https URL to fetch")
        var url: String
    }

    let runner: ChatToolRunner
    func call(arguments: Arguments) async throws -> String {
        let args = WebFetchArgs(url: arguments.url)
        return await runner.runRaw(name: name, args: args).result
    }
}

// MARK: - Provider

/// LLMProvider backed by Apple Intelligence (FoundationModels).
/// The framework drives its own tool loop; we emit synthetic stream events.
@available(iOS 26.0, *)
public final class AppleIntelligenceProvider: LLMProvider, @unchecked Sendable {

    public let supportsNativeTokenStreaming = false

    private let toolRunner: ChatToolRunner
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

        // Fresh collector + session per streamStep — avoids state leaking
        // across conversations and ensures any system-prompt change takes effect.
        let collector = DraftCollector()
        let fmTools: [any Tool] = [
            FMSearchNotesTool(runner: toolRunner),
            FMListNotesTool(runner: toolRunner),
            FMReadNoteTool(runner: toolRunner),
            FMOutlineNoteTool(runner: toolRunner),
            FMListRecentNotesTool(runner: toolRunner),
            FMProposeNoteTool(runner: toolRunner, collector: collector),
            FMWebFetchTool(runner: toolRunner)
        ]
        let sess = LanguageModelSession(tools: fmTools, instructions: systemPrompt)

        // LanguageModelSession only accepts a single `respond(to:)` input, so
        // serialise prior user/assistant turns into a transcript preamble so
        // multi-turn context isn't lost. Tool-result turns are dropped — the
        // framework drives its own tool loop and re-runs tools on the next turn.
        let prompt = Self.buildPrompt(from: messages)

        let response = try await sess.respond(to: prompt)
        let text = response.content

        continuation.yield(.assistantDelta(text))
        let drafts = await collector.drain()
        if !drafts.isEmpty {
            continuation.yield(.draftsProposed(drafts))
        }
        continuation.yield(.finish(.stop))
        continuation.finish()
    }

    private static func buildPrompt(from messages: [LLMChatMessage]) -> String {
        var turns: [(role: String, text: String)] = []
        for msg in messages {
            switch msg {
            case .user(let t):
                turns.append(("User", t))
            case .assistant(let t):
                if let t, !t.isEmpty { turns.append(("Assistant", t)) }
            case .assistantToolCalls(let content, _):
                if let content, !content.isEmpty { turns.append(("Assistant", content)) }
            case .system, .toolResult:
                continue
            }
        }
        guard let last = turns.last, last.role == "User" else {
            return turns.last?.text ?? "Please help."
        }
        if turns.count == 1 { return last.text }
        let history = turns.dropLast()
            .map { "\($0.role): \($0.text)" }
            .joined(separator: "\n\n")
        return "Conversation so far:\n\n\(history)\n\nCurrent question:\n\(last.text)"
    }
}

#endif
