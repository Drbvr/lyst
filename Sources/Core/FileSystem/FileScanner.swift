import Foundation

/// Represents a markdown file with its metadata
public struct MarkdownFile: Equatable {
    public let path: String
    public let content: String
    public let modifiedAt: Date
    public let folder: String  // Immediate parent folder name

    public init(path: String, content: String, modifiedAt: Date, folder: String) {
        self.path = path
        self.content = content
        self.modifiedAt = modifiedAt
        self.folder = folder
    }
}

/// Scans directories for markdown files
public class FileScanner {

    private let fileManager = DefaultFileSystemManager()
    public let exclusions: [String] = [".obsidian", ".git", ".DS_Store", "node_modules", ".venv"]

    public init() {}

    /// Scans folders for markdown files and returns their contents
    public func scanForMarkdown(in folders: [String]) -> Result<[MarkdownFile], FileError> {
        var markdownFiles: [MarkdownFile] = []

        for folder in folders {
            // Scan the folder recursively
            let scanResult = fileManager.scanDirectory(at: folder, recursive: true)

            switch scanResult {
            case .success(let filePaths):
                // Read each markdown file
                for filePath in filePaths {
                    switch fileManager.readFile(at: filePath) {
                    case .success(let content):
                        // Get file modification date
                        let modifiedAt = getFileModificationDate(filePath) ?? Date()
                        let folderName = getImmediateParentFolder(filePath)

                        let markdownFile = MarkdownFile(
                            path: filePath,
                            content: content,
                            modifiedAt: modifiedAt,
                            folder: folderName
                        )

                        markdownFiles.append(markdownFile)

                    case .failure:
                        // Skip files that can't be read
                        continue
                    }
                }

            case .failure:
                // Skip folders that can't be scanned (consistent with per-file handling above)
                continue
            }
        }

        return .success(markdownFiles.sorted { $0.path < $1.path })
    }

    /// Scans a single folder for markdown files
    public func scanFolder(_ folder: String) -> Result<[MarkdownFile], FileError> {
        return scanForMarkdown(in: [folder])
    }

    // MARK: - Helper Methods

    private func getFileModificationDate(_ path: String) -> Date? {
        let expandedPath = (path as NSString).expandingTildeInPath

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: expandedPath)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    private func getImmediateParentFolder(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingLastPathComponent().lastPathComponent
    }
}
