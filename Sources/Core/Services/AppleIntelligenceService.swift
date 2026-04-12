import Foundation
import FoundationModels

// MARK: - Error

public enum AppleIntelligenceError: LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "Apple Intelligence is not available on this device. " +
        "Enable it in Settings → Apple Intelligence & Siri, or switch to Personal LLM in AI settings."
    }
}

// MARK: - Service

/// Handles on-device AI note generation using Apple Intelligence (iOS 26+).
@available(iOS 26.0, macOS 26.0, *)
public actor AppleIntelligenceService {

    /// Whether Apple Intelligence is enabled and available on this device.
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public init() {}

    /// Generate a model response for the given system prompt and user message.
    ///
    /// If `retryPrompt` is provided, it is called with the first response. When
    /// it returns a non-nil string that string is sent as a second turn on the
    /// **same** session — which retains conversation history — and the retry
    /// response is returned instead. Pass `nil` to skip the retry path entirely.
    public func complete(
        systemPrompt: String,
        userMessage: String,
        retryPrompt: (@Sendable (String) -> String?)? = nil
    ) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)
        let first = try await session.respond(to: userMessage)
        let firstContent = first.content
        if let retryMessage = retryPrompt?(firstContent) {
            let retry = try await session.respond(to: retryMessage)
            return retry.content
        }
        return firstContent
    }
}
