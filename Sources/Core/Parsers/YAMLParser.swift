import Foundation

/// Error types for parsing operations
public enum ParseError: Error, Equatable {
    case invalidYAML(String)
    case missingRequiredField(String)
    case invalidFieldType(String, expected: String, got: String)
}

/// Protocol for parsing frontmatter from markdown
public protocol FrontmatterParser {
    func extractFrontmatter(from content: String) -> (yaml: String?, body: String)
    func parseListType(yaml: String) -> Result<ListType, ParseError>
    func parseView(yaml: String) -> Result<SavedView, ParseError>
    func parseItemProperties(yaml: String) -> Result<[String: PropertyValue], ParseError>
}

/// Simple YAML frontmatter parser for markdown files
public class YAMLFrontmatterParser: FrontmatterParser {

    public init() {}

    /// Extracts YAML frontmatter from markdown content
    public func extractFrontmatter(from content: String) -> (yaml: String?, body: String) {
        let lines = content.components(separatedBy: .newlines)

        // Frontmatter must start at the beginning
        guard lines.count > 0, lines[0] == "---" else {
            return (nil, content)
        }

        // Find closing delimiter
        for i in 1..<lines.count {
            if lines[i] == "---" {
                let yaml = lines[1..<i].joined(separator: "\n")
                let body = lines[(i + 1)...].joined(separator: "\n")
                return (yaml, body)
            }
        }

        // No closing delimiter found
        return (nil, content)
    }

    /// Parses YAML into a ListType definition
    public func parseListType(yaml: String) -> Result<ListType, ParseError> {
        do {
            guard let name = parseStringField(yaml, field: "name") else {
                return .failure(.missingRequiredField("name"))
            }

            let fields = parseFieldDefinitions(yaml)
            let prompt = parseStringField(yaml, field: "llmExtractionPrompt")

            let listType = ListType(
                name: name,
                fields: fields,
                llmExtractionPrompt: prompt
            )

            return .success(listType)
        }
    }

    /// Parses YAML into a SavedView definition
    public func parseView(yaml: String) -> Result<SavedView, ParseError> {
        do {
            guard let name = parseStringField(yaml, field: "name") else {
                return .failure(.missingRequiredField("name"))
            }

            let displayStyleStr = parseStringField(yaml, field: "display_style") ?? "list"
            guard let displayStyle = DisplayStyle(rawValue: displayStyleStr) else {
                return .failure(.invalidFieldType("display_style", expected: "list|card", got: displayStyleStr))
            }

            let filters = parseViewFilters(yaml)

            let view = SavedView(
                name: name,
                filters: filters,
                displayStyle: displayStyle
            )

            return .success(view)
        }
    }

    /// Parses YAML into Item properties dictionary
    public func parseItemProperties(yaml: String) -> Result<[String: PropertyValue], ParseError> {
        var properties: [String: PropertyValue] = [:]

        // Parse all fields that aren't metadata
        let lines = yaml.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("type:") {
                continue
            }

            // Parse key: value pairs
            if let (key, value) = parseKeyValue(line) {
                if let propertyValue = parsePropertyValue(value) {
                    properties[key] = propertyValue
                }
            }
        }

        return .success(properties)
    }

    // MARK: - Helper Methods

    private func parseStringField(_ yaml: String, field: String) -> String? {
        let lines = yaml.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(field):") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count > 1 {
                    let value = parts[1...].joined(separator: ":")
                        .trimmingCharacters(in: .whitespaces)
                    // Treat `title:` with no value as absent, not as the empty
                    // string — an empty title is always a caller bug and
                    // should not round-trip through the system.
                    return value.isEmpty ? nil : value
                }
            }
        }

        return nil
    }

    private func parseNumberField(_ yaml: String, field: String) -> Double? {
        guard let stringValue = parseStringField(yaml, field: field) else {
            return nil
        }
        return Double(stringValue)
    }

    private func parseBoolField(_ yaml: String, field: String) -> Bool? {
        guard let stringValue = parseStringField(yaml, field: field) else {
            return nil
        }
        return stringValue.lowercased() == "true"
    }

    private func parseFieldDefinitions(_ yaml: String) -> [FieldDefinition] {
        var fields: [FieldDefinition] = []
        let lines = yaml.components(separatedBy: .newlines)

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Look for field list start
            if trimmed.hasPrefix("fields:") || trimmed == "fields:" {
                i += 1
                while i < lines.count {
                    let fieldLine = lines[i]
                    let fieldTrimmed = fieldLine.trimmingCharacters(in: .whitespaces)

                    // Check for list item
                    if fieldTrimmed.hasPrefix("- name:") {
                        var fieldDef: (name: String, type: String, required: Bool, min: Double?, max: Double?) = ("", "", false, nil, nil)

                        // Extract name
                        if let name = extractListItemValue(fieldLine) {
                            fieldDef.name = name
                        }

                        // Look ahead for type, required, min, max
                        i += 1
                        while i < lines.count {
                            let nextLine = lines[i]
                            let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)

                            if nextTrimmed.hasPrefix("type:") {
                                if let type = extractKeyValue(nextLine, key: "type") {
                                    fieldDef.type = type
                                }
                            } else if nextTrimmed.hasPrefix("required:") {
                                if let req = extractKeyValue(nextLine, key: "required") {
                                    fieldDef.required = req.lowercased() == "true"
                                }
                            } else if nextTrimmed.hasPrefix("min:") {
                                if let min = extractKeyValue(nextLine, key: "min"), let minVal = Double(min) {
                                    fieldDef.min = minVal
                                }
                            } else if nextTrimmed.hasPrefix("max:") {
                                if let max = extractKeyValue(nextLine, key: "max"), let maxVal = Double(max) {
                                    fieldDef.max = maxVal
                                }
                            } else if nextTrimmed.hasPrefix("- ") {
                                // Next list item
                                break
                            } else if nextTrimmed.isEmpty || !nextLine.hasPrefix("  ") {
                                // End of this field
                                i += 1
                                break
                            }

                            i += 1
                        }

                        if !fieldDef.name.isEmpty, !fieldDef.type.isEmpty {
                            if let fieldType = FieldType(rawValue: fieldDef.type) {
                                let field = FieldDefinition(
                                    name: fieldDef.name,
                                    type: fieldType,
                                    required: fieldDef.required,
                                    min: fieldDef.min,
                                    max: fieldDef.max
                                )
                                fields.append(field)
                            }
                        }

                        continue
                    }

                    i += 1
                }

                break
            }

            i += 1
        }

        return fields
    }

    private func parseViewFilters(_ yaml: String) -> ViewFilters {
        var tags: [String]?
        var itemTypes: [String]?
        var dueBefore: Date?
        var dueAfter: Date?
        var completed: Bool?
        var folders: [String]?

        let lines = yaml.components(separatedBy: .newlines)

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("filters:") {
                i += 1
                while i < lines.count {
                    let filterLine = lines[i]
                    let filterTrimmed = filterLine.trimmingCharacters(in: .whitespaces)

                    if filterTrimmed.hasPrefix("tags:") {
                        if let tagsList = extractArrayValue(filterLine) {
                            tags = tagsList
                        }
                    } else if filterTrimmed.hasPrefix("item_types:") {
                        if let typesList = extractArrayValue(filterLine) {
                            itemTypes = typesList
                        }
                    } else if filterTrimmed.hasPrefix("completed:") {
                        if let comp = extractKeyValue(filterLine, key: "completed") {
                            completed = comp.lowercased() == "true"
                        }
                    } else if filterTrimmed.hasPrefix("folders:") {
                        if let folderList = extractArrayValue(filterLine) {
                            folders = folderList
                        }
                    } else if filterTrimmed.hasPrefix("due_before:") {
                        if let dateStr = extractKeyValue(filterLine, key: "due_before") {
                            dueBefore = parseRelativeOrAbsoluteDate(dateStr)
                        }
                    } else if filterTrimmed.hasPrefix("due_after:") {
                        if let dateStr = extractKeyValue(filterLine, key: "due_after") {
                            dueAfter = parseRelativeOrAbsoluteDate(dateStr)
                        }
                    } else if !filterTrimmed.isEmpty && !filterLine.hasPrefix("  ") {
                        break
                    }

                    i += 1
                }

                break
            }

            i += 1
        }

        return ViewFilters(
            tags: tags,
            itemTypes: itemTypes,
            dueBefore: dueBefore,
            dueAfter: dueAfter,
            completed: completed,
            folders: folders
        )
    }

    private func parseKeyValue(_ line: String) -> (key: String, value: String)? {
        let parts = line.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }

        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)

        return (key, value)
    }

    private func extractKeyValue(_ line: String, key: String) -> String? {
        if let (lineKey, value) = parseKeyValue(line), lineKey == key {
            return value
        }
        return nil
    }

    private func extractListItemValue(_ line: String) -> String? {
        let pattern = "- \(NSRegularExpression.escapedPattern(for: "name")): (.+)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if let valueRange = Range(match.range(at: 1), in: line) {
                    return String(line[valueRange])
                }
            }
        }
        return nil
    }

    private func extractArrayValue(_ line: String) -> [String]? {
        // Parse [item1, item2, item3] format
        if let start = line.firstIndex(of: "["), let end = line.lastIndex(of: "]") {
            let arrayStr = String(line[line.index(after: start)..<end])
            let items = arrayStr.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                .filter { !$0.isEmpty }
            return items.isEmpty ? nil : items
        }
        return nil
    }

    private func parsePropertyValue(_ value: String) -> PropertyValue? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Try to parse as number
        if let number = Double(trimmed) {
            return .number(number)
        }

        // Try to parse as boolean
        if trimmed.lowercased() == "true" {
            return .bool(true)
        } else if trimmed.lowercased() == "false" {
            return .bool(false)
        }

        // Try to parse as date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: trimmed) {
            return .date(date)
        }

        // Default to text
        return .text(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
    }

    private func parseRelativeOrAbsoluteDate(_ dateStr: String) -> Date? {
        let trimmed = dateStr.trimmingCharacters(in: .whitespaces)

        // Try relative date format (+7d, -30d, etc.)
        if let date = parseRelativeDate(trimmed) {
            return date
        }

        // Try absolute date format (YYYY-MM-DD)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: trimmed) {
            return date
        }

        return nil
    }

    private func parseRelativeDate(_ dateStr: String) -> Date? {
        let pattern = "([+-])(\\d+)([dwmy])"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(dateStr.startIndex..., in: dateStr)
            if let match = regex.firstMatch(in: dateStr, range: range) {
                let signRange = Range(match.range(at: 1), in: dateStr)
                let numberRange = Range(match.range(at: 2), in: dateStr)
                let unitRange = Range(match.range(at: 3), in: dateStr)

                guard let signRange = signRange, let numberRange = numberRange, let unitRange = unitRange else {
                    return nil
                }

                let sign = String(dateStr[signRange])
                let number = Int(dateStr[numberRange]) ?? 0
                let unit = String(dateStr[unitRange])

                let multiplier = sign == "+" ? 1 : -1
                var dateComponent = DateComponents()

                switch unit {
                case "d":
                    dateComponent.day = multiplier * number
                case "w":
                    dateComponent.day = multiplier * (number * 7)
                case "m":
                    dateComponent.month = multiplier * number
                case "y":
                    dateComponent.year = multiplier * number
                default:
                    return nil
                }

                let calendar = Calendar.current
                return calendar.date(byAdding: dateComponent, to: Date())
            }
        }

        return nil
    }
}
