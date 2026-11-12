import XCTest
@testable import Punctual

final class CalendarSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CalendarSelectionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testWithoutOverrideFollowsGoogleSelectedFlag() {
        XCTAssertTrue(AppSettings.isCalendarEnabled(id: "a", selectedInGoogle: true, defaults: defaults))
        XCTAssertFalse(AppSettings.isCalendarEnabled(id: "b", selectedInGoogle: false, defaults: defaults))
    }

    func testOverrideBeatsGoogleSelectedFlag() {
        AppSettings.setCalendar(id: "a", enabled: false, defaults: defaults)
        AppSettings.setCalendar(id: "b", enabled: true, defaults: defaults)

        XCTAssertFalse(AppSettings.isCalendarEnabled(id: "a", selectedInGoogle: true, defaults: defaults))
        XCTAssertTrue(AppSettings.isCalendarEnabled(id: "b", selectedInGoogle: false, defaults: defaults))
    }

    func testOverridesAreIndependentPerCalendar() {
        AppSettings.setCalendar(id: "a", enabled: false, defaults: defaults)

        XCTAssertTrue(AppSettings.isCalendarEnabled(id: "other", selectedInGoogle: true, defaults: defaults))
        XCTAssertEqual(AppSettings.calendarOverrides(defaults: defaults), ["a": false])
    }

    func testOverrideCanBeToggledBack() {
        AppSettings.setCalendar(id: "a", enabled: false, defaults: defaults)
        AppSettings.setCalendar(id: "a", enabled: true, defaults: defaults)

        XCTAssertTrue(AppSettings.isCalendarEnabled(id: "a", selectedInGoogle: false, defaults: defaults))
    }
}
