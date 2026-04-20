import SwiftUI
import Core
import PhotosUI
#if os(iOS)
import UIKit
#endif

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
        .onChange(of: appState.pendingImport?.id) { _, _ in
            guard let vm = viewModel, let pending = appState.pendingImport else { return }
            addPendingImportToChat(pending, viewModel: vm)
            appState.pendingImport = nil
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

    private func addPendingImportToChat(_ pending: PendingImport, viewModel: ChatViewModel) {
        for text in pending.texts        { viewModel.addAttachment(.text(text)) }
        for url  in pending.webURLs      { viewModel.addAttachment(.url(url)) }
        for url  in pending.imageURLs    { viewModel.addAttachment(.image(url)) }
    }

    private func setup() async {
        let settings = appState.llmSettings
        let index = appState.noteIndex
        let coreFS = DefaultFileSystemManager()
        let creator = AppNoteCreator(appState: appState)
        let runner = ChatToolRunner(index: index, fileSystem: coreFS, noteCreator: creator)

        let provider: any LLMProvider
        if settings.processingMode == .onDevice {
#if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                provider = AppleIntelligenceProvider(toolRunner: runner)
            } else {
                provider = OpenAIProvider(settings: settings)
            }
#else
            provider = OpenAIProvider(settings: settings)
#endif
        } else {
            provider = OpenAIProvider(settings: settings)
        }

        let agent = ChatAgent(provider: provider, toolRunner: runner)
        let vm = await MainActor.run {
            ChatViewModel(agent: agent, appState: appState)
        }
        // Drain any pending import that arrived before the view model existed.
        if let pending = appState.pendingImport {
            addPendingImportToChat(pending, viewModel: vm)
            appState.pendingImport = nil
        }
        viewModel = vm
    }
}

// MARK: - Conversation view

private struct ChatConversationView: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(AppState.self) private var appState

    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var isPhotoPickerPresented: Bool = false
    @State private var isLoadingPhoto: Bool = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { msg in
                            ChatMessageRow(message: msg) { id, allow in
                                viewModel.respondToApproval(id: id, allow: allow)
                            }
                            .id(msg.id)
                        }
                        if viewModel.budgetExceeded {
                            budgetBanner
                        }
                    }
                    .padding(.vertical, 12)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isComposerFocused = false
                }
#if os(iOS)
                .scrollDismissesKeyboard(.interactively)
#endif
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.messages.last?.content) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()
            if !viewModel.attachments.isEmpty {
                attachmentsBar
            }
            composerBar
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            selectedPhoto = nil
            isLoadingPhoto = true
            Task { await loadPhoto(newItem) }
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

    // MARK: - Attachments row

    private var attachmentsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.attachments) { att in
                    AttachmentChip(attachment: att) {
                        viewModel.removeAttachment(att)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Composer

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            attachmentMenu

            TextField("Ask about your notes…", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isComposerFocused)
                .onSubmit {
                    sendIfAllowed()
                }

            if viewModel.isGenerating {
                Button(action: viewModel.cancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    sendIfAllowed()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
#if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isComposerFocused = false
                }
            }
        }
#endif
    }

    private var canSend: Bool {
        let hasText = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || !viewModel.attachments.isEmpty
    }

    private func sendIfAllowed() {
        guard canSend else { return }
        isComposerFocused = false
        Task { await viewModel.send() }
    }

    @ViewBuilder
    private var attachmentMenu: some View {
        Menu {
            Button {
                isPhotoPickerPresented = true
            } label: {
                Label("Add Photo", systemImage: "photo")
            }
            #if os(iOS)
            Button {
                pasteFromClipboard()
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            #endif
            Button {
                addURLFromInput()
            } label: {
                Label("Attach URL from text", systemImage: "link")
            }
            .disabled(detectedURLInInput == nil)
        } label: {
            if isLoadingPhoto {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(viewModel.isGenerating)
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
    }

    // MARK: - Attachment helpers

    private var detectedURLInInput: URL? {
        let trimmed = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty
        else { return nil }
        return components.url
    }

    private func addURLFromInput() {
        guard let url = detectedURLInInput else { return }
        viewModel.addAttachment(.url(url))
        viewModel.inputText = ""
    }

    #if os(iOS)
    private func pasteFromClipboard() {
        let pb = UIPasteboard.general
        if pb.hasImages, let image = pb.image {
            Task {
                guard let data = image.jpegData(compressionQuality: 0.85) else { return }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".jpg")
                guard (try? data.write(to: tempURL)) != nil else { return }
                await MainActor.run { viewModel.addAttachment(.image(tempURL)) }
            }
            return
        }
        if pb.hasURLs, let url = pb.url {
            viewModel.addAttachment(.url(url))
            return
        }
        if pb.hasStrings, let text = pb.string, !text.isEmpty {
            if let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               let scheme = components.scheme?.lowercased(),
               ["http", "https"].contains(scheme),
               let url = components.url {
                viewModel.addAttachment(.url(url))
            } else {
                viewModel.addAttachment(.text(text))
            }
        }
    }
    #endif

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { Task { @MainActor in isLoadingPhoto = false } }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        guard (try? data.write(to: tempURL)) != nil else { return }
        await MainActor.run {
            viewModel.addAttachment(.image(tempURL))
        }
    }
}

// MARK: - Attachment chip

private struct AttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.systemImage)
                .font(.caption)
            Text(attachment.displayLabel)
                .font(.caption)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }
}
