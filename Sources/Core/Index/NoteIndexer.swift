import Foundation

/// Maintains the NoteIndex in sync with file-system writes.
/// Call `upsertFile` / `removeFile` from the existing `AppFileSystemManager` write hooks.
public actor NoteIndexer {

    private let index: NoteIndex
    private let parser: ObsidianTodoParser
    private let embeddingProvider: any EmbeddingProvider

    public init(index: NoteIndex, embeddingProvider: (any EmbeddingProvider)? = nil) {
        self.index = index
        self.parser = ObsidianTodoParser()
        self.embeddingProvider = embeddingProvider ?? StubEmbeddingProvider()
    }

    /// Re-index a single file after it has been written.
    public func upsertFile(path: String, fileSystem: FileSystemManager) async {
        guard case .success(let content) = fileSystem.readFile(at: path) else { return }
        let (title, body, tags) = extractMetadata(from: content, path: path)
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        await index.upsertFile(
            path: path,
            title: title,
            body: body,
            tags: tags,
            mtime: mtime?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        )

        // Build and store chunks + embeddings
        let headings = parser.extractHeadings(from: content)
        let chunks = Chunker.chunk(content: content, headings: headings)
        await index.upsertChunks(chunks, forFile: path, embedding: embeddingProvider)
    }

    /// Remove a file's index entries.
    public func removeFile(path: String) async {
        await index.removeFile(path: path)
    }

    /// Full vault scan — call once after the vault is loaded.
    public func buildInitialIndex(vaultURL: URL, fileSystem: FileSystemManager) async {
        guard case .success(let paths) = fileSystem.scanDirectory(at: vaultURL.path, recursive: true) else { return }
        for path in paths {
            guard !Task.isCancelled else { return }
            await upsertFile(path: path, fileSystem: fileSystem)
        }
    }

    // MARK: - Private

    private func extractMetadata(from content: String, path: String) -> (title: String, body: String, tags: [String]) {
        let lines = content.components(separatedBy: .newlines)

        // Check for YAML frontmatter
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") {
            var yamlLines: [String] = []
            var bodyStart = 0
            var inFrontmatter = false
            for (i, line) in lines.enumerated() {
                if i == 0 && line.trimmingCharacters(in: .whitespaces) == "---" {
                    inFrontmatter = true
                    continue
                }
                if inFrontmatter {
                    if line.trimmingCharacters(in: .whitespaces) == "---" {
                        bodyStart = i + 1
                        break
                    }
                    yamlLines.append(line)
                }
            }
            let body = lines.dropFirst(bodyStart).joined(separator: "\n")
            var title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            var tags: [String] = []
            for line in yamlLines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("title:") {
                    title = t.dropFirst("title:".count).trimmingCharacters(in: .whitespaces)
                } else if t.hasPrefix("tags:") {
                    let raw = t.dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
                    let stripped = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                    tags = stripped.components(separatedBy: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }.filter { !$0.isEmpty }
                }
            }
            return (title, body, tags)
        }

        // No frontmatter — use first H1 as title, extract inline tags
        var title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") {
                title = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        let tagPattern = try? NSRegularExpression(pattern: "#([\\w/]+)")
        var tags: [String] = []
        if let regex = tagPattern {
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let r = Range(match.range(at: 1), in: content) {
                    tags.append(String(content[r]))
                }
            }
        }
        return (title, content, Array(Set(tags)))
    }
}
