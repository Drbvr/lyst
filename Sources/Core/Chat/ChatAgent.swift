import Foundation

// MARK: - Chat events emitted to the UI

public enum ChatEvent: Sendable {
    case assistantDelta(String)
    case toolCallStart(id: String, name: String)
    /// Emitted before a gated tool (e.g. web_fetch) runs. The UI should show
    /// an approval card and call back via `ChatAgent.respondToApproval`.
    case toolCallNeedsApproval(id: String, name: String, summary: String)
    case toolCallComplete(id: String, result: String)
    /// Emitted once per assistant turn after all `propose_note` calls in that
    /// turn have run. Carries every draft produced in the turn so the UI can
    /// attach a single `DraftBundle` to the current assistant message.
    case draftsProposed(drafts: [NoteEdit])
    case done(citations: [NoteRef])
    case budgetExceeded(iterationCount: Int)
    case cancelled
    case failure(String)
}

// MARK: - ChatAgent

/// Drives the provider's tool-use loop, dispatches tool calls concurrently,
/// and emits ChatEvents for the UI to consume.
public actor ChatAgent {

    private let provider: any LLMProvider
    private let toolRunner: ChatToolRunner
    private let maxIterations: Int

    private var currentTask: Task<Void, Never>?
    private var pendingApprovals: [String: CheckedContinuation<Bool, Never>] = [:]

    public init(
        provider: any LLMProvider,
        toolRunner: ChatToolRunner,
        maxIterations: Int = 8
    ) {
        self.provider = provider
        self.toolRunner = toolRunner
        self.maxIterations = maxIterations
    }

    /// Run one user turn. Calls `onEvent` for every stream event until `.done` or `.cancelled`.
    public func run(
        messages: [ChatMessage],
        vaultName: String,
        noteCount: Int,
        onEvent: @escaping @Sendable (ChatEvent) async -> Void
    ) async {
        let task = Task {
            await self.executeLoop(
                messages: messages,
                vaultName: vaultName,
                noteCount: noteCount,
                onEvent: onEvent
            )
        }
        currentTask = task
        await task.value
        currentTask = nil
    }

    public func cancel() {
        currentTask?.cancel()
        provider.cancel()
        // Resolve any outstanding approvals as denials so the loop can unwind.
        let pendingIds = Array(pendingApprovals.keys)
        for id in pendingIds {
            resolvePendingApproval(id: id, allow: false)
        }
    }

    /// Called by the UI when the user approves or denies a gated tool call.
    public func respondToApproval(id: String, allow: Bool) {
        resolvePendingApproval(id: id, allow: allow)
    }

    private func resolvePendingApproval(id: String, allow: Bool) {
        guard let cont = pendingApprovals.removeValue(forKey: id) else { return }
        cont.resume(returning: allow)
    }

    private func waitForApproval(callId: String) async -> Bool {
        if Task.isCancelled {
            return false
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    pendingApprovals[callId] = continuation
                }
            }
        } onCancel: {
            Task { await self.resolvePendingApproval(id: callId, allow: false) }
        }
    }

    // MARK: - Loop

    private func executeLoop(
        messages: [ChatMessage],
        vaultName: String,
        noteCount: Int,
        onEvent: @escaping @Sendable (ChatEvent) async -> Void
    ) async {
        var transcript = buildTranscript(messages: messages, vaultName: vaultName, noteCount: noteCount)
        var allCitations: [NoteRef] = []
        var iterationCount = 0

        while iterationCount < maxIterations {
            guard !Task.isCancelled else {
                await onEvent(.cancelled)
                return
            }

            iterationCount += 1
            let stream = provider.streamStep(messages: transcript, tools: ChatTools.all)

            var assistantText = ""
            var pendingCalls: [ToolCallRequest] = []
            var finishReason: FinishReason = .stop
            var providerDrafts: [NoteEdit] = []

            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }

                    switch event {
                    case .assistantDelta(let delta):
                        assistantText += delta
                        await onEvent(.assistantDelta(delta))

                    case .toolCallStart(let req):
                        await onEvent(.toolCallStart(id: req.id, name: req.name))

                    case .toolCallArgsDelta:
                        break  // UI can optionally show streaming args

                    case .toolCallComplete(let id):
                        _ = id  // handled on finish

                    case .draftsProposed(let drafts):
                        providerDrafts.append(contentsOf: drafts)

                    case .finish(let reason):
                        finishReason = reason
                    }
                }
            } catch {
                if Task.isCancelled {
                    await onEvent(.cancelled)
                } else {
                    await onEvent(.failure(error.localizedDescription))
                }
                return
            }

            if Task.isCancelled {
                await onEvent(.cancelled)
                return
            }

            // Append assistant turn to transcript
            switch finishReason {
            case .toolCalls(let calls):
                pendingCalls = calls
                transcript.append(.assistantToolCalls(content: assistantText.isEmpty ? nil : assistantText,
                                                       calls: calls))

            case .stop, .maxTokens, .cancelled:
                if !assistantText.isEmpty {
                    transcript.append(.assistant(content: assistantText))
                }
                if !providerDrafts.isEmpty {
                    await onEvent(.draftsProposed(drafts: providerDrafts))
                }
                await onEvent(.done(citations: Array(Set(allCitations))))
                return
            }

            // No tool calls despite toolCalls finish reason — treat as stop
            if pendingCalls.isEmpty {
                await onEvent(.done(citations: Array(Set(allCitations))))
                return
            }

            // Gate calls that require explicit user approval. Approval is
            // serial (one prompt at a time) but non-gated calls can run
            // concurrently.
            for call in pendingCalls where GatedChatTools.requiresApproval(call.name) {
                let summary = Self.approvalSummary(name: call.name, argumentsJSON: call.argumentsJSON)
                await onEvent(.toolCallNeedsApproval(id: call.id, name: call.name, summary: summary))
            }

            // Execute tool calls concurrently (after the UI is informed about
            // any that need approval). Gated tools await the user's response
            // inside their branch before running.
            var toolResults: [(callId: String, result: String)] = []
            var stepRefs: [NoteRef] = []
            var stepDrafts: [NoteEdit] = []

            await withTaskGroup(
                of: (callId: String, result: String, refs: [NoteRef], drafts: [NoteEdit]).self
            ) { group in
                for call in pendingCalls {
                    group.addTask {
                        if GatedChatTools.requiresApproval(call.name) {
                            let allow = await self.waitForApproval(callId: call.id)
                            if !allow {
                                let denied = Self.encodeErrorJSON("user_declined")
                                return (call.id, denied, [], [])
                            }
                        }
                        let (result, refs, drafts) = await self.toolRunner.run(
                            name: call.name,
                            argumentsJSON: call.argumentsJSON
                        )
                        return (call.id, result, refs, drafts)
                    }
                }
                for await outcome in group {
                    toolResults.append((outcome.callId, outcome.result))
                    stepRefs.append(contentsOf: outcome.refs)
                    stepDrafts.append(contentsOf: outcome.drafts)
                    await onEvent(.toolCallComplete(id: outcome.callId, result: outcome.result))
                }
            }

            allCitations.append(contentsOf: stepRefs)

            if !stepDrafts.isEmpty {
                await onEvent(.draftsProposed(drafts: stepDrafts))
            }

            // Append tool results to transcript
            for (callId, result) in toolResults {
                transcript.append(.toolResult(callId: callId, content: result))
            }
        }

        // Budget exceeded
        await onEvent(.budgetExceeded(iterationCount: iterationCount))
    }

    // MARK: - Helpers

    private func buildTranscript(messages: [ChatMessage], vaultName: String, noteCount: Int) -> [LLMChatMessage] {
        var transcript: [LLMChatMessage] = [
            .system(ChatPromptBuilder.systemPrompt(vaultName: vaultName, noteCount: noteCount))
        ]
        for msg in messages {
            switch msg.role {
            case .user:
                transcript.append(.user(msg.content))
            case .assistant:
                if msg.toolCalls.isEmpty {
                    transcript.append(.assistant(content: msg.content))
                } else {
                    let calls = msg.toolCalls.map { tc in
                        ToolCallRequest(id: tc.id, name: tc.name, argumentsJSON: tc.argumentsJSON)
                    }
                    transcript.append(.assistantToolCalls(content: msg.content.isEmpty ? nil : msg.content,
                                                           calls: calls))
                    for tc in msg.toolCalls {
                        let result = tc.resultJSON ?? tc.errorMessage.map(Self.encodeErrorJSON) ?? "{}"
                        transcript.append(.toolResult(callId: tc.id, content: result))
                    }
                }
            case .tool, .system:
                break  // handled above or skip
            }
        }
        return transcript
    }

    private static func encodeErrorJSON(_ message: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: ["error": message]),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"unknown\"}"
        }
        return str
    }

    /// Builds a one-line description of a pending tool call for the approval card.
    public static func approvalSummary(name: String, argumentsJSON: String) -> String {
        let data = argumentsJSON.data(using: .utf8) ?? Data()
        let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        switch name {
        case "web_fetch":
            let raw = (dict["url"] as? String) ?? ""
            if let host = URL(string: raw)?.host {
                return "Fetch \(host)"
            }
            return "Fetch \(raw)"
        default:
            return name
        }
    }
}
