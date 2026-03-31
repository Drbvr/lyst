import Foundation

/// Describes what kind of content was shared.
public enum SharedContentType: Sendable {
    case url(String)
    case image
}

/// Builds LLM messages for note creation from shared content.
public struct PromptBuilder {

    public init() {}

    // MARK: - System Prompt

    /// Build the system message that describes available note types and expected output.
    public func buildSystemPrompt(listTypes: [ListType], sampleNotes: [String]) -> String {
        var lines: [String] = []

        lines.append("""
        You are a note creation assistant for a personal knowledge management app. \
        Your job is to analyse shared content and create a structured note in YAML frontmatter format.
        """)
        lines.append("")
        lines.append("## Available Note Types")
        lines.append("")

        for listType in listTypes {
            lines.append("### \(listType.name)")
            if let prompt = listType.llmExtractionPrompt, !prompt.isEmpty {
                lines.append(prompt)
            }
            lines.append("Fields:")
            for field in listType.fields {
                let req  = field.required ? " (required)" : ""
                var desc = "  - \(field.name): \(field.type.rawValue)\(req)"
                if let min = field.min, let max = field.max {
                    desc += " [range: \(Int(min))–\(Int(max))]"
                }
                lines.append(desc)
            }
            lines.append("")
        }

        lines.append("## Output Format")
        lines.append("")
        lines.append("Return ONLY a single YAML frontmatter block inside triple-backtick yaml fences:")
        lines.append("```yaml")
        lines.append("---")
        lines.append("type: <note_type_lowercase>")
        lines.append("title: <title>")
        lines.append("<field>: <value>")
        lines.append("tags: [tag1, tag2]")
        lines.append("---")
        lines.append("```")
        lines.append("")
        lines.append("Rules:")
        lines.append("- Choose the most appropriate type from the list above (use lowercase)")
        lines.append("- Fill in as many fields as you can infer from the content")
        lines.append("- Use ISO 8601 dates (YYYY-MM-DD) for date fields")
        lines.append("- Use plain numbers (not strings) for number fields")
        lines.append("- Keep tags short and relevant (optional)")
        lines.append("- Return ONLY the ```yaml block — no other text, explanation, or markdown")

        if !sampleNotes.isEmpty {
            lines.append("")
            lines.append("## Style Examples (existing notes from the vault)")
            lines.append("")
            for (i, note) in sampleNotes.prefix(5).enumerated() {
                lines.append("Example \(i + 1):")
                lines.append("```yaml")
                lines.append(note)
                lines.append("```")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - User Message

    /// Build the user turn message with the shared content + optional extra text.
    public func buildUserMessage(
        content: String,
        contentType: SharedContentType,
        additionalText: String
    ) -> String {
        var parts: [String] = []

        switch contentType {
        case .url(let url):
            parts.append("I'm sharing a webpage from: \(url)")
            parts.append("")
            if content.isEmpty {
                parts.append("(Could not fetch page content — please infer from the URL.)")
            } else {
                parts.append("Webpage content:")
                parts.append(content)
            }
        case .image:
            parts.append("I'm sharing an image.")
            parts.append("")
            if content.isEmpty {
                parts.append("No text was found in the image.")
            } else {
                parts.append("Text found in the image (via OCR):")
                parts.append(content)
            }
        }

        if !additionalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("")
            parts.append("My additional context:")
            parts.append(additionalText)
        }

        parts.append("")
        parts.append("Please create an appropriate note.")
        return parts.joined(separator: "\n")
    }

    // MARK: - Retry Message

    /// Build a correction message appended to an existing conversation.
    public func buildRetryMessage(reason: String) -> String {
        "Your previous response was invalid: \(reason). " +
        "Please correct it and return ONLY valid YAML frontmatter inside ```yaml ``` fences."
    }

    // MARK: - Sample Note Extraction

    /// Extract YAML frontmatter strings from a list of items for prompt context.
    public func extractSampleNotes(from items: [Item], max: Int = 5) -> [String] {
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]

        return items
            .filter { $0.type != "todo" }
            .prefix(max)
            .map { item in
                var lines = ["---", "type: \(item.type)", "title: \(item.title)"]
                if !item.tags.isEmpty {
                    let tagsStr = item.tags.map { "\"\($0)\"" }.joined(separator: ", ")
                    lines.append("tags: [\(tagsStr)]")
                }
                for (key, value) in item.properties.sorted(by: { $0.key < $1.key }) {
                    switch value {
                    case .text(let t):   lines.append("\(key): \(t)")
                    case .number(let n): lines.append(n.truncatingRemainder(dividingBy: 1) == 0
                                            ? "\(key): \(Int(n))" : "\(key): \(n)")
                    case .date(let d):   lines.append("\(key): \(isoFmt.string(from: d))")
                    case .bool(let b):   lines.append("\(key): \(b)")
                    }
                }
                lines.append("---")
                return lines.joined(separator: "\n")
            }
    }
}
