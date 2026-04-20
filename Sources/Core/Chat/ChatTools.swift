import Foundation

// MARK: - Tool argument structs (used by ChatToolRunner and AppleIntelligenceProvider)

public struct SearchNotesArgs: Sendable {
    public let query: String
    public let maxResults: Int?
    public let outputMode: String?
    public init(query: String, maxResults: Int? = nil, outputMode: String? = nil) {
        self.query = query; self.maxResults = maxResults; self.outputMode = outputMode
    }
}

public struct ListNotesArgs: Sendable {
    public let folder: String?
    public let tag: String?
    public let limit: Int?
    public init(folder: String? = nil, tag: String? = nil, limit: Int? = nil) {
        self.folder = folder; self.tag = tag; self.limit = limit
    }
}

public struct ReadNoteArgs: Sendable {
    public let noteFile: String
    public let offset: Int?
    public let limit: Int?
    public init(noteFile: String, offset: Int? = nil, limit: Int? = nil) {
        self.noteFile = noteFile; self.offset = offset; self.limit = limit
    }
}

public struct OutlineNoteArgs: Sendable {
    public let noteFile: String
    public init(noteFile: String) { self.noteFile = noteFile }
}

public struct ListRecentNotesArgs: Sendable {
    public let withinHours: Int?
    public let limit: Int?
    public init(withinHours: Int? = nil, limit: Int? = nil) {
        self.withinHours = withinHours; self.limit = limit
    }
}

public struct CreateNoteArgs: Sendable {
    public let type: String
    public let title: String
    public let tags: [String]
    public let properties: [String: String]
    public init(type: String, title: String, tags: [String] = [], properties: [String: String] = [:]) {
        self.type = type; self.title = title; self.tags = tags; self.properties = properties
    }
}

public struct WebFetchArgs: Sendable {
    public let url: String
    public init(url: String) { self.url = url }
}

// MARK: - Tool definitions

/// Tools exposed to OpenAI-compatible endpoints. The last two (`create_note`
/// and `web_fetch`) are gated — see `GatedChatTools` — and require explicit
/// user approval before the runner executes them.
public enum ChatTools {

    public static let all: [LLMToolDefinition] = [
        listNotes, searchNotes, readNote, outlineNote, listRecentNotes,
        createNote, webFetch
    ]

    public static let searchNotes = LLMToolDefinition(
        name: "search_notes",
        description: "Search notes by text query using FTS5 full-text search. Use for specific terms or phrases.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "query": {
              "type": "string",
              "description": "Search query text or FTS5 MATCH expression"
            },
            "output_mode": {
              "type": "string",
              "enum": ["snippets", "ids_only", "count"],
              "description": "How to return results. Default: snippets"
            },
            "max_results": {
              "type": "integer",
              "description": "Maximum number of results (default 20, max 50)"
            }
          },
          "required": ["query"]
        }
        """
    )

    public static let listNotes = LLMToolDefinition(
        name: "list_notes",
        description: "List notes filtered by folder, tag, or date range. Returns metadata only.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "folder": { "type": "string", "description": "Filter to notes in this folder" },
            "tag": { "type": "string", "description": "Filter by this tag (exact match)" },
            "updated_after": { "type": "string", "description": "ISO8601 datetime lower bound on mtime" },
            "updated_before": { "type": "string", "description": "ISO8601 datetime upper bound on mtime" },
            "limit": { "type": "integer", "description": "Max results (default 50, max 200)" },
            "sort": {
              "type": "string",
              "enum": ["updated_desc", "updated_asc", "title"],
              "description": "Sort order (default updated_desc)"
            }
          },
          "required": []
        }
        """
    )

    public static let readNote = LLMToolDefinition(
        name: "read_note",
        description: "Read a note's content by file path. Returns up to 4000 characters and an outline of the rest when truncated.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "note_file": { "type": "string", "description": "Absolute file path returned by list_notes or search_notes" },
            "offset": { "type": "integer", "description": "Character offset to start reading from (default 0)" },
            "limit": { "type": "integer", "description": "Maximum characters to return (default 4000)" }
          },
          "required": ["note_file"]
        }
        """
    )

    public static let outlineNote = LLMToolDefinition(
        name: "outline_note",
        description: "Get the heading structure and word count of a note without reading its full body.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "note_file": { "type": "string", "description": "Absolute file path of the note" }
          },
          "required": ["note_file"]
        }
        """
    )

    public static let listRecentNotes = LLMToolDefinition(
        name: "list_recent_notes",
        description: "List recently modified notes. Use for temporal queries like 'what did I write about X yesterday'.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "within_hours": { "type": "integer", "description": "How many hours back to look (default 168 = 7 days)" },
            "limit": { "type": "integer", "description": "Maximum results (default 20)" }
          },
          "required": []
        }
        """
    )

    public static let createNote = LLMToolDefinition(
        name: "create_note",
        description: "Create a new note (todo, book, movie, restaurant, etc.) in the vault. Requires explicit user approval before running.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "type": {
              "type": "string",
              "description": "Item type: 'todo', 'book', 'movie', 'restaurant', 'note', etc."
            },
            "title": {
              "type": "string",
              "description": "Required title of the note"
            },
            "tags": {
              "type": "array",
              "items": { "type": "string" },
              "description": "Optional tags, e.g. ['work', 'project/alpha']"
            },
            "properties": {
              "type": "object",
              "additionalProperties": { "type": "string" },
              "description": "Optional fields specific to the type, e.g. {\\"author\\":\\"…\\",\\"rating\\":\\"4\\"}. Dates use ISO8601."
            }
          },
          "required": ["type", "title"]
        }
        """
    )

    public static let webFetch = LLMToolDefinition(
        name: "web_fetch",
        description: "Fetch the readable text of a public http(s) URL. Requires explicit user approval before running.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "url": {
              "type": "string",
              "description": "Public http or https URL to fetch"
            }
          },
          "required": ["url"]
        }
        """
    )
}
