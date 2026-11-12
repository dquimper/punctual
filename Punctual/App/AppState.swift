import AppKit
import Foundation
import Observation

/// Single source of truth: auth status, today's meetings, the menu bar title.
/// Owns and wires all services.
@MainActor
@Observable
final class AppState {
    enum AuthState: Equatable {
        case signedOut
        case signedIn(email: String?)
    }

    var authState: AuthState = .signedOut
    var meetings: [Meeting] = []
    /// Every calendar on the account, for the Settings picker.
    var calendars: [CalendarInfo] = []
    var menuTitle: String = "…"
    var lastUpdated: Date?
    var lastError: String?
    var isSigningIn = false

    let auth = GoogleAuthController()
    let alertScheduler = AlertScheduler()

    @ObservationIgnored private lazy var calendarService = CalendarService(auth: auth)
    @ObservationIgnored private let ticker = MenuTitleTicker()
    @ObservationIgnored private let refreshCoordinator = RefreshCoordinator()
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    init() {
        if let tokens = auth.storedTokens {
            authState = .signedIn(email: tokens.email)
        }

        alertScheduler.onJoin = { [weak self] meeting in self?.join(meeting) }
        ticker.onTick = { [weak self] in self?.tick() }
        refreshCoordinator.onRefresh = { [weak self] in await self?.refresh() }
        refreshCoordinator.start()

        // Lead time changed in Settings → re-aim pending alerts immediately.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let leadTime = AppSettings.alertLeadTime
                if self.alertScheduler.leadTime != leadTime {
                    self.alertScheduler.leadTime = leadTime
                    self.alertScheduler.reconcile(meetings: self.remainingMeetings)
                }
            }
        }

        tick()
        Task { await refresh() }
    }

    // MARK: - Derived

    /// Meetings (today and tomorrow) that have not ended yet; feeds the alert scheduler.
    var remainingMeetings: [Meeting] { meetings.filter { !$0.hasEnded } }

    /// Today's not-yet-ended meetings, for the dropdown's main list.
    var todaysRemainingMeetings: [Meeting] {
        remainingMeetings.filter { Calendar.current.isDateInToday($0.start) }
    }

    /// Tomorrow's meetings, for the dropdown's "Tomorrow" section.
    var tomorrowsMeetings: [Meeting] {
        meetings.filter { Calendar.current.isDateInTomorrow($0.start) }
    }

    var upcomingMeetings: [Meeting] { meetings.filter { $0.start > Date() } }

    var nextMeeting: Meeting? { upcomingMeetings.first }

    var currentMeeting: Meeting? { meetings.first { $0.isInProgress } }

    // MARK: - Data refresh

    func refresh() async {
        guard case .signedIn = authState else {
            tick()
            return
        }
        do {
            let result = try await calendarService.fetchMeetings()
            meetings = result.meetings
            calendars = result.calendars
            lastUpdated = Date()
            lastError = nil
        } catch AuthError.signedOut {
            handleSignedOut()
            return
        } catch is CancellationError {
            return
        } catch {
            // Keep showing the last good data; surface the problem subtly.
            lastError = error.localizedDescription
        }
        alertScheduler.leadTime = AppSettings.alertLeadTime
        // Non-ended (not merely upcoming) meetings: an in-progress meeting whose
        // alert is showing must keep its key, or reconcile would prune it
        // and close the alert moments after the meeting starts.
        alertScheduler.reconcile(meetings: remainingMeetings)
        tick()
    }

    /// Recomputes the menu title and re-arms the ticker for the next change.
    private func tick() {
        menuTitle = computeMenuTitle()
        ticker.rearm(nextChange: nextMeeting?.start ?? currentMeeting?.end)
    }

    private func computeMenuTitle() -> String {
        guard case .signedIn = authState else { return "Sign in" }
        return MenuTitleFormatter.title(next: nextMeeting, current: currentMeeting)
    }

    // MARK: - Auth actions

    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let tokens = try await auth.signIn()
            authState = .signedIn(email: tokens.email)
            lastError = nil
            await refresh()
        } catch AuthError.cancelled {
            // User closed the window; not an error worth surfacing.
        } catch {
            lastError = error.localizedDescription
            tick()
        }
    }

    func signOut() async {
        await auth.signOut()
        handleSignedOut()
    }

    private func handleSignedOut() {
        authState = .signedOut
        meetings = []
        calendars = []
        lastUpdated = nil
        alertScheduler.clearAll()
        tick()
    }

    // MARK: - Joining

    func join(_ meeting: Meeting) {
        if let url = meeting.joinURL ?? meeting.htmlLink {
            NSWorkspace.shared.open(url)
        }
    }
}
