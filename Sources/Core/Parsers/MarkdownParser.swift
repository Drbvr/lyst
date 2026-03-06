import Foundation

/// Protocol for parsing markdown content into items
public protocol MarkdownParser {
    func parseTodos(from content: String, sourceFile: String) -> [Item]
}

/// Obsidian-compatible todo parser for markdown files
public class ObsidianTodoParser: MarkdownParser {

    private let yamlParser = YAMLFrontmatterParser()

    public init() {}

    /// Parses markdown content and extracts items.
    /// Handles two formats:
    ///   1. YAML frontmatter with type field → creates one Item per file (books, movies, etc.)
    ///   2. Checkbox lines (- [ ] / - [x]) → creates one Item per checkbox (todos)
    public func parseTodos(from content: String, sourceFile: String) -> [Item] {
        // Check for YAML frontmatter first
        let (yaml, body) = yamlParser.extractFrontmatter(from: content)

        if let yaml = yaml {
            // File has frontmatter — create a single item from it
            if let item = createItemFromFrontmatter(yaml: yaml, body: body, sourceFile: sourceFile) {
                return [item]
            }
        }

        // No frontmatter (or unrecognized) — parse checkbox lines as todos
        let lines = content.components(separatedBy: .newlines)
        var items: [Item] = []
        var currentTodo: (checkbox: Substring, text: String)?
        var inCodeBlock = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Track code blocks
            if trimmedLine.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }

            // Skip if in code block
            if inCodeBlock {
                continue
            }

            // Check if this is a todo line
            if let checkboxMatch = extractCheckbox(from: line) {
                // If we have a previous todo, add it
                if let (checkbox, text) = currentTodo {
                    if let item = createItem(from: String(checkbox), text: text, sourceFile: sourceFile) {
                        items.append(item)
                    }
                }

                // Start new todo
                let todoText = extractTodoText(from: line)
                currentTodo = (checkboxMatch, todoText)
            } else if let (checkbox, text) = currentTodo {
                // Continue multi-line todo
                if !trimmedLine.isEmpty {
                    currentTodo = (checkbox, text + "\n" + trimmedLine)
                }
            }
        }

        // Add last todo
        if let (checkbox, text) = currentTodo {
            if let item = createItem(from: String(checkbox), text: text, sourceFile: sourceFile) {
                items.append(item)
            }
        }

        return items
    }

    /// Extracts checkbox from a line (returns "[ ]" or "[x]" if found)
    private func extractCheckbox(from line: String) -> Substring? {
        // Match "- [ ]", "- [x]", "* [ ]", "* [x]"
        let pattern = "^\\s*[-*]\\s+\\[(.?)\\]"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if let checkboxRange = Range(match.range(at: 0), in: line) {
                    let checkbox = line[checkboxRange]
                    // Extract just the bracket part
                    if let bracketStart = checkbox.firstIndex(of: "["),
                       let bracketEnd = checkbox.firstIndex(of: "]") {
                        let nextIndex = checkbox.index(after: bracketEnd)
                        if nextIndex <= checkbox.endIndex {
                            return checkbox[bracketStart..<nextIndex]
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Extracts todo text after the checkbox
    private func extractTodoText(from line: String) -> String {
        // Remove the checkbox part and return the text
        let pattern = "^\\s*[-*]\\s+\\[.?\\]\\s*"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(line.startIndex..., in: line)
            let result = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            return result
        }
        return line
    }

    /// Creates an Item from parsed todo components
    private func createItem(from checkbox: String, text: String, sourceFile: String) -> Item? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil  // Skip empty checkboxes
        }

        let completed = checkbox.contains("x") || checkbox.contains("X")
        let title = extractTitle(from: text)
        let tags = extractTags(from: text)
        let dueDate = extractDate(from: text)
        let priority = extractPriority(from: text)

        var properties: [String: PropertyValue] = [:]

        if let priority = priority {
            properties["priority"] = PropertyValue.text(priority)
        }

        if let dueDate = dueDate {
            properties["dueDate"] = PropertyValue.date(dueDate)
        }

        let item = Item(
            type: "todo",
            title: title,
            properties: properties,
            tags: tags,
            completed: completed,
            sourceFile: sourceFile
        )

        return item
    }

    /// Extracts clean title (removes metadata)
    private func extractTitle(from text: String) -> String {
        var result = text

        // Remove dates
        result = result.replacingOccurrences(of: "📅\\s*\\d{4}-\\d{2}-\\d{2}(?:T\\d{2}:\\d{2})?", with: "", options: .regularExpression)

        // Remove priority emojis
        result = result.replacingOccurrences(of: "[⏫🔼🔽]", with: "", options: .regularExpression)

        // Remove tags
        result = result.replacingOccurrences(of: "#[\\w/]+", with: "", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Extracts tags from text
    private func extractTags(from text: String) -> [String] {
        var tags: [String] = []
        let pattern = "#([\\w/]+)"

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                if let tagRange = Range(match.range(at: 1), in: text) {
                    let tag = String(text[tagRange])
                    tags.append(tag)
                }
            }
        }

        return tags
    }

    /// Extracts due date from text
    private func extractDate(from text: String) -> Date? {
        // Look for 📅 YYYY-MM-DD or 📅 YYYY-MM-DDTHH:MM
        let pattern = "📅\\s*(\\d{4}-\\d{2}-\\d{2})(?:T(\\d{2}):(\\d{2}))?"

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range) {
                if let dateRange = Range(match.range(at: 1), in: text) {
                    let dateString = String(text[dateRange])

                    // Try to parse date
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]

                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    /// Extracts priority from text
    private func extractPriority(from text: String) -> String? {
        if text.contains("⏫") {
            return "high"
        } else if text.contains("🔼") {
            return "medium"
        } else if text.contains("🔽") {
            return "low"
        }
        return nil
    }

    // MARK: - YAML Frontmatter Item Creation

    /// Creates a single Item from YAML frontmatter (for books, movies, notes, etc.)
    private func createItemFromFrontmatter(yaml: String, body: String, sourceFile: String) -> Item? {
        // Extract the type field
        let lines = yaml.components(separatedBy: .newlines)
        var type: String?
        var title: String?
        var tagsRaw: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("type:") {
                type = trimmed.dropFirst("type:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("title:") {
                title = trimmed.dropFirst("title:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("tags:") {
                tagsRaw = trimmed.dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
            }
        }

        guard let itemType = type, !itemType.isEmpty else {
            return nil  // No type → not a recognized frontmatter item
        }

        // Use filename as fallback title
        let fileName = URL(fileURLWithPath: sourceFile).deletingPathExtension().lastPathComponent
        let itemTitle = title ?? fileName.replacingOccurrences(of: "_", with: " ")

        // Parse tags from inline array format: [tag1, tag2] or bare: tag1, tag2
        var tags: [String] = []
        if let rawTags = tagsRaw {
            let stripped = rawTags.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            tags = stripped.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
        }

        // Parse all other properties
        var properties: [String: PropertyValue] = [:]
        if case .success(let props) = yamlParser.parseItemProperties(yaml: yaml) {
            properties = props
            // Remove title and tags from properties (shown separately)
            properties.removeValue(forKey: "title")
            properties.removeValue(forKey: "tags")
        }

        // Determine completed state from tags or properties
        // Movies: "movies/watched" tag → completed. Books: "books/read" → completed
        let completedByTag = tags.contains { tag in
            tag.hasSuffix("/watched") || tag.hasSuffix("/read")
        }
        let completedByProp = (properties["completed"].flatMap {
            if case .bool(let b) = $0 { return b } else { return nil }
        }) ?? false
        let completed = completedByTag || completedByProp

        // Use date_read or date_watched as createdAt if available
        var createdAt = Date()
        if case .date(let d) = properties["date_read"] { createdAt = d }
        else if case .date(let d) = properties["date_watched"] { createdAt = d }

        return Item(
            type: itemType,
            title: itemTitle,
            properties: properties,
            tags: tags,
            completed: completed,
            sourceFile: sourceFile,
            createdAt: createdAt
        )
    }
}
