import SwiftUI
import Core
import Vision

// MARK: - ViewModel

@Observable
@MainActor
final class ImportViewModel {
    enum Step { case processing, preview }

    var step: Step = .processing
    var statusMessage = "Analysing content…"
    var errorMessage: String? = nil

    // Generated notes shown in the preview step
    var notes: [NoteEdit] = []

    // ask_user tool: non-nil while waiting for the user to answer
    var pendingQuestion: String? = nil
    var questionAnswer: String = ""
    private var questionContinuation: CheckedContinuation<String, Never>? = nil

    // Refinement (regenerate the whole batch with feedback)
    var refinementText: String = ""
    var isRegenerating: Bool = false

    // Stored conversation for regeneration
    private var storedSystemPrompt: String = ""
    private var storedMessages: [[String: Any]] = []
    private var storedLastResponse: String = ""
    private var generatedWithOnDevice: Bool = false

    let pending: PendingImport

    init(pending: PendingImport) {
        self.pending = pending
    }

    // MARK: - Entry point

    func processWithAI(settings: LLMSettings, listTypes: [ListType], items: [Item]) async {
        step = .processing
        errorMessage = nil

        if #available(iOS 26, macOS 26, *), settings.processingMode == .onDevice {
            if AppleIntelligenceService.isAvailable {
                await processWithAppleIntelligence(
                    listTypes: listTypes, items: items,
                    customInstructions: settings.customSystemPromptInstructions
                )
            } else {
                errorMessage = AppleIntelligenceError.unavailable.localizedDescription
            }
        } else {
            await processWithPersonalLLM(settings: settings, listTypes: listTypes, items: items)
        }
    }

    // MARK: - Apple Intelligence

    @available(iOS 26.0, macOS 26.0, *)
    private func processWithAppleIntelligence(
        listTypes: [ListType], items: [Item], customInstructions: String
    ) async {
        let promptBuilder = PromptBuilder()
        let parser = NoteResponseParser()
        let systemPrompt = promptBuilder.buildSystemPrompt(
            listTypes: listTypes,
            sampleNotes: promptBuilder.extractSampleNotes(from: items),
            customInstructions: customInstructions
        )
        storedSystemPrompt = systemPrompt

        do {
            // Pass URLs as-is; the web_fetch tool fetches them on demand.
            let userMessage = try await buildTextUserMessage(promptBuilder: promptBuilder, fetchURLs: false)
            let service = AppleIntelligenceService()
            let response = try await service.complete(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                onAsk: { [weak self] question in
                    await self?.waitForAnswer(question: question) ?? "[cancelled]"
                },
                retryPrompt: { [parser, listTypes] first in
                    parser.parseAll(response: first, listTypes: listTypes).isEmpty
                        ? promptBuilder.buildRetryMessage(reason: "No valid ```yaml blocks found.")
                        : nil
                }
            )
            storedLastResponse = response
            storedMessages = [["role": "user", "content": userMessage]]
            applyResponse(response, parser: parser, listTypes: listTypes)
            generatedWithOnDevice = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Personal LLM (tool calling loop)

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
        storedSystemPrompt = systemPrompt

        do {
            statusMessage = "Connecting to AI…"
            let updateStatus: @Sendable (String) async -> Void = { [weak self] msg in
                await MainActor.run { self?.statusMessage = msg }
            }
            try await llm.waitUntilReady(onProgress: updateStatus)

            var messages = try await buildLLMMessages(
                settings: settings, promptBuilder: promptBuilder, systemPrompt: systemPrompt
            )
            let tools = promptBuilder.buildTools()
            storedMessages = messages

            statusMessage = "Generating notes…"
            var iterations = 0
            while iterations < 10 {
                iterations += 1
                let result = try await llm.completeStep(messages: messages, tools: tools)

                switch result {
                case .content(let text):
                    storedMessages = messages
                    storedLastResponse = text
                    generatedWithOnDevice = false
                    applyResponse(text, parser: parser, listTypes: listTypes)
                    return

                case .toolCalls(let assistantTurn, let calls):
                    messages.append(assistantTurn)
                    for call in calls {
                        let output = await executeToolCall(call)
                        messages.append(promptBuilder.buildToolResult(callID: call.id, content: output))
                    }
                }
            }
            // Exhausted iterations — try plain completion with what we have
            let fallback = try await llm.complete(messages: messages)
            storedMessages = messages
            storedLastResponse = fallback
            generatedWithOnDevice = false
            applyResponse(fallback, parser: parser, listTypes: listTypes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Tool execution

    private func validatedWebFetchURL(from candidate: String) -> URL? {
        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let host = components.host?.lowercased(), !host.isEmpty,
            !["localhost", "127.0.0.1", "::1"].contains(host)
        else { return nil }
        return components.url
    }

    private func executeToolCall(_ call: LLMToolCall) async -> String {
        switch call.name {
        case "web_fetch":
            let raw = call.arguments["url"] as? String ?? ""
            guard let validatedURL = validatedWebFetchURL(from: raw) else {
                return "Could not fetch: only http/https URLs with a public host are supported."
            }
            statusMessage = "Fetching \(validatedURL.host ?? validatedURL.absoluteString)…"
            return (try? await WebContentFetcher().fetchText(from: validatedURL.absoluteString))
                ?? "Could not fetch content from \(validatedURL.absoluteString)."

        case "ask_user":
            let question = call.arguments["question"] as? String ?? "Please provide more information."
            statusMessage = "Waiting for your input…"
            return await waitForAnswer(question: question)

        default:
            return "Unknown tool: \(call.name)"
        }
    }

    // MARK: - ask_user pause/resume

    private func waitForAnswer(question: String) async -> String {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingQuestion = question
                questionContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.questionContinuation?.resume(returning: "[cancelled]")
                self.questionContinuation = nil
                self.pendingQuestion = nil
            }
        }
    }

    func submitAnswer() {
        guard !questionAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let answer = questionAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        questionContinuation?.resume(returning: answer)
        questionContinuation = nil
        pendingQuestion = nil
        questionAnswer = ""
    }

    func cancelAnswer() {
        questionContinuation?.resume(returning: "[User declined to answer]")
        questionContinuation = nil
        pendingQuestion = nil
        questionAnswer = ""
    }

    // MARK: - Regeneration with feedback

    func regenerate(settings: LLMSettings, listTypes: [ListType]) async {
        let feedback = refinementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty else { return }

        isRegenerating = true
        errorMessage = nil
        defer { isRegenerating = false }

        let parser = NoteResponseParser()
        let promptBuilder = PromptBuilder()

        if #available(iOS 26, macOS 26, *), generatedWithOnDevice {
            let enhanced = (storedMessages.last?["content"] as? String ?? "")
                + "\n\nPrevious result:\n```yaml\n\(storedLastResponse)\n```"
                + "\n\nPlease revise with this feedback: \(feedback)"
            do {
                let response = try await AppleIntelligenceService().complete(
                    systemPrompt: storedSystemPrompt,
                    userMessage: enhanced,
                    onAsk: { [weak self] question in
                        await self?.waitForAnswer(question: question) ?? "[cancelled]"
                    }
                )
                applyResponse(response, parser: parser, listTypes: listTypes)
                refinementText = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            var msgs = storedMessages
            msgs.append(["role": "assistant", "content": storedLastResponse])
            msgs.append(["role": "user", "content": feedback])
            let llm = LLMService(settings: settings)
            do {
                // Plain completion for refinement — content is already in context,
                // no need for a tool loop.
                let text = try await llm.complete(messages: msgs)
                storedMessages = msgs
                storedLastResponse = text
                applyResponse(text, parser: parser, listTypes: listTypes)
                refinementText = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func applyResponse(_ response: String, parser: NoteResponseParser, listTypes: [ListType]) {
        let parsed = parser.parseAll(response: response, listTypes: listTypes)
        if parsed.isEmpty {
            errorMessage = "No valid notes found in the AI response. Try refining or regenerating."
        } else {
            notes = parsed
            step = .preview
        }
    }

    /// Build a plain-text user message with all inputs pre-processed (for Apple Intelligence).
    /// When fetchURLs is true, URLs are fetched upfront.
    func buildTextUserMessage(promptBuilder: PromptBuilder, fetchURLs: Bool) async throws -> String {
        var parts: [String] = ["Please create one or more notes from the following content."]

        for (i, imageURL) in pending.imageURLs.enumerated() {
            statusMessage = "Extracting text from image\(pending.imageURLs.count > 1 ? " \(i + 1)" : "")…"
            let text = await extractText(from: imageURL)
            if !text.isEmpty {
                parts.append("--- Image \(i + 1) ---\n\(text)")
            }
        }

        for webURL in pending.webURLs {
            if fetchURLs {
                statusMessage = "Fetching \(webURL.host ?? webURL.absoluteString)…"
                let text = (try? await WebContentFetcher().fetchText(from: webURL.absoluteString)) ?? ""
                if !text.isEmpty {
                    parts.append("--- Page: \(webURL.absoluteString) ---\n\(text)")
                } else {
                    parts.append("--- URL ---\n\(webURL.absoluteString)")
                }
            } else {
                parts.append("--- URL ---\n\(webURL.absoluteString)")
            }
        }

        for text in pending.texts {
            parts.append("--- Text ---\n\(text)")
        }

        return parts.joined(separator: "\n\n")
    }

    /// Build the messages array for the personal LLM, handling base64 images vs OCR.
    private func buildLLMMessages(
        settings: LLMSettings,
        promptBuilder: PromptBuilder,
        systemPrompt: String
    ) async throws -> [[String: Any]] {
        var contentBlocks: [[String: Any]] = []
        var textParts: [String] = ["Please create one or more notes from the following content."]

        for (i, imageURL) in pending.imageURLs.enumerated() {
            if settings.imageProcessingMode == .base64 {
                statusMessage = "Encoding image\(pending.imageURLs.count > 1 ? " \(i + 1)" : "")…"
                if let base64 = encodeImageBase64(at: imageURL) {
                    contentBlocks.append([
                        "type": "image_url",
                        "image_url": ["url": base64],
                    ])
                }
            } else {
                statusMessage = "Extracting text from image\(pending.imageURLs.count > 1 ? " \(i + 1)" : "")…"
                let text = await extractText(from: imageURL)
                if !text.isEmpty {
                    textParts.append("--- Image \(i + 1) ---\n\(text)")
                }
            }
        }

        // Include URLs as text in the message — the AI can call web_fetch for details
        for webURL in pending.webURLs {
            textParts.append("--- URL ---\n\(webURL.absoluteString)")
        }

        for text in pending.texts {
            textParts.append("--- Text ---\n\(text)")
        }

        let textBlock: [String: Any] = ["type": "text", "text": textParts.joined(separator: "\n\n")]

        let userContent: Any = contentBlocks.isEmpty
            ? textParts.joined(separator: "\n\n")
            : contentBlocks + [textBlock]

        return [
            ["role": "system", "content": systemPrompt],
            ["role": "user",   "content": userContent],
        ]
    }

    private func encodeImageBase64(at fileURL: URL) -> String? {
        #if os(iOS)
        guard let uiImage = UIImage(contentsOfFile: fileURL.path),
              let data = uiImage.jpegData(compressionQuality: 0.85) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
        #else
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
        #endif
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
    @Environment(\.dismiss) private var dismiss

    init(pending: PendingImport) {
        self.pending = pending
        _viewModel = State(initialValue: ImportViewModel(pending: pending))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .processing: processingView
                case .preview:    previewView
                }
            }
            .navigationBarTitleInline()
            .navigationTitle("Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelAnswer()
                        appState.pendingImport = nil
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.processWithAI(
                settings: appState.llmSettings,
                listTypes: appState.listTypes,
                items: appState.items
            )
        }
        .sheet(isPresented: Binding(
            get: { viewModel.pendingQuestion != nil },
            set: { if !$0 { viewModel.cancelAnswer() } }
        )) {
            askUserSheet
        }
    }

    // MARK: Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text(viewModel.statusMessage)
                .foregroundStyle(.secondary)
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Retry") {
                    Task {
                        await viewModel.processWithAI(
                            settings: appState.llmSettings,
                            listTypes: appState.listTypes,
                            items: appState.items
                        )
                    }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: ask_user sheet

    private var askUserSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text(viewModel.pendingQuestion ?? "")
                        .font(.body)
                } header: {
                    Text("AI needs your input")
                }
                Section {
                    TextField("Your answer…", text: $viewModel.questionAnswer, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle("Question")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { viewModel.cancelAnswer() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { viewModel.submitAnswer() }
                        .fontWeight(.semibold)
                        .disabled(viewModel.questionAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Preview

    private var includedCount: Int { viewModel.notes.filter(\.isIncluded).count }
    private var canSave: Bool {
        viewModel.notes.contains { $0.isIncluded && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var previewView: some View {
        List {
            ForEach($viewModel.notes) { $note in
                NoteCardSection(note: $note, listTypes: appState.listTypes)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }

            Section {
                TextField(
                    "e.g. \"These are restaurants, not cafés\"",
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
                        Label("Regenerate All", systemImage: "arrow.clockwise.sparkles")
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
                Text("Describe what to change and regenerate all notes.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save \(includedCount == 1 ? "1 Note" : "\(includedCount) Notes")") {
                    Task { await saveNotes() }
                }
                .disabled(!canSave)
            }
        }
    }

    // MARK: Save

    private func saveNotes() async {
        for note in viewModel.notes where note.isIncluded {
            let tags = note.tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let title = note.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }

            if note.type == "todo" {
                await appState.createTodo(title: title, tags: tags, properties: note.properties)
            } else {
                await appState.createYAMLItem(
                    type: note.type, title: title, tags: tags, properties: note.properties
                )
            }
        }
        appState.pendingImport = nil
        dismiss()
    }
}

// MARK: - Note Card Section

private struct NoteCardSection: View {
    @Binding var note: NoteEdit
    let listTypes: [ListType]

    private var matchedListType: ListType? {
        listTypes.first { $0.name.lowercased() == note.type.lowercased() }
    }

    private var orderedPropertyKeys: [String] {
        let schemaKeys = matchedListType?.fields
            .filter { $0.name.lowercased() != "title" }
            .map { $0.name } ?? []
        let extraKeys = note.properties.keys
            .filter { key in !schemaKeys.contains { $0.lowercased() == key.lowercased() } }
            .sorted()
        return schemaKeys.filter { note.properties[$0] != nil } + extraKeys
    }

    var body: some View {
        Section {
            // Include toggle
            Toggle(isOn: $note.isIncluded) {
                Text(note.isIncluded ? "Include" : "Skip")
                    .foregroundStyle(note.isIncluded ? .primary : .secondary)
            }
            .tint(.accentColor)

            // Type picker
            Picker("Type", selection: $note.type) {
                ForEach(listTypes.map { $0.name }, id: \.self) { name in
                    Text(name.capitalized).tag(name.lowercased())
                }
            }
            .pickerStyle(.menu)

            // Title
            TextField("Title", text: $note.title)
                .fontWeight(.semibold)

            // Tags
            TextField("tag1, tag2", text: $note.tags)
                .noAutocapitalization()
                .foregroundStyle(.secondary)
                .font(.subheadline)
        } header: {
            Text(note.type.capitalized)
        }

        if !orderedPropertyKeys.isEmpty {
            Section {
                ForEach(orderedPropertyKeys, id: \.self) { key in
                    propertyRow(key: key)
                }
            }
        }
    }

    @ViewBuilder
    private func propertyRow(key: String) -> some View {
        let label = key.replacingOccurrences(of: "_", with: " ").capitalized
        switch note.properties[key] {
        case .text:
            if key.lowercased() == "priority" {
                Picker(label, selection: Binding<String>(
                    get: { if case .text(let t) = note.properties[key] { return t }; return "" },
                    set: { note.properties[key] = .text($0) }
                )) {
                    Text("None").tag("")
                    Text("🔴 High").tag("high")
                    Text("🟠 Medium").tag("medium")
                    Text("🔵 Low").tag("low")
                }.pickerStyle(.menu)
            } else {
                HStack {
                    Text(label)
                    Spacer()
                    TextField("Optional", text: Binding<String>(
                        get: { if case .text(let t) = note.properties[key] { return t }; return "" },
                        set: { note.properties[key] = .text($0) }
                    ))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                }
            }
        case .number:
            NumberFieldRow(label: label, key: key, properties: $note.properties)
        case .date:
            DatePicker(label, selection: Binding<Date>(
                get: { if case .date(let d) = note.properties[key] { return d }; return Date() },
                set: { note.properties[key] = .date($0) }
            ), displayedComponents: .date)
        case .bool:
            Toggle(label, isOn: Binding<Bool>(
                get: { if case .bool(let b) = note.properties[key] { return b }; return false },
                set: { note.properties[key] = .bool($0) }
            ))
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Number Field Row

private struct NumberFieldRow: View {
    let label: String
    let key: String
    @Binding var properties: [String: PropertyValue]

    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("Optional", text: $text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
        .onAppear {
            if case .number(let n) = properties[key] {
                text = n.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(n))" : "\(n)"
            }
        }
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty {
                properties.removeValue(forKey: key)
            } else if let d = Double(newValue) {
                properties[key] = .number(d)
            }
        }
    }
}
