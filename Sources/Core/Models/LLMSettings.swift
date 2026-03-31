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

/// Persisted LLM configuration shared between the main app and the share extension
/// via the App Group UserDefaults suite.
public struct LLMSettings: Codable {
    public static let appGroupID      = "group.com.bvanriessen.listapp"
    public static let userDefaultsKey = "llmSettings"
    public static let vaultBookmarkKey = "sharedVaultBookmark"

    public var processingMode: ProcessingMode
    public var baseURL: String
    public var model: String
    public var useThinking: Bool
    public var apiKey: String

    public init(
        processingMode: ProcessingMode = .onDevice,
        baseURL: String = "",
        model: String = "",
        useThinking: Bool = false,
        apiKey: String = ""
    ) {
        self.processingMode = processingMode
        self.baseURL        = baseURL
        self.model          = model
        self.useThinking    = useThinking
        self.apiKey         = apiKey
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
