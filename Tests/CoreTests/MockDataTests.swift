import Foundation
import XCTest

#if canImport(Core)
import Core
#endif

final class MockDataTests: XCTestCase {

    func testMockTodoItems() {
        XCTAssertEqual(MockData.todoItems.count, 10)
        for item in MockData.todoItems {
            XCTAssertEqual(item.type, "todo")
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.sourceFile.isEmpty)
            XCTAssertFalse(item.tags.isEmpty)
        }
    }

    func testMockBookItems() {
        XCTAssertEqual(MockData.bookItems.count, 5)
        for item in MockData.bookItems {
            XCTAssertEqual(item.type, "book")
            XCTAssertNotNil(item.properties["author"])
        }
    }

    func testMockMovieItems() {
        XCTAssertEqual(MockData.movieItems.count, 3)
        for item in MockData.movieItems {
            XCTAssertEqual(item.type, "movie")
            XCTAssertNotNil(item.properties["director"])
        }
    }

    func testMockAllItems() {
        XCTAssertEqual(
            MockData.allItems.count,
            MockData.todoItems.count + MockData.bookItems.count + MockData.movieItems.count
        )
    }

    func testMockSavedViews() {
        XCTAssertEqual(MockData.savedViews.count, 5)
        for view in MockData.savedViews {
            XCTAssertFalse(view.name.isEmpty)
        }
    }

    func testMockListTypes() {
        XCTAssertEqual(MockData.listTypes.count, 4)
        let typeNames = MockData.listTypes.map { $0.name }
        XCTAssert(typeNames.contains("Todo"))
        XCTAssert(typeNames.contains("Book"))
        XCTAssert(typeNames.contains("Movie"))
        XCTAssert(typeNames.contains("Restaurant"))
    }

    func testMockItemsHaveUniqueIds() {
        let ids = MockData.allItems.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testMockSavedViewsHaveUniqueIds() {
        let ids = MockData.savedViews.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
