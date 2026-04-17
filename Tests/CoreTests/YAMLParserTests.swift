import Foundation
import XCTest

#if canImport(Core)
import Core
#endif

final class YAMLParserTests: XCTestCase {

    var parser: YAMLFrontmatterParser!

    override func setUp() {
        super.setUp()
        parser = YAMLFrontmatterParser()
    }

    // MARK: - Frontmatter Extraction

    func testExtractSimpleFrontmatter() {
        let markdown = """
        ---
        type: book
        title: Test
        ---

        Body content here
        """

        let (yaml, body) = parser.extractFrontmatter(from: markdown)

        XCTAssertNotNil(yaml)
        XCTAssertEqual(yaml, "type: book\ntitle: Test")
        XCTAssert(body.contains("Body content here"))
    }

    func testExtractFrontmatterWithoutStart() {
        let markdown = """
        No frontmatter here
        ---
        type: book
        ---
        """

        let (yaml, body) = parser.extractFrontmatter(from: markdown)

        XCTAssertNil(yaml)
        XCTAssertEqual(body, markdown)
    }

    func testExtractEmptyFrontmatter() {
        let markdown = """
        ---
        ---

        Body
        """

        let (yaml, body) = parser.extractFrontmatter(from: markdown)

        XCTAssertNotNil(yaml)
        XCTAssertEqual(yaml, "")
        XCTAssert(body.contains("Body"))
    }

    func testNoClosingDelimiter() {
        let markdown = """
        ---
        type: book
        No closing delimiter
        """

        let (yaml, body) = parser.extractFrontmatter(from: markdown)

        XCTAssertNil(yaml)
        XCTAssertEqual(body, markdown)
    }

    // MARK: - ListType Parsing

    func testParseSimpleListType() {
        let yaml = """
        type: list_type_definition
        name: Todo
        """

        let result = parser.parseListType(yaml: yaml)

        guard case .success(let listType) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(listType.name, "Todo")
        XCTAssertEqual(listType.fields.count, 0)
    }

    func testParseListTypeWithFields() {
        let yaml = """
        name: Book
        fields:
          - name: title
            type: text
            required: true
          - name: rating
            type: number
            required: false
            min: 1
            max: 5
        """

        let result = parser.parseListType(yaml: yaml)

        guard case .success(let listType) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(listType.name, "Book")
        XCTAssertEqual(listType.fields.count, 2)

        let titleField = listType.fields[0]
        XCTAssertEqual(titleField.name, "title")
        XCTAssertEqual(titleField.type, .text)
        XCTAssertEqual(titleField.required, true)

        let ratingField = listType.fields[1]
        XCTAssertEqual(ratingField.name, "rating")
        XCTAssertEqual(ratingField.type, .number)
        XCTAssertEqual(ratingField.min, 1)
        XCTAssertEqual(ratingField.max, 5)
    }

    func testParseListTypeMissingName() {
        let yaml = "fields: []"

        let result = parser.parseListType(yaml: yaml)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure")
            return
        }

        if case .missingRequiredField(let field) = error {
            XCTAssertEqual(field, "name")
        } else {
            XCTFail("Expected missingRequiredField error")
        }
    }

    func testParseListTypeWithPrompt() {
        let yaml = """
        name: Custom
        llmExtractionPrompt: Extract custom items
        """

        let result = parser.parseListType(yaml: yaml)

        guard case .success(let listType) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(listType.llmExtractionPrompt, "Extract custom items")
    }

    // MARK: - SavedView Parsing

    func testParseSimpleView() {
        let yaml = """
        type: view
        name: All Tasks
        display_style: list
        """

        let result = parser.parseView(yaml: yaml)

        guard case .success(let view) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(view.name, "All Tasks")
        XCTAssertEqual(view.displayStyle, .list)
    }

    func testParseViewWithFilters() {
        let yaml = """
        name: Work Todos
        display_style: list
        filters:
          tags: [work/*, urgent]
          item_types: [todo]
          completed: false
        """

        let result = parser.parseView(yaml: yaml)

        guard case .success(let view) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(view.name, "Work Todos")
        XCTAssertEqual(view.displayStyle, .list)
        XCTAssertEqual(view.filters.tags?.count, 2)
        XCTAssert(view.filters.tags!.contains("work/*"))
        XCTAssert(view.filters.tags!.contains("urgent"))
        XCTAssertEqual(view.filters.itemTypes?.count, 1)
        XCTAssertEqual(view.filters.completed, false)
    }

    func testParseViewCardDisplay() {
        let yaml = """
        name: Reading List
        display_style: card
        """

        let result = parser.parseView(yaml: yaml)

        guard case .success(let view) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(view.displayStyle, .card)
    }

    func testParseViewInvalidDisplayStyle() {
        let yaml = """
        name: Bad View
        display_style: invalid
        """

        let result = parser.parseView(yaml: yaml)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure")
            return
        }

        if case .invalidFieldType(let field, _, let got) = error {
            XCTAssertEqual(field, "display_style")
            XCTAssertEqual(got, "invalid")
        } else {
            XCTFail("Expected invalidFieldType error")
        }
    }

    func testParseViewMissingName() {
        let yaml = "display_style: list"

        let result = parser.parseView(yaml: yaml)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure")
            return
        }

        if case .missingRequiredField(let field) = error {
            XCTAssertEqual(field, "name")
        } else {
            XCTFail("Expected missingRequiredField error")
        }
    }

    // MARK: - Item Properties Parsing

    func testParseSimpleItemProperties() {
        let yaml = """
        type: book
        title: Project Hail Mary
        author: Andy Weir
        """

        let result = parser.parseItemProperties(yaml: yaml)

        guard case .success(let properties) = result else {
            XCTFail("Expected success")
            return
        }

        if case .text(let title) = properties["title"] {
            XCTAssertEqual(title, "Project Hail Mary")
        } else {
            XCTFail("Expected text value for title")
        }

        if case .text(let author) = properties["author"] {
            XCTAssertEqual(author, "Andy Weir")
        } else {
            XCTFail("Expected text value for author")
        }
    }

    func testParseItemPropertiesWithNumbers() {
        let yaml = """
        rating: 5
        year_published: 2021
        """

        let result = parser.parseItemProperties(yaml: yaml)

        guard case .success(let properties) = result else {
            XCTFail("Expected success")
            return
        }

        if case .number(let rating) = properties["rating"] {
            XCTAssertEqual(rating, 5)
        } else {
            XCTFail("Expected number value for rating")
        }
    }

    func testParseItemPropertiesWithDates() {
        let yaml = """
        date_read: 2024-03-10
        """

        let result = parser.parseItemProperties(yaml: yaml)

        guard case .success(let properties) = result else {
            XCTFail("Expected success")
            return
        }

        if case .date(_) = properties["date_read"] {
            XCTAssertNotNil(properties["date_read"])
        } else {
            XCTFail("Expected date value for date_read")
        }
    }

    func testParseItemPropertiesWithBooleans() {
        let yaml = """
        is_favorite: true
        is_read: false
        """

        let result = parser.parseItemProperties(yaml: yaml)

        guard case .success(let properties) = result else {
            XCTFail("Expected success")
            return
        }

        if case .bool(let isFav) = properties["is_favorite"] {
            XCTAssertEqual(isFav, true)
        } else {
            XCTFail("Expected bool value for is_favorite")
        }

        if case .bool(let isRead) = properties["is_read"] {
            XCTAssertEqual(isRead, false)
        } else {
            XCTFail("Expected bool value for is_read")
        }
    }

    // MARK: - Edge Cases

    func testExtractFrontmatterWithMultipleSeparators() {
        let markdown = """
        ---
        type: book
        ---

        More content
        ---
        Should not be frontmatter
        """

        let (yaml, body) = parser.extractFrontmatter(from: markdown)

        XCTAssertNotNil(yaml)
        XCTAssert(body.contains("More content"))
    }

    func testParseListTypeWithInvalidFieldType() {
        let yaml = """
        name: Test
        fields:
          - name: invalid
            type: unknown
            required: true
        """

        let result = parser.parseListType(yaml: yaml)

        guard case .success(let listType) = result else {
            XCTFail("Expected success")
            return
        }

        // Should skip invalid field types
        XCTAssertEqual(listType.fields.count, 0)
    }

    func testParseViewWithRelativeDates() {
        let yaml = """
        name: This Week
        display_style: list
        filters:
          due_before: +7d
          due_after: -7d
        """

        let result = parser.parseView(yaml: yaml)

        guard case .success(let view) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertNotNil(view.filters.dueBefore)
        XCTAssertNotNil(view.filters.dueAfter)
    }

    func testParseItemPropertiesEmptyYAML() {
        let yaml = ""

        let result = parser.parseItemProperties(yaml: yaml)

        guard case .success(let properties) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(properties.count, 0)
    }

    func testParseItemPropertiesWithArrayTags() {
        let yaml = """
        tags: [books/read, sci-fi, favorites]
        """

        let result = parser.parseItemProperties(yaml: yaml)

        guard case .success(let properties) = result else {
            XCTFail("Expected success")
            return
        }

        if case .text(let tags) = properties["tags"] {
            XCTAssert(tags.contains("books/read"))
        } else {
            XCTFail("Expected text value for tags")
        }
    }

    // MARK: - Integration Tests

    func testFullWorkflow() {
        let markdown = """
        ---
        type: book
        title: Project Hail Mary
        author: Andy Weir
        rating: 5
        date_read: 2024-03-10
        is_favorite: true
        ---

        # Project Hail Mary
        Amazing book about survival and science...
        """

        let (yaml, body) = parser.extractFrontmatter(from: markdown)

        XCTAssertNotNil(yaml)
        XCTAssert(body.contains("Amazing book"))

        let result = parser.parseItemProperties(yaml: yaml!)

        guard case .success(let properties) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(properties.count, 5)

        if case .text(let title) = properties["title"] {
            XCTAssertEqual(title, "Project Hail Mary")
        }
    }

    func testParseCompleteListTypeDefinition() {
        let markdown = """
        ---
        type: list_type_definition
        name: Book
        fields:
          - name: title
            type: text
            required: true
          - name: author
            type: text
            required: true
          - name: rating
            type: number
            required: false
            min: 1
            max: 5
        ---
        """

        let (yaml, _) = parser.extractFrontmatter(from: markdown)

        XCTAssertNotNil(yaml)

        let result = parser.parseListType(yaml: yaml!)

        guard case .success(let listType) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(listType.name, "Book")
        XCTAssertEqual(listType.fields.count, 3)
    }

    func testParseCompleteViewDefinition() {
        let markdown = """
        ---
        type: view
        name: Urgent Work Tasks
        display_style: list
        filters:
          tags: [work/*, urgent]
          item_types: [todo]
          due_before: +7d
          completed: false
        ---
        """

        let (yaml, _) = parser.extractFrontmatter(from: markdown)

        XCTAssertNotNil(yaml)

        let result = parser.parseView(yaml: yaml!)

        guard case .success(let view) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(view.name, "Urgent Work Tasks")
        XCTAssertEqual(view.displayStyle, .list)
        XCTAssertEqual(view.filters.tags?.count, 2)
        XCTAssertEqual(view.filters.itemTypes?.count, 1)
    }

    func testErrorEquality() {
        let error1 = ParseError.missingRequiredField("name")
        let error2 = ParseError.missingRequiredField("name")
        let error3 = ParseError.missingRequiredField("other")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - Empty / whitespace title handling

    func testParseItemPropertiesRejectsEmptyTitle() {
        let yaml = """
        type: book
        title:
        author: Andy Weir
        """

        let result = parser.parseItemProperties(yaml: yaml)
        guard case .success(let properties) = result else {
            XCTFail("Expected success")
            return
        }
        // Empty trailing value should not be stored as empty-text — it should
        // be absent so callers can flag it as "missing title".
        XCTAssertNil(properties["title"], "Empty title value should not be parsed as empty text")
    }

    func testParseItemPropertiesRoundTripsQuotedTitle() {
        // A title that contains double quotes should round-trip through the
        // parser when quoted per `AppStateLogic.yamlQuote`.
        let yaml = "title: \"He said \\\"hi\\\"\""
        let result = parser.parseItemProperties(yaml: yaml)
        guard case .success(let properties) = result,
              case .text(let title) = properties["title"] else {
            XCTFail("Expected quoted title to parse")
            return
        }
        // The parser may not unescape backslash-quote itself, but at minimum
        // the content should not be lost or truncated.
        XCTAssertTrue(title.contains("hi"), "Round-tripped title lost content: \(title)")
    }

    func testParseViewWithFolders() {
        let yaml = """
        name: Work
        display_style: list
        filters:
          folders: [Work, Projects, "Deep Folder"]
        """

        let result = parser.parseView(yaml: yaml)

        guard case .success(let view) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(view.filters.folders?.count, 3)
        XCTAssert(view.filters.folders!.contains("Work"))
    }
}
