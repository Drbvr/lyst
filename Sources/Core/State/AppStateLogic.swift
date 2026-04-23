import Foundation

/// Pure functions used by the iOS AppState view-model. Lives in Core so these
/// can be exercised on Linux with `swift test` — no SwiftUI / @Observable here.
///
/// Every function is deterministic: given the same inputs it returns the same
/// output with no file system or UI side effects. The view-model layer is
/// responsible for wiring inputs (reading files) and outputs (writing files,
/// updating @Observable state).
public enum AppStateLogic {

    // MARK: - YAML helpers

    /// Quote a string for safe inclusion as a YAML scalar.
    /// Escapes `\` and `"`, then wraps the result in double quotes.
    /// Callers should use this for every value that came from user input.
    public static func yamlQuote(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: - Filename sanitization

    /// Sanitize a user title for use as a filename. Strips characters illegal
    /// on iOS/macOS, trims whitespace, and rejects results that would escape
    /// the containing folder (`..`, leading `/`, empty).
    public static func sanitizedFilename(from title: String) -> String? {
        // Reject absolute-path-looking titles before stripping so
        // `/etc/passwd` can't become `-etc-passwd` and hide its intent.
        let trimmedInput = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedInput.hasPrefix("/") else { return nil }

        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = trimmedInput
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: "-", omittingEmptySubsequences: true)
        if parts.contains(where: { $0 == ".." }) { return nil }
        if cleaned == "." || cleaned == ".." { return nil }
        return cleaned
    }

    // MARK: - Todo checkbox line

    /// Build a `- [ ] Title …` line for Inbox.md with priority emoji, due date,
    /// and `#tag` suffixes.
    public static func buildTodoLine(
        title: String,
        tags: [String],
        properties: [String: PropertyValue]
    ) -> String {
        var line = "- [ ] \(title)"

        if case .text(let p) = properties["priority"] {
            let emoji: String
            switch p {
            case "high",   "p1": emoji = "⏫"
            case "medium", "p2": emoji = "🔼"
            case "p3":           emoji = "🔽"
            case "low",    "p4": emoji = "🔽"
            default:             emoji = ""
            }
            if !emoji.isEmpty { line += " \(emoji)" }
        }

        if case .date(let d) = properties["dueDate"] {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withFullDate]
            line += " 📅 \(fmt.string(from: d))"
        }

        for tag in tags { line += " #\(tag)" }
        return line
    }

    /// Append a todo line to the existing inbox content.
    /// Ensures exactly one newline separates the existing content from the new
    /// entry (no spurious blank lines). CRLF is normalised to LF.
    public static func appendTodoToInbox(existingContent: String, line: String) -> String {
        var base = existingContent.replacingOccurrences(of: "\r\n", with: "\n")
        // Strip all trailing newlines then add exactly one before the new entry.
        while base.hasSuffix("\n") { base.removeLast() }
        return base + "\n" + line + "\n"
    }

    // MARK: - YAML item serialization

    /// Produce the YAML-frontmatter markdown contents for a new non-todo item.
    /// All user strings (title, tags, text properties) are YAML-quoted so titles
    /// containing `"`, `\n`, or `---` cannot inject additional frontmatter fields.
    public static func serializeYAMLItem(
        type: String,
        title: String,
        tags: [String],
        properties: [String: PropertyValue]
    ) -> String {
        var lines: [String] = ["---"]
        lines.append("type: \(yamlQuote(type))")
        lines.append("title: \(yamlQuote(title))")

        if !tags.isEmpty {
            let tagList = tags.map { yamlQuote($0) }.joined(separator: ", ")
            lines.append("tags: [\(tagList)]")
        }

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withFullDate]

        for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
            switch value {
            case .text(let t):
                lines.append("\(key): \(yamlQuote(t))")
            case .number(let n):
                lines.append(n.truncatingRemainder(dividingBy: 1) == 0
                             ? "\(key): \(Int(n))"
                             : "\(key): \(n)")
            case .date(let d):
                lines.append("\(key): \(isoFull.string(from: d))")
            case .bool(let b):
                lines.append("\(key): \(b)")
            }
        }

        lines += ["---", ""]
        return lines.joined(separator: "\n")
    }

    // MARK: - Checkbox matching

    /// Does `line` represent an Obsidian checkbox line whose task-text equals
    /// `itemTitle`? Extracts the task text (everything after `- [ ]`), strips
    /// the same metadata the todo parser strips (dates, priority emojis,
    /// tags), and compares the result. Used instead of
    /// `line.contains(item.title)`, which incorrectly matches "Buy" inside
    /// "Buy milk".
    public static func isCheckboxLine(_ line: String, forTitle itemTitle: String) -> Bool {
        let pattern = "^\\s*[-*]\\s+\\[[ xX]\\]\\s+(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let taskRange = Range(match.range(at: 1), in: line) else {
            return false
        }
        let taskText = String(line[taskRange])
        return stripTaskMetadata(taskText) == normalizedCheckboxMatchTitle(itemTitle)
    }

    /// Checkbox lines are single-line; parser titles can include additional
    /// continuation lines for multiline todos. Match against the first line.
    private static func normalizedCheckboxMatchTitle(_ title: String) -> String {
        // Fallback to original title when first line is unavailable to avoid
        // producing an empty match key for malformed multiline strings.
        title
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? title
    }

    /// Remove the same Obsidian task metadata the todo parser removes:
    /// 📅-prefixed dates, priority emojis (⏫🔼🔽), and `#tag` suffixes.
    /// Kept private so the stripping rules stay in sync with the parser.
    private static func stripTaskMetadata(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: "📅\\s*\\d{4}-\\d{2}-\\d{2}(?:T\\d{2}:\\d{2})?",
            with: "", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "[⏫🔼🔽]", with: "", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "#[\\w/]+", with: "", options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Flip `[ ]`/`[x]` on the first line that matches `itemTitle` via
    /// `isCheckboxLine`. Returns the updated content, or nil if no match.
    public static func toggleCheckbox(in content: String, matching itemTitle: String) -> String? {
        var lines = content.components(separatedBy: "\n")
        for i in lines.indices {
            guard isCheckboxLine(lines[i], forTitle: itemTitle) else { continue }
            if let r = lines[i].range(of: "[ ]") {
                lines[i].replaceSubrange(r, with: "[x]")
                return lines.joined(separator: "\n")
            }
            if let r = lines[i].range(of: "[x]") ?? lines[i].range(of: "[X]") {
                lines[i].replaceSubrange(r, with: "[ ]")
                return lines.joined(separator: "\n")
            }
        }
        return nil
    }

    /// Rewrite the first checkbox line matching `originalTitle` with the latest
    /// values from `item` (completed marker, title, due date, priority, tags).
    public static func updateCheckbox(in content: String, matching originalTitle: String, with item: Item) -> String? {
        var lines = content.components(separatedBy: "\n")
        for i in lines.indices {
            guard isCheckboxLine(lines[i], forTitle: originalTitle) else { continue }
            let line = lines[i]
            let pattern = "^(\\s*[-*]\\s+)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let prefixRange = Range(match.range(at: 1), in: line) else {
                return nil
            }
            let prefix = String(line[prefixRange])
            let checkbox = item.completed ? "[x]" : "[ ]"
            var rebuilt = "\(prefix)\(checkbox) \(normalizedCheckboxMatchTitle(item.title))"

            if case .text(let p) = item.properties["priority"] {
                let emoji: String
                switch p.lowercased() {
                case "high", "p1": emoji = "⏫"
                case "medium", "p2": emoji = "🔼"
                case "low", "p3", "p4": emoji = "🔽"
                default: emoji = ""
                }
                if !emoji.isEmpty { rebuilt += " \(emoji)" }
            }
            if case .date(let d) = item.properties["dueDate"] {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withFullDate]
                rebuilt += " 📅 \(fmt.string(from: d))"
            }
            for tag in item.tags {
                rebuilt += " #\(tag)"
            }

            lines[i] = rebuilt
            return lines.joined(separator: "\n")
        }
        return nil
    }

    /// Remove the first checkbox line matching `itemTitle` via `isCheckboxLine`.
    /// Returns the updated content, or nil if no match.
    public static func deleteCheckbox(in content: String, matching itemTitle: String) -> String? {
        var lines = content.components(separatedBy: "\n")
        for i in lines.indices {
            if isCheckboxLine(lines[i], forTitle: itemTitle) {
                lines.remove(at: i)
                return lines.joined(separator: "\n")
            }
        }
        return nil
    }

    // MARK: - YAML frontmatter editing

    /// Locate the closing `---` of a frontmatter block, given the lines array.
    /// Returns nil if the content does not begin with a well-formed frontmatter.
    private static func frontmatterRange(_ lines: [String]) -> Range<Int>? {
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                return 1..<i
            }
        }
        return nil
    }

    /// Set (or insert) `completed: true|false` in the frontmatter. Returns
    /// updated content, or nil if the frontmatter is malformed.
    public static func toggleYAMLCompleted(in content: String, to completed: Bool) -> String? {
        var lines = content.components(separatedBy: "\n")
        guard let range = frontmatterRange(lines) else { return nil }

        let newValue = completed ? "true" : "false"
        for i in range {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("completed:") {
                lines[i] = "completed: \(newValue)"
                return lines.joined(separator: "\n")
            }
        }
        // Not found — insert just before the closing ---
        lines.insert("completed: \(newValue)", at: range.upperBound)
        return lines.joined(separator: "\n")
    }

    /// Update title / tags / completed in the frontmatter block. Returns the
    /// updated content, or nil if the frontmatter is malformed.
    public static func updateYAMLItem(in content: String, item: Item) -> String? {
        let lines = content.components(separatedBy: "\n")
        guard let range = frontmatterRange(lines) else { return nil }

        var frontmatter: [String] = ["---"]
        frontmatter.append("type: \(yamlQuote(item.type))")
        frontmatter.append("title: \(yamlQuote(item.title))")
        if item.tags.isEmpty {
            frontmatter.append("tags: []")
        } else {
            frontmatter.append("tags: [\(item.tags.map { yamlQuote($0) }.joined(separator: ", "))]")
        }
        frontmatter.append("completed: \(item.completed)")

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withFullDate]
        // Keep a stable key order so YAML diffs remain deterministic.
        for (key, value) in item.properties.sorted(by: { $0.key < $1.key }) {
            if key == "type" || key == "title" || key == "tags" || key == "completed" { continue }
            switch value {
            case .text(let t):
                frontmatter.append("\(key): \(yamlQuote(t))")
            case .number(let n):
                frontmatter.append(n.truncatingRemainder(dividingBy: 1) == 0
                                   ? "\(key): \(Int(n))"
                                   : "\(key): \(n)")
            case .date(let d):
                frontmatter.append("\(key): \(isoFull.string(from: d))")
            case .bool(let b):
                frontmatter.append("\(key): \(b)")
            }
        }
        frontmatter.append("---")

        let bodyStart = range.upperBound + 1 // skip closing ---
        let body = bodyStart < lines.count ? Array(lines[bodyStart...]) : []
        return (frontmatter + body).joined(separator: "\n")
    }
}
