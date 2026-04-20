import Foundation
import Core

/// App-layer bridge that lets `ChatToolRunner` (a Core actor) create notes via
/// `AppState`. Main-actor-isolated so every mutation of `AppState.items` /
/// `.errorMessage` happens on the main actor — no `@unchecked Sendable`.
@MainActor
struct AppNoteCreator: NoteCreating {
    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func createNote(
        type: String,
        title: String,
        tags: [String],
        stringProperties: [String: String]
    ) async throws -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw NoteCreateError.missingTitle }

        let normalisedType = type.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalisedType.isEmpty else { throw NoteCreateError.invalidType }

        let properties = Self.convertProperties(stringProperties)

        if normalisedType == "todo" {
            return try await appState.createTodo(
                title: trimmedTitle, tags: tags, properties: properties
            )
        } else {
            return try await appState.createYAMLItem(
                type: normalisedType,
                title: trimmedTitle,
                tags: tags,
                properties: properties
            )
        }
    }

    // MARK: - Helpers

    static func convertProperties(_ raw: [String: String]) -> [String: PropertyValue] {
        var result: [String: PropertyValue] = [:]
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let dateOnlyFormatter = ISO8601DateFormatter()
        dateOnlyFormatter.formatOptions = [.withFullDate]

        for (key, value) in raw {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let date = dateFormatter.date(from: trimmed) ?? dateOnlyFormatter.date(from: trimmed) {
                result[key] = .date(date)
            } else if let number = Double(trimmed) {
                result[key] = .number(number)
            } else if trimmed.lowercased() == "true" {
                result[key] = .bool(true)
            } else if trimmed.lowercased() == "false" {
                result[key] = .bool(false)
            } else {
                result[key] = .text(trimmed)
            }
        }
        return result
    }
}

enum NoteCreateError: LocalizedError {
    case missingTitle
    case invalidType

    var errorDescription: String? {
        switch self {
        case .missingTitle: return "A title is required."
        case .invalidType:  return "A type is required (e.g. 'todo', 'book', 'note')."
        }
    }
}
