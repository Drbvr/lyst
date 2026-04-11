import SwiftUI
import Core
import Vision

// MARK: - ViewModel

@Observable
@MainActor
final class ImportViewModel {
    enum Step { case decision, processing, preview }

    var step: Step = .decision
    var statusMessage = "Analysing content…"
    var errorMessage: String? = nil

    // Editable preview fields
    var editTitle = ""
    var editTags = ""   // comma-separated
    var editType = "todo"
    var editProperties: [String: PropertyValue] = [:]

    let pending: PendingImport

    init(pending: PendingImport) {
        self.pending = pending
    }

    // MARK: - AI Processing

    func processWithAI(settings: LLMSettings, listTypes: [ListType], items: [Item]) async {
        step = .processing
        errorMessage = nil

        let llm = LLMService(settings: settings)
        let promptBuilder = PromptBuilder()
        let parser = NoteResponseParser()
        let systemPrompt = promptBuilder.buildSystemPrompt(
            listTypes: listTypes,
            sampleNotes: promptBuilder.extractSampleNotes(from: items)
        )

        do {
            let messages: [[String: Any]]

            switch pending {
            case .image(let fileURL):
                messages = try await buildImageMessages(
                    fileURL: fileURL,
                    settings: settings,
                    systemPrompt: systemPrompt,
                    promptBuilder: promptBuilder
                )
            case .webURL(let url):
                statusMessage = "Fetching page content…"
                let pageText = (try? await WebContentFetcher().fetchText(from: url.absoluteString)) ?? ""
                let userMsg = promptBuilder.buildUserMessage(
                    content: pageText,
                    contentType: .url(url.absoluteString),
                    additionalText: ""
                )
                messages = [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user",   "content": userMsg],
                ]
            }

            statusMessage = "Connecting to AI…"
            let updateStatus: @Sendable (String) async -> Void = { [weak self] msg in
                await MainActor.run { self?.statusMessage = msg }
            }
            try await llm.waitUntilReady(onProgress: updateStatus)
            statusMessage = "Generating note…"
            let response = try await llm.complete(messages: messages)

            // Parse with one retry on failure
            let result = parser.parse(response: response, listTypes: listTypes)
            switch result {
            case .success(let title, let type, let properties, let tags):
                applyResult(title: title, type: type, properties: properties, tags: tags)
            case .invalid(let reason):
                statusMessage = "Refining response…"
                var retryMsgs = messages
                retryMsgs.append(["role": "assistant", "content": response])
                retryMsgs.append(["role": "user", "content": promptBuilder.buildRetryMessage(reason: reason)])
                let retryResponse = try await llm.complete(messages: retryMsgs)
                switch parser.parse(response: retryResponse, listTypes: listTypes) {
                case .success(let title, let type, let properties, let tags):
                    applyResult(title: title, type: type, properties: properties, tags: tags)
                case .invalid(let reason2):
                    errorMessage = reason2
                    step = .decision
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            step = .decision
        }
    }

    // MARK: - Private helpers

    private func applyResult(title: String, type: String, properties: [String: PropertyValue], tags: [String]) {
        editTitle = title
        editType = type
        editProperties = properties
        editTags = tags.joined(separator: ", ")
        step = .preview
    }

    private func buildImageMessages(
        fileURL: URL,
        settings: LLMSettings,
        systemPrompt: String,
        promptBuilder: PromptBuilder
    ) async throws -> [[String: Any]] {
        if settings.imageProcessingMode == .base64 {
            statusMessage = "Encoding image…"
            let jpegData: Data
            #if os(iOS)
            guard let uiImage = UIImage(contentsOfFile: fileURL.path),
                  let encoded = uiImage.jpegData(compressionQuality: 0.85) else {
                throw LLMError.invalidResponse
            }
            jpegData = encoded
            #else
            guard let data = try? Data(contentsOf: fileURL) else {
                throw LLMError.invalidResponse
            }
            jpegData = data
            #endif
            let base64 = "data:image/jpeg;base64," + jpegData.base64EncodedString()
            let userText = promptBuilder.buildUserMessage(content: "", contentType: .image, additionalText: "")
            return [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": base64]],
                    ["type": "text",      "text": userText],
                ]],
            ]
        } else {
            statusMessage = "Extracting text from image…"
            let ocrText = await extractText(from: fileURL)
            let userMsg = promptBuilder.buildUserMessage(
                content: ocrText, contentType: .image, additionalText: ""
            )
            return [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userMsg],
            ]
        }
    }

    private func extractText(from fileURL: URL) async -> String {
        guard let ciImage = CIImage(contentsOf: fileURL) else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(ciImage: ciImage, options: [:]).perform([request])
        }
    }
}

// MARK: - View

struct ImportView: View {
    let pending: PendingImport
    @Environment(AppState.self) private var appState
    @State private var viewModel: ImportViewModel
    @State private var showManualEntry = false
    @Environment(\.dismiss) private var dismiss

    init(pending: PendingImport) {
        self.pending = pending
        _viewModel = State(initialValue: ImportViewModel(pending: pending))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .decision:   decisionView
                case .processing: processingView
                case .preview:    previewView
                }
            }
            .navigationBarTitleInline()
            .navigationTitle("Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appState.pendingImport = nil
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showManualEntry) {
            CreateItemView()
                .environment(appState)
                .onDisappear { appState.pendingImport = nil }
        }
    }

    // MARK: Decision

    private var decisionView: some View {
        VStack(spacing: 24) {
            contentPreview
                .padding(.top)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.processWithAI(
                            settings: appState.llmSettings,
                            listTypes: appState.listTypes,
                            items: appState.items
                        )
                    }
                } label: {
                    Label("Process with AI", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Button {
                    showManualEntry = true
                } label: {
                    Label("Manual Entry", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch pending {
        case .image(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit().cornerRadius(8)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: 220)
            .padding(.horizontal)

        case .webURL(let url):
            VStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(url.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text(viewModel.statusMessage)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Preview

    private var previewView: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $viewModel.editTitle)
            }
            Section("Tags") {
                TextField("tag1, tag2", text: $viewModel.editTags)
                    .noAutocapitalization()
            }
            if !viewModel.editProperties.isEmpty {
                Section("Details") {
                    ForEach(viewModel.editProperties.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key.capitalized)
                            Spacer()
                            Text(propertyDisplayString(viewModel.editProperties[key]))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await saveNote() }
                }
                .disabled(viewModel.editTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func propertyDisplayString(_ value: PropertyValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .text(let t):   return t
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(n))" : "\(n)"
        case .date(let d):
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            return fmt.string(from: d)
        case .bool(let b):   return b ? "Yes" : "No"
        }
    }

    // MARK: Save

    private func saveNote() async {
        let tags = viewModel.editTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let title = viewModel.editTitle.trimmingCharacters(in: .whitespaces)

        if viewModel.editType == "todo" {
            await appState.createTodo(title: title, tags: tags, properties: viewModel.editProperties)
        } else {
            await appState.createYAMLItem(
                type: viewModel.editType,
                title: title,
                tags: tags,
                properties: viewModel.editProperties
            )
        }

        appState.pendingImport = nil
        dismiss()
    }
}
