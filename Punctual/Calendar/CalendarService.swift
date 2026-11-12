import Foundation

/// Stateless REST client for the Google Calendar API v3.
@MainActor
struct CalendarService {
    let auth: GoogleAuthController

    private nonisolated static let baseURL = URL(string: "https://www.googleapis.com/calendar/v3")!

    /// Today's and tomorrow's timed meetings across all selected calendars,
    /// deduped and sorted by start. Fetching a day ahead keeps the menu bar
    /// useful after the last meeting and lets alerts for early-morning
    /// meetings arm before an overnight sleep.
    func fetchMeetings() async throws -> [Meeting] {
        var token = try await auth.validAccessToken()
        do {
            return try await fetchAll(token: token)
        } catch CalendarAPIError.unauthorized {
            // Access token rejected despite local expiry check — refresh once and retry.
            token = try await auth.validAccessToken(forceRefresh: true)
            return try await fetchAll(token: token)
        }
    }

    private func fetchAll(token: String) async throws -> [Meeting] {
        let calendarIDs = try await fetchSelectedCalendarIDs(token: token)

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfDay)!

        let meetings = try await withThrowingTaskGroup(of: [Meeting].self) { group in
            for calendarID in calendarIDs {
                group.addTask {
                    try await Self.fetchEvents(
                        calendarID: calendarID, token: token,
                        timeMin: startOfDay, timeMax: endOfTomorrow
                    )
                }
            }
            var merged: [Meeting] = []
            for try await batch in group { merged.append(contentsOf: batch) }
            return merged
        }
        return Self.dedupe(meetings).sorted { $0.start < $1.start }
    }

    /// The same event invited to several of the user's calendars shares an iCalUID
    /// and a start time; keep the copy that has a join link. Every instance of a
    /// recurring series also shares the iCalUID, so the start time is part of the
    /// key — otherwise today's and tomorrow's instances collapse into one.
    nonisolated static func dedupe(_ meetings: [Meeting]) -> [Meeting] {
        struct Key: Hashable {
            let iCalUID: String
            let start: Date
        }
        var byKey: [Key: Meeting] = [:]
        for meeting in meetings {
            let key = Key(iCalUID: meeting.iCalUID, start: meeting.start)
            if let existing = byKey[key], existing.joinURL != nil { continue }
            byKey[key] = meeting
        }
        return Array(byKey.values)
    }

    private func fetchSelectedCalendarIDs(token: String) async throws -> [String] {
        var components = URLComponents(
            url: Self.baseURL.appending(path: "users/me/calendarList"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "minAccessRole", value: "reader"),
            URLQueryItem(name: "fields", value: "items(id,summary,selected,primary)"),
        ]
        let response: GCalCalendarListResponse = try await Self.get(components.url!, token: token)
        return (response.items ?? [])
            .filter { $0.selected != false }
            .map(\.id)
    }

    private nonisolated static func fetchEvents(
        calendarID: String, token: String, timeMin: Date, timeMax: Date
    ) async throws -> [Meeting] {
        let formatter = ISO8601DateFormatter()
        var components = URLComponents(
            url: baseURL.appending(path: "calendars/\(calendarID)/events"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(
                name: "fields",
                value: "items(id,iCalUID,status,summary,start,end,location,description,"
                    + "hangoutLink,htmlLink,conferenceData(entryPoints),attendees(self,responseStatus))"
            ),
        ]
        let response: GCalEventsResponse = try await get(components.url!, token: token)

        return (response.items ?? []).compactMap { event in
            guard event.status != "cancelled",
                  !event.isAllDay,
                  !event.isDeclinedByMe,
                  let start = event.start?.parsedDateTime,
                  let end = event.end?.parsedDateTime
            else { return nil }
            return Meeting(
                id: event.id,
                iCalUID: event.iCalUID ?? event.id,
                calendarID: calendarID,
                title: event.summary?.isEmpty == false ? event.summary! : "(No title)",
                start: start,
                end: end,
                joinURL: JoinLinkExtractor.joinURL(for: event),
                htmlLink: event.htmlLink.flatMap(URL.init(string:))
            )
        }
    }

    private nonisolated static func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CalendarAPIError.badResponse }
        switch http.statusCode {
        case 200: return try JSONDecoder().decode(T.self, from: data)
        case 401: throw CalendarAPIError.unauthorized
        default:
            throw CalendarAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}

enum CalendarAPIError: LocalizedError {
    case unauthorized
    case badResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Google Calendar authorization expired."
        case .badResponse: "Unexpected response from Google Calendar."
        case .http(let code, _): "Google Calendar request failed (HTTP \(code))."
        }
    }
}
