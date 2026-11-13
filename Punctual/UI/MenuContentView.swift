import SwiftUI

private struct ListContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The dropdown shown when clicking the menu bar item.
struct MenuContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @State private var listContentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 340)
        .task { await appState.refresh() }
    }

    private var header: some View {
        HStack {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.headline)
            Spacer()
            if case .signedIn = appState.authState {
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch appState.authState {
        case .signedOut:
            signedOutView
        case .signedIn:
            if appState.todaysRemainingMeetings.isEmpty && appState.tomorrowsMeetings.isEmpty {
                emptyView
            } else {
                meetingList
            }
        }
    }

    private var signedOutView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Connect your Google Calendar to see upcoming meetings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await appState.signIn() }
            } label: {
                if appState.isSigningIn {
                    Text("Waiting for Google…")
                } else {
                    Label("Sign in with Google", systemImage: "person.crop.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isSigningIn || !OAuthConfig.isConfigured)

            if !OAuthConfig.isConfigured {
                Text("Set the OAuth client ID in OAuthConfig.swift first.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(20)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.max")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No more meetings today")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var meetingList: some View {
        ScrollView {
            VStack(spacing: 2) {
                if appState.todaysRemainingMeetings.isEmpty {
                    Text("No more meetings today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(appState.todaysRemainingMeetings) { meeting in
                        MeetingRowView(
                            meeting: meeting,
                            isNext: meeting.id == appState.nextMeeting?.id
                        )
                    }
                }
                if !appState.tomorrowsMeetings.isEmpty {
                    HStack {
                        Text("Tomorrow")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    ForEach(appState.tomorrowsMeetings) { meeting in
                        MeetingRowView(
                            meeting: meeting,
                            isNext: meeting.id == appState.nextMeeting?.id
                        )
                    }
                }
            }
            .padding(6)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ListContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        // A ScrollView has no intrinsic height, and inside a MenuBarExtra window it
        // collapses to zero. Give it the measured content height, capped.
        .frame(height: min(listContentHeight, 320))
        .onPreferenceChange(ListContentHeightKey.self) { listContentHeight = $0 }
    }

    private var footer: some View {
        HStack {
            if let error = appState.lastError, case .signedIn = appState.authState {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(error)
            } else if let updated = appState.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Punctual")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
