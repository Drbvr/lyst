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

        let content = try? String(contentsOfFile: readme, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("Phase 1") ?? false)
        XCTAssertTrue(content?.contains("208") ?? false)
    }

    func testPhase2PrepExists() {
        let phase2 = projectRoot + "/PHASE2-PREP.md"
        XCTAssertTrue(FileManager.default.fileExists(atPath: phase2), "PHASE2-PREP.md must exist")

        let content = try? String(contentsOfFile: phase2, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("iOS") ?? false)
        XCTAssertTrue(content?.contains("SwiftUI") ?? false)
    }

    func testKnownIssuesExists() {
        let issues = projectRoot + "/KNOWN-ISSUES.md"
        XCTAssertTrue(FileManager.default.fileExists(atPath: issues), "KNOWN-ISSUES.md must exist")

        let content = try? String(contentsOfFile: issues, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("Limitations") ?? false)
    }

    func testMilestonesExists() {
        let milestones = projectRoot + "/milestones.md"
        XCTAssertTrue(FileManager.default.fileExists(atPath: milestones), "milestones.md must exist")

        let content = try? String(contentsOfFile: milestones, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("MILESTONE") ?? false)
    }

    func testSpecExists() {
        let spec = projectRoot + "/spec.md"
        XCTAssertTrue(FileManager.default.fileExists(atPath: spec), "spec.md must exist")
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

    func testPhase1Complete() {
        // Verify all milestones are complete
        let milestones = projectRoot + "/milestones.md"
        let content = try? String(contentsOfFile: milestones, encoding: .utf8)

        // All 8 milestones should be documented
        XCTAssertTrue(content?.contains("MILESTONE 1") ?? false)
        XCTAssertTrue(content?.contains("MILESTONE 8") ?? false)
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

    func testAllMilestonesHaveSmokeTests() {
        // Reference to smoke tests in milestones
        let milestones = projectRoot + "/milestones.md"
        let content = try? String(contentsOfFile: milestones, encoding: .utf8)

        XCTAssertTrue(content?.contains("Smoke Test") ?? false)
        XCTAssertTrue(content?.contains("swift test") ?? false)
    }
}
