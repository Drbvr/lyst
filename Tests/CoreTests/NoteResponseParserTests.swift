import Foundation
import XCTest

#if canImport(Core)
import Core
#endif

final class NoteResponseParserTests: XCTestCase {

    // MARK: - Helpers

    private let parser = NoteResponseParser()

    private let bookType = ListType(
        name: "book",
        fields: [
            FieldDefinition(name: "title",  type: .text,   required: true),
            FieldDefinition(name: "author", type: .text,   required: false),
            FieldDefinition(name: "rating", type: .number, required: false),
        ]
    )

    private let movieType = ListType(
        name: "movie",
        fields: [
            FieldDefinition(name: "title",    type: .text,   required: true),
            FieldDefinition(name: "director", type: .text,   required: false),
        ]
    )

    // MARK: - Single block

    func testSingleValidBlock() {
        let response = """
        ```yaml
        ---
        type: book
        title: Dune
        author: Frank Herbert
        ---
        ```
        """
        let results = parser.parseAll(response: response, listTypes: [bookType, movieType])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Dune")
        XCTAssertEqual(results[0].type,  "book")
        if case .text(let a) = results[0].properties["author"] {
            XCTAssertEqual(a, "Frank Herbert")
        } else {
            XCTFail("Expected text value for author")
        }
    }

    // MARK: - Multiple blocks

    func testMultipleValidBlocks() {
        let response = """
        ```yaml
        ---
        type: book
        title: Dune
        ---
        ```
        ```yaml
        ---
        type: movie
        title: Arrival
        ---
        ```
        """
        let results = parser.parseAll(response: response, listTypes: [bookType, movieType])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Dune")
        XCTAssertEqual(results[0].type,  "book")
        XCTAssertEqual(results[1].title, "Arrival")
        XCTAssertEqual(results[1].type,  "movie")
    }

    // MARK: - Invalid blocks dropped

    func testInvalidBlocksAreDropped() {
        let response = """
        ```yaml
        ---
        type: book
        title: Foundation
        ---
        ```
        ```yaml
        ---
        type: unknowntype
        title: SomethingElse
        ---
        ```
        ```yaml
        ---
        title: MissingType
        ---
        ```
        """
        let results = parser.parseAll(response: response, listTypes: [bookType, movieType])
        // Only the first block has a recognised type
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Foundation")
    }

    // MARK: - Surrounding prose ignored

    func testSurroundingProseIsIgnored() {
        let response = """
        Here are the notes I created for you:

        ```yaml
        ---
        type: book
        title: Neuromancer
        author: William Gibson
        ---
        ```

        And another one:

        ```yaml
        ---
        type: movie
        title: Blade Runner
        ---
        ```

        Let me know if you'd like changes!
        """
        let results = parser.parseAll(response: response, listTypes: [bookType, movieType])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Neuromancer")
        XCTAssertEqual(results[1].title, "Blade Runner")
    }

    // MARK: - Windows line endings

    func testWindowsLineEndings() {
        let response = "```yaml\r\n---\r\ntype: book\r\ntitle: The Road\r\n---\r\n```"
        let results = parser.parseAll(response: response, listTypes: [bookType, movieType])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "The Road")
    }

    // MARK: - Tags

    func testTagsAreParsed() {
        let response = """
        ```yaml
        ---
        type: book
        title: Dune
        tags: [scifi, classic]
        ---
        ```
        """
        let results = parser.parseAll(response: response, listTypes: [bookType])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].tags, "scifi, classic")
    }

    // MARK: - Number property

    func testNumberPropertyParsed() {
        let response = """
        ```yaml
        ---
        type: book
        title: Dune
        rating: 9
        ---
        ```
        """
        let results = parser.parseAll(response: response, listTypes: [bookType])
        XCTAssertEqual(results.count, 1)
        if case .number(let r) = results[0].properties["rating"] {
            XCTAssertEqual(r, 9.0)
        } else {
            XCTFail("Expected number value for rating")
        }
    }

    // MARK: - Empty response

    func testEmptyResponseReturnsEmpty() {
        let results = parser.parseAll(response: "", listTypes: [bookType])
        XCTAssertTrue(results.isEmpty)
    }

    func testResponseWithNoBlocksReturnsEmpty() {
        let results = parser.parseAll(response: "Here is my analysis of the content.", listTypes: [bookType])
        XCTAssertTrue(results.isEmpty)
    }
}
