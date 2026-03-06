import Foundation
import XCTest

#if canImport(Core)
import Core
#endif

final class ViewTests: XCTestCase {

    func testDisplayStyleEnum() {
        XCTAssertEqual(DisplayStyle.list.rawValue, "list")
        XCTAssertEqual(DisplayStyle.card.rawValue, "card")
    }

    func testViewFiltersInitialization() {
        let filters = ViewFilters()

        XCTAssertNil(filters.tags)
        XCTAssertNil(filters.itemTypes)
        XCTAssertNil(filters.dueBefore)
        XCTAssertNil(filters.dueAfter)
        XCTAssertNil(filters.completed)
        XCTAssertNil(filters.folders)
    }

    func testViewFiltersWithTags() {
        let filters = ViewFilters(tags: ["work/*", "urgent"])

        XCTAssertEqual(filters.tags?.count, 2)
        XCTAssert(filters.tags!.contains("work/*"))
    }

    func testViewFiltersWithItemTypes() {
        let filters = ViewFilters(itemTypes: ["todo", "book"])

        XCTAssertEqual(filters.itemTypes?.count, 2)
        XCTAssert(filters.itemTypes!.contains("todo"))
    }

    func testViewFiltersWithDateRange() {
        let before = Date().addingTimeInterval(86400 * 7)
        let after = Date()
        let filters = ViewFilters(dueBefore: before, dueAfter: after)

        XCTAssertNotNil(filters.dueBefore)
        XCTAssertNotNil(filters.dueAfter)
        XCTAssert(filters.dueBefore! > filters.dueAfter!)
    }

    func testViewFiltersWithCompletion() {
        let incompleteFilters = ViewFilters(completed: false)
        let completeFilters = ViewFilters(completed: true)

        XCTAssertEqual(incompleteFilters.completed, false)
        XCTAssertEqual(completeFilters.completed, true)
    }

    func testViewFiltersCodable() throws {
        let filters = ViewFilters(
            tags: ["work/backend", "urgent"],
            itemTypes: ["todo"],
            completed: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(filters)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ViewFilters.self, from: data)

        XCTAssertEqual(decoded.tags, filters.tags)
        XCTAssertEqual(decoded.itemTypes, filters.itemTypes)
        XCTAssertEqual(decoded.completed, filters.completed)
    }

    func testSavedViewInitialization() {
        let view = SavedView(name: "All Tasks")

        XCTAssertEqual(view.name, "All Tasks")
        XCTAssertEqual(view.displayStyle, .list)
        XCTAssertNotNil(view.id)
    }

    func testSavedViewWithFilters() {
        let filters = ViewFilters(
            tags: ["work/*"],
            itemTypes: ["todo"],
            completed: false
        )
        let view = SavedView(
            name: "Work Todos",
            filters: filters,
            displayStyle: .list
        )

        XCTAssertEqual(view.name, "Work Todos")
        XCTAssertEqual(view.displayStyle, .list)
        XCTAssertEqual(view.filters.tags?.count, 1)
    }

    func testSavedViewCardDisplay() {
        let view = SavedView(
            name: "Book Cards",
            displayStyle: .card
        )

        XCTAssertEqual(view.displayStyle, .card)
    }

    func testSavedViewCodable() throws {
        let filters = ViewFilters(
            tags: ["books/*"],
            itemTypes: ["book"],
            completed: nil
        )
        let originalView = SavedView(
            name: "Reading List",
            filters: filters,
            displayStyle: .card
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(originalView)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedView = try decoder.decode(SavedView.self, from: data)

        XCTAssertEqual(decodedView.id, originalView.id)
        XCTAssertEqual(decodedView.name, originalView.name)
        XCTAssertEqual(decodedView.displayStyle, originalView.displayStyle)
        XCTAssertEqual(decodedView.filters.tags, originalView.filters.tags)
    }

    func testSavedViewJSON() throws {
        let json = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "name": "Urgent Tasks",
            "filters": {
                "tags": ["work/*", "urgent"],
                "itemTypes": ["todo"],
                "dueBefore": "2024-03-15T00:00:00Z",
                "dueAfter": null,
                "completed": false,
                "folders": null
            },
            "displayStyle": "list"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let view = try decoder.decode(SavedView.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(view.id, UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000"))
        XCTAssertEqual(view.name, "Urgent Tasks")
        XCTAssertEqual(view.displayStyle, .list)
        XCTAssertEqual(view.filters.tags?.count, 2)
        XCTAssertEqual(view.filters.completed, false)
    }

    func testSavedViewIdentifiable() {
        let view1 = SavedView(name: "View 1")
        let view2 = SavedView(name: "View 2")

        XCTAssertNotEqual(view1.id, view2.id)
    }

    func testSavedViewHashable() {
        let id = UUID()
        let view1 = SavedView(id: id, name: "Same View")
        let view2 = SavedView(id: id, name: "Same View")

        XCTAssertEqual(view1, view2)
        XCTAssertEqual(view1.hashValue, view2.hashValue)

        let view3 = SavedView(name: "Different View")
        XCTAssertNotEqual(view1, view3)
    }

    func testViewFiltersEquatable() {
        let filters1 = ViewFilters(tags: ["work/*"], completed: false)
        let filters2 = ViewFilters(tags: ["work/*"], completed: false)
        let filters3 = ViewFilters(tags: ["personal/*"], completed: true)

        XCTAssertEqual(filters1, filters2)
        XCTAssertNotEqual(filters1, filters3)
    }

    func testViewFiltersWithFolders() {
        let filters = ViewFilters(folders: ["Work", "Projects"])

        XCTAssertEqual(filters.folders?.count, 2)
        XCTAssert(filters.folders!.contains("Work"))
    }

    func testComplexViewFilters() {
        let before = Date().addingTimeInterval(86400 * 7)
        let after = Date().addingTimeInterval(-86400 * 30)

        let filters = ViewFilters(
            tags: ["work/backend/*", "urgent"],
            itemTypes: ["todo", "bug"],
            dueBefore: before,
            dueAfter: after,
            completed: false,
            folders: ["Work", "Projects"]
        )

        XCTAssertEqual(filters.tags?.count, 2)
        XCTAssertEqual(filters.itemTypes?.count, 2)
        XCTAssertNotNil(filters.dueBefore)
        XCTAssertNotNil(filters.dueAfter)
        XCTAssertEqual(filters.completed, false)
        XCTAssertEqual(filters.folders?.count, 2)
    }
}
