import SwiftUI
import Core

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: ChatViewModel?

    var body: some View {
        NavigationStack {
            if let vm = viewModel {
                ChatConversationView(viewModel: vm)
                    .navigationTitle("Chat")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Clear") { vm.clearHistory() }
                                .disabled(vm.messages.isEmpty || vm.isGenerating)
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            providerPill
                        }
                    }
            } else {
                ProgressView("Setting up…")
                    .task { await setup() }
            }
        }
    }

    private var providerPill: some View {
        let label = appState.llmSettings.processingMode == .onDevice ? "Apple Intelligence" : "Personal LLM"
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
    }

    private func setup() async {
        let settings = appState.llmSettings
        let index = appState.noteIndex
        let coreFS = DefaultFileSystemManager()
        let runner = ChatToolRunner(index: index, fileSystem: coreFS)

        let provider: any LLMProvider
        if settings.processingMode == .onDevice {
            if #available(iOS 26.0, *) {
                provider = AppleIntelligenceProvider(toolRunner: runner)
            } else {
                provider = OpenAIProvider(settings: settings)
            }
        } else {
            provider = OpenAIProvider(settings: settings)
        }

        let agent = ChatAgent(provider: provider, toolRunner: runner)
        let vm = await MainActor.run {
            ChatViewModel(agent: agent, appState: appState)
        }
        viewModel = vm
    }
}

// MARK: - Conversation view

private struct ChatConversationView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { msg in
                            ChatMessageRow(message: msg)
                                .id(msg.id)
                        }
                        if viewModel.budgetExceeded {
                            budgetBanner
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.messages.last?.content) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()
            composerBar
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var budgetBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text("Stopped after \(viewModel.budgetExceededIterationCount) iterations.")
            Spacer()
            Button("Resume") {
                Task { await viewModel.resume() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .font(.footnote)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }

    private var composerBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your notes…", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit {
                    guard !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { await viewModel.send() }
                }

            if viewModel.isGenerating {
                Button(action: viewModel.cancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? .tertiary : .accent
                        )
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
