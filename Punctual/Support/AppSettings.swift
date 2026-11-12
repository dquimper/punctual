import Foundation

enum AppSettings {
    static let alertLeadTimeMinutesKey = "alertLeadTimeMinutes"
    static let calendarOverridesKey = "calendarEnabledOverrides"

    /// Minutes before the meeting start when the full-screen alert fires. Default: 1.
    static var alertLeadTimeMinutes: Int {
        UserDefaults.standard.object(forKey: alertLeadTimeMinutesKey) as? Int ?? 1
    }

    static var alertLeadTime: TimeInterval { TimeInterval(alertLeadTimeMinutes * 60) }

    // MARK: - Calendar selection

    /// Calendars the user has explicitly switched on or off in Settings, keyed by
    /// calendar ID. Calendars without an entry follow Google Calendar's own
    /// "selected" flag, so new calendars and existing installs behave as before
    /// until the user changes something.
    static func calendarOverrides(defaults: UserDefaults = .standard) -> [String: Bool] {
        defaults.dictionary(forKey: calendarOverridesKey) as? [String: Bool] ?? [:]
    }

    static func isCalendarEnabled(
        id: String, selectedInGoogle: Bool, defaults: UserDefaults = .standard
    ) -> Bool {
        calendarOverrides(defaults: defaults)[id] ?? selectedInGoogle
    }

    static func setCalendar(id: String, enabled: Bool, defaults: UserDefaults = .standard) {
        var overrides = calendarOverrides(defaults: defaults)
        overrides[id] = enabled
        defaults.set(overrides, forKey: calendarOverridesKey)
    }
}
