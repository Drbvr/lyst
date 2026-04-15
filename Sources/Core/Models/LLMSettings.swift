import Foundation

/// Where AI note processing happens.
public enum ProcessingMode: String, Codable, CaseIterable {
    case onDevice   = "onDevice"
    case personalLLM = "personalLLM"

    public var displayName: String {
        switch self {
        case .onDevice:    return "On-Device (Apple Intelligence)"
        case .personalLLM: return "Personal LLM"
        }
    }
}

/// How shared images are processed before being sent to the LLM.
public enum ImageProcessingMode: String, Codable, CaseIterable {
    case base64 = "base64"
    case ocr    = "ocr"

    public var displayName: String {
        switch self {
        case .base64: return "Send image directly (vision)"
        case .ocr:    return "Extract text first (OCR)"
        }
    }
}

/// Persisted LLM configuration shared between the main app and the share extension
/// via the App Group UserDefaults suite.
public struct LLMSettings: Codable {
    public static let appGroupID      = "group.com.bvanriessen.listapp"
    public static let userDefaultsKey = "llmSettings"
    public static let vaultBookmarkKey = "sharedVaultBookmark"

    public var processingMode: ProcessingMode
    public var imageProcessingMode: ImageProcessingMode
    public var baseURL: String
    public var model: String
    public var useThinking: Bool
    public var apiKey: String
    public var customSystemPromptInstructions: String
    public var developerMode: Bool

    public init(
        processingMode: ProcessingMode = .onDevice,
        imageProcessingMode: ImageProcessingMode = .base64,
        baseURL: String = "",
        model: String = "",
        useThinking: Bool = false,
        apiKey: String = "",
        customSystemPromptInstructions: String = "",
        developerMode: Bool = false
    ) {
        self.processingMode                   = processingMode
        self.imageProcessingMode              = imageProcessingMode
        self.baseURL                          = baseURL
        self.model                            = model
        self.useThinking                      = useThinking
        self.apiKey                           = apiKey
        self.customSystemPromptInstructions   = customSystemPromptInstructions
        self.developerMode                    = developerMode
    }

    /// Custom decoder so that existing stored JSON (without customSystemPromptInstructions
    /// or developerMode) continues to decode successfully — fields default when absent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        processingMode                 = try c.decode(ProcessingMode.self,     forKey: .processingMode)
        imageProcessingMode            = try c.decode(ImageProcessingMode.self, forKey: .imageProcessingMode)
        baseURL                        = try c.decode(String.self,             forKey: .baseURL)
        model                          = try c.decode(String.self,             forKey: .model)
        useThinking                    = try c.decode(Bool.self,               forKey: .useThinking)
        apiKey                         = try c.decode(String.self,             forKey: .apiKey)
        customSystemPromptInstructions = try c.decodeIfPresent(String.self,    forKey: .customSystemPromptInstructions) ?? ""
        developerMode                  = try c.decodeIfPresent(Bool.self,      forKey: .developerMode) ?? false
    }

    /// Load from the shared App Group container, falling back to defaults.
    public static func load() -> LLMSettings {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data     = defaults.data(forKey: userDefaultsKey),
            let settings = try? JSONDecoder().decode(LLMSettings.self, from: data)
        else { return LLMSettings() }
        return settings
    }

    /// Persist to the shared App Group container.
    public func save() {
        guard
            let defaults = UserDefaults(suiteName: LLMSettings.appGroupID),
            let data     = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: LLMSettings.userDefaultsKey)
    }
}
