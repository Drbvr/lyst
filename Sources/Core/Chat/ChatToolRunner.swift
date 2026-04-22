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
    private let todoItems: [Item]

    public init(
        index: NoteIndex,
        fileSystem: FileSystemManager,
        webFetcher: WebContentFetcher = WebContentFetcher(),
        todoItems: [Item] = []
    ) {
        self.index = index
        self.fileSystem = fileSystem
        self.parser = ObsidianTodoParser()
        self.webFetcher = webFetcher
        self.todoItems = todoItems
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

        case "query_todos":
            let scope = args["scope"] as? String
            let priority = args["priority"] as? String
            let tag = args["tag"] as? String
            let project = args["project"] as? String
            let limit = args["limit"] as? Int
            let r = runQueryTodos(scope: scope, priority: priority, tag: tag, project: project, limit: limit)
            return (r, [], [])

        case "update_todos":
            guard let ids = args["ids"] as? [String] else {
                return (errorJSON("missing_argument", "update_todos requires 'ids'"), [], [])
            }
            let dueDate = args["dueDate"] as? String
            let priority = args["priority"] as? String
            let addTags = args["addTags"] as? [String]
            let completed = args["completed"] as? Bool
            let r = runUpdateTodos(ids: ids, dueDate: dueDate, priority: priority, addTags: addTags, completed: completed)
            return (r, [], [])

        case "break_down_task":
            guard let todoId = args["todo_id"] as? String,
                  let subtasks = args["subtasks"] as? [String] else {
                return (errorJSON("missing_argument", "break_down_task requires 'todo_id' and 'subtasks'"), [], [])
            }
            let r = runBreakDownTask(todoId: todoId, subtasks: subtasks)
            return (r, [], [])

        case "extract_todos_from_note":
            guard let noteFile = args["note_file"] as? String else {
                return (errorJSON("missing_argument", "extract_todos_from_note requires 'note_file'"), [], [])
            }
            let (r, drafts) = runExtractTodosFromNote(noteFile: noteFile)
            return (r, [], drafts)

        case "plan_my_day":
            let date = args["date"] as? String
            let start = args["start"] as? String
            let r = await runPlanMyDay(date: date, start: start)
            return (r, [], [])

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

    // MARK: - Todo tools

    private func runQueryTodos(scope: String?, priority: String?, tag: String?, project: String?, limit: Int?) -> String {
        var filtered = todoItems.filter { $0.type == "todo" }

        // Scope filters
        if let scope = scope {
            let now = Date()
            let calendar = Calendar.current
            switch scope {
            case "today":
                let start = calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
                filtered = filtered.filter { item in
                    if let due = Self.extractDateProperty(item.properties["dueDate"]),
                       let parsed = Self.parseISO8601Date(due) {
                        return parsed >= start && parsed < end && !item.completed
                    }
                    return false
                }
            case "upcoming":
                filtered = filtered.filter { item in
                    if let due = Self.extractDateProperty(item.properties["dueDate"]),
                       let parsed = Self.parseISO8601Date(due) {
                        return parsed >= now && !item.completed
                    }
                    return false
                }
            case "overdue":
                filtered = filtered.filter { item in
                    if let due = Self.extractDateProperty(item.properties["dueDate"]),
                       let parsed = Self.parseISO8601Date(due) {
                        return parsed < now && !item.completed
                    }
                    return false
                }
            case "inbox":
                // Inbox = items without a due date
                filtered = filtered.filter { $0.properties["dueDate"] == nil }
            case "all":
                break
            default:
                break
            }
        }

        // Priority filter
        if let priority = priority {
            filtered = filtered.filter { Self.extractTextProperty($0.properties["priority"]) == priority }
        }

        // Tag filter (exact match)
        if let tag = tag {
            filtered = filtered.filter { $0.tags.contains(tag) }
        }

        // Project filter (top-level tag)
        if let project = project {
            filtered = filtered.filter { $0.tags.contains { $0.hasPrefix(project) } }
        }

        let maxLimit = min(limit ?? 20, 100)
        let results = filtered.prefix(maxLimit).map { item -> [String: Any] in
            var dict: [String: Any] = [
                "id": item.id.uuidString,
                "title": item.title,
                "completed": item.completed,
                "tags": item.tags
            ]
            if let due = Self.extractDateProperty(item.properties["dueDate"]) {
                dict["dueDate"] = due
            }
            if let pri = Self.extractTextProperty(item.properties["priority"]) {
                dict["priority"] = pri
            }
            return dict
        }
        return json(["todos": Array(results), "count": results.count])
    }

    private func runUpdateTodos(ids: [String], dueDate: String?, priority: String?, addTags: [String]?, completed: Bool?) -> String {
        var updated: [String] = []
        for idStr in ids {
            if let uuid = UUID(uuidString: idStr),
               let idx = todoItems.firstIndex(where: { $0.id == uuid }) {
                updated.append(idStr)
            }
        }
        // Return proposed update (actual mutations happen in AppState with user confirmation)
        var changes: [String: Any] = [:]
        if let dueDate = dueDate { changes["dueDate"] = dueDate }
        if let priority = priority { changes["priority"] = priority }
        if let addTags = addTags { changes["addTags"] = addTags }
        if let completed = completed { changes["completed"] = completed }

        return json([
            "proposed_updates": true,
            "ids": updated,
            "changes": changes,
            "detail": "Proposed updates for \(updated.count) todos. User confirmation required."
        ])
    }

    private func runBreakDownTask(todoId: String, subtasks: [String]) -> String {
        if let uuid = UUID(uuidString: todoId),
           let _ = todoItems.first(where: { $0.id == uuid }) {
            return json([
                "proposed": true,
                "todo_id": todoId,
                "subtasks": subtasks,
                "detail": "Proposed \(subtasks.count) subtasks. User confirmation to append to todo required."
            ])
        }
        return errorJSON("todo_not_found", "Could not find todo with id '\(todoId)'")
    }

    private func runExtractTodosFromNote(noteFile: String) -> (String, [NoteEdit]) {
        guard case .success(let content) = fileSystem.readFile(at: noteFile) else {
            return (errorJSON("note_not_found", "Could not read file: \(noteFile)"), [])
        }

        // Extract lines that look like todos: checkboxes, action verbs, bullet lists
        var proposed: [NoteEdit] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Check for markdown checkbox: - [ ] or - [x]
            if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") {
                let title = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    proposed.append(NoteEdit(
                        type: "todo",
                        title: String(title),
                        properties: [:],
                        tags: []
                    ))
                }
            }
        }

        if proposed.isEmpty {
            return (json(["extracted": false, "detail": "No todos found in note"]), [])
        }

        return (json([
            "extracted": true,
            "count": proposed.count,
            "detail": "Extracted \(proposed.count) todo(s) from note. Review and save in draft cards."
        ]), proposed)
    }

    private func runPlanMyDay(date: String?, start: String?) async -> String {
        let targetDate: Date
        if let dateStr = date {
            targetDate = Self.parseISO8601Date(dateStr) ?? Date()
        } else {
            targetDate = Date()
        }

        let startTime: Date
        if let startStr = start {
            startTime = Self.parseISO8601Time(startStr) ?? Date()
        } else {
            let calendar = Calendar.current
            var comps = calendar.dateComponents([.year, .month, .day], from: targetDate)
            comps.hour = 9
            comps.minute = 0
            startTime = calendar.date(from: comps) ?? Date()
        }

        // Filter todos due today, sort by priority
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: targetDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? targetDate

        var todayTodos = todoItems.filter { item in
            if item.type != "todo" || item.completed { return false }
            if let due = Self.extractDateProperty(item.properties["dueDate"]),
               let parsed = Self.parseISO8601Date(due) {
                return parsed >= dayStart && parsed < dayEnd
            }
            return false
        }

        // Sort by priority (p1, p2, p3, p4)
        let priorityOrder = ["p1": 0, "p2": 1, "p3": 2, "p4": 3]
        todayTodos.sort { a, b in
            let aPri = priorityOrder[Self.extractTextProperty(a.properties["priority"]) ?? "p4"] ?? 4
            let bPri = priorityOrder[Self.extractTextProperty(b.properties["priority"]) ?? "p4"] ?? 4
            return aPri < bPri
        }

        // Time-box: estimate 30 min per todo, adjust for priority
        var slots: [[String: Any]] = []
        var currentTime = startTime
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        for (idx, todo) in todayTodos.prefix(10).enumerated() {
            let durationMins = Self.extractTextProperty(todo.properties["priority"]) == "p1" ? 45 : 30
            let timeStr = timeFormatter.string(from: currentTime)
            slots.append([
                "startTime": timeStr,
                "title": todo.title,
                "todoId": todo.id.uuidString,
                "durationMinutes": durationMins
            ])
            currentTime = calendar.date(byAdding: .minute, value: durationMins, to: currentTime) ?? currentTime
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: targetDate)

        return json([
            "date": dateStr,
            "slots": slots,
            "count": slots.count
        ])
    }

    // MARK: - Helpers

    private static func extractTextProperty(_ value: PropertyValue?) -> String? {
        guard let value = value else { return nil }
        if case .text(let str) = value { return str }
        return nil
    }

    private static func extractDateProperty(_ value: PropertyValue?) -> String? {
        guard let value = value else { return nil }
        if case .text(let str) = value { return str }
        if case .date(let date) = value {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return formatter.string(from: date)
        }
        return nil
    }

    private static func parseISO8601Date(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: str)
    }

    private static func parseISO8601Time(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullTime, .withTimeZone]
        return formatter.date(from: str)
    }

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
