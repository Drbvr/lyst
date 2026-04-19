import SwiftUI
import Core

@Observable
@MainActor
final class ChatViewModel {

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isGenerating: Bool = false
    var budgetExceeded: Bool = false
    var budgetExceededIterationCount: Int = 0

    private let agent: ChatAgent
    private let appState: AppState

    init(agent: ChatAgent, appState: AppState) {
        self.agent = agent
        self.appState = appState
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        inputText = ""
        isGenerating = true
        budgetExceeded = false

        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)

        // Placeholder assistant message streamed into — lookup by id each
        // callback so concurrent mutations (e.g. clearHistory) can't cause
        // out-of-bounds writes.
        let assistantMsg = ChatMessage(role: .assistant)
        let assistantId = assistantMsg.id
        messages.append(assistantMsg)

        await agent.run(
            messages: Array(messages.dropLast()),  // exclude the empty placeholder
            vaultName: appState.vaultDisplayName,
            noteCount: appState.items.count
        ) { [weak self] event in
            guard let self else { return }
            await MainActor.run {
                guard let idx = self.messages.firstIndex(where: { $0.id == assistantId }) else {
                    // Assistant placeholder was removed (e.g. history cleared). Drop the event.
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
                    let record = ToolCallRecord(id: id, name: name, argumentsJSON: "")
                    self.messages[idx].toolCalls.append(record)

                case .toolCallComplete(let id, let result):
                    if let tci = self.messages[idx].toolCalls.firstIndex(where: { $0.id == id }) {
                        self.messages[idx].toolCalls[tci].resultJSON = result
                        self.messages[idx].toolCalls[tci].isRunning = false
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

    func cancel() {
        Task { await agent.cancel() }
        isGenerating = false
    }

    func resume() async {
        guard budgetExceeded else { return }
        budgetExceeded = false
        // Append a continue instruction
        inputText = "Please continue."
        await send()
    }

    func clearHistory() {
        messages = []
    }
}
