import Foundation
import Core

/// iOS-side wrapper around Core's AppStateLogic. Performs the actual file I/O
/// (read/write via an injected FileSystemManager) and surfaces observable
/// status for the UI layer. All pure string transforms live in AppStateLogic.
@Observable
class AppFileSystemManager {

    var selectedFolders: [URL] = []
    var isScanning: Bool = false
    var lastScanDate: Date? = nil
    var error: String? = nil

    private let coreFileSystem: FileSystemManager
    private let todoParser = ObsidianTodoParser()
    var noteIndexer: NoteIndexer?

    init(fileSystem: FileSystemManager = DefaultFileSystemManager()) {
        self.coreFileSystem = fileSystem
        if let documentsURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first {
            selectedFolders = [documentsURL]
        }
    }

    /// Select a folder for scanning (currently adds to default Documents).
    /// Future: Replace with UIDocumentPickerViewController for iCloud Drive.
    func selectFolder() {
        error = nil
        guard let documentsURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else {
            error = "No Documents folder available."
            return
        }
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
            let scanResult = coreFileSystem.scanDirectory(at: folderPath, recursive: true)

            switch scanResult {
            case .success(let filePaths):
                for filePath in filePaths {
                    let readResult = coreFileSystem.readFile(at: filePath)
                    switch readResult {
                    case .success(let content):
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
    /// Handles both checkbox-based todos ([ ]/[x]) and YAML frontmatter items.
    /// `item.completed` already holds the desired (post-toggle) state.
    func toggleTodoCompletion(_ item: Item) async -> Bool {
        error = nil

        guard case .success(let content) = coreFileSystem.readFile(at: item.sourceFile) else {
            error = "Could not read source file: \(item.sourceFile)"
            return false
        }

        let updated: String?
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") {
            updated = AppStateLogic.toggleYAMLCompleted(in: content, to: item.completed)
            if updated == nil { error = "Invalid YAML frontmatter" }
        } else {
            updated = AppStateLogic.toggleCheckbox(in: content, matching: item.title)
            if updated == nil { error = "Could not find item '\(item.title)' in source file" }
        }

        guard let newContent = updated else { return false }
        let ok = writeOrReport(newContent, to: item.sourceFile)
        if ok, let indexer = noteIndexer {
            Task { await indexer.upsertFile(path: item.sourceFile, fileSystem: coreFileSystem) }
        }
        return ok
    }

    /// Write an item back to its source file (update properties).
    /// Only supported for YAML frontmatter items; markdown-only checkbox files
    /// have no metadata to update.
    func writeItem(_ item: Item) async -> Bool {
        error = nil

        guard case .success(let content) = coreFileSystem.readFile(at: item.sourceFile) else {
            error = "Could not read source file: \(item.sourceFile)"
            return false
        }

        guard content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") else {
            error = "Cannot update item properties in markdown-only files. Use YAML frontmatter."
            return false
        }

        guard let newContent = AppStateLogic.updateYAMLItem(in: content, item: item) else {
            error = "Invalid YAML frontmatter"
            return false
        }
        let ok = writeOrReport(newContent, to: item.sourceFile)
        if ok, let indexer = noteIndexer {
            Task { await indexer.upsertFile(path: item.sourceFile, fileSystem: coreFileSystem) }
        }
        return ok
    }

    /// Delete an item from its source file.
    /// YAML frontmatter files (one item per file) are deleted wholesale.
    /// Checkbox items have their single line removed.
    func deleteItem(_ item: Item) async -> Bool {
        error = nil

        guard case .success(let content) = coreFileSystem.readFile(at: item.sourceFile) else {
            error = "Could not read source file: \(item.sourceFile)"
            return false
        }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") {
            do {
                try FileManager.default.removeItem(atPath: item.sourceFile)
                if let indexer = noteIndexer {
                    Task { await indexer.removeFile(path: item.sourceFile) }
                }
                return true
            } catch {
                self.error = "Failed to delete file: \(error.localizedDescription)"
                return false
            }
        }

        guard let newContent = AppStateLogic.deleteCheckbox(in: content, matching: item.title) else {
            error = "Could not find item '\(item.title)' in source file"
            return false
        }
        let ok = writeOrReport(newContent, to: item.sourceFile)
        if ok, let indexer = noteIndexer {
            Task { await indexer.upsertFile(path: item.sourceFile, fileSystem: coreFileSystem) }
        }
        return ok
    }

    // MARK: - Private

    private func writeOrReport(_ content: String, to path: String) -> Bool {
        switch coreFileSystem.writeFile(at: path, content: content) {
        case .success:
            return true
        case .failure(let e):
            error = "Failed to write file: \(e)"
            return false
        }
    }
}
