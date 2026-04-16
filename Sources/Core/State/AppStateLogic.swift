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
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = title
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty else { return nil }
        guard !cleaned.hasPrefix("/") else { return nil }
        // Reject any path-traversal component.
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
            case "high":   emoji = "⏫"
            case "medium": emoji = "🔼"
            case "low":    emoji = "🔽"
            default:       emoji = ""
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

    /// Append a todo line to the existing inbox content, normalizing trailing
    /// newlines so the result has exactly one blank line between entries.
    public static func appendTodoToInbox(existingContent: String, line: String) -> String {
        var base = existingContent
        if !base.hasSuffix("\n") { base += "\n" }
        return base + line + "\n"
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

    /// Regex-anchored test: does `line` represent a checkbox line whose task
    /// text matches `itemTitle` exactly (up to trailing metadata like #tags or
    /// date emojis)? This is what callers should use instead of
    /// `line.contains(item.title)`, which matches "Buy" inside "Buy milk".
    public static func isCheckboxLine(_ line: String, forTitle itemTitle: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: itemTitle)
        // ^[whitespace]*[-*] [whitespace]+ \[[ xX]\] [whitespace]+ <title> ( $ | [whitespace] | # )
        let pattern = "^\\s*[-*]\\s+\\[[ xX]\\]\\s+\(escaped)(\\s|$|#)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(line.startIndex..., in: line)
        return regex.firstMatch(in: line, range: range) != nil
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
        var lines = content.components(separatedBy: "\n")
        guard let range = frontmatterRange(lines) else { return nil }
        var end = range.upperBound

        func replaceOrInsert(prefix: String, line: String) {
            for i in range.lowerBound..<end {
                if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(prefix) {
                    lines[i] = line
                    return
                }
            }
            lines.insert(line, at: end)
            end += 1
        }

        replaceOrInsert(prefix: "title:", line: "title: \(yamlQuote(item.title))")

        let tagLine: String
        if item.tags.isEmpty {
            tagLine = "tags: []"
        } else {
            tagLine = "tags: [\(item.tags.map { yamlQuote($0) }.joined(separator: ", "))]"
        }
        // Only insert `tags:` if it exists or item has tags; skip insertion when empty & absent
        var tagsFound = false
        for i in range.lowerBound..<end {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("tags:") {
                lines[i] = tagLine
                tagsFound = true
                break
            }
        }
        if !tagsFound && !item.tags.isEmpty {
            lines.insert(tagLine, at: end)
            end += 1
        }

        replaceOrInsert(prefix: "completed:", line: "completed: \(item.completed)")

        return lines.joined(separator: "\n")
    }
}
