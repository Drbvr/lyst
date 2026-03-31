import Foundation

// MARK: - Result

public enum NoteParseResult {
    /// Successfully parsed — ready to save.
    case success(
        title: String,
        type: String,
        properties: [String: PropertyValue],
        tags: [String]
    )
    /// Validation failed with a human-readable reason (use as retry message body).
    case invalid(reason: String)
}

// MARK: - Parser

/// Extracts and validates the YAML block from an LLM response.
/// Uses the existing `YAMLFrontmatterParser` from Core for property parsing.
public struct NoteResponseParser {

    public init() {}

    /// Parse an LLM response string and validate it against the known list types.
    public func parse(response: String, listTypes: [ListType]) -> NoteParseResult {
        guard let yaml = extractYAMLBlock(from: response) else {
            return .invalid(reason: "No ```yaml block found in response. Please wrap your YAML frontmatter in ```yaml fences.")
        }

        let yamlParser = YAMLFrontmatterParser()

        // --- type ---
        guard let type = extractScalarField(yaml, key: "type"), !type.isEmpty else {
            return .invalid(reason: "Missing required 'type' field.")
        }

        let matchedListType = listTypes.first {
            $0.name.lowercased() == type.lowercased()
        }
        guard let listType = matchedListType else {
            let known = listTypes.map { $0.name.lowercased() }.joined(separator: ", ")
            return .invalid(reason: "Unknown type '\(type)'. Valid types are: \(known).")
        }

        // --- title ---
        guard let title = extractScalarField(yaml, key: "title"), !title.isEmpty else {
            return .invalid(reason: "Missing required 'title' field.")
        }

        // --- properties ---
        guard case .success(let rawProperties) = yamlParser.parseItemProperties(yaml: yaml) else {
            return .invalid(reason: "Could not parse YAML properties. Check for syntax errors.")
        }
        // Remove meta-keys that are stored separately
        var properties = rawProperties
        properties.removeValue(forKey: "type")
        properties.removeValue(forKey: "title")
        properties.removeValue(forKey: "tags")

        // --- required field check ---
        for fieldDef in listType.fields where fieldDef.required {
            if fieldDef.name == "title" { continue }
            if properties[fieldDef.name] == nil {
                return .invalid(reason: "Missing required field '\(fieldDef.name)' for type '\(listType.name)'.")
            }
        }

        // --- tags ---
        let tags = extractTags(from: yaml)

        return .success(
            title: title,
            type: type.lowercased(),
            properties: properties,
            tags: tags
        )
    }

    // MARK: - Private helpers

    /// Extract the content inside the first ```yaml ... ``` fence.
    private func extractYAMLBlock(from text: String) -> String? {
        let pattern = #"```yaml\s*\n([\s\S]*?)```"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }

        return String(text[range])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip surrounding --- delimiters if present
            .components(separatedBy: .newlines)
            .filter { $0 != "---" }
            .joined(separator: "\n")
    }

    /// Extract a simple scalar value: `key: value` (first match wins).
    private func extractScalarField(_ yaml: String, key: String) -> String? {
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }
            let value = trimmed
                .dropFirst("\(key):".count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Extract `tags: [a, b, c]` list.
    private func extractTags(from yaml: String) -> [String] {
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("tags:") else { continue }
            if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]") {
                let inner = String(trimmed[trimmed.index(after: start)..<end])
                return inner
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces)
                             .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                    .filter { !$0.isEmpty }
            }
        }
        return []
    }
}
