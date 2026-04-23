import Foundation
import XCTest

#if canImport(Core)
import Core
#endif

final class RelativeDateParserTests: XCTestCase {

    var parser: RelativeDateParser!

    override func setUp() {
        super.setUp()
        parser = RelativeDateParser()
    }

    // MARK: - Days Tests

    func testParsePlusDays() {
        let now = Date()
        let result = parser.parse("+7d")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        // Should be approximately 7 days from now (within 1 second tolerance)
        let diff = result.timeIntervalSince(now)
        let expectedDiff = 7 * 24 * 3600.0
        XCTAssertEqual(diff, expectedDiff, accuracy: 1.0)
    }

    func testParseMinusDays() {
        let now = Date()
        let result = parser.parse("-30d")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        let calendar = Calendar.current
        var components = DateComponents()
        components.day = 30
        let advanced = calendar.date(byAdding: components, to: result)!
        let diff = abs(now.timeIntervalSince(advanced))
        XCTAssertLessThan(diff, 86400)
    }

    func testParseSingleDay() {
        let now = Date()
        let result = parser.parse("+1d")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        let diff = result.timeIntervalSince(now)
        let expectedDiff = 24 * 3600.0
        XCTAssertEqual(diff, expectedDiff, accuracy: 1.0)
    }

    // MARK: - Weeks Tests

    func testPluseWeeks() {
        let now = Date()
        let result = parser.parse("+2w")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        let diff = result.timeIntervalSince(now)
        let expectedDiff = 2 * 7 * 24 * 3600.0
        XCTAssertEqual(diff, expectedDiff, accuracy: 1.0)
    }

    func testParseMinusWeeks() {
        let now = Date()
        let result = parser.parse("-1w")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        let calendar = Calendar.current
        var components = DateComponents()
        components.weekOfYear = 1
        let advanced = calendar.date(byAdding: components, to: result)!
        let diff = abs(now.timeIntervalSince(advanced))
        XCTAssertLessThan(diff, 86400)
    }

    // MARK: - Months Tests

    func testPluseMonths() {
        let now = Date()
        let result = parser.parse("+1m")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: now, to: result)
        XCTAssertEqual(components.month, 1)
    }

    func testParseMinusMonths() {
        let now = Date()
        let result = parser.parse("-3m")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        // Result should be 3 months ago
        let calendar = Calendar.current
        // Compare by adding 3 months to result and should get close to now
        var components = DateComponents()
        components.month = 3
        let advanced = calendar.date(byAdding: components, to: result)!

        // Should be very close to now (within 1 day)
        let diff = abs(now.timeIntervalSince(advanced))
        XCTAssertLessThan(diff, 86400)
    }

    // MARK: - Years Tests

    func testPlusYears() {
        let now = Date()
        let result = parser.parse("+1y")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: now, to: result)
        XCTAssertEqual(components.year, 1)
    }

    func testParseMinusYears() {
        let now = Date()
        let result = parser.parse("-2y")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        // Result should be 2 years ago
        let calendar = Calendar.current
        // Compare by adding 2 years to result and should get close to now
        var components = DateComponents()
        components.year = 2
        let advanced = calendar.date(byAdding: components, to: result)!

        // Should be very close to now (within 1 day)
        let diff = abs(now.timeIntervalSince(advanced))
        XCTAssertLessThan(diff, 86400)
    }

    // MARK: - Invalid Input Tests

    func testParseInvalidFormat() {
        XCTAssertNil(parser.parse("invalid"))
    }

    func testParseEmptyString() {
        XCTAssertNil(parser.parse(""))
    }

    func testParseNonNumericValue() {
        XCTAssertNil(parser.parse("+abd"))
    }

    func testParseInvalidUnit() {
        XCTAssertNil(parser.parse("+7x"))
    }

    // MARK: - Edge Cases

    func testParseZeroDays() {
        guard let result = parser.parse("+0d") else {
            XCTFail("Expected date for +0d, got nil")
            return
        }
        XCTAssertTrue(Calendar.current.isDate(result, inSameDayAs: Date()))
    }

    func testParseLargeValue() {
        let now = Date()
        let result = parser.parse("+365d")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        let diff = result.timeIntervalSince(now)
        let expectedDiff = 365 * 24 * 3600.0
        XCTAssertEqual(diff, expectedDiff, accuracy: 1.0)
    }

    func testParseMultiDigitNumbers() {
        let now = Date()
        let result = parser.parse("+123d")

        guard let result = result else {
            XCTFail("Expected date, got nil")
            return
        }

        // Use calendar-aware comparison to handle DST transitions
        let components = Calendar.current.dateComponents([.day], from: now, to: result)
        XCTAssertEqual(components.day, 123)
    }
}

final class ViewManagerTests: XCTestCase {

    var viewManager: DefaultViewManager!
    var fileSystem: TestFileSystemManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        fileSystem = TestFileSystemManager()
        viewManager = DefaultViewManager(fileSystem: fileSystem)
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - View Loading Tests

    func testLoadValidView() {
        let viewContent = """
        ---
        type: view
        name: Urgent Work Tasks
        display_style: list
        tags: [work/*, urgent]
        item_types: [todo]
        due_before: +7d
        completed: false
        ---
        """

        fileSystem.files["/views/urgent.md"] = viewContent

        let result = viewManager.loadViews(from: ["/views"])

        switch result {
        case .success(let views):
            XCTAssertEqual(views.count, 1)
            XCTAssertEqual(views[0].name, "Urgent Work Tasks")
            XCTAssertEqual(views[0].displayStyle, .list)
            XCTAssertEqual(views[0].filters.tags, ["work/*", "urgent"])
            XCTAssertEqual(views[0].filters.itemTypes, ["todo"])
            XCTAssertEqual(views[0].filters.completed, false)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func testLoadMultipleViews() {
        let view1 = """
        ---
        type: view
        name: Work Tasks
        display_style: list
        ---
        """

        let view2 = """
        ---
        type: view
        name: Reading List
        display_style: card
        ---
        """

        fileSystem.files["/views/work.md"] = view1
        fileSystem.files["/views/reading.md"] = view2

        let result = viewManager.loadViews(from: ["/views"])

        switch result {
        case .success(let views):
            XCTAssertEqual(views.count, 2)
            XCTAssert(views.contains { $0.name == "Work Tasks" })
            XCTAssert(views.contains { $0.name == "Reading List" })
        case .failure:
            XCTFail("Expected success")
        }
    }

    func testLoadViewWithMinimalFields() {
        let viewContent = """
        ---
        type: view
        name: Simple View
        ---
        """

        fileSystem.files["/views/simple.md"] = viewContent

        let result = viewManager.loadViews(from: ["/views"])

        switch result {
        case .success(let views):
            XCTAssertEqual(views.count, 1)
            XCTAssertEqual(views[0].name, "Simple View")
            XCTAssertEqual(views[0].displayStyle, .list)  // Default
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func testLoadViewInvalidType() {
        let viewContent = """
        ---
        type: invalid
        name: Wrong Type
        ---
        """

        fileSystem.files["/views/invalid.md"] = viewContent

        let result = viewManager.loadViews(from: ["/views"])

        switch result {
        case .success(let views):
            XCTAssertEqual(views.count, 0)  // Invalid views are skipped
        case .failure:
            XCTFail("Expected success")
        }
    }

    func testLoadViewMissingName() {
        let viewContent = """
        ---
        type: view
        display_style: list
        ---
        """

        fileSystem.files["/views/noname.md"] = viewContent

        let result = viewManager.loadViews(from: ["/views"])

        switch result {
        case .success(let views):
            XCTAssertEqual(views.count, 0)  // Invalid views are skipped
        case .failure:
            XCTFail("Expected success")
        }
    }

    // MARK: - View Validation Tests

    func testValidateViewValid() {
        let view = SavedView(
            name: "Test View",
            filters: ViewFilters(itemTypes: ["todo"]),
            displayStyle: .list
        )

        let result = viewManager.validateView(view)

        switch result {
        case .success:
            break  // Expected
        case .failure(let error):
            XCTFail("Expected valid, got error: \(error)")
        }
    }

    func testValidateViewEmptyName() {
        let view = SavedView(
            name: "",
            displayStyle: .list
        )

        let result = viewManager.validateView(view)

        switch result {
        case .success:
            XCTFail("Expected error for empty name")
        case .failure:
            break  // Expected
        }
    }

    func testValidateViewValidDisplayStyle() {
        let viewList = SavedView(name: "Test", displayStyle: .list)
        let viewCard = SavedView(name: "Test", displayStyle: .card)

        XCTAssertTrue(viewManager.validateView(viewList).isSuccess)
        XCTAssertTrue(viewManager.validateView(viewCard).isSuccess)
    }

    // MARK: - View Application Tests

    func testApplyViewNoFilters() {
        let items = [
            Item(type: "todo", title: "Task 1", completed: false, sourceFile: "test.md"),
            Item(type: "todo", title: "Task 2", completed: false, sourceFile: "test.md"),
        ]

        let view = SavedView(name: "All", filters: ViewFilters())
        let result = viewManager.applyView(view, to: items)

        XCTAssertEqual(result.count, 2)
    }

    func testApplyViewWithFilters() {
        let items = [
            Item(type: "todo", title: "Work Task", tags: ["work"], completed: false, sourceFile: "test.md"),
            Item(type: "book", title: "Reading", tags: ["books"], completed: false, sourceFile: "test.md"),
        ]

        let view = SavedView(
            name: "Todos",
            filters: ViewFilters(itemTypes: ["todo"])
        )
        let result = viewManager.applyView(view, to: items)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].type, "todo")
    }

    func testApplyViewWithRelativeDateFilter() {
        let now = Date()
        let tomorrow = now.addingTimeInterval(86400)
        let nextWeek = now.addingTimeInterval(7 * 86400)

        let items = [
            Item(type: "todo", title: "Due tomorrow", properties: ["dueDate": .date(tomorrow)], completed: false, sourceFile: "test.md"),
            Item(type: "todo", title: "Due next week", properties: ["dueDate": .date(nextWeek)], completed: false, sourceFile: "test.md"),
        ]

        let relativeDateParser = RelativeDateParser()
        guard let dueBefore = relativeDateParser.parse("+3d") else {
            XCTFail("Failed to parse relative date")
            return
        }

        let view = SavedView(
            name: "Due Soon",
            filters: ViewFilters(dueBefore: dueBefore)
        )
        let result = viewManager.applyView(view, to: items)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Due tomorrow")
    }

    // MARK: - View File Scanning Tests

    func testScanViewFolder() {
        let view1 = """
        ---
        type: view
        name: View 1
        ---
        """
        let view2 = """
        ---
        type: view
        name: View 2
        ---
        """

        fileSystem.files["/views/view1.md"] = view1
        fileSystem.files["/views/view2.md"] = view2

        let result = viewManager.loadViews(from: ["/views"])

        switch result {
        case .success(let views):
            XCTAssertEqual(views.count, 2)
        case .failure:
            XCTFail("Expected success")
        }
    }

    func testLoadViewsEmptyFolder() {
        let result = viewManager.loadViews(from: ["/empty"])

        switch result {
        case .success(let views):
            XCTAssertEqual(views.count, 0)
        case .failure:
            XCTFail("Expected success")
        }
    }

    func testLoadViewsNonMarkdownFilesIgnored() {
        fileSystem.files["/views/readme.txt"] = "Not markdown"
        fileSystem.files["/views/script.py"] = "print('hello')"

        let result = viewManager.loadViews(from: ["/views"])

        switch result {
        case .success(let views):
            XCTAssertEqual(views.count, 0)
        case .failure:
            XCTFail("Expected success")
        }
    }
}

// MARK: - Test Helpers

extension Result {
    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

/// Mock file system for testing
class TestFileSystemManager: FileSystemManager {
    var files: [String: String] = [:]

    func readFile(at path: String) -> Result<String, FileError> {
        if let content = files[path] {
            return .success(content)
        }
        return .failure(.notFound("File not found: \(path)"))
    }

    func writeFile(at path: String, content: String) -> Result<Void, FileError> {
        files[path] = content
        return .success(())
    }

    func scanDirectory(at path: String, recursive: Bool) -> Result<[String], FileError> {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        let markdownFiles = files.keys.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".md") }
        return .success(markdownFiles.sorted())
    }

    func listSubdirectories(at path: String) -> Result<[String], FileError> {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        let subdirs = Set<String>(files.keys.compactMap { filePath in
            guard filePath.hasPrefix(prefix), filePath != prefix else { return nil }
            let remainder = String(filePath.dropFirst(prefix.count))
            let components = remainder.components(separatedBy: "/")
            return components.count > 1 ? components[0] : nil
        })
        return .success(subdirs.sorted())
    }
}
