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

    // MARK: - Batch Parsing

    /// Result of parsing an LLM response containing multiple \`\`\`yaml blocks.
    public struct BatchResult {
        public let valid: [NoteEdit]
        /// Reasons blocks failed validation, in the order they appeared. Count
        /// = number of invalid blocks; callers can surface this to users so
        /// they aren't surprised when "5 notes" renders as 3 drafts.
        public let invalidReasons: [String]

        public var invalidCount: Int { invalidReasons.count }
    }

    /// Parse all \`\`\`yaml blocks in a response. Unlike `parseAll`, returns
    /// both the valid notes and the reasons invalid blocks were dropped so the
    /// UI can warn the user ("1 draft couldn't be parsed").
    public func parseAllWithDiagnostics(
        response: String, listTypes: [ListType]
    ) -> BatchResult {
        var valid: [NoteEdit] = []
        var invalid: [String] = []
        for block in extractAllYAMLBlocks(from: response) {
            let wrapped = "```yaml\n\(block)\n```"
            switch parse(response: wrapped, listTypes: listTypes) {
            case .success(let title, let type, let properties, let tags):
                valid.append(NoteEdit(type: type, title: title, properties: properties, tags: tags))
            case .invalid(let reason):
                invalid.append(reason)
            }
        }
        return BatchResult(valid: valid, invalidReasons: invalid)
    }

    /// Parse all \`\`\`yaml blocks in a response. Returns only the valid notes
    /// for back-compat with existing callers; new code should prefer
    /// `parseAllWithDiagnostics` so invalid blocks can be surfaced.
    public func parseAll(response: String, listTypes: [ListType]) -> [NoteEdit] {
        parseAllWithDiagnostics(response: response, listTypes: listTypes).valid
    }

    // MARK: - Private helpers

    /// Extract the content inside the first ```yaml ... ``` fence.
    private func extractYAMLBlock(from text: String) -> String? {
        extractAllYAMLBlocks(from: text).first
    }

    /// Extract the content of every YAML frontmatter document the response
    /// contains. A document is any `---`-delimited block, whether it sits in
    /// its own ```` ```yaml ``` ```` fence or shares a fence with siblings
    /// (Apple Intelligence commonly returns the latter for batch imports).
    private func extractAllYAMLBlocks(from text: String) -> [String] {
        let pattern = #"```yaml\s*\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        var results: [String] = []
        for match in regex.matches(in: text, range: nsRange) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let fenceContent = String(text[range])
            results.append(contentsOf: splitYAMLDocuments(fenceContent))
        }
        return results
    }

    /// Split a fence's content into individual YAML documents by treating
    /// every line that is exactly `---` (after trimming) as a separator.
    /// Runs of separators and empty leading/trailing sections are dropped.
    private func splitYAMLDocuments(_ content: String) -> [String] {
        var documents: [String] = []
        var current: [String] = []

        func flush() {
            let joined = current
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { documents.append(joined) }
            current.removeAll(keepingCapacity: true)
        }

        for line in content.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                flush()
            } else {
                current.append(line)
            }
        }
        flush()
        return documents
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
