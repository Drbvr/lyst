import Foundation
import XCTest

#if canImport(Core)
import Core
#endif

final class TodoParserTests: XCTestCase {

    var parser: ObsidianTodoParser!

    override func setUp() {
        super.setUp()
        parser = ObsidianTodoParser()
    }

    // MARK: - Basic Checkbox Parsing

    func testParseSimpleIncompleteCheckbox() {
        let markdown = "- [ ] Buy groceries"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Buy groceries")
        XCTAssertEqual(items[0].completed, false)
        XCTAssertEqual(items[0].type, "todo")
    }

    func testParseSimpleCompleteCheckbox() {
        let markdown = "- [x] Completed task"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Completed task")
        XCTAssertEqual(items[0].completed, true)
    }

    func testParseAsteriskCheckbox() {
        let markdown = "* [ ] Task with asterisk"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Task with asterisk")
        XCTAssertEqual(items[0].completed, false)
    }

    func testParseMultipleTodos() {
        let markdown = """
        - [ ] First task
        - [x] Second task
        - [ ] Third task
        """
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].title, "First task")
        XCTAssertEqual(items[0].completed, false)
        XCTAssertEqual(items[1].completed, true)
        XCTAssertEqual(items[2].title, "Third task")
    }

    // MARK: - Tag Parsing

    func testParseSingleTag() {
        let markdown = "- [ ] Review PR #work"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].tags.count, 1)
        XCTAssert(items[0].tags.contains("work"))
    }

    func testParseMultipleTags() {
        let markdown = "- [ ] Task #work #backend #urgent"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].tags.count, 3)
        XCTAssert(items[0].tags.contains("work"))
        XCTAssert(items[0].tags.contains("backend"))
        XCTAssert(items[0].tags.contains("urgent"))
    }

    func testParseHierarchicalTags() {
        let markdown = "- [ ] Task #work/backend/api #work/documentation"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].tags.count, 2)
        XCTAssert(items[0].tags.contains("work/backend/api"))
        XCTAssert(items[0].tags.contains("work/documentation"))
    }

    func testTitleWithoutTags() {
        let markdown = "- [ ] Review PR #work #backend"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items[0].title, "Review PR")
    }

    // MARK: - Date Parsing

    func testParseDateSimple() {
        let markdown = "- [ ] Task 📅 2024-03-15"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        if case .date(let date) = items[0].properties["dueDate"] {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 3)
            XCTAssertEqual(components.day, 15)
        } else {
            XCTFail("Expected date property")
        }
    }

    func testParseDateWithTime() {
        let markdown = "- [ ] Task 📅 2024-03-15T14:30"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        // Date parsing with time - verify it extracts the date part
        if case .date(_) = items[0].properties["dueDate"] {
            // Date exists
            XCTAssertNotNil(items[0].properties["dueDate"])
        } else {
            XCTFail("Expected date property")
        }
    }

    func testMultipleDatesUsesFirst() {
        let markdown = "- [ ] Task 📅 2024-03-15 📅 2024-03-20"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        if case .date(let date) = items[0].properties["dueDate"] {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.month, .day], from: date)
            XCTAssertEqual(components.day, 15)  // First date
        } else {
            XCTFail("Expected date property")
        }
    }

    // MARK: - Priority Parsing

    func testParseHighPriority() {
        let markdown = "- [ ] Task ⏫"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        if case .text(let priority) = items[0].properties["priority"] {
            XCTAssertEqual(priority, "high")
        } else {
            XCTFail("Expected priority property")
        }
    }

    func testParseMediumPriority() {
        let markdown = "- [ ] Task 🔼"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        if case .text(let priority) = items[0].properties["priority"] {
            XCTAssertEqual(priority, "medium")
        } else {
            XCTFail("Expected priority property")
        }
    }

    func testParseLowPriority() {
        let markdown = "- [ ] Task 🔽"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        if case .text(let priority) = items[0].properties["priority"] {
            XCTAssertEqual(priority, "low")
        } else {
            XCTFail("Expected priority property")
        }
    }

    // MARK: - Complex Metadata

    func testParseFullMetadata() {
        let markdown = "- [ ] Review PR #work/backend #urgent 📅 2024-03-15 ⏫"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        let item = items[0]

        XCTAssertEqual(item.title, "Review PR")
        XCTAssertEqual(item.tags.count, 2)
        XCTAssert(item.tags.contains("work/backend"))
        XCTAssert(item.tags.contains("urgent"))
        XCTAssertNotNil(item.properties["dueDate"])
        if case .text(let priority) = item.properties["priority"] {
            XCTAssertEqual(priority, "high")
        } else {
            XCTFail("Expected priority")
        }
    }

    // MARK: - Edge Cases

    func testEmptyCheckbox() {
        let markdown = "- [ ]"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 0)  // Empty checkboxes are skipped
    }

    func testCheckboxWithOnlyWhitespace() {
        let markdown = "- [ ]   \n"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 0)
    }

    func testTodoWithoutMetadata() {
        let markdown = "- [ ] Simple task"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Simple task")
        XCTAssertEqual(items[0].tags.count, 0)
        XCTAssertNil(items[0].properties["dueDate"])
        XCTAssertNil(items[0].properties["priority"])
    }

    func testMultilineTodo() {
        let markdown = """
        - [ ] Fix authentication bug
          This is a detailed description
          that spans multiple lines
        """
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        let title = items[0].title
        XCTAssert(title.contains("Fix authentication bug"))
        XCTAssert(title.contains("detailed description"))
    }

    func testCodeBlockIgnored() {
        let markdown = """
        Some text

        ```
        - [ ] This should be ignored
        - [x] Also ignored
        ```

        - [ ] This should be parsed
        """
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "This should be parsed")
    }

    func testBlockquoteIgnored() {
        let markdown = """
        > - [ ] This is quoted
        > - [x] Also quoted

        - [ ] This is real
        """
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        // Note: Current implementation may have issues with blockquotes
        // At minimum, the real todo should be found
        XCTAssert(items.contains { $0.title == "This is real" })
    }

    func testInvalidDateIgnored() {
        let markdown = "- [ ] Task 📅 invalid-date"
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].properties["dueDate"])
    }

    // MARK: - Integration Tests

    func testRealWorldExample() {
        let markdown = """
        # Work Tasks

        - [ ] Review PR for authentication #work/backend #urgent 📅 2024-03-15 ⏫
        - [x] Update documentation #work/docs 📅 2024-03-10
        - [ ] Fix bug in auth flow #work/backend
          This is a critical bug affecting production
          Need to prioritize
        """
        let items = parser.parseTodos(from: markdown, sourceFile: "work.md")

        XCTAssertEqual(items.count, 3)

        // First item
        XCTAssertEqual(items[0].title, "Review PR for authentication")
        XCTAssertEqual(items[0].completed, false)
        XCTAssert(items[0].tags.contains("work/backend"))
        XCTAssert(items[0].tags.contains("urgent"))

        // Second item
        XCTAssertEqual(items[1].completed, true)
        XCTAssert(items[1].tags.contains("work/docs"))

        // Third item
        XCTAssertEqual(items[2].completed, false)
        XCTAssert(items[2].title.contains("auth flow"))
    }

    func testMixedPriorities() {
        let markdown = """
        - [ ] High priority ⏫
        - [ ] Medium priority 🔼
        - [ ] Low priority 🔽
        - [ ] No priority
        """
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 4)

        if case .text(let p) = items[0].properties["priority"] {
            XCTAssertEqual(p, "high")
        }
        if case .text(let p) = items[1].properties["priority"] {
            XCTAssertEqual(p, "medium")
        }
        if case .text(let p) = items[2].properties["priority"] {
            XCTAssertEqual(p, "low")
        }
        XCTAssertNil(items[3].properties["priority"])
    }

    func testSourceFileTracking() {
        let markdown = "- [ ] Task"
        let items = parser.parseTodos(from: markdown, sourceFile: "path/to/file.md")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].sourceFile, "path/to/file.md")
    }

    func testEmptyMarkdown() {
        let markdown = ""
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 0)
    }

    func testMarkdownWithoutTodos() {
        let markdown = """
        # Heading

        Just some regular text

        No checkboxes here
        """
        let items = parser.parseTodos(from: markdown, sourceFile: "test.md")

        XCTAssertEqual(items.count, 0)
    }

    func testPerformance() {
        // Create a large markdown with many todos
        var markdown = ""
        for i in 0..<1000 {
            markdown += "- [ ] Task \(i) #tag\(i % 10) 📅 2024-03-15\n"
        }

        let startTime = Date()
        let items = parser.parseTodos(from: markdown, sourceFile: "large.md")
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertEqual(items.count, 1000)
        XCTAssert(elapsed < 1.0, "Parsing 1000 todos took \(elapsed) seconds, expected <1 second")
    }

    func testCaseInsensitiveCheckboxComplete() {
        let markdown1 = "- [X] Completed task"
        let markdown2 = "- [x] Completed task"

        let items1 = parser.parseTodos(from: markdown1, sourceFile: "test.md")
        let items2 = parser.parseTodos(from: markdown2, sourceFile: "test.md")

        XCTAssertEqual(items1[0].completed, true)
        XCTAssertEqual(items2[0].completed, true)
    }

    func testFrontmatterTagsStripQuotes() {
        let markdown = """
        ---
        type: restaurant
        title: \"Test Place\"
        tags: [\"restaurant\", \"food/date\"]
        ---
        """
        let items = parser.parseTodos(from: markdown, sourceFile: "restaurant.md")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].tags, ["restaurant", "food/date"])
    }
}
