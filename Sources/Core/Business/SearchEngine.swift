import Foundation

/// Result of a search query
public struct SearchResult {
    public let item: Item
    public let score: Double
    public let matches: [Match]

    public init(item: Item, score: Double, matches: [Match]) {
        self.item = item
        self.score = score
        self.matches = matches
    }
}

/// Represents a single match of the search query
public struct Match: Equatable {
    public let field: String  // "title", "tags", "content", etc.
    public let range: NSRange

    public init(field: String, range: NSRange) {
        self.field = field
        self.range = range
    }
}

/// Protocol for searching items
public protocol SearchEngine {
    func search(query: String, in items: [Item]) -> [SearchResult]
}

/// Default implementation of search engine
public class FullTextSearchEngine: SearchEngine {

    public init() {}

    /// Searches items for matching content and returns results ranked by relevance
    public func search(query: String, in items: [Item]) -> [SearchResult] {
        guard !query.isEmpty else {
            return []
        }

        let lowerQuery = query.lowercased()

        var results: [SearchResult] = []

        for item in items {
            var matches: [Match] = []
            var score: Double = 0

            // Search in title (highest weight)
            if let titleMatches = findMatches(in: item.title, query: lowerQuery, field: "title") {
                matches.append(contentsOf: titleMatches)

                if item.title.lowercased() == lowerQuery {
                    // Full title matches the query exactly
                    score += Double(titleMatches.count) * 10
                } else {
                    // Query is a substring of the title
                    score += Double(titleMatches.count) * 5
                }
            }

            // Search in tags (medium weight)
            for tag in item.tags {
                if let tagMatches = findMatches(in: tag, query: lowerQuery, field: "tags") {
                    matches.append(contentsOf: tagMatches)
                    score += Double(tagMatches.count) * 3
                }
            }

            // Search in properties (medium weight)
            for (key, value) in item.properties {
                let valueStr = propertyValueToString(value)
                if let propMatches = findMatches(in: valueStr, query: lowerQuery, field: key) {
                    matches.append(contentsOf: propMatches)
                    score += Double(propMatches.count) * 2
                }
            }

            // Search in source file path (lower weight, count occurrences)
            let contentMatches = countMatches(in: item.sourceFile, query: lowerQuery)
            score += Double(contentMatches) * 1

            if score > 0 {
                let result = SearchResult(item: item, score: score, matches: matches)
                results.append(result)
            }
        }

        // Sort by score (descending)
        return results.sorted { $0.score > $1.score }
    }

    // MARK: - Private Helpers

    private func findMatches(in text: String, query: String, field: String) -> [Match]? {
        let lowerText = text.lowercased()
        guard lowerText.contains(query) else {
            return nil
        }

        var matches: [Match] = []
        var currentStart = lowerText.startIndex

        while currentStart < lowerText.endIndex,
              let range = lowerText.range(of: query, range: currentStart..<lowerText.endIndex) {
            let nsRange = NSRange(range, in: text)
            matches.append(Match(field: field, range: nsRange))

            // Move to after this match
            currentStart = range.upperBound
        }

        return matches.isEmpty ? nil : matches
    }

    private func countMatches(in text: String, query: String) -> Int {
        let lowerText = text.lowercased()
        var count = 0
        var searchStart = lowerText.startIndex

        while let range = lowerText.range(of: query, range: searchStart..<lowerText.endIndex) {
            count += 1
            searchStart = range.upperBound
        }

        return count
    }

    private func propertyValueToString(_ value: PropertyValue) -> String {
        switch value {
        case .text(let text):
            return text
        case .number(let number):
            return String(number)
        case .date(let date):
            return ISO8601DateFormatter().string(from: date)
        case .bool(let bool):
            return String(bool)
        }
    }
}
