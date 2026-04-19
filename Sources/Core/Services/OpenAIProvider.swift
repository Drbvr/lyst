import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(Darwin)

/// LLMProvider backed by any OpenAI-compatible SSE streaming endpoint.
public final class OpenAIProvider: LLMProvider, @unchecked Sendable {

    public let supportsNativeTokenStreaming = true

    private let settings: LLMSettings
    private let session: URLSession

    // Cancellation
    private var streamTask: Task<Void, Never>?
    private let lock = NSLock()

    public init(settings: LLMSettings) {
        self.settings = settings
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    public func cancel() {
        lock.lock()
        let t = streamTask
        lock.unlock()
        t?.cancel()
    }

    public func streamStep(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            let task = Task {
                do {
                    try await self.stream(messages: messages, tools: tools, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self.lock.lock()
            self.streamTask = task
            self.lock.unlock()
            continuation.onTermination = { [weak self] _ in self?.cancel() }
        }
    }

    // MARK: - Private

    private func stream(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition],
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        guard !settings.baseURL.isEmpty else { throw LLMError.missingConfiguration }
        let base = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/v1/chat/completions") else {
            throw LLMError.invalidResponse
        }

        let messagesJSON = messages.map { serializeMessage($0) }
        let toolsJSON = tools.map { $0.toOpenAIDict() }

        var body: [String: Any] = [
            "model": settings.model,
            "messages": messagesJSON,
            "stream": true,
            "stream_options": ["include_usage": false]
        ]
        if !toolsJSON.isEmpty {
            body["tools"] = toolsJSON
            body["tool_choice"] = "auto"
        }
        if settings.useThinking { body["enable_thinking"] = true }

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Accumulator for tool-call argument deltas keyed by index
        var pendingCalls: [Int: (id: String, name: String, args: String)] = [:]
        var emittedCallIds: [Int: String] = [:]

        for try await line in SSELineStream(request: request, session: session) {
            guard !Task.isCancelled else { break }
            guard line.hasPrefix("data: "), line != "data: [DONE]" else {
                if line == "data: [DONE]" { break }
                continue
            }
            let jsonStr = String(line.dropFirst("data: ".count))
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first,
                  let delta = choice["delta"] as? [String: Any]
            else { continue }

            // Text delta
            if let text = delta["content"] as? String, !text.isEmpty {
                continuation.yield(.assistantDelta(text))
            }

            // Tool-call deltas
            if let toolCallDeltas = delta["tool_calls"] as? [[String: Any]] {
                for tc in toolCallDeltas {
                    guard let idx = tc["index"] as? Int else { continue }
                    let id = tc["id"] as? String
                    let fn = tc["function"] as? [String: Any]
                    let namePart = fn?["name"] as? String ?? ""
                    let argsPart = fn?["arguments"] as? String ?? ""

                    if var existing = pendingCalls[idx] {
                        existing.args += argsPart
                        pendingCalls[idx] = existing
                    } else {
                        let newId = id ?? "call_\(idx)"
                        pendingCalls[idx] = (id: newId, name: namePart, args: argsPart)
                        if !namePart.isEmpty {
                            let req = ToolCallRequest(id: newId, name: namePart, argumentsJSON: "")
                            continuation.yield(.toolCallStart(req))
                            emittedCallIds[idx] = newId
                        }
                    }
                    if !argsPart.isEmpty, let callId = emittedCallIds[idx] {
                        continuation.yield(.toolCallArgsDelta(id: callId, json: argsPart))
                    }
                }
            }

            // Finish reason
            if let reason = choice["finish_reason"] as? String, !reason.isEmpty {
                // Complete any pending tool calls
                let completedCalls = pendingCalls.values.map { call in
                    ToolCallRequest(id: call.id, name: call.name, argumentsJSON: call.args)
                }
                for call in completedCalls {
                    continuation.yield(.toolCallComplete(id: call.id))
                }

                let finish: FinishReason
                if reason == "tool_calls" || !completedCalls.isEmpty {
                    finish = .toolCalls(completedCalls)
                } else if reason == "length" {
                    finish = .maxTokens
                } else {
                    finish = .stop
                }
                continuation.yield(.finish(finish))
                continuation.finish()
                return
            }
        }

        if Task.isCancelled {
            continuation.yield(.finish(.cancelled))
        }
        continuation.finish()
    }

    private func serializeMessage(_ msg: LLMChatMessage) -> [String: Any] {
        switch msg {
        case .system(let text):
            return ["role": "system", "content": text]
        case .user(let text):
            return ["role": "user", "content": text]
        case .assistant(let content):
            return ["role": "assistant", "content": content as Any]
        case .assistantToolCalls(let content, let calls):
            let toolCallsJSON = calls.map { call -> [String: Any] in
                let argsData = call.argumentsJSON.data(using: .utf8) ?? Data()
                let argsStr = String(data: argsData, encoding: .utf8) ?? call.argumentsJSON
                return [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": argsStr] as [String: Any]
                ]
            }
            var dict: [String: Any] = ["role": "assistant", "tool_calls": toolCallsJSON]
            if let content { dict["content"] = content }
            return dict
        case .toolResult(let callId, let content):
            return ["role": "tool", "tool_call_id": callId, "content": content]
        }
    }
}

// MARK: - SSE Line Stream

/// Async sequence of raw SSE lines from a streaming HTTP response.
private struct SSELineStream: AsyncSequence {
    typealias Element = String

    let request: URLRequest
    let session: URLSession

    struct AsyncIterator: AsyncIteratorProtocol {
        let request: URLRequest
        let session: URLSession
        private var bytesIterator: URLSession.AsyncBytes.Iterator?
        private var started = false
        private var buffer = ""
        private var byteStream: URLSession.AsyncBytes?

        init(request: URLRequest, session: URLSession) {
            self.request = request
            self.session = session
        }

        mutating func next() async throws -> String? {
            if !started {
                started = true
                let (bytes, response) = try await session.bytes(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    var body = ""
                    for try await char in bytes.characters { body.append(char) }
                    throw LLMError.httpError(http.statusCode, body)
                }
                byteStream = bytes
                bytesIterator = bytes.makeAsyncIterator()
            }

            guard var it = bytesIterator else { return nil }
            while true {
                guard let byte = try await it.next() else {
                    bytesIterator = it
                    return nil
                }
                bytesIterator = it
                let char = Character(UnicodeScalar(byte))
                if char == "\n" {
                    let line = buffer
                    buffer = ""
                    if !line.isEmpty { return line }
                    // Empty line = SSE event boundary, continue
                } else if char != "\r" {
                    buffer.append(char)
                }
            }
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(request: request, session: session)
    }
}

#else

// MARK: - Linux stub
// URLSession.bytes(for:) / AsyncBytes aren't in swift-corelibs-foundation,
// so on Linux the SSE streaming provider only exists as a stub that throws.
// No Core code or CoreTests consume OpenAIProvider directly; it's wired up
// from the iOS-only ListApp target.

public final class OpenAIProvider: LLMProvider, @unchecked Sendable {
    public let supportsNativeTokenStreaming = true

    public init(settings: LLMSettings) {
        _ = settings
    }

    public func cancel() {}

    public func streamStep(
        messages: [LLMChatMessage],
        tools: [LLMToolDefinition]
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMError.missingConfiguration)
        }
    }
}

#endif
