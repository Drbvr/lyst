import SwiftUI
import Core

/// A piece of content attached to the user's next chat message. Identity is a
/// UUID assigned at creation — the payload is not embedded so that large text
/// attachments don't balloon SwiftUI diffing cost. Deduplication of equivalent
/// payloads is handled explicitly via `payloadKey` below.
struct ChatAttachment: Identifiable, Equatable {
    enum Kind: Equatable {
        case text(String)
        case url(URL)
        case image(URL)
    }

    let id: UUID
    let kind: Kind

    init(_ kind: Kind, id: UUID = UUID()) {
        self.kind = kind
        self.id = id
    }

    static func text(_ s: String) -> ChatAttachment { .init(.text(s)) }
    static func url(_ u: URL) -> ChatAttachment { .init(.url(u)) }
    static func image(_ u: URL) -> ChatAttachment { .init(.image(u)) }

    /// Stable key used to detect duplicate payloads (same content should not be
    /// attached twice in a row). Kept separate from `id` so identity is cheap.
    var payloadKey: String {
        switch kind {
        case .text(let s):  return "t:" + s
        case .url(let u):   return "u:" + u.absoluteString
        case .image(let u): return "i:" + u.path
        }
    }

    var displayLabel: String {
        switch kind {
        case .text(let s):
            let preview = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(preview.prefix(40)) + (preview.count > 40 ? "…" : "")
        case .url(let u):  return u.host ?? u.absoluteString
        case .image(let u): return u.lastPathComponent
        }
    }

    var systemImage: String {
        switch kind {
        case .text:  return "text.alignleft"
        case .url:   return "link"
        case .image: return "photo"
        }
    }
}

@Observable
@MainActor
final class ChatViewModel {

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var attachments: [ChatAttachment] = []
    var isGenerating: Bool = false
    var budgetExceeded: Bool = false
    var budgetExceededIterationCount: Int = 0

    private let agent: ChatAgent
    private let appState: AppState
    private let noteCreator: NoteCreating

    init(agent: ChatAgent, appState: AppState, noteCreator: NoteCreating) {
        self.agent = agent
        self.appState = appState
        self.noteCreator = noteCreator
    }

    // MARK: - Attachments

    func addAttachment(_ attachment: ChatAttachment) {
        if !attachments.contains(where: { $0.payloadKey == attachment.payloadKey }) {
            attachments.append(attachment)
        }
    }

    func removeAttachment(_ attachment: ChatAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - Send

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !attachments.isEmpty), !isGenerating else { return }

        let pendingAttachments = attachments
        inputText = ""
        attachments = []
        isGenerating = true
        budgetExceeded = false

        // Build the user message: visible text first, then a stable summary
        // of each attachment. Images run through OCR via AttachmentProcessor.
        let userVisible = text.isEmpty ? "(attachments)" : text
        let userMsg = ChatMessage(role: .user, content: userVisible)
        messages.append(userMsg)

        let composed = await AttachmentProcessor.compose(
            userText: text,
            attachments: pendingAttachments
        )

        // Replace the placeholder's content with the composed, model-bound text.
        // The user-visible bubble stays as the human-typed text; the full body
        // is what we ship to the model (stored internally on the last message).
        if let idx = messages.lastIndex(where: { $0.id == userMsg.id }) {
            messages[idx].content = composed.userFacing
        }

        let assistantMsg = ChatMessage(role: .assistant)
        let assistantId = assistantMsg.id
        messages.append(assistantMsg)

        // Drop the empty placeholder, then swap the user message's content for
        // the model-bound version before sending.
        var transcript = Array(messages.dropLast())
        if let idx = transcript.lastIndex(where: { $0.id == userMsg.id }) {
            transcript[idx].content = composed.modelBound
        }

        await agent.run(
            messages: transcript,
            vaultName: appState.vaultDisplayName,
            noteCount: appState.items.count
        ) { [weak self] event in
            guard let self else { return }
            await MainActor.run { self.handleAgentEvent(event, assistantId: assistantId) }
        }
    }

    // MARK: - Approvals

    func respondToApproval(id: String, allow: Bool) {
        // Optimistically update the record; the tool result will confirm.
        for mi in messages.indices {
            if let tci = messages[mi].toolCalls.firstIndex(where: { $0.id == id }) {
                messages[mi].toolCalls[tci].approvalState = allow ? .approved : .denied
            }
        }
        Task { await agent.respondToApproval(id: id, allow: allow) }
    }

    func cancel() {
        Task { await agent.cancel() }
        isGenerating = false
    }

    func resume() async {
        guard budgetExceeded else { return }
        budgetExceeded = false
        inputText = "Please continue."
        await send()
    }

    func clearHistory() {
        messages = []
    }

    // MARK: - Draft bundle editing

    /// Mutate a single draft within a message's bundle. The caller supplies
    /// the mutation closure; this keeps the call-site ergonomic
    /// (`vm.updateDraft(...) { $0.title = "New" }`) while centralising the
    /// index bookkeeping.
    func updateDraft(
        messageId: UUID,
        draftId: UUID,
        mutate: (inout NoteEdit) -> Void
    ) {
        guard
            let mi = messages.firstIndex(where: { $0.id == messageId }),
            var bundle = messages[mi].draftBundle,
            let di = bundle.drafts.firstIndex(where: { $0.id == draftId })
        else { return }
        mutate(&bundle.drafts[di])
        messages[mi].draftBundle = bundle
    }

    func toggleIncluded(messageId: UUID, draftId: UUID) {
        updateDraft(messageId: messageId, draftId: draftId) { $0.isIncluded.toggle() }
    }

    /// Persist every included draft via `NoteCreating`, then flip the bundle
    /// to `isSaved` and append an assistant confirmation turn. Stops on the
    /// first failure; partial saves leave `isSaved` false so the user can
    /// retry the remaining drafts.
    func saveDrafts(messageId: UUID) async {
        guard
            let mi = messages.firstIndex(where: { $0.id == messageId }),
            let bundle = messages[mi].draftBundle,
            !bundle.isSaved
        else { return }

        let included = bundle.drafts.filter(\.isIncluded)
        guard !included.isEmpty else { return }

        var savedCount = 0
        for draft in included {
            let tags = draft.tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let stringProps = draft.properties.reduce(into: [String: String]()) { acc, pair in
                acc[pair.key] = Self.propertyValueString(pair.value)
            }
            do {
                _ = try await noteCreator.createNote(
                    type: draft.type,
                    title: draft.title,
                    tags: tags,
                    stringProperties: stringProps
                )
                savedCount += 1
            } catch {
                let failureMsg = ChatMessage(
                    role: .assistant,
                    content: "⚠️ Saved \(savedCount) of \(included.count) drafts. Error on '\(draft.title)': \(error.localizedDescription)"
                )
                messages.append(failureMsg)
                return
            }
        }

        if var refreshed = messages.first(where: { $0.id == messageId })?.draftBundle {
            refreshed.isSaved = true
            if let mi = messages.firstIndex(where: { $0.id == messageId }) {
                messages[mi].draftBundle = refreshed
            }
        }

        let noun = savedCount == 1 ? "note" : "notes"
        messages.append(ChatMessage(
            role: .assistant,
            content: "Saved \(savedCount) \(noun)."
        ))
    }

    /// Re-run the agent with the user's feedback. Prior drafts are serialised
    /// into the new user turn so the model has full context for its revision.
    func regenerateDrafts(messageId: UUID, feedback: String) async {
        guard
            let bundle = messages.first(where: { $0.id == messageId })?.draftBundle,
            !bundle.drafts.isEmpty,
            !isGenerating
        else { return }

        let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let serialised = Self.serialiseDrafts(bundle.drafts)
        let userVisible = "Revise the drafts above: \(trimmed)"
        let modelBound = """
        Revise the drafts you just proposed. Feedback: \(trimmed)

        Prior drafts JSON:
        \(serialised)
        """
        inputText = ""
        attachments = []

        let userMsg = ChatMessage(role: .user, content: userVisible)
        messages.append(userMsg)

        let assistantMsg = ChatMessage(role: .assistant)
        let assistantId = assistantMsg.id
        messages.append(assistantMsg)

        isGenerating = true
        budgetExceeded = false

        var transcript = Array(messages.dropLast())
        if let idx = transcript.lastIndex(where: { $0.id == userMsg.id }) {
            transcript[idx].content = modelBound
        }

        await agent.run(
            messages: transcript,
            vaultName: appState.vaultDisplayName,
            noteCount: appState.items.count
        ) { [weak self] event in
            guard let self else { return }
            await MainActor.run { self.handleAgentEvent(event, assistantId: assistantId) }
        }
    }

    // MARK: - Event routing (shared by send and regenerateDrafts)

    private func handleAgentEvent(_ event: ChatEvent, assistantId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else {
            switch event {
            case .done, .cancelled, .budgetExceeded, .failure:
                isGenerating = false
            default: break
            }
            return
        }
        switch event {
        case .assistantDelta(let delta):
            messages[idx].content += delta

        case .toolCallStart(let id, let name):
            if !messages[idx].toolCalls.contains(where: { $0.id == id }) {
                let gated = GatedChatTools.requiresApproval(name)
                let record = ToolCallRecord(
                    id: id, name: name, argumentsJSON: "",
                    approvalState: gated ? .pending : .notRequired
                )
                messages[idx].toolCalls.append(record)
            }

        case .toolCallNeedsApproval(let id, let name, let summary):
            if let tci = messages[idx].toolCalls.firstIndex(where: { $0.id == id }) {
                messages[idx].toolCalls[tci].approvalState = .pending
                messages[idx].toolCalls[tci].approvalSummary = summary
                messages[idx].toolCalls[tci].isRunning = false
            } else {
                var record = ToolCallRecord(
                    id: id, name: name, argumentsJSON: "",
                    approvalState: .pending, approvalSummary: summary
                )
                record.isRunning = false
                messages[idx].toolCalls.append(record)
            }

        case .toolCallComplete(let id, let result):
            if let tci = messages[idx].toolCalls.firstIndex(where: { $0.id == id }) {
                messages[idx].toolCalls[tci].resultJSON = result
                messages[idx].toolCalls[tci].isRunning = false
                let state = messages[idx].toolCalls[tci].approvalState
                if state == .pending || state == .approved {
                    messages[idx].toolCalls[tci].approvalState =
                        Self.isUserDeclined(result) ? .denied : .approved
                }
            }

        case .draftsProposed(let drafts):
            let existing = messages[idx].draftBundle?.drafts ?? []
            messages[idx].draftBundle = DraftBundle(
                id: messages[idx].draftBundle?.id ?? UUID(),
                drafts: existing + drafts,
                isSaved: false
            )

        case .done(let citations):
            messages[idx].citations = citations
            isGenerating = false

        case .budgetExceeded(let count):
            budgetExceeded = true
            budgetExceededIterationCount = count
            isGenerating = false

        case .cancelled:
            isGenerating = false

        case .failure(let msg):
            messages[idx].content += "\n\n⚠️ Error: \(msg)"
            isGenerating = false
        }
    }

    // MARK: - Helpers

    private static func propertyValueString(_ value: PropertyValue) -> String {
        switch value {
        case .text(let s):   return s
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 {
                return String(Int(n))
            }
            return String(n)
        case .bool(let b):   return b ? "true" : "false"
        case .date(let d):
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate]
            return f.string(from: d)
        }
    }

    private static func serialiseDrafts(_ drafts: [NoteEdit]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(drafts),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    /// Returns true iff the tool result JSON has `error == "user_declined"`.
    /// Checking the decoded field (rather than substring-matching the raw
    /// string) avoids false positives when a legitimately fetched page or
    /// note body happens to contain the literal text "user_declined".
    private static func isUserDeclined(_ resultJSON: String) -> Bool {
        guard
            let data = resultJSON.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let err = obj["error"] as? String
        else { return false }
        return err == "user_declined"
    }
}
