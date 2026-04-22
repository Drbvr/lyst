import XCTest
@testable import Core

final class QuickAddParserTests: XCTestCase {
    // 2026-04-22 is a Wednesday
    private var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 22; c.hour = 9
        c.timeZone = TimeZone(identifier: "UTC")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    private var utcCal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testExtractsPriority() {
        let r = QuickAddParser.parse("Plan offsite p1", now: now, calendar: utcCal)
        XCTAssertEqual(r.priority, "p1")
        XCTAssertEqual(r.title, "Plan offsite")
    }

    func testExtractsProjectAndLabels() {
        let r = QuickAddParser.parse("Email team #work @urgent @today", now: now, calendar: utcCal)
        XCTAssertEqual(r.project, "work")
        XCTAssertEqual(r.labels, ["urgent", "today"])
        XCTAssertEqual(r.title, "Email team")
    }

    func testTodayTomorrow() {
        let today = QuickAddParser.parse("Standup today", now: now, calendar: utcCal)
        XCTAssertNotNil(today.dueDate)
        XCTAssertEqual(today.title, "Standup")

        let tomorrow = QuickAddParser.parse("Call bank tomorrow", now: now, calendar: utcCal)
        XCTAssertNotNil(tomorrow.dueDate)
        XCTAssertEqual(utcCal.dateComponents([.day], from: tomorrow.dueDate!).day, 23)
    }

    func testWeekdayWithTime() {
        // 22 Apr 2026 is Wed → next "fri" = 24 Apr
        let r = QuickAddParser.parse("Demo fri 10am", now: now, calendar: utcCal)
        XCTAssertEqual(r.title, "Demo")
        guard let d = r.dueDate else { return XCTFail("no date") }
        let comps = utcCal.dateComponents([.day, .hour], from: d)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.hour, 10)
    }

    func testWeekdayOnSameDayMovesForwardAWeek() {
        // today is Wed → "wed" should mean next week (29th)
        let r = QuickAddParser.parse("Sync wed", now: now, calendar: utcCal)
        XCTAssertEqual(utcCal.dateComponents([.day], from: r.dueDate!).day, 29)
    }

    func testRecurrence() {
        let r = QuickAddParser.parse("Water plants every mon", now: now, calendar: utcCal)
        XCTAssertEqual(r.recurrence, "every mon")
        XCTAssertNotNil(r.dueDate)
        XCTAssertEqual(r.title, "Water plants")
    }

    func testReminder() {
        let r = QuickAddParser.parse("Meeting ◷2h", now: now, calendar: utcCal)
        XCTAssertEqual(r.reminder, "2h")
    }

    func testTime24h() {
        let r = QuickAddParser.parse("Call fri 14:30", now: now, calendar: utcCal)
        guard let d = r.dueDate else { return XCTFail() }
        let comps = utcCal.dateComponents([.hour, .minute], from: d)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
    }

    func testOnlyTitle() {
        let r = QuickAddParser.parse("just a plain todo", now: now, calendar: utcCal)
        XCTAssertEqual(r.title, "just a plain todo")
        XCTAssertNil(r.dueDate)
        XCTAssertNil(r.priority)
    }
}
