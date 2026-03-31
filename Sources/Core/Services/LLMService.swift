import Foundation

// MARK: - Error types

public enum LLMError: LocalizedError {
    case serverNotReady
    case networkError(Error)
    case httpError(Int, String?)
    case invalidResponse
    case emptyResponse
    case missingConfiguration

    public var errorDescription: String? {
        switch self {
        case .serverNotReady:
            return "The LLM server did not become ready within 2 minutes. Make sure it is running and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code, let body):
            if let body, !body.isEmpty {
                return "Server returned HTTP \(code): \(body)"
            }
            return "Server returned HTTP \(code)."
        case .invalidResponse:
            return "Received an invalid or unexpected response from the server."
        case .emptyResponse:
            return "The server returned an empty response."
        case .missingConfiguration:
            return "No LLM server is configured. Please set a Base URL in Settings → AI Note Generation."
        }
    }
}

// MARK: - Service

/// Handles communication with an OpenAI-compatible LLM server.
public actor LLMService {

    private let settings: LLMSettings

    public init(settings: LLMSettings) {
        self.settings = settings
    }

    // MARK: Health Polling

    /// Poll `{baseURL}/health` until the server responds HTTP 200 or timeout (120 s).
    /// `onProgress` is called periodically with a human-readable status string.
    public func waitUntilReady(
        onProgress: @Sendable (String) async -> Void
    ) async throws {
        guard !settings.baseURL.isEmpty else {
            throw LLMError.missingConfiguration
        }

        let timeout: TimeInterval = 120
        let start = Date()
        var delay: TimeInterval = 2

        while true {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= timeout {
                throw LLMError.serverNotReady
            }

            if await checkHealth() { return }

            let elapsedInt = Int(elapsed)
            await onProgress("Starting server… (\(elapsedInt)s / 120s)")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay = min(delay * 1.5, 15)
        }
    }

    /// Public one-shot health check — returns `true` if the server responds HTTP 200.
    public func checkHealthPublic() async -> Bool {
        await checkHealth()
    }

    private func checkHealth() async -> Bool {
        guard let url = buildURL(path: "/health") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: Chat Completion

    /// Call `POST {baseURL}/v1/chat/completions` and return the first assistant message.
    /// Messages must be `[["role": "system"/"user"/"assistant", "content": "..."]]`.
    public func complete(messages: [[String: Any]]) async throws -> String {
        guard !settings.baseURL.isEmpty else {
            throw LLMError.missingConfiguration
        }
        guard let url = buildURL(path: "/v1/chat/completions") else {
            throw LLMError.invalidResponse
        }

        var body: [String: Any] = [
            "model": settings.model,
            "messages": messages,
        ]
        if settings.useThinking {
            body["enable_thinking"] = true
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw LLMError.invalidResponse
        }

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8)
            throw LLMError.httpError(http.statusCode, bodyStr)
        }

        guard
            let json     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices  = json["choices"] as? [[String: Any]],
            let first    = choices.first,
            let message  = first["message"] as? [String: Any],
            let content  = message["content"] as? String
        else {
            throw LLMError.invalidResponse
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.emptyResponse
        }

        return content
    }

    // MARK: Helpers

    private func buildURL(path: String) -> URL? {
        let base = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + path)
    }
}
