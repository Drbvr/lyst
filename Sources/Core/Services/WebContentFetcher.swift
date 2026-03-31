import Foundation

public enum WebFetchError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(Int)
    case noContent

    public var errorDescription: String? {
        switch self {
        case .invalidURL:          return "The URL is not valid."
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .httpError(let code): return "The server returned HTTP \(code)."
        case .noContent:           return "No readable content was found at the URL."
        }
    }
}

/// Fetches a web page and returns its readable plain-text content.
public struct WebContentFetcher {

    /// Maximum number of characters to include in the prompt (keeps tokens manageable).
    public static let contentLimit = 4_000

    public init() {}

    /// Download `urlString`, strip HTML, and return plain text truncated to `contentLimit`.
    public func fetchText(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw WebFetchError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WebFetchError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WebFetchError.httpError(http.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
        else {
            throw WebFetchError.noContent
        }

        let plain = stripHTML(html)
        guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebFetchError.noContent
        }

        return String(plain.prefix(Self.contentLimit))
    }

    // MARK: - HTML stripping

    private func stripHTML(_ html: String) -> String {
        var text = html

        // Remove entire blocks we don't want
        for tag in ["script", "style", "nav", "header", "footer", "aside", "noscript"] {
            if let re = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                options: [.caseInsensitive]
            ) {
                text = re.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: " "
                )
            }
        }

        // Strip remaining tags
        if let re = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = re.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }

        // Decode common HTML entities
        text = text
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        // Collapse runs of whitespace
        if let re = try? NSRegularExpression(pattern: "\\s{2,}") {
            text = re.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
