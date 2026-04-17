import Foundation
#if canImport(os)
import os.log
#endif

/// Error types for file system operations
public enum FileError: Error, Equatable {
    case notFound(String)
    case permissionDenied(String)
    case diskFull
    case invalidPath(String)
    case ioError(String)
}

/// Protocol for file system operations.
///
/// `Sendable` so implementations can be shared across actor boundaries and
/// captured by detached tasks (e.g. AppState moves file scanning off the
/// MainActor). Conformers are expected to have no mutable stored state.
public protocol FileSystemManager: Sendable {
    func readFile(at path: String) -> Result<String, FileError>
    func writeFile(at path: String, content: String) -> Result<Void, FileError>
    func scanDirectory(at path: String, recursive: Bool) -> Result<[String], FileError>
    func listSubdirectories(at path: String) -> Result<[String], FileError>
}

/// Default implementation of FileSystemManager
public final class DefaultFileSystemManager: FileSystemManager, @unchecked Sendable {

    private let fileManager = FileManager.default

    public init() {}

    /// Reads a file and returns its contents
    public func readFile(at path: String) -> Result<String, FileError> {
        guard !path.isEmpty else {
            return .failure(.invalidPath("Path cannot be empty"))
        }

        let expandedPath = expandPath(path)

        // Check if file exists
        guard fileManager.fileExists(atPath: expandedPath) else {
            return .failure(.notFound("File not found: \(expandedPath)"))
        }

        // Check if it's actually a file (not a directory)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir), !isDir.boolValue else {
            return .failure(.invalidPath("Path is a directory, not a file: \(expandedPath)"))
        }

        do {
            let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
            return .success(content)
        } catch let error as NSError {
            if error.code == NSFileReadNoPermissionError {
                return .failure(.permissionDenied("Permission denied: \(expandedPath)"))
            } else {
                return .failure(.ioError("Failed to read file: \(error.localizedDescription)"))
            }
        }
    }

    /// Writes content to a file (creates parent directories if needed)
    public func writeFile(at path: String, content: String) -> Result<Void, FileError> {
        guard !path.isEmpty else {
            return .failure(.invalidPath("Path cannot be empty"))
        }

        let expandedPath = expandPath(path)

        // Create parent directories if needed
        let parentPath = (expandedPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: parentPath) {
            do {
                try fileManager.createDirectory(atPath: parentPath, withIntermediateDirectories: true, attributes: nil)
            } catch let error as NSError {
                if error.code == NSFileWriteNoPermissionError {
                    return .failure(.permissionDenied("Permission denied: \(parentPath)"))
                } else {
                    return .failure(.ioError("Failed to create directory: \(error.localizedDescription)"))
                }
            }
        }

        // Write to temporary file first, then rename (atomic write)
        let tempPath = expandedPath + ".tmp"

        do {
            try content.write(toFile: tempPath, atomically: true, encoding: .utf8)

            // Move temp file to final location
            if fileManager.fileExists(atPath: expandedPath) {
                try fileManager.removeItem(atPath: expandedPath)
            }
            try fileManager.moveItem(atPath: tempPath, toPath: expandedPath)

            return .success(())
        } catch let error as NSError {
            // Clean up temp file; log if cleanup itself fails so orphaned
            // .tmp siblings are traceable rather than silently leaked.
            do {
                if fileManager.fileExists(atPath: tempPath) {
                    try fileManager.removeItem(atPath: tempPath)
                }
            } catch let cleanupError {
                #if canImport(os)
                Logger(subsystem: "list-app.core", category: "FileSystemManager")
                    .error("Failed to remove temp file \(tempPath, privacy: .public): \(cleanupError.localizedDescription, privacy: .public)")
                #else
                FileHandle.standardError.write(Data("[FileSystemManager] failed to remove temp file \(tempPath): \(cleanupError.localizedDescription)\n".utf8))
                #endif
            }

            if error.code == NSFileWriteNoPermissionError {
                return .failure(.permissionDenied("Permission denied: \(expandedPath)"))
            } else if error.code == NSFileWriteOutOfSpaceError {
                return .failure(.diskFull)
            } else {
                return .failure(.ioError("Failed to write file: \(error.localizedDescription)"))
            }
        }
    }

    /// Scans a directory and returns markdown file paths
    public func scanDirectory(at path: String, recursive: Bool) -> Result<[String], FileError> {
        guard !path.isEmpty else {
            return .failure(.invalidPath("Path cannot be empty"))
        }

        let expandedPath = expandPath(path)

        // Check if path exists and is a directory
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir), isDir.boolValue else {
            return .failure(.notFound("Directory not found: \(expandedPath)"))
        }

        var markdownFiles: [String] = []

        do {
            if recursive {
                markdownFiles = try scanDirectoryRecursive(expandedPath)
            } else {
                markdownFiles = try scanDirectoryNonRecursive(expandedPath)
            }

            return .success(markdownFiles)
        } catch let error as NSError {
            if error.code == NSFileReadNoPermissionError {
                return .failure(.permissionDenied("Permission denied: \(expandedPath)"))
            } else {
                return .failure(.ioError("Failed to scan directory: \(error.localizedDescription)"))
            }
        }
    }

    /// Lists subdirectories in a path
    public func listSubdirectories(at path: String) -> Result<[String], FileError> {
        guard !path.isEmpty else {
            return .failure(.invalidPath("Path cannot be empty"))
        }

        let expandedPath = expandPath(path)

        // Check if path exists and is a directory
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir), isDir.boolValue else {
            return .failure(.notFound("Directory not found: \(expandedPath)"))
        }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: expandedPath)
            var subdirs: [String] = []

            for item in contents {
                let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                var isItemDir: ObjCBool = false

                if fileManager.fileExists(atPath: itemPath, isDirectory: &isItemDir), isItemDir.boolValue {
                    // Skip hidden directories and exclusions
                    if !item.hasPrefix(".") && !isExcluded(item) {
                        subdirs.append(item)
                    }
                }
            }

            return .success(subdirs.sorted())
        } catch let error as NSError {
            if error.code == NSFileReadNoPermissionError {
                return .failure(.permissionDenied("Permission denied: \(expandedPath)"))
            } else {
                return .failure(.ioError("Failed to list directories: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Private Helpers

    private func expandPath(_ path: String) -> String {
        return (path as NSString).expandingTildeInPath
    }

    private func isExcluded(_ name: String) -> Bool {
        let exclusions = [".obsidian", ".git", ".DS_Store", "node_modules", ".venv"]
        return exclusions.contains(name)
    }

    private func scanDirectoryRecursive(_ path: String) throws -> [String] {
        var files: [String] = []

        let contents = try fileManager.contentsOfDirectory(atPath: path)

        for item in contents {
            let itemPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false

            guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                // Skip excluded directories and hidden files
                if !item.hasPrefix(".") && !isExcluded(item) {
                    let subfiles = try scanDirectoryRecursive(itemPath)
                    files.append(contentsOf: subfiles)
                }
            } else if item.hasSuffix(".md") && !item.hasPrefix(".") {
                // Include markdown files
                files.append(itemPath)
            }
        }

        return files.sorted()
    }

    private func scanDirectoryNonRecursive(_ path: String) throws -> [String] {
        var files: [String] = []

        let contents = try fileManager.contentsOfDirectory(atPath: path)

        for item in contents {
            if item.hasSuffix(".md") && !item.hasPrefix(".") {
                let filePath = (path as NSString).appendingPathComponent(item)
                files.append(filePath)
            }
        }

        return files.sorted()
    }
}
