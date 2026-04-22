import Foundation

// MARK: - Result types

public struct NoteRow: Sendable {
    public let file: String
    public let title: String
    public let mtime: TimeInterval
    public let tags: [String]
    public let folder: String

    public init(file: String, title: String, mtime: TimeInterval, tags: [String], folder: String) {
        self.file = file
        self.title = title
        self.mtime = mtime
        self.tags = tags
        self.folder = folder
    }
}

public struct SearchSnippet: Sendable {
    public let noteFile: String
    public let noteTitle: String
    public let matchCount: Int
    public let snippets: [String]

    public init(noteFile: String, noteTitle: String, matchCount: Int, snippets: [String]) {
        self.noteFile = noteFile
        self.noteTitle = noteTitle
        self.matchCount = matchCount
        self.snippets = snippets
    }
}

public struct ChunkSearchResult: Sendable {
    public let noteFile: String
    public let noteTitle: String
    public let chunkId: Int64
    public let score: Float
    public let excerpt: String
    public let startLine: Int
    public let endLine: Int

    public init(noteFile: String, noteTitle: String, chunkId: Int64, score: Float,
                excerpt: String, startLine: Int, endLine: Int) {
        self.noteFile = noteFile
        self.noteTitle = noteTitle
        self.chunkId = chunkId
        self.score = score
        self.excerpt = excerpt
        self.startLine = startLine
        self.endLine = endLine
    }
}

// MARK: - NoteIndexError

public enum NoteIndexError: Error {
    case openFailed(String)
    case migrationFailed(String)
    case notOpen
}

// MARK: - NoteIndex

#if canImport(SQLite3)
import SQLite3

/// SQLite-backed FTS5 index for notes.
/// All methods are actor-isolated — call from any async context.
public actor NoteIndex {

    private var db: OpaquePointer?
    public let dbURL: URL
    private var isOpen = false

    public init(dbURL: URL) {
        self.dbURL = dbURL
    }

    // MARK: Lifecycle

    public func open() throws {
        let path = dbURL.path
        // Create parent directory (.listapp/) if needed
        let dir = dbURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw NoteIndexError.openFailed(msg)
        }
        try runMigrations()
        isOpen = true
    }

    public func close() {
        if let db { sqlite3_close(db) }
        db = nil
        isOpen = false
    }

    // MARK: Write

    public func upsertFile(path: String, title: String, body: String, tags: [String], mtime: TimeInterval) {
        guard let db else { return }
        let tagsFlat = tags.joined(separator: " ")
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        let now = Date().timeIntervalSince1970

        exec(db, """
            INSERT INTO notes(file, title, folder, tags_flat, mtime, indexed_at)
            VALUES(?,?,?,?,?,?)
            ON CONFLICT(file) DO UPDATE SET
              title=excluded.title,
              folder=excluded.folder,
              tags_flat=excluded.tags_flat,
              mtime=excluded.mtime,
              indexed_at=excluded.indexed_at
        """, path, title, folder, tagsFlat, mtime, now)

        // Rebuild FTS5 row
        exec(db, "DELETE FROM notes_fts WHERE file=?", path)
        exec(db, "INSERT INTO notes_fts(file, title, body, tags) VALUES(?,?,?,?)",
             path, title, body, tagsFlat)
    }

    public func removeFile(path: String) {
        guard let db else { return }
        exec(db, "DELETE FROM notes WHERE file=?", path)
        exec(db, "DELETE FROM notes_fts WHERE file=?", path)
        exec(db, "DELETE FROM chunks WHERE file=?", path)
    }

    public func upsertChunks(_ chunks: [NoteChunk], forFile path: String,
                              embedding: EmbeddingProvider) {
        guard let db else { return }
        // Wrap all deletes + inserts in a transaction so the index is never
        // left in a partially-updated state if an insert fails mid-loop.
        exec(db, "BEGIN")
        // chunk_vectors has ON DELETE CASCADE on chunks.chunk_id, but cascade
        // requires foreign_keys=ON; delete vectors first explicitly to be safe.
        exec(db, "DELETE FROM chunk_vectors WHERE chunk_id IN (SELECT chunk_id FROM chunks WHERE file=?)", path)
        exec(db, "DELETE FROM chunks WHERE file=?", path)

        for chunk in chunks {
            // Parenthesise `try?` so `.flatMap` dispatches on `Data?` (Optional)
            // rather than `Data` (Sequence, where $0 would be UInt8). The latter
            // compiles on Linux Swift 5.10 but Xcode 26's compiler rejects it.
            let headingData = try? JSONSerialization.data(withJSONObject: chunk.headingPath)
            let headingJSON = headingData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            exec(db, """
                INSERT INTO chunks(file, heading_path, start_line, end_line, text)
                VALUES(?,?,?,?,?)
            """, path, headingJSON, chunk.startLine, chunk.endLine, chunk.text)

            let chunkId = sqlite3_last_insert_rowid(db)

            if let vec = embedding.embed(chunk.text), !vec.isEmpty {
                let blob = vec.withUnsafeBytes { Data($0) }
                var stmt: OpaquePointer?
                let sql = "INSERT INTO chunk_vectors(chunk_id, dim, vec) VALUES(?,?,?)"
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_int64(stmt, 1, chunkId)
                    sqlite3_bind_int64(stmt, 2, Int64(vec.count))
                    _ = blob.withUnsafeBytes { ptr in
                        sqlite3_bind_blob(stmt, 3, ptr.baseAddress, Int32(blob.count), nil)
                    }
                    sqlite3_step(stmt)
                    sqlite3_finalize(stmt)
                }
            }
        }
        exec(db, "COMMIT")
    }

    // MARK: Search

    public func searchNotes(query: String, limit: Int = 20) -> [SearchSnippet] {
        guard let db, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let safeQuery = sanitizeFTSQuery(query)
        let sql = """
            SELECT notes_fts.file, n.title,
                   snippet(notes_fts, 2, '**', '**', '…', 20) as snip
            FROM notes_fts
            JOIN notes n ON notes_fts.file = n.file
            WHERE notes_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, safeQuery, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [String: SearchSnippet] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let file = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let snip = String(cString: sqlite3_column_text(stmt, 2))

            if var existing = results[file] {
                var snips = existing.snippets
                snips.append(snip)
                results[file] = SearchSnippet(noteFile: file, noteTitle: title,
                                               matchCount: snips.count, snippets: snips)
            } else {
                results[file] = SearchSnippet(noteFile: file, noteTitle: title,
                                               matchCount: 1, snippets: [snip])
            }
        }
        return Array(results.values)
    }

    public func semanticSearch(query: String, embedding: EmbeddingProvider,
                                topK: Int = 8, minScore: Float = 0.45) -> [ChunkSearchResult] {
        guard let db, let queryVec = embedding.embed(query), !queryVec.isEmpty else { return [] }

        // Load all chunk vectors and cosine-rank them (fast up to ~100k chunks on device)
        let sql = "SELECT c.chunk_id, c.file, c.start_line, c.end_line, c.text, cv.vec, cv.dim, n.title FROM chunks c JOIN chunk_vectors cv ON cv.chunk_id=c.chunk_id JOIN notes n ON n.file=c.file"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var scored: [(ChunkSearchResult, Float)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunkId = sqlite3_column_int64(stmt, 0)
            let file = String(cString: sqlite3_column_text(stmt, 1))
            let startLine = Int(sqlite3_column_int(stmt, 2))
            let endLine = Int(sqlite3_column_int(stmt, 3))
            let text = String(cString: sqlite3_column_text(stmt, 4))
            let blobLen = Int(sqlite3_column_bytes(stmt, 5))
            let dim = Int(sqlite3_column_int(stmt, 6))
            let title = String(cString: sqlite3_column_text(stmt, 7))

            let floatSize = MemoryLayout<Float>.size
            guard dim == queryVec.count,
                  blobLen == dim * floatSize,
                  let blobPtr = sqlite3_column_blob(stmt, 5) else { continue }

            let vecData = Data(bytes: blobPtr, count: blobLen)
            let vec = vecData.withUnsafeBytes { rawBuf -> [Float] in
                var out = [Float]()
                out.reserveCapacity(dim)
                for i in 0..<dim {
                    out.append(rawBuf.loadUnaligned(fromByteOffset: i * floatSize, as: Float.self))
                }
                return out
            }

            let score = cosineSimilarity(queryVec, vec)
            if score >= minScore {
                let result = ChunkSearchResult(
                    noteFile: file, noteTitle: title, chunkId: chunkId,
                    score: score, excerpt: String(text.prefix(300)),
                    startLine: startLine, endLine: endLine
                )
                scored.append((result, score))
            }
        }

        let top = scored.sorted { $0.1 > $1.1 }.prefix(topK)
        return top.map { $0.0 }
    }

    public func listNotes(folder: String? = nil, tags: [String] = [],
                           updatedAfter: Date? = nil, updatedBefore: Date? = nil,
                           limit: Int = 50, sortDescending: Bool = true) -> [NoteRow] {
        guard let db else { return [] }

        var conditions: [String] = []
        var bindings: [Any] = []

        if let folder {
            conditions.append("folder = ?")
            bindings.append(folder)
        }
        for tag in tags {
            // Escape LIKE special characters so tag values are matched literally.
            let escapedTag = tag
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            conditions.append("(' ' || tags_flat || ' ') LIKE ? ESCAPE '\\'")
            bindings.append("% \(escapedTag) %")
        }
        if let after = updatedAfter {
            conditions.append("mtime >= ?")
            bindings.append(after.timeIntervalSince1970)
        }
        if let before = updatedBefore {
            conditions.append("mtime <= ?")
            bindings.append(before.timeIntervalSince1970)
        }

        let where_ = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let order = sortDescending ? "DESC" : "ASC"
        let sql = "SELECT file, title, mtime, tags_flat, folder FROM notes \(where_) ORDER BY mtime \(order) LIMIT ?"
        bindings.append(limit)

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for (i, binding) in bindings.enumerated() {
            let col = Int32(i + 1)
            switch binding {
            case let s as String:
                sqlite3_bind_text(stmt, col, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let d as Double:
                sqlite3_bind_double(stmt, col, d)
            case let n as Int:
                sqlite3_bind_int64(stmt, col, Int64(n))
            default: break
            }
        }

        var rows: [NoteRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let file = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let mtime = sqlite3_column_double(stmt, 2)
            let tagsFlat = String(cString: sqlite3_column_text(stmt, 3))
            let folder = String(cString: sqlite3_column_text(stmt, 4))
            let tags = tagsFlat.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            rows.append(NoteRow(file: file, title: title, mtime: mtime, tags: tags, folder: folder))
        }
        return rows
    }

    public func getNote(file: String) -> NoteRow? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT file, title, mtime, tags_flat, folder FROM notes WHERE file=? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, file, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let title = String(cString: sqlite3_column_text(stmt, 1))
        let mtime = sqlite3_column_double(stmt, 2)
        let tagsFlat = String(cString: sqlite3_column_text(stmt, 3))
        let folder = String(cString: sqlite3_column_text(stmt, 4))
        let tags = tagsFlat.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return NoteRow(file: file, title: title, mtime: mtime, tags: tags, folder: folder)
    }

    public func noteCount() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM notes", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    // MARK: Migrations

    private func runMigrations() throws {
        guard let db else { throw NoteIndexError.notOpen }

        exec(db, "PRAGMA journal_mode=WAL")
        exec(db, "PRAGMA foreign_keys=ON")

        // Migration 1: notes + FTS5
        exec(db, """
            CREATE TABLE IF NOT EXISTS notes (
                file       TEXT PRIMARY KEY,
                title      TEXT NOT NULL DEFAULT '',
                folder     TEXT NOT NULL DEFAULT '',
                tags_flat  TEXT NOT NULL DEFAULT '',
                mtime      REAL NOT NULL DEFAULT 0,
                indexed_at REAL NOT NULL DEFAULT 0
            )
        """)

        exec(db, """
            CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
                file UNINDEXED,
                title,
                body,
                tags,
                tokenize = 'porter unicode61 remove_diacritics 2'
            )
        """)

        // Migration 2: chunks + vectors
        exec(db, """
            CREATE TABLE IF NOT EXISTS chunks (
                chunk_id     INTEGER PRIMARY KEY AUTOINCREMENT,
                file         TEXT NOT NULL REFERENCES notes(file) ON DELETE CASCADE,
                heading_path TEXT NOT NULL DEFAULT '[]',
                start_line   INTEGER NOT NULL DEFAULT 0,
                end_line     INTEGER NOT NULL DEFAULT 0,
                text         TEXT NOT NULL DEFAULT ''
            )
        """)
        exec(db, "CREATE INDEX IF NOT EXISTS idx_chunks_file ON chunks(file)")

        exec(db, """
            CREATE TABLE IF NOT EXISTS chunk_vectors (
                chunk_id INTEGER PRIMARY KEY REFERENCES chunks(chunk_id) ON DELETE CASCADE,
                dim      INTEGER NOT NULL,
                vec      BLOB NOT NULL
            )
        """)
    }

    // MARK: Helpers

    @discardableResult
    private func exec(_ db: OpaquePointer, _ sql: String, _ args: Any?...) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        for (i, arg) in args.enumerated() {
            let col = Int32(i + 1)
            switch arg {
            case let s as String:
                sqlite3_bind_text(stmt, col, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let d as Double:
                sqlite3_bind_double(stmt, col, d)
            case let n as Int:
                sqlite3_bind_int64(stmt, col, Int64(n))
            case let n as Int64:
                sqlite3_bind_int64(stmt, col, n)
            case let n as Int32:
                sqlite3_bind_int(stmt, col, n)
            case let data as Data:
                _ = data.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, col, ptr.baseAddress, Int32(data.count), nil)
                }
            case .none:
                sqlite3_bind_null(stmt, col)
            default: break
            }
        }

        let rc = sqlite3_step(stmt)
        return rc == SQLITE_DONE || rc == SQLITE_ROW
    }

    private func sanitizeFTSQuery(_ query: String) -> String {
        // Escape FTS5 special characters for plain-phrase queries
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // If it looks like an FTS5 expression (contains AND/OR/NOT/quotes/*, keep it as-is
        let ftsOperators = ["AND", "OR", "NOT", "*", "\"", "(", ")"]
        if ftsOperators.contains(where: { trimmed.contains($0) }) {
            return trimmed
        }
        // Otherwise wrap in quotes for exact phrase matching
        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

#else

// MARK: - Stub for Linux

public actor NoteIndex {
    public let dbURL: URL
    public init(dbURL: URL) { self.dbURL = dbURL }
    public func open() throws {}
    public func close() {}
    public func upsertFile(path: String, title: String, body: String, tags: [String], mtime: TimeInterval) {}
    public func removeFile(path: String) {}
    public func upsertChunks(_ chunks: [NoteChunk], forFile path: String, embedding: EmbeddingProvider) {}
    public func searchNotes(query: String, limit: Int = 20) -> [SearchSnippet] { [] }
    public func semanticSearch(query: String, embedding: EmbeddingProvider, topK: Int = 8, minScore: Float = 0.45) -> [ChunkSearchResult] { [] }
    public func listNotes(folder: String? = nil, tags: [String] = [], updatedAfter: Date? = nil, updatedBefore: Date? = nil, limit: Int = 50, sortDescending: Bool = true) -> [NoteRow] { [] }
    public func getNote(file: String) -> NoteRow? { nil }
    public func noteCount() -> Int { 0 }
}

#endif
