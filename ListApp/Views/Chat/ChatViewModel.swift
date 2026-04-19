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

        // Placeholder assistant message streamed into
        var assistantMsg = ChatMessage(role: .assistant)
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        await agent.run(
            messages: Array(messages.dropLast()),  // exclude the empty placeholder
            vaultName: appState.vaultDisplayName,
            noteCount: appState.items.count
        ) { [weak self] event in
            guard let self else { return }
            await MainActor.run {
                switch event {
                case .assistantDelta(let delta):
                    self.messages[assistantIndex].content += delta

                case .toolCallStart(let id, let name):
                    let record = ToolCallRecord(id: id, name: name, argumentsJSON: "")
                    self.messages[assistantIndex].toolCalls.append(record)

                case .toolCallComplete(let id, let result):
                    if let idx = self.messages[assistantIndex].toolCalls.firstIndex(where: { $0.id == id }) {
                        self.messages[assistantIndex].toolCalls[idx].resultJSON = result
                        self.messages[assistantIndex].toolCalls[idx].isRunning = false
                    }

                case .done(let citations):
                    self.messages[assistantIndex].citations = citations
                    self.isGenerating = false

                case .budgetExceeded(let count):
                    self.budgetExceeded = true
                    self.budgetExceededIterationCount = count
                    self.isGenerating = false

                case .cancelled:
                    self.isGenerating = false

                case .failure(let msg):
                    self.messages[assistantIndex].content += "\n\n⚠️ Error: \(msg)"
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
