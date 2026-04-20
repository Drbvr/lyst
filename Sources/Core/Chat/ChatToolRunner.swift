import Foundation

private let maxResultBytes = 8_000

/// App-layer bridge for saving drafts. Used by the chat view model once the
/// user approves a proposed draft — not by `ChatToolRunner`, which is pure.
public protocol NoteCreating: Sendable {
    /// Create a note of the given `type` in the vault. Returns the resulting
    /// note's file path on success, or throws with a human-readable reason.
    func createNote(type: String, title: String, tags: [String], stringProperties: [String: String]) async throws -> String
}

/// Executes chat tool calls against the NoteIndex and file system.
/// Returns a JSON string result, any NoteRefs cited, and any note drafts
/// produced (for `propose_note`).
public actor ChatToolRunner {

    private let index: NoteIndex
    private let fileSystem: FileSystemManager
    private let parser: ObsidianTodoParser
    private let webFetcher: WebContentFetcher

    public init(
        index: NoteIndex,
        fileSystem: FileSystemManager,
        webFetcher: WebContentFetcher = WebContentFetcher()
    ) {
        self.index = index
        self.fileSystem = fileSystem
        self.parser = ObsidianTodoParser()
        self.webFetcher = webFetcher
    }

    // MARK: - Dispatch

    public func run(name: String, argumentsJSON: String) async -> (result: String, refs: [NoteRef], drafts: [NoteEdit]) {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return (errorJSON("invalid_arguments", "Could not parse tool arguments"), [], [])
        }

        switch name {
        case "search_notes":
            let query = args["query"] as? String ?? ""
            let limit = args["max_results"] as? Int ?? 20
            let mode = args["output_mode"] as? String ?? "snippets"
            let (r, refs) = await runSearchNotes(SearchNotesArgs(query: query, maxResults: limit, outputMode: mode))
            return (r, refs, [])

        case "list_notes":
            let (r, refs) = await runListNotes(ListNotesArgs(
                folder: args["folder"] as? String,
                tag: args["tag"] as? String,
                limit: args["limit"] as? Int
            ))
            return (r, refs, [])

        case "read_note":
            guard let file = args["note_file"] as? String else {
                return (errorJSON("missing_argument", "note_file is required"), [], [])
            }
            let (r, refs) = await runReadNote(ReadNoteArgs(
                noteFile: file,
                offset: args["offset"] as? Int,
                limit: args["limit"] as? Int
            ))
            return (r, refs, [])

        case "outline_note":
            guard let file = args["note_file"] as? String else {
                return (errorJSON("missing_argument", "note_file is required"), [], [])
            }
            let (r, refs) = await runOutlineNote(OutlineNoteArgs(noteFile: file))
            return (r, refs, [])

        case "list_recent_notes":
            let (r, refs) = await runListRecentNotes(ListRecentNotesArgs(
                withinHours: args["within_hours"] as? Int,
                limit: args["limit"] as? Int
            ))
            return (r, refs, [])

        case "propose_note":
            guard let type = args["type"] as? String, let title = args["title"] as? String else {
                return (errorJSON("missing_argument", "propose_note requires 'type' and 'title'"), [], [])
            }
            let tags = (args["tags"] as? [String]) ?? []
            let props = (args["properties"] as? [String: Any]) ?? [:]
            let stringProps = props.reduce(into: [String: String]()) { acc, pair in
                acc[pair.key] = String(describing: pair.value)
            }
            return runProposeNote(ProposeNoteArgs(type: type, title: title, tags: tags, properties: stringProps))

        case "web_fetch":
            guard let url = args["url"] as? String else {
                return (errorJSON("missing_argument", "web_fetch requires 'url'"), [], [])
            }
            let (r, refs) = await runWebFetch(WebFetchArgs(url: url))
            return (r, refs, [])

        default:
            return (errorJSON("unknown_tool", "No tool named '\(name)'"), [], [])
        }
    }

    /// Convenience for AppleIntelligenceProvider's typed tool structs. Returns
    /// the JSON result and any drafts produced; call sites that don't need
    /// drafts can ignore the tuple's second element.
    public func runRaw<A>(name: String, args: A) async -> (result: String, drafts: [NoteEdit]) where A: Sendable {
        switch args {
        case let a as SearchNotesArgs:
            return (await runSearchNotes(a).0, [])
        case let a as ListNotesArgs:
            return (await runListNotes(a).0, [])
        case let a as ReadNoteArgs:
            return (await runReadNote(a).0, [])
        case let a as OutlineNoteArgs:
            return (await runOutlineNote(a).0, [])
        case let a as ListRecentNotesArgs:
            return (await runListRecentNotes(a).0, [])
        case let a as ProposeNoteArgs:
            let out = runProposeNote(a)
            return (out.0, out.2)
        case let a as WebFetchArgs:
            return (await runWebFetch(a).0, [])
        default:
            return (errorJSON("unsupported_args", "Unrecognised argument type"), [])
        }
    }

    // MARK: - Tool implementations

    private func runSearchNotes(_ args: SearchNotesArgs) async -> (String, [NoteRef]) {
        let limit = min(args.maxResults ?? 20, 50)
        let results = await index.searchNotes(query: args.query, limit: limit)

        if results.isEmpty {
            return (json(["results": [], "count": 0]), [])
        }

        let refs = results.map { NoteRef(file: $0.noteFile) }
        let mode = args.outputMode ?? "snippets"

        switch mode {
        case "count":
            return (json(["count": results.count]), refs)
        case "ids_only":
            let ids = results.map { ["file": $0.noteFile, "title": $0.noteTitle] }
            return (truncated(json(["results": ids, "count": results.count])), refs)
        default: // "snippets"
            let items = results.map { r -> [String: Any] in
                [
                    "file": r.noteFile,
                    "title": r.noteTitle,
                    "match_count": r.matchCount,
                    "snippets": r.snippets
                ]
            }
            return (truncated(json(["results": items, "count": results.count])), refs)
        }
    }

    private func runListNotes(_ args: ListNotesArgs) async -> (String, [NoteRef]) {
        let limit = min(args.limit ?? 50, 200)
        let rows = await index.listNotes(
            folder: args.folder,
            tags: args.tag.map { [$0] } ?? [],
            limit: limit
        )
        let refs = rows.map { NoteRef(file: $0.file) }
        let items = rows.map { r -> [String: Any] in
            ["file": r.file, "title": r.title, "folder": r.folder,
             "tags": r.tags, "mtime": r.mtime]
        }
        return (truncated(json(["notes": items, "count": rows.count])), refs)
    }

    private func runReadNote(_ args: ReadNoteArgs) async -> (String, [NoteRef]) {
        let file = args.noteFile
        guard case .success(let content) = fileSystem.readFile(at: file) else {
            return (errorJSON("note_not_found", "Could not read file: \(file)"), [])
        }

        let offset = args.offset ?? 0
        let maxChars = args.limit ?? 4_000
        let scalars = content.unicodeScalars
        let totalChars = scalars.count

        guard offset < totalChars else {
            return (json(["content": "", "truncated": false, "total_chars": totalChars]), [NoteRef(file: file)])
        }

        let startIdx = scalars.index(scalars.startIndex, offsetBy: offset, limitedBy: scalars.endIndex) ?? scalars.endIndex
        let end = min(offset + maxChars, totalChars)
        let endIdx = scalars.index(startIdx, offsetBy: end - offset, limitedBy: scalars.endIndex) ?? scalars.endIndex
        let slice = String(String.UnicodeScalarView(scalars[startIdx..<endIdx]))
        let truncated = end < totalChars

        var result: [String: Any] = [
            "file": file,
            "content": slice,
            "truncated": truncated,
            "offset": offset,
            "total_chars": totalChars
        ]

        // Append outline of remainder when truncated
        if truncated {
            let remainder = String(String.UnicodeScalarView(scalars[endIdx...]))
            let headings = parser.extractHeadings(from: remainder)
            let outline = headings.prefix(20).map { h -> [String: Any] in
                ["level": h.level, "heading": h.text, "approx_offset": end + (h.startLine * 80)]
            }
            result["outline_of_rest"] = outline
        }

        return (json(result), [NoteRef(file: file, startLine: 0)])
    }

    private func runOutlineNote(_ args: OutlineNoteArgs) async -> (String, [NoteRef]) {
        let file = args.noteFile
        guard case .success(let content) = fileSystem.readFile(at: file) else {
            return (errorJSON("note_not_found", "Could not read file: \(file)"), [])
        }

        let headings = parser.extractHeadings(from: content)
        let wordCount = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count

        let headingList = headings.map { h -> [String: Any] in
            ["level": h.level, "text": h.text, "start_line": h.startLine]
        }

        let row = await index.getNote(file: file)
        let result: [String: Any] = [
            "file": file,
            "title": row?.title ?? URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent,
            "word_count": wordCount,
            "headings": headingList
        ]
        return (json(result), [NoteRef(file: file)])
    }

    private func runProposeNote(_ args: ProposeNoteArgs) -> (String, [NoteRef], [NoteEdit]) {
        let properties: [String: PropertyValue] = args.properties.reduce(into: [:]) { acc, pair in
            acc[pair.key] = .text(pair.value)
        }
        let draft = NoteEdit(
            type: args.type,
            title: args.title,
            properties: properties,
            tags: args.tags
        )
        let result = json([
            "proposed": true,
            "draft_id": draft.id.uuidString,
            "title": args.title,
            "type": args.type
        ])
        return (result, [], [draft])
    }

    private func runWebFetch(_ args: WebFetchArgs) async -> (String, [NoteRef]) {
        guard let validated = Self.validatedWebFetchURL(from: args.url) else {
            return (errorJSON("invalid_url", "Only http/https URLs with a public host are supported."), [])
        }
        do {
            let text = try await webFetcher.fetchText(from: validated.absoluteString)
            return (truncated(json(["url": validated.absoluteString, "text": text])), [])
        } catch {
            return (errorJSON("fetch_failed", error.localizedDescription), [])
        }
    }

    /// Restrict `web_fetch` to public http(s) hosts — no localhost, no loopback.
    public static func validatedWebFetchURL(from candidate: String) -> URL? {
        guard
            let components = URLComponents(string: candidate.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let host = components.host?.lowercased(), !host.isEmpty,
            !["localhost", "127.0.0.1", "::1"].contains(host)
        else { return nil }
        return components.url
    }

    private func runListRecentNotes(_ args: ListRecentNotesArgs) async -> (String, [NoteRef]) {
        let hours = args.withinHours ?? 168
        let limit = min(args.limit ?? 20, 50)
        let since = Date().addingTimeInterval(TimeInterval(-hours * 3600))
        let rows = await index.listNotes(updatedAfter: since, limit: limit, sortDescending: true)
        let refs = rows.map { NoteRef(file: $0.file) }
        let items = rows.map { r -> [String: Any] in
            ["file": r.file, "title": r.title, "folder": r.folder,
             "tags": r.tags, "mtime": r.mtime]
        }
        return (truncated(json(["notes": items, "count": rows.count, "within_hours": hours])), refs)
    }

    // MARK: - Helpers

    private func json(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    /// Replaces oversized results with a valid-JSON placeholder that preserves
    /// the tool output contract. Callers are expected to paginate (e.g. via
    /// `read_note` offset/limit) rather than rely on truncated mid-stream JSON.
    private func truncated(_ str: String) -> String {
        guard str.utf8.count > maxResultBytes else { return str }
        return json([
            "truncated": true,
            "original_byte_count": str.utf8.count,
            "max_result_bytes": maxResultBytes,
            "detail": "Result exceeded \(maxResultBytes) bytes. Narrow the query (smaller limit, specific folder/tag) or use read_note with offset to paginate."
        ])
    }

    private func errorJSON(_ code: String, _ detail: String) -> String {
        json(["error": code, "detail": detail])
    }
}
