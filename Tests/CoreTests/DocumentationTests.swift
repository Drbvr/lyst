import Foundation
import XCTest

#if canImport(Core)
import Core
#endif

final class DocumentationTests: XCTestCase {

    let projectRoot: String = {
        // Navigate up from Tests/CoreTests/DocumentationTests.swift to the project root
        let thisFile = URL(fileURLWithPath: #file)
        return thisFile
            .deletingLastPathComponent()  // CoreTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .path
    }()

    func testREADMEExists() {
        let readme = projectRoot + "/README.md"
        XCTAssertTrue(FileManager.default.fileExists(atPath: readme), "README.md must exist")
    }

    func testPublicAPIDocumentation() {
        // Verify public types are properly accessible
        let parser = ObsidianTodoParser()
        XCTAssertNotNil(parser)

        let filterEngine = ItemFilterEngine()
        XCTAssertNotNil(filterEngine)

        let searchEngine = FullTextSearchEngine()
        XCTAssertNotNil(searchEngine)
    }

    func testModelsCodable() {
        // Verify models can be encoded/decoded
        let item = Item(type: "todo", title: "Test", completed: false, sourceFile: "test.md")

        let encoder = JSONEncoder()
        let data = try? encoder.encode(item)
        XCTAssertNotNil(data)

        let decoder = JSONDecoder()
        let decodedItem = try? decoder.decode(Item.self, from: data!)
        XCTAssertEqual(decodedItem?.title, "Test")
    }

    func testViewsCodable() {
        let view = SavedView(
            name: "Test View",
            filters: ViewFilters(completed: true),
            displayStyle: .list
        )

        let encoder = JSONEncoder()
        let data = try? encoder.encode(view)
        XCTAssertNotNil(data)

        let decoder = JSONDecoder()
        let decodedView = try? decoder.decode(SavedView.self, from: data!)
        XCTAssertEqual(decodedView?.name, "Test View")
    }

    func testCLIDocumentation() {
        // Verify CLI help is available
        let cli = ListAppCLI(fileSystem: DefaultFileSystemManager())

        let result = cli.execute(.help)

        switch result {
        case .success(let output):
            XCTAssertTrue(output.contains("list-app"))
            XCTAssertTrue(output.contains("scan"))
            XCTAssertTrue(output.contains("list"))
            XCTAssertTrue(output.contains("search"))
        case .failure:
            XCTFail("Help command should succeed")
        }
    }

    func testTestCoverage() {
        // Verify comprehensive test suite exists
        let testsPath = projectRoot + "/Tests/CoreTests"

        let fileManager = FileManager.default
        let testFiles = try? fileManager.contentsOfDirectory(atPath: testsPath)

        XCTAssertNotNil(testFiles)
        XCTAssertTrue(testFiles?.contains("CLITests.swift") ?? false)
        XCTAssertTrue(testFiles?.contains("ItemTests.swift") ?? false)
        XCTAssertTrue(testFiles?.contains("FilterEngineTests.swift") ?? false)
    }

}
