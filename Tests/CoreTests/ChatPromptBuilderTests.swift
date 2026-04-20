import Foundation
import XCTest

#if canImport(Core)
import Core
#endif

final class ChatPromptBuilderTests: XCTestCase {

    func testSystemPromptSteersToSingularExistingTypes() {
        let prompt = ChatPromptBuilder.systemPrompt(vaultName: "ListAppVault", noteCount: 10)
        XCTAssertTrue(prompt.contains("book\", not \"books"))
    }

    func testSystemPromptRequiresConfirmationBeforeNewType() {
        let prompt = ChatPromptBuilder.systemPrompt(vaultName: "ListAppVault", noteCount: 10)
        XCTAssertTrue(prompt.contains("explicitly asks for one or confirms it"))
    }
}
