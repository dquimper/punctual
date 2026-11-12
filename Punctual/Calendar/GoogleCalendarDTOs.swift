import Foundation

// Codable mirrors of the Google Calendar API v3 responses (only the fields we request).

struct GCalCalendarListResponse: Decodable {
    let items: [GCalCalendarListEntry]?
}

struct GCalCalendarListEntry: Decodable {
    let id: String
    let summary: String?
    let selected: Bool?
    let primary: Bool?
    let backgroundColor: String?
}

struct GCalEventsResponse: Decodable {
    let items: [GCalEvent]?
}

struct GCalEvent: Decodable {
    let id: String
    let iCalUID: String?
    let status: String?
    let summary: String?
    let start: GCalEventTime?
    let end: GCalEventTime?
    let location: String?
    let description: String?
    let hangoutLink: String?
    let htmlLink: String?
    let conferenceData: GCalConferenceData?
    let attendees: [GCalAttendee]?

    var isAllDay: Bool { start?.dateTime == nil }

    var isDeclinedByMe: Bool {
        attendees?.first(where: { $0.isSelf == true })?.responseStatus == "declined"
    }
}

struct GCalEventTime: Decodable {
    let date: String?       // all-day events: "2026-06-12"
    let dateTime: String?   // timed events: RFC 3339

    private static let iso8601 = ISO8601DateFormatter()

    var parsedDateTime: Date? {
        guard let dateTime else { return nil }
        return Self.iso8601.date(from: dateTime)
    }
}

struct GCalConferenceData: Decodable {
    let entryPoints: [GCalEntryPoint]?
}

struct GCalEntryPoint: Decodable {
    let entryPointType: String?  // "video", "phone", "more"
    let uri: String?
}

struct GCalAttendee: Decodable {
    let isSelf: Bool?
    let responseStatus: String?  // "accepted", "declined", "tentative", "needsAction"

    enum CodingKeys: String, CodingKey {
        case isSelf = "self"
        case responseStatus
    }
}
