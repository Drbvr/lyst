import Foundation
import Core

/// File system manager for iOS app.
/// Scans Documents folder for markdown files and parses them into items.
/// Uses Core's FileSystemManager and ObsidianTodoParser.
@Observable
class AppFileSystemManager {

    var selectedFolders: [URL] = []
    var isScanning: Bool = false
    var lastScanDate: Date? = nil
    var error: String? = nil

    private let coreFileSystem = DefaultFileSystemManager()
    private let todoParser = ObsidianTodoParser()

    /// Initialize with default Documents folder for scanning.
    init() {
        let documentsURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        selectedFolders = [documentsURL]
    }

    /// Select a folder for scanning (currently adds to default Documents).
    /// Future: Replace with UIDocumentPickerViewController for iCloud Drive.
    func selectFolder() {
        error = nil
        // For now, documents folder is the default
        let documentsURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        if !selectedFolders.contains(documentsURL) {
            selectedFolders.append(documentsURL)
        }
        error = "Using Documents folder. iCloud Drive setup coming in Phase 3."
    }

    /// Scan Documents folder for markdown files and parse items.
    func scanFolders() async -> [Item] {
        isScanning = true
        defer {
            isScanning = false
            lastScanDate = Date()
        }

        var allItems: [Item] = []
        error = nil

        for folderURL in selectedFolders {
            let folderPath = folderURL.path

            // Scan for .md files recursively
            let scanResult = coreFileSystem.scanDirectory(at: folderPath, recursive: true)

            switch scanResult {
            case .success(let filePaths):
                for filePath in filePaths {
                    // Read file content
                    let readResult = coreFileSystem.readFile(at: filePath)

                    switch readResult {
                    case .success(let content):
                        // Parse markdown content
                        let items = todoParser.parseTodos(from: content, sourceFile: filePath)
                        allItems.append(contentsOf: items)

                    case .failure(let fileError):
                        error = "Failed to read \(filePath): \(fileError)"
                    }
                }

            case .failure(let scanError):
                error = "Failed to scan \(folderPath): \(scanError)"
            }
        }

        return allItems
    }

    /// Toggle a todo's completion status in its source file.
    /// Handles both checkbox-based todos ([ ]/[x]) and YAML frontmatter items (books, movies).
    func toggleTodoCompletion(_ item: Item) async -> Bool {
        error = nil

        let readResult = coreFileSystem.readFile(at: item.sourceFile)
        guard case .success(let content) = readResult else {
            error = "Could not read source file: \(item.sourceFile)"
            return false
        }

        // YAML frontmatter files start with ---
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") {
            return toggleYAMLCompletion(content: content, item: item)
        } else {
            return toggleCheckboxCompletion(content: content, item: item)
        }
    }

    /// Toggle completion by updating `completed:` field in YAML frontmatter.
    /// `item.completed` already holds the new (desired) state.
    private func toggleYAMLCompletion(content: String, item: Item) -> Bool {
        var lines = content.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            error = "Not a valid YAML frontmatter file"
            return false
        }

        // Find the closing ---
        var closingIdx: Int? = nil
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIdx = i
                break
            }
        }
        guard let closingIdx = closingIdx else {
            error = "No closing --- in frontmatter"
            return false
        }

        let newValue = item.completed ? "true" : "false"
        var foundCompleted = false

        for i in 1..<closingIdx {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("completed:") {
                lines[i] = "completed: \(newValue)"
                foundCompleted = true
                break
            }
        }

        if !foundCompleted {
            // Insert completed field just before closing ---
            lines.insert("completed: \(newValue)", at: closingIdx)
        }

        let updatedContent = lines.joined(separator: "\n")
        switch coreFileSystem.writeFile(at: item.sourceFile, content: updatedContent) {
        case .success: return true
        case .failure(let e):
            error = "Failed to write file: \(e)"
            return false
        }
    }

    /// Toggle completion by flipping [ ] <-> [x] on the matching checkbox line.
    private func toggleCheckboxCompletion(content: String, item: Item) -> Bool {
        var lines = content.components(separatedBy: "\n")
        var found = false

        for (index, line) in lines.enumerated() {
            if line.contains(item.title) {
                if line.contains("[ ]") {
                    lines[index] = line.replacingOccurrences(of: "[ ]", with: "[x]")
                    found = true
                } else if line.contains("[x]") {
                    lines[index] = line.replacingOccurrences(of: "[x]", with: "[ ]")
                    found = true
                }
            }
        }

        guard found else {
            error = "Could not find item '\(item.title)' in source file"
            return false
        }

        let updatedContent = lines.joined(separator: "\n")
        switch coreFileSystem.writeFile(at: item.sourceFile, content: updatedContent) {
        case .success: return true
        case .failure(let e):
            error = "Failed to write file: \(e)"
            return false
        }
    }

    /// Write an item back to its source file (update properties).
    /// Handles updating title, tags, properties in YAML frontmatter items.
    func writeItem(_ item: Item) async -> Bool {
        error = nil

        let readResult = coreFileSystem.readFile(at: item.sourceFile)
        guard case .success(let content) = readResult else {
            error = "Could not read source file: \(item.sourceFile)"
            return false
        }

        // Handle YAML frontmatter files
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") {
            return updateYAMLItem(content: content, item: item)
        }

        // For markdown checkbox files, we can't update metadata without YAML
        error = "Cannot update item properties in markdown-only files. Use YAML frontmatter."
        return false
    }

    /// Update an item's properties in YAML frontmatter.
    private func updateYAMLItem(content: String, item: Item) -> Bool {
        var lines = content.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            error = "Not a valid YAML frontmatter file"
            return false
        }

        // Find the closing ---
        var closingIdx: Int? = nil
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIdx = i
                break
            }
        }
        guard var closingIdx = closingIdx else {
            error = "No closing --- in frontmatter"
            return false
        }

        // Update or insert title
        var foundTitle = false
        for i in 1..<closingIdx {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("title:") {
                lines[i] = "title: \(item.title)"
                foundTitle = true
                break
            }
        }
        if !foundTitle {
            lines.insert("title: \(item.title)", at: closingIdx)
            closingIdx += 1
        }

        // Update tags
        var foundTags = false
        for i in 1..<closingIdx {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("tags:") {
                let tagsStr = item.tags.isEmpty ? "[]" : "[\(item.tags.map { "\"\($0)\"" }.joined(separator: ", "))]"
                lines[i] = "tags: \(tagsStr)"
                foundTags = true
                break
            }
        }
        if !foundTags && !item.tags.isEmpty {
            let tagsStr = "[\(item.tags.map { "\"\($0)\"" }.joined(separator: ", "))]"
            lines.insert("tags: \(tagsStr)", at: closingIdx)
            closingIdx += 1
        }

        // Update completed status
        var foundCompleted = false
        for i in 1..<closingIdx {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("completed:") {
                lines[i] = "completed: \(item.completed)"
                foundCompleted = true
                break
            }
        }
        if !foundCompleted {
            lines.insert("completed: \(item.completed)", at: closingIdx)
        }

        let updatedContent = lines.joined(separator: "\n")
        switch coreFileSystem.writeFile(at: item.sourceFile, content: updatedContent) {
        case .success: return true
        case .failure(let e):
            error = "Failed to write file: \(e)"
            return false
        }
    }

    /// Delete an item from its source file.
    /// For YAML frontmatter files, removes the entire file (one item per file).
    /// For markdown checkbox files, attempts to remove the matching line.
    func deleteItem(_ item: Item) async -> Bool {
        error = nil

        let readResult = coreFileSystem.readFile(at: item.sourceFile)
        guard case .success(let content) = readResult else {
            error = "Could not read source file: \(item.sourceFile)"
            return false
        }

        // For YAML frontmatter files (one item per file), delete the entire file
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") {
            do {
                try FileManager.default.removeItem(atPath: item.sourceFile)
                return true
            } catch {
                self.error = "Failed to delete file: \(error.localizedDescription)"
                return false
            }
        }

        // For markdown files with multiple items, remove the matching checkbox line
        var lines = content.components(separatedBy: "\n")
        var found = false

        for (index, line) in lines.enumerated() {
            if line.contains(item.title) && (line.contains("[ ]") || line.contains("[x]")) {
                lines.remove(at: index)
                found = true
                break
            }
        }

        guard found else {
            error = "Could not find item '\(item.title)' in source file"
            return false
        }

        let updatedContent = lines.joined(separator: "\n")
        switch coreFileSystem.writeFile(at: item.sourceFile, content: updatedContent) {
        case .success: return true
        case .failure(let e):
            error = "Failed to write file: \(e)"
            return false
        }
    }
}
