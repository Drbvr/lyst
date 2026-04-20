import Foundation
import Core

/// App-layer bridge that lets `ChatToolRunner` create notes via `AppState`
/// without Core having to know about SwiftUI/AppState.
final class AppNoteCreator: NoteCreating, @unchecked Sendable {
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

        let vaultURL = await MainActor.run { appState.currentVaultURL }
        guard let vaultURL else { throw NoteCreateError.noVault }

        if normalisedType == "todo" {
            await appState.createTodo(title: trimmedTitle, tags: tags, properties: properties)
            return vaultURL.appendingPathComponent("Inbox.md").path
        } else {
            await appState.createYAMLItem(
                type: normalisedType,
                title: trimmedTitle,
                tags: tags,
                properties: properties
            )
            let folder = normalisedType.capitalized + "s"
            let safe = AppStateLogic.sanitizedFilename(from: trimmedTitle) ?? trimmedTitle
            return vaultURL
                .appendingPathComponent(folder)
                .appendingPathComponent("\(safe).md")
                .path
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
    case noVault
    case missingTitle
    case invalidType

    var errorDescription: String? {
        switch self {
        case .noVault:      return "No vault folder is selected. Pick one in Settings."
        case .missingTitle: return "A title is required."
        case .invalidType:  return "A type is required (e.g. 'todo', 'book', 'note')."
        }
    }
}
