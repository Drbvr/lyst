import Foundation

/// Handles hierarchical tag operations
public struct TagHierarchy {

    public init() {}

    /// Expands a wildcard tag to matching tags
    /// Example: "work/*" matches ["work/backend", "work/frontend"] but not ["work/backend/api"]
    public func expandWildcard(tag: String, in allTags: Set<String>) -> Set<String> {
        guard tag.contains("*") else {
            // No wildcard, return exact match only
            return allTags.contains(tag) ? [tag] : []
        }

        // Escape the tag first, then replace \* with the regex pattern
        let escapedTag = NSRegularExpression.escapedPattern(for: tag)
        let regexPattern = "^" + escapedTag.replacingOccurrences(of: "\\*", with: "[^/]*") + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return []
        }

        var matches = Set<String>()

        for itemTag in allTags {
            let range = NSRange(itemTag.startIndex..., in: itemTag)
            if regex.firstMatch(in: itemTag, range: range) != nil {
                matches.insert(itemTag)
            }
        }

        return matches
    }

    /// Gets all descendants of a tag
    /// Example: "work" returns ["work/backend", "work/backend/api", "work/frontend"]
    public func getDescendants(of tag: String, in allTags: Set<String>) -> Set<String> {
        let prefix = tag.hasSuffix("/") ? tag : tag + "/"
        return Set(allTags.filter { $0.hasPrefix(prefix) })
    }

    /// Gets all ancestors of a tag
    /// Example: "work/backend/api" returns ["work", "work/backend", "work/backend/api"]
    public func getAncestors(of tag: String) -> [String] {
        var ancestors: [String] = []
        let components = tag.components(separatedBy: "/")
        guard !components.isEmpty else { return [] }

        for i in 1...components.count {
            let ancestor = components[0..<i].joined(separator: "/")
            ancestors.append(ancestor)
        }

        return ancestors
    }

    /// Checks if a tag matches a pattern (with wildcards)
    public func matches(tag: String, pattern: String) -> Bool {
        if !pattern.contains("*") {
            return tag == pattern
        }

        let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escapedPattern.replacingOccurrences(of: "\\*", with: "[^/]*") + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }

        let range = NSRange(tag.startIndex..., in: tag)
        return regex.firstMatch(in: tag, range: range) != nil
    }
}
