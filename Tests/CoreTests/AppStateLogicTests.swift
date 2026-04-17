import Foundation
import XCTest

#if canImport(Core)
import Core
#endif

/// Exercises the pure functions extracted to `Core/State/AppStateLogic.swift`.
/// All tests run on Linux; no `@Observable` / SwiftUI dependencies.
final class AppStateLogicTests: XCTestCase {

    // MARK: - yamlQuote

    func testYAMLQuoteWrapsPlainString() {
        XCTAssertEqual(AppStateLogic.yamlQuote("Dune"), "\"Dune\"")
    }

    func testYAMLQuoteEscapesDoubleQuote() {
        XCTAssertEqual(AppStateLogic.yamlQuote("He said \"hi\""), "\"He said \\\"hi\\\"\"")
    }

    func testYAMLQuoteEscapesBackslash() {
        XCTAssertEqual(AppStateLogic.yamlQuote("path\\to\\file"), "\"path\\\\to\\\\file\"")
    }

    func testYAMLQuoteEmptyString() {
        XCTAssertEqual(AppStateLogic.yamlQuote(""), "\"\"")
    }

    // MARK: - sanitizedFilename

    func testSanitizedFilenameStripsSlashes() {
        XCTAssertEqual(AppStateLogic.sanitizedFilename(from: "a/b"), "a-b")
    }

    func testSanitizedFilenameRejectsParentTraversal() {
        XCTAssertNil(AppStateLogic.sanitizedFilename(from: ".."))
        XCTAssertNil(AppStateLogic.sanitizedFilename(from: "../secret"))
    }

    func testSanitizedFilenameRejectsLeadingSlash() {
        XCTAssertNil(AppStateLogic.sanitizedFilename(from: "/etc/passwd"))
    }

    func testSanitizedFilenameRejectsEmpty() {
        XCTAssertNil(AppStateLogic.sanitizedFilename(from: ""))
        XCTAssertNil(AppStateLogic.sanitizedFilename(from: "   "))
    }

    func testSanitizedFilenameAcceptsUnicode() {
        XCTAssertEqual(AppStateLogic.sanitizedFilename(from: "Café ☕"), "Café ☕")
    }

    // MARK: - buildTodoLine

    func testBuildTodoLineBasic() {
        let line = AppStateLogic.buildTodoLine(title: "Pay rent", tags: [], properties: [:])
        XCTAssertEqual(line, "- [ ] Pay rent")
    }

    func testBuildTodoLineWithTags() {
        let line = AppStateLogic.buildTodoLine(title: "Ship", tags: ["work", "urgent"], properties: [:])
        XCTAssertEqual(line, "- [ ] Ship #work #urgent")
    }

    func testBuildTodoLineWithHighPriority() {
        let line = AppStateLogic.buildTodoLine(
            title: "Fix bug", tags: [], properties: ["priority": .text("high")]
        )
        XCTAssertTrue(line.contains("⏫"))
    }

    // MARK: - appendTodoToInbox

    func testAppendTodoAddsTrailingNewline() {
        let result = AppStateLogic.appendTodoToInbox(existingContent: "# Inbox", line: "- [ ] A")
        XCTAssertEqual(result, "# Inbox\n- [ ] A\n")
    }

    func testAppendTodoNormalizesCRLF() {
        let result = AppStateLogic.appendTodoToInbox(existingContent: "# Inbox\r\n- [ ] X\r\n", line: "- [ ] A")
        XCTAssertFalse(result.contains("\r"))
        XCTAssertTrue(result.hasSuffix("- [ ] A\n"))
    }

    // MARK: - serializeYAMLItem

    func testSerializeYAMLQuotesTitleTypeAndTags() {
        let out = AppStateLogic.serializeYAMLItem(
            type: "book",
            title: "The \"Classic\"",
            tags: ["quote\"tag", "plain"],
            properties: [:]
        )
        XCTAssertTrue(out.contains("type: \"book\""))
        XCTAssertTrue(out.contains("title: \"The \\\"Classic\\\"\""))
        XCTAssertTrue(out.contains("\"quote\\\"tag\""))
        XCTAssertTrue(out.contains("\"plain\""))
    }

    func testSerializeYAMLPreventsFrontmatterInjection() {
        // A malicious title with embedded `---` and `owned: true` must not
        // leak out of its quoted scalar.
        let out = AppStateLogic.serializeYAMLItem(
            type: "book",
            title: "bad\n---\nowned: true",
            tags: [],
            properties: [:]
        )
        // The closing --- appears exactly twice (opening + closing of real frontmatter).
        let tripleDashCount = out.components(separatedBy: "\n---").count - 1
        XCTAssertEqual(tripleDashCount, 2, "Injected `---` should be inside quoted title, not a real frontmatter delimiter")
    }

    func testSerializeYAMLOmitsTagsWhenEmpty() {
        let out = AppStateLogic.serializeYAMLItem(type: "book", title: "X", tags: [], properties: [:])
        XCTAssertFalse(out.contains("tags:"))
    }

    // MARK: - isCheckboxLine

    func testIsCheckboxLineMatchesExactTitle() {
        XCTAssertTrue(AppStateLogic.isCheckboxLine("- [ ] Buy", forTitle: "Buy"))
        XCTAssertTrue(AppStateLogic.isCheckboxLine("- [x] Buy", forTitle: "Buy"))
    }

    func testIsCheckboxLineDoesNotMatchTitlePrefix() {
        // Regression: "Buy" must not match "Buy milk".
        XCTAssertFalse(AppStateLogic.isCheckboxLine("- [ ] Buy milk", forTitle: "Buy"))
    }

    func testIsCheckboxLineMatchesWithTags() {
        XCTAssertTrue(AppStateLogic.isCheckboxLine("- [ ] Buy #groceries", forTitle: "Buy"))
    }

    func testIsCheckboxLineHandlesLeadingWhitespace() {
        XCTAssertTrue(AppStateLogic.isCheckboxLine("  - [ ] Buy", forTitle: "Buy"))
    }

    func testIsCheckboxLineRejectsNonCheckbox() {
        XCTAssertFalse(AppStateLogic.isCheckboxLine("Just a Buy line", forTitle: "Buy"))
    }

    func testIsCheckboxLineEscapesRegexMetacharacters() {
        // Title with regex metacharacters must match literally.
        XCTAssertTrue(AppStateLogic.isCheckboxLine("- [ ] Fix (bug)", forTitle: "Fix (bug)"))
    }

    // MARK: - toggleCheckbox

    func testToggleCheckboxOnlyFlipsMatchingTitle() {
        let content = """
        - [ ] Buy
        - [ ] Buy milk
        """
        let toggled = AppStateLogic.toggleCheckbox(in: content, matching: "Buy")
        XCTAssertEqual(toggled, "- [x] Buy\n- [ ] Buy milk")
    }

    func testToggleCheckboxCanFlipCheckedToUnchecked() {
        let toggled = AppStateLogic.toggleCheckbox(in: "- [x] Buy", matching: "Buy")
        XCTAssertEqual(toggled, "- [ ] Buy")
    }

    func testToggleCheckboxReturnsNilWhenNoMatch() {
        let toggled = AppStateLogic.toggleCheckbox(in: "- [ ] Other", matching: "Buy")
        XCTAssertNil(toggled)
    }

    // MARK: - deleteCheckbox

    func testDeleteCheckboxRemovesMatchingLine() {
        let content = """
        - [ ] Buy
        - [ ] Buy milk
        """
        let deleted = AppStateLogic.deleteCheckbox(in: content, matching: "Buy")
        XCTAssertEqual(deleted, "- [ ] Buy milk")
    }

    func testDeleteCheckboxLeavesPrefixedTitlesIntact() {
        let content = "- [ ] Buy milk"
        let deleted = AppStateLogic.deleteCheckbox(in: content, matching: "Buy")
        XCTAssertNil(deleted, "Should not match 'Buy' inside 'Buy milk'")
    }

    // MARK: - toggleYAMLCompleted / updateYAMLItem

    func testToggleYAMLCompletedInsertsWhenMissing() {
        let content = """
        ---
        type: book
        title: Dune
        ---
        """
        let updated = AppStateLogic.toggleYAMLCompleted(in: content, to: true)
        XCTAssertNotNil(updated)
        XCTAssertTrue(updated!.contains("completed: true"))
    }

    func testToggleYAMLCompletedReplacesExisting() {
        let content = """
        ---
        type: book
        title: Dune
        completed: false
        ---
        """
        let updated = AppStateLogic.toggleYAMLCompleted(in: content, to: true)
        XCTAssertTrue(updated!.contains("completed: true"))
        XCTAssertFalse(updated!.contains("completed: false"))
    }

    func testToggleYAMLCompletedReturnsNilWhenMalformed() {
        let content = "not frontmatter at all"
        XCTAssertNil(AppStateLogic.toggleYAMLCompleted(in: content, to: true))
    }

    func testUpdateYAMLItemQuotesTitleAndTags() {
        var item = Item(
            type: "book",
            title: "He said \"hi\"",
            properties: [:],
            tags: ["a\"b"],
            completed: true,
            sourceFile: "/tmp/x.md"
        )
        item.createdAt = Date()
        item.updatedAt = Date()

        let content = """
        ---
        type: book
        title: Old
        ---
        """
        let updated = AppStateLogic.updateYAMLItem(in: content, item: item)
        XCTAssertNotNil(updated)
        XCTAssertTrue(updated!.contains("title: \"He said \\\"hi\\\"\""))
        XCTAssertTrue(updated!.contains("\"a\\\"b\""))
        XCTAssertTrue(updated!.contains("completed: true"))
    }
}
