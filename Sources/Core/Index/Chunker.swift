import Foundation

/// A contiguous slice of a note, bounded by heading structure.
public struct NoteChunk: Sendable {
    public let headingPath: [String]
    public let startLine: Int
    public let endLine: Int
    public let text: String

    public init(headingPath: [String], startLine: Int, endLine: Int, text: String) {
        self.headingPath = headingPath
        self.startLine = startLine
        self.endLine = endLine
        self.text = text
    }
}

/// Splits note content into chunks bounded by heading boundaries.
/// Chunks that exceed maxLines are further split with overlap.
public enum Chunker {

    public static func chunk(
        content: String,
        headings: [(level: Int, text: String, startLine: Int)],
        maxLines: Int = 80,
        overlapLines: Int = 8
    ) -> [NoteChunk] {
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }

        // Build heading boundary list sorted by startLine
        var boundaries = headings.sorted { $0.startLine < $1.startLine }
        // Add sentinel at end
        let endLine = lines.count

        // Track the current heading path (stack by level)
        var headingStack: [(level: Int, text: String)] = []
        var chunks: [NoteChunk] = []

        func currentPath() -> [String] {
            headingStack.map { $0.text }
        }

        // No headings: treat whole content as one chunk (with sliding window if large)
        if boundaries.isEmpty {
            let allChunks = splitLines(lines: lines, from: 0, to: endLine,
                                        headingPath: [], maxLines: maxLines, overlapLines: overlapLines)
            return allChunks
        }

        // Before the first heading
        let firstHeadingLine = boundaries.first!.startLine
        if firstHeadingLine > 0 {
            let pre = splitLines(lines: lines, from: 0, to: firstHeadingLine,
                                  headingPath: [], maxLines: maxLines, overlapLines: overlapLines)
            chunks.append(contentsOf: pre)
        }

        for (i, heading) in boundaries.enumerated() {
            // Update heading stack
            headingStack.removeAll { $0.level >= heading.level }
            headingStack.append((level: heading.level, text: heading.text))

            let sectionStart = heading.startLine
            let sectionEnd = i + 1 < boundaries.count ? boundaries[i + 1].startLine : endLine

            let sectionChunks = splitLines(lines: lines, from: sectionStart, to: sectionEnd,
                                            headingPath: currentPath(),
                                            maxLines: maxLines, overlapLines: overlapLines)
            chunks.append(contentsOf: sectionChunks)
        }

        return chunks
    }

    private static func splitLines(
        lines: [String],
        from start: Int,
        to end: Int,
        headingPath: [String],
        maxLines: Int,
        overlapLines: Int
    ) -> [NoteChunk] {
        guard end > start else { return [] }
        let slice = Array(lines[start..<min(end, lines.count)])
        let text = slice.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        if slice.count <= maxLines {
            return [NoteChunk(headingPath: headingPath, startLine: start, endLine: end - 1, text: text)]
        }

        // Sliding window split
        var chunks: [NoteChunk] = []
        var cursor = 0
        while cursor < slice.count {
            let windowEnd = min(cursor + maxLines, slice.count)
            let windowText = slice[cursor..<windowEnd].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !windowText.isEmpty {
                chunks.append(NoteChunk(
                    headingPath: headingPath,
                    startLine: start + cursor,
                    endLine: start + windowEnd - 1,
                    text: windowText
                ))
            }
            let advance = max(1, maxLines - overlapLines)
            cursor += advance
        }
        return chunks
    }
}
