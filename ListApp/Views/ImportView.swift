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

    // Refinement UI state
    var refinementText: String = ""
    var isRegenerating: Bool = false

    // Stored conversation state for per-note regeneration
    private var storedSystemPrompt: String = ""
    private var storedUserMessage: String = ""          // Apple Intelligence path
    private var storedMessages: [[String: Any]] = []    // Personal LLM path
    private var storedLastResponse: String = ""
    private var generatedWithOnDevice: Bool = false     // tracks which engine to reuse

    let pending: PendingImport

    init(pending: PendingImport) {
        self.pending = pending
    }

    // MARK: - AI Processing

    func processWithAI(settings: LLMSettings, listTypes: [ListType], items: [Item]) async {
        step = .processing
        errorMessage = nil

        if #available(iOS 26, macOS 26, *), settings.processingMode == .onDevice {
            if AppleIntelligenceService.isAvailable {
                await processWithAppleIntelligence(
                    listTypes: listTypes,
                    items: items,
                    customInstructions: settings.customSystemPromptInstructions
                )
            } else {
                errorMessage = AppleIntelligenceError.unavailable.localizedDescription
                step = .decision
            }
        } else {
            await processWithPersonalLLM(settings: settings, listTypes: listTypes, items: items)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func processWithAppleIntelligence(
        listTypes: [ListType],
        items: [Item],
        customInstructions: String
    ) async {
        let promptBuilder = PromptBuilder()
        let parser = NoteResponseParser()
        let systemPrompt = promptBuilder.buildSystemPrompt(
            listTypes: listTypes,
            sampleNotes: promptBuilder.extractSampleNotes(from: items),
            customInstructions: customInstructions
        )

        do {
            let userMessage: String
            switch pending {
            case .image(let fileURL):
                // Always OCR for on-device — FoundationModels has no vision input
                statusMessage = "Extracting text from image…"
                let ocrText = await extractText(from: fileURL)
                userMessage = promptBuilder.buildUserMessage(
                    content: ocrText, contentType: .image, additionalText: "")
            case .webURL(let url):
                statusMessage = "Fetching page content…"
                let pageText = (try? await WebContentFetcher().fetchText(from: url.absoluteString)) ?? ""
                userMessage = promptBuilder.buildUserMessage(
                    content: pageText, contentType: .url(url.absoluteString), additionalText: "")
            }

            statusMessage = "Generating note…"
            let service = AppleIntelligenceService()
            let response = try await service.complete(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                retryPrompt: { [parser, listTypes] first in
                    if case .invalid(let reason) = parser.parse(response: first, listTypes: listTypes) {
                        return promptBuilder.buildRetryMessage(reason: reason)
                    }
                    return nil
                }
            )

            switch parser.parse(response: response, listTypes: listTypes) {
            case .success(let title, let type, let properties, let tags):
                storedSystemPrompt = systemPrompt
                storedUserMessage = userMessage
                storedLastResponse = response
                generatedWithOnDevice = true
                applyResult(title: title, type: type, properties: properties, tags: tags)
            case .invalid(let reason):
                errorMessage = reason
                step = .decision
            }
        } catch {
            errorMessage = error.localizedDescription
            step = .decision
        }
    }

    private func processWithPersonalLLM(
        settings: LLMSettings, listTypes: [ListType], items: [Item]
    ) async {
        let llm = LLMService(settings: settings)
        let promptBuilder = PromptBuilder()
        let parser = NoteResponseParser()
        let systemPrompt = promptBuilder.buildSystemPrompt(
            listTypes: listTypes,
            sampleNotes: promptBuilder.extractSampleNotes(from: items),
            customInstructions: settings.customSystemPromptInstructions
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
                storedMessages = messages
                storedLastResponse = response
                generatedWithOnDevice = false
                applyResult(title: title, type: type, properties: properties, tags: tags)
            case .invalid(let reason):
                statusMessage = "Refining response…"
                var retryMsgs = messages
                retryMsgs.append(["role": "assistant", "content": response])
                retryMsgs.append(["role": "user", "content": promptBuilder.buildRetryMessage(reason: reason)])
                let retryResponse = try await llm.complete(messages: retryMsgs)
                switch parser.parse(response: retryResponse, listTypes: listTypes) {
                case .success(let title, let type, let properties, let tags):
                    storedMessages = retryMsgs
                    storedLastResponse = retryResponse
                    generatedWithOnDevice = false
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

    // MARK: - Per-note regeneration with feedback

    func regenerate(settings: LLMSettings, listTypes: [ListType]) async {
        let feedback = refinementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty else { return }

        isRegenerating = true
        errorMessage = nil
        defer { isRegenerating = false }

        let parser = NoteResponseParser()

        if #available(iOS 26, macOS 26, *), generatedWithOnDevice {
            // Re-run using the same on-device engine, with prior attempt + feedback in user message
            let enhancedUser = storedUserMessage
                + "\n\nPrevious attempt:\n```yaml\n\(storedLastResponse)\n```"
                + "\n\nPlease revise with this feedback: \(feedback)"
            do {
                let response = try await AppleIntelligenceService().complete(
                    systemPrompt: storedSystemPrompt,
                    userMessage: enhancedUser
                )
                switch parser.parse(response: response, listTypes: listTypes) {
                case .success(let title, let type, let props, let tags):
                    storedLastResponse = response
                    refinementText = ""
                    applyResult(title: title, type: type, properties: props, tags: tags)
                case .invalid(let reason):
                    errorMessage = reason
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            // Personal LLM: true multi-turn — extend the conversation chain
            var msgs = storedMessages
            msgs.append(["role": "assistant", "content": storedLastResponse])
            msgs.append(["role": "user",      "content": feedback])
            let llm = LLMService(settings: settings)
            do {
                let response = try await llm.complete(messages: msgs)
                switch parser.parse(response: response, listTypes: listTypes) {
                case .success(let title, let type, let props, let tags):
                    storedMessages = msgs
                    storedLastResponse = response
                    refinementText = ""
                    applyResult(title: title, type: type, properties: props, tags: tags)
                case .invalid(let reason):
                    errorMessage = reason
                }
            } catch {
                errorMessage = error.localizedDescription
            }
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

    private var previewMatchedListType: ListType? {
        appState.listTypes.first { $0.name.lowercased() == viewModel.editType.lowercased() }
    }

    private var previewOrderedPropertyKeys: [String] {
        let schemaKeys = previewMatchedListType?.fields
            .filter { $0.name.lowercased() != "title" }
            .map { $0.name } ?? []
        let extraKeys = viewModel.editProperties.keys
            .filter { key in !schemaKeys.contains { $0.lowercased() == key.lowercased() } }
            .sorted()
        return schemaKeys + extraKeys
    }

    private var previewView: some View {
        Form {
            Section("Type") {
                Picker("Type", selection: $viewModel.editType) {
                    ForEach(appState.listTypes.map { $0.name }, id: \.self) { name in
                        Text(name.capitalized).tag(name.lowercased())
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Title") {
                TextField("Title", text: $viewModel.editTitle)
            }

            Section("Tags") {
                TextField("tag1, tag2", text: $viewModel.editTags)
                    .noAutocapitalization()
            }

            if !viewModel.editProperties.isEmpty {
                Section("Details") {
                    ForEach(previewOrderedPropertyKeys, id: \.self) { key in
                        propertyEditRow(key: key)
                    }
                }
            }

            if let regenerateError = viewModel.errorMessage {
                Section {
                    Text(regenerateError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            Section {
                TextField(
                    "e.g. \"This is actually a movie\"",
                    text: $viewModel.refinementText,
                    axis: .vertical
                )
                .lineLimit(3...)
                Button {
                    Task {
                        await viewModel.regenerate(
                            settings: appState.llmSettings,
                            listTypes: appState.listTypes
                        )
                    }
                } label: {
                    if viewModel.isRegenerating {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Regenerate", systemImage: "arrow.clockwise.sparkles")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.refinementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isRegenerating
                )
            } header: {
                Text("Refine")
            } footer: {
                Text("Optional: describe what to change and regenerate the note.")
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

    @ViewBuilder
    private func propertyEditRow(key: String) -> some View {
        let label = key.replacingOccurrences(of: "_", with: " ").capitalized
        switch viewModel.editProperties[key] {
        case .text:
            if key.lowercased() == "priority" {
                Picker(label, selection: Binding<String>(
                    get: { if case .text(let t) = viewModel.editProperties[key] { return t }; return "" },
                    set: { viewModel.editProperties[key] = .text($0) }
                )) {
                    Text("None").tag("")
                    Text("🔴 High").tag("high")
                    Text("🟠 Medium").tag("medium")
                    Text("🔵 Low").tag("low")
                }
                .pickerStyle(.menu)
            } else {
                HStack {
                    Text(label)
                    Spacer()
                    TextField("Optional", text: Binding<String>(
                        get: { if case .text(let t) = viewModel.editProperties[key] { return t }; return "" },
                        set: { viewModel.editProperties[key] = .text($0) }
                    ))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                }
            }
        case .number:
            HStack {
                Text(label)
                Spacer()
                TextField("Optional", text: Binding<String>(
                    get: {
                        if case .number(let n) = viewModel.editProperties[key] {
                            return n.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(n))" : "\(n)"
                        }
                        return ""
                    },
                    set: { if let d = Double($0) { viewModel.editProperties[key] = .number(d) } }
                ))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            }
        case .date:
            DatePicker(label, selection: Binding<Date>(
                get: { if case .date(let d) = viewModel.editProperties[key] { return d }; return Date() },
                set: { viewModel.editProperties[key] = .date($0) }
            ), displayedComponents: .date)
        case .bool:
            Toggle(label, isOn: Binding<Bool>(
                get: { if case .bool(let b) = viewModel.editProperties[key] { return b }; return false },
                set: { viewModel.editProperties[key] = .bool($0) }
            ))
        case .none:
            EmptyView()
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
