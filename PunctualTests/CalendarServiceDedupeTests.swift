import XCTest
@testable import Punctual

final class CalendarServiceDedupeTests: XCTestCase {
    private func meeting(
        id: String, iCalUID: String, calendarID: String = "primary", withLink: Bool,
        start: TimeInterval = 800_000_000
    ) -> Meeting {
        Meeting(
            id: id,
            iCalUID: iCalUID,
            calendarID: calendarID,
            title: "Standup",
            start: Date(timeIntervalSinceReferenceDate: start),
            end: Date(timeIntervalSinceReferenceDate: start + 1_800),
            joinURL: withLink ? URL(string: "https://meet.google.com/abc-defg-hij") : nil,
            htmlLink: nil
        )
    }

    func testKeepsCopyWithJoinLinkRegardlessOfOrder() {
        let bare = meeting(id: "a", iCalUID: "uid1", calendarID: "work", withLink: false)
        let linked = meeting(id: "b", iCalUID: "uid1", calendarID: "personal", withLink: true)

        for order in [[bare, linked], [linked, bare]] {
            let result = CalendarService.dedupe(order)
            XCTAssertEqual(result.count, 1)
            XCTAssertNotNil(result[0].joinURL)
        }
    }

    func testKeepsDistinctEvents() {
        let one = meeting(id: "a", iCalUID: "uid1", withLink: true)
        let two = meeting(id: "b", iCalUID: "uid2", withLink: false)
        XCTAssertEqual(CalendarService.dedupe([one, two]).count, 2)
    }

    func testDuplicatesWithoutLinksCollapseToOne() {
        let first = meeting(id: "a", iCalUID: "uid1", calendarID: "work", withLink: false)
        let second = meeting(id: "b", iCalUID: "uid1", calendarID: "personal", withLink: false)
        XCTAssertEqual(CalendarService.dedupe([first, second]).count, 1)
    }

    // Instances of one recurring series share an iCalUID but differ in start.

    private let day: TimeInterval = 86_400

    func testRecurringInstancesWithoutLinksAllSurvive() {
        let today = meeting(id: "a_1", iCalUID: "series", withLink: false)
        let tomorrow = meeting(id: "a_2", iCalUID: "series", withLink: false, start: 800_000_000 + day)

        let result = CalendarService.dedupe([today, tomorrow])

        XCTAssertEqual(Set(result.map(\.id)), ["a_1", "a_2"])
    }

    func testRecurringInstancesWithLinksAllSurvive() {
        let today = meeting(id: "a_1", iCalUID: "series", withLink: true)
        let tomorrow = meeting(id: "a_2", iCalUID: "series", withLink: true, start: 800_000_000 + day)

        XCTAssertEqual(CalendarService.dedupe([today, tomorrow]).count, 2)
    }

    func testSeriesRecurringTwiceInOneDayKeepsBothInstances() {
        let morning = meeting(id: "a_1", iCalUID: "series", withLink: true)
        let afternoon = meeting(id: "a_2", iCalUID: "series", withLink: true, start: 800_000_000 + 14_400)

        XCTAssertEqual(CalendarService.dedupe([morning, afternoon]).count, 2)
    }

    func testCopiesOfRecurringInstancesAcrossCalendarsStillMerge() {
        let workToday = meeting(id: "a_1", iCalUID: "series", calendarID: "work", withLink: false)
        let personalToday = meeting(id: "b_1", iCalUID: "series", calendarID: "personal", withLink: true)
        let workTomorrow = meeting(id: "a_2", iCalUID: "series", calendarID: "work", withLink: false, start: 800_000_000 + day)

        let result = CalendarService.dedupe([workToday, personalToday, workTomorrow])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.start == workToday.start }?.calendarID, "personal")
    }
}
