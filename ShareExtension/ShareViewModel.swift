import Foundation
import SwiftUI
import Core
import Vision
import UniformTypeIdentifiers

// MARK: - Step state machine

enum ShareStep {
    case loadingContent          // Extracting URL/image from extension context
    case decision                // "Use AI?" prompt
    case aiProcessing            // Health check + LLM call
    case preview                 // Editable note preview
    case manualForm              // Manual type + field form
    case saving
    case done
    case error(String)           // Fatal error with a message
}

// MARK: - Draft helpers

/// A mutable note draft that the user can edit in NotePreviewView.
struct NoteDraft {
    var title: String
    var type: String
    var properties: [String: String]  // String-keyed for editing; converted on save
    var tagsString: String            // Comma-separated for UI
}

// MARK: - ViewModel

@Observable
@MainActor
final class ShareViewModel {

    // MARK: State
    var step: ShareStep = .loadingContent
    var processingStatus: String = "Loading…"
    var alertTitle: String = ""
    var alertMessage: String = ""
    var showAlert: Bool = false

    // Shared content
    var sharedURL: String?
    var sharedImages: [UIImage] = []

    // AI decision
    var additionalText: String = ""

    // Editable draft (populated after LLM response)
    var draft: NoteDraft = NoteDraft(title: "", type: "", properties: [:], tagsString: "")

    // Manual form
    var manualSelectedType: ListType = MockData.listTypes[0]
    var manualFieldValues: [String: String] = [:]
    var manualTagsString: String = ""

    // Populated from vault or fallback to MockData
    private(set) var listTypes: [ListType] = MockData.listTypes

    // MARK: Private
    private let extensionContext: NSExtensionContext
    private let settings: LLMSettings
    private let promptBuilder = PromptBuilder()
    private let responseParser = NoteResponseParser()
    private var llmConversation: [[String: Any]] = []   // Full conversation for retry

    init(extensionContext: NSExtensionContext) {
        self.extensionContext = extensionContext
        self.settings = LLMSettings.load()
        Task { await extractSharedContent() }
    }

    // MARK: - Content extraction

    private func extractSharedContent() async {
        step = .loadingContent
        processingStatus = "Reading shared content…"

        for item in extensionContext.inputItems as? [NSExtensionItem] ?? [] {
            for provider in item.attachments ?? [] {
                // URL
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider) {
                        sharedURL = url.absoluteString
                        step = .decision
                        return
                    }
                }
                // Plain-text URL fallback
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadPlainText(from: provider),
                       let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                       url.scheme?.hasPrefix("http") == true {
                        sharedURL = url.absoluteString
                        step = .decision
                        return
                    }
                }
                // Image
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let image = await loadImage(from: provider) {
                        sharedImages = [image]
                        step = .decision
                        return
                    }
                }
            }
        }

        step = .error("Could not read the shared content. Only URLs and images are supported.")
    }

    // MARK: - AI path

    func startAIGeneration() async {
        step = .aiProcessing
        processingStatus = "Preparing…"

        // 1. Load sample notes from vault for context
        let sampleNotes = promptBuilder.extractSampleNotes(from: loadVaultItems())
        let systemPrompt = promptBuilder.buildSystemPrompt(
            listTypes: listTypes,
            sampleNotes: sampleNotes
        )

        // 2. Build messages based on content type
        if let urlString = sharedURL {
            let pageText: String
            do {
                processingStatus = "Fetching page content…"
                pageText = try await WebContentFetcher().fetchText(from: urlString)
            } catch {
                pageText = ""
            }
            let userMessage = promptBuilder.buildUserMessage(
                content: pageText,
                contentType: .url(urlString),
                additionalText: additionalText
            )
            llmConversation = [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userMessage],
            ]
        } else if let image = sharedImages.first {
            if settings.imageProcessingMode == .base64 {
                processingStatus = "Preparing image…"
                let userContent = buildImageMessageParts(image)
                llmConversation = [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user",   "content": userContent],
                ]
            } else {
                processingStatus = "Reading image text…"
                let ocrText = await extractText(from: image)
                let userMessage = promptBuilder.buildUserMessage(
                    content: ocrText,
                    contentType: .image,
                    additionalText: additionalText
                )
                llmConversation = [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user",   "content": userMessage],
                ]
            }
        } else {
            step = .error("No shared content available.")
            return
        }

        // 4. Warm up server if needed
        if settings.processingMode == .personalLLM {
            do {
                try await LLMService(settings: settings).waitUntilReady { [weak self] status in
                    await MainActor.run { self?.processingStatus = status }
                }
            } catch {
                handleError(error)
                return
            }
        }

        // 5. Call LLM
        await callLLMWithRetry()
    }

    private func callLLMWithRetry() async {
        processingStatus = "Generating note…"
        let service = LLMService(settings: settings)

        // First attempt
        let firstResponse: String
        do {
            firstResponse = try await service.complete(messages: llmConversation)
        } catch {
            handleError(error)
            return
        }

        llmConversation.append(["role": "assistant", "content": firstResponse])

        switch responseParser.parse(response: firstResponse, listTypes: listTypes) {
        case .success(let title, let type, let props, let tags):
            applyDraft(title: title, type: type, properties: props, tags: tags)
        case .invalid(let reason):
            // One automatic retry
            processingStatus = "Adjusting response…"
            let retryMsg = promptBuilder.buildRetryMessage(reason: reason)
            llmConversation.append(["role": "user", "content": retryMsg])

            let secondResponse: String
            do {
                secondResponse = try await service.complete(messages: llmConversation)
            } catch {
                handleError(error)
                return
            }

            switch responseParser.parse(response: secondResponse, listTypes: listTypes) {
            case .success(let title, let type, let props, let tags):
                applyDraft(title: title, type: type, properties: props, tags: tags)
            case .invalid:
                // Fallback to manual with raw text in a note
                showAlertAndFallback(
                    title: "AI Could Not Create a Note",
                    message: "The AI response was not in the expected format. Switched to manual entry."
                )
            }
        }
    }

    private func applyDraft(title: String, type: String, properties: [String: PropertyValue], tags: [String]) {
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]

        var stringProps: [String: String] = [:]
        for (key, value) in properties {
            switch value {
            case .text(let t):   stringProps[key] = t
            case .number(let n): stringProps[key] = n.truncatingRemainder(dividingBy: 1) == 0
                                     ? "\(Int(n))" : "\(n)"
            case .date(let d):   stringProps[key] = isoFmt.string(from: d)
            case .bool(let b):   stringProps[key] = b ? "true" : "false"
            }
        }

        draft = NoteDraft(
            title: title,
            type: type,
            properties: stringProps,
            tagsString: tags.joined(separator: ", ")
        )
        step = .preview
    }

    // MARK: - Manual path

    func useManualEntry() {
        manualSelectedType = listTypes.first ?? MockData.listTypes[0]
        manualFieldValues = [:]
        manualTagsString = ""
        step = .manualForm
    }

    // MARK: - Saving

    func savePreview() async {
        step = .saving
        let tags = parseTags(draft.tagsString)
        let properties = buildProperties(from: draft.properties, listType: listTypes.first { $0.name.lowercased() == draft.type })

        do {
            try saveToVault(type: draft.type, title: draft.title, properties: properties, tags: tags)
            step = .done
        } catch {
            handleError(error)
        }
    }

    func saveManual() async {
        step = .saving
        let tags = parseTags(manualTagsString)

        var type = manualSelectedType.name.lowercased()
        var title = manualFieldValues["title"] ?? "Untitled"

        // For todo, use the "title" field value
        if type == "todo" {
            title = manualFieldValues["title"] ?? "Untitled"
        }

        var properties = buildProperties(from: manualFieldValues, listType: manualSelectedType)
        properties.removeValue(forKey: "title")

        do {
            try saveToVault(type: type, title: title, properties: properties, tags: tags)
            step = .done
        } catch {
            handleError(error)
        }
    }

    func dismiss() {
        extensionContext.completeRequest(returningItems: nil)
    }

    func dismissWithDone() {
        extensionContext.completeRequest(returningItems: nil)
    }

    // MARK: - Vault I/O

    private func saveToVault(
        type: String,
        title: String,
        properties: [String: PropertyValue],
        tags: [String]
    ) throws {
        guard let vaultURL = resolveVaultURL() else {
            throw ShareVaultError.notConfigured
        }

        let coreFS = DefaultFileSystemManager()

        if type == "todo" {
            // Append to Inbox.md
            let inboxPath = vaultURL.appendingPathComponent("Inbox.md").path
            var line = "- [ ] \(title)"
            for tag in tags { line += " #\(tag)" }

            let existing: String
            if case .success(let c) = coreFS.readFile(at: inboxPath) { existing = c }
            else { existing = "# Inbox\n" }

            let newContent = existing.hasSuffix("\n") ? existing + line + "\n" : existing + "\n" + line + "\n"
            guard case .success = coreFS.writeFile(at: inboxPath, content: newContent) else {
                throw ShareVaultError.writeFailed
            }
        } else {
            // Write YAML frontmatter file
            let folderName = type.capitalized + "s"
            let folderURL  = vaultURL.appendingPathComponent(folderName)
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let safeName = title
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespaces)
            let filePath = folderURL.appendingPathComponent("\(safeName).md").path

            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withFullDate]

            var lines = ["---", "type: \(type)", "title: \(title)"]
            if !tags.isEmpty {
                lines.append("tags: [\(tags.map { "\"\($0)\"" }.joined(separator: ", "))]")
            }
            for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
                switch value {
                case .text(let t):   lines.append("\(key): \(t)")
                case .number(let n): lines.append(n.truncatingRemainder(dividingBy: 1) == 0
                                         ? "\(key): \(Int(n))" : "\(key): \(n)")
                case .date(let d):   lines.append("\(key): \(isoFmt.string(from: d))")
                case .bool(let b):   lines.append("\(key): \(b)")
                }
            }
            lines += ["---", ""]
            guard case .success = coreFS.writeFile(at: filePath, content: lines.joined(separator: "\n")) else {
                throw ShareVaultError.writeFailed
            }
        }
    }

    // MARK: - Vault URL resolution

    private func resolveVaultURL() -> URL? {
        let defaults = UserDefaults(suiteName: LLMSettings.appGroupID)

        // Try security-scoped bookmark (iCloud Drive / external folder)
        if let bookmarkData = defaults?.data(forKey: LLMSettings.vaultBookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }

        // Fallback to Documents/ListAppVault
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let vault = docs.appendingPathComponent("ListAppVault")
        if FileManager.default.fileExists(atPath: vault.path) {
            return vault
        }
        return nil
    }

    private func loadVaultItems() -> [Item] {
        guard let vaultURL = resolveVaultURL() else { return [] }
        let coreFS = DefaultFileSystemManager()
        let parser = ObsidianTodoParser()

        guard case .success(let paths) = coreFS.scanDirectory(at: vaultURL.path, recursive: true)
        else { return [] }

        return paths.prefix(20).flatMap { path in
            guard case .success(let content) = coreFS.readFile(at: path) else { return [Item]() }
            return parser.parseTodos(from: content, sourceFile: path)
        }
    }

    // MARK: - Image processing

    /// On-device OCR via Vision framework — returns extracted text.
    private func extractText(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
        }
    }

    /// Encodes a UIImage as a base64 JPEG data URI and returns the
    /// OpenAI-compatible multimodal content array for the user message.
    private func buildImageMessageParts(_ image: UIImage) -> [[String: Any]] {
        var parts: [[String: Any]] = []

        if let data = image.jpegData(compressionQuality: 0.85) {
            let base64 = data.base64EncodedString()
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ])
        }

        var text = "Please create an appropriate note from this image."
        let trimmed = additionalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            text += "\n\nMy additional context: \(trimmed)"
        }
        parts.append(["type": "text", "text": text])

        return parts
    }

    // MARK: - NSItemProvider helpers

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                cont.resume(returning: item as? URL)
            }
        }
    }

    private func loadPlainText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                if let data = item as? Data {
                    cont.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    cont.resume(returning: item as? String)
                }
            }
        }
    }

    private func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                if let image = item as? UIImage {
                    cont.resume(returning: image)
                } else if let data = item as? Data {
                    cont.resume(returning: UIImage(data: data))
                } else if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    cont.resume(returning: UIImage(data: data))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Utilities

    private func parseTags(_ string: String) -> [String] {
        string.components(separatedBy: ",")
              .map { $0.trimmingCharacters(in: .whitespaces) }
              .filter { !$0.isEmpty }
    }

    private func buildProperties(
        from stringValues: [String: String],
        listType: ListType?
    ) -> [String: PropertyValue] {
        guard let listType else {
            return stringValues.compactMapValues { .text($0) }
        }
        var out: [String: PropertyValue] = [:]
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]

        for field in listType.fields {
            guard let raw = stringValues[field.name], !raw.isEmpty else { continue }
            switch field.type {
            case .text:
                out[field.name] = .text(raw)
            case .number:
                if let n = Double(raw) { out[field.name] = .number(n) }
                else { out[field.name] = .text(raw) }
            case .date:
                if let d = isoFmt.date(from: raw) { out[field.name] = .date(d) }
                else { out[field.name] = .text(raw) }
            }
        }
        return out
    }

    private func handleError(_ error: Error) {
        let msg = error.localizedDescription
        alertTitle   = "Error"
        alertMessage = msg
        showAlert    = true
        // Recover to decision step so user can still try manual entry
        step = .decision
    }

    private func showAlertAndFallback(title: String, message: String) {
        alertTitle   = title
        alertMessage = message
        showAlert    = true
        useManualEntry()
    }
}

// MARK: - Internal errors

enum ShareVaultError: LocalizedError {
    case notConfigured
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No vault is configured. Please open the Lyst app and select a vault folder first."
        case .writeFailed:
            return "Could not write to the vault. Check that the app has permission to access the folder."
        }
    }
}
