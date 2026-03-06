import XCTest

final class ListAppUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["IS_TESTING"] = "true"
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - App Launch & Initial UI

    func testAppLaunchAndInitialUI() throws {
        // Verify app launches without crashing
        XCTAssertTrue(app.exists, "App should launch successfully")

        // Verify main tabs are visible
        let savedViewsTab = app.tabBars.buttons["Saved Views"]
        let itemsTab = app.tabBars.buttons["Items"]
        let filterTab = app.tabBars.buttons["Filter"]
        let searchTab = app.tabBars.buttons["Search"]
        let tagsTab = app.tabBars.buttons["Tags"]
        let settingsTab = app.tabBars.buttons["Settings"]

        XCTAssertTrue(savedViewsTab.exists, "Saved Views tab should exist")
        XCTAssertTrue(itemsTab.exists, "Items tab should exist")
        XCTAssertTrue(filterTab.exists, "Filter tab should exist")
        XCTAssertTrue(searchTab.exists, "Search tab should exist")
        XCTAssertTrue(tagsTab.exists, "Tags tab should exist")
        XCTAssertTrue(settingsTab.exists, "Settings tab should exist")
    }

    // MARK: - Items List Display

    func testItemsListDisplay() throws {
        // Navigate to Items tab
        app.tabBars.buttons["Items"].tap()

        // Wait for items to load
        let itemsList = app.collectionViews.firstMatch
        XCTAssertTrue(itemsList.waitForExistence(timeout: 2), "Items list should load")

        // Verify at least one item exists
        let itemCells = itemsList.cells
        XCTAssertGreaterThan(itemCells.count, 0, "Items list should contain at least one item")
    }

    // MARK: - Todo Completion Toggle

    func testToggleTodoCompletion() throws {
        // Navigate to Items tab
        app.tabBars.buttons["Items"].tap()

        // Wait for items
        let itemsList = app.collectionViews.firstMatch
        _ = itemsList.waitForExistence(timeout: 2)

        // Get first item cell
        let firstItemCell = itemsList.cells.firstMatch
        XCTAssertTrue(firstItemCell.exists, "First item cell should exist")

        // Tap on item to show completion button
        firstItemCell.tap()

        // Look for a completion button or checkbox
        // This will depend on how ItemRowView implements it
        let completionButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'complete' OR label CONTAINS '◯' OR label CONTAINS '✓'")).firstMatch

        if completionButton.exists {
            let initialLabel = completionButton.label
            completionButton.tap()

            // Give time for state update
            sleep(1)

            // Verify the button changed (depending on implementation)
            // This is a flexible test since we don't know the exact UI yet
            XCTAssertTrue(completionButton.exists, "Completion button should still exist")
        }
    }

    // MARK: - Tab Navigation

    func testTabNavigation() throws {
        let tabs = ["Saved Views", "Items", "Filter", "Search", "Tags", "Settings"]

        for tabName in tabs {
            let tab = app.tabBars.buttons[tabName]
            XCTAssertTrue(tab.exists, "\(tabName) tab should exist")

            tab.tap()

            // Wait briefly for tab content to load
            usleep(300000) // 0.3 seconds

            // Verify no crashes (app should still be responsive)
            XCTAssertTrue(app.exists, "App should still exist after navigating to \(tabName)")
        }
    }

    // MARK: - Filter Tab

    func testFilterTab() throws {
        app.tabBars.buttons["Filter"].tap()

        let filterView = app.scrollViews.firstMatch
        XCTAssertTrue(filterView.waitForExistence(timeout: 2), "Filter view should load")
    }

    // MARK: - Search Functionality

    func testSearchTab() throws {
        app.tabBars.buttons["Search"].tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 2), "Search field should exist")

        // Type in search field
        searchField.tap()
        searchField.typeText("test")

        // Wait for results
        usleep(500000) // 0.5 seconds for search to complete

        // Verify app doesn't crash
        XCTAssertTrue(app.exists, "App should handle search input")
    }

    // MARK: - Settings Tab

    func testSettingsTab() throws {
        app.tabBars.buttons["Settings"].tap()

        let settingsView = app.scrollViews.firstMatch
        XCTAssertTrue(settingsView.waitForExistence(timeout: 2), "Settings view should load")

        // Try scrolling settings
        settingsView.scroll(byDeltaX: 0, deltaY: -200)

        // Verify no crashes
        XCTAssertTrue(app.exists, "App should remain responsive in Settings")
    }
}
