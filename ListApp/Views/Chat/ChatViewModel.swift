import SwiftUI
import Core

/// A piece of content attached to the user's next chat message.
enum ChatAttachment: Identifiable, Equatable {
    case text(String)
    case url(URL)
    case image(URL)

    var id: String {
        switch self {
        case .text(let s):  return "t:" + s
        case .url(let u):   return "u:" + u.absoluteString
        case .image(let u): return "i:" + u.path
        }
    }

    var displayLabel: String {
        switch self {
        case .text(let s):
            let preview = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(preview.prefix(40)) + (preview.count > 40 ? "…" : "")
        case .url(let u):  return u.host ?? u.absoluteString
        case .image(let u): return u.lastPathComponent
        }
    }

    var systemImage: String {
        switch self {
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

    init(agent: ChatAgent, appState: AppState) {
        self.agent = agent
        self.appState = appState
    }

    // MARK: - Attachments

    func addAttachment(_ attachment: ChatAttachment) {
        if !attachments.contains(where: { $0.id == attachment.id }) {
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
            await MainActor.run {
                guard let idx = self.messages.firstIndex(where: { $0.id == assistantId }) else {
                    if case .done = event { self.isGenerating = false }
                    if case .cancelled = event { self.isGenerating = false }
                    if case .budgetExceeded = event { self.isGenerating = false }
                    if case .failure = event { self.isGenerating = false }
                    return
                }
                switch event {
                case .assistantDelta(let delta):
                    self.messages[idx].content += delta

                case .toolCallStart(let id, let name):
                    if !self.messages[idx].toolCalls.contains(where: { $0.id == id }) {
                        let gated = GatedChatTools.requiresApproval(name)
                        let record = ToolCallRecord(
                            id: id,
                            name: name,
                            argumentsJSON: "",
                            approvalState: gated ? .pending : .notRequired
                        )
                        self.messages[idx].toolCalls.append(record)
                    }

                case .toolCallNeedsApproval(let id, let name, let summary):
                    if let tci = self.messages[idx].toolCalls.firstIndex(where: { $0.id == id }) {
                        self.messages[idx].toolCalls[tci].approvalState = .pending
                        self.messages[idx].toolCalls[tci].approvalSummary = summary
                    } else {
                        var record = ToolCallRecord(
                            id: id, name: name, argumentsJSON: "",
                            approvalState: .pending,
                            approvalSummary: summary
                        )
                        record.isRunning = false
                        self.messages[idx].toolCalls.append(record)
                    }

                case .toolCallComplete(let id, let result):
                    if let tci = self.messages[idx].toolCalls.firstIndex(where: { $0.id == id }) {
                        self.messages[idx].toolCalls[tci].resultJSON = result
                        self.messages[idx].toolCalls[tci].isRunning = false
                        // If it was pending and we got a result, it was approved
                        // and ran — or the denial produced the synthetic result.
                        let state = self.messages[idx].toolCalls[tci].approvalState
                        if state == .pending {
                            self.messages[idx].toolCalls[tci].approvalState =
                                result.contains("user_declined") ? .denied : .approved
                        }
                    }

                case .done(let citations):
                    self.messages[idx].citations = citations
                    self.isGenerating = false

                case .budgetExceeded(let count):
                    self.budgetExceeded = true
                    self.budgetExceededIterationCount = count
                    self.isGenerating = false

                case .cancelled:
                    self.isGenerating = false

                case .failure(let msg):
                    self.messages[idx].content += "\n\n⚠️ Error: \(msg)"
                    self.isGenerating = false
                }
            }
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
}
