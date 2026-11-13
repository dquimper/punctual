import SwiftUI

private struct CalendarListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppSettings.alertLeadTimeMinutesKey) private var leadTimeMinutes = 1
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var calendarOverrides = AppSettings.calendarOverrides()
    @State private var calendarContentHeight: CGFloat = 0

    var body: some View {
        Form {
            Section("Account") {
                accountRow
            }

            Section("Meeting Alert") {
                Picker("Show full-screen alert", selection: $leadTimeMinutes) {
                    Text("When the meeting starts").tag(0)
                    Text("1 minute before").tag(1)
                    Text("2 minutes before").tag(2)
                    Text("5 minutes before").tag(5)
                }
                .pickerStyle(.menu)
            }

            Section {
                calendarRows
            } header: {
                Text("Calendars")
            } footer: {
                Text("Only events from checked calendars trigger alerts. Until you change a calendar here, it follows whether it is shown in Google Calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if !LaunchAtLogin.set(newValue) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }

            #if DEBUG
            Section("Debug") {
                Button("Trigger test alert") {
                    appState.alertScheduler.presentTestAlert()
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    @ViewBuilder
    private var calendarRows: some View {
        if case .signedOut = appState.authState {
            Text("Sign in to choose calendars.")
                .foregroundStyle(.secondary)
        } else if appState.calendars.isEmpty {
            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading calendars…")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            // Show at most `maxVisibleCalendars` rows; scroll for the rest. A ScrollView
            // has no intrinsic height (it collapses to zero in a Form), so give it an
            // explicit one: the measured content height, capped to N rows' worth.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(appState.calendars) { calendar in
                        calendarRow(calendar)
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: CalendarListHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .frame(height: calendarListHeight)
            .onPreferenceChange(CalendarListHeightKey.self) { calendarContentHeight = $0 }
        }
    }

    /// Rows visible at once. The half row peeking out below the fifth hints that
    /// the list scrolls.
    private static let visibleCalendarRows: CGFloat = 5.5

    /// Height of the calendar list: everything if it fits, otherwise
    /// `visibleCalendarRows` rows (rows are uniform, so average the measured total).
    private var calendarListHeight: CGFloat {
        let count = CGFloat(appState.calendars.count)
        guard count > Self.visibleCalendarRows else { return calendarContentHeight }
        return calendarContentHeight / count * Self.visibleCalendarRows
    }

    private func calendarRow(_ calendar: CalendarInfo) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Self.color(fromHex: calendar.colorHex))
                .frame(width: 10, height: 10)
            Text(calendar.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Toggle(calendar.name, isOn: calendarBinding(for: calendar))
                .labelsHidden()
                .toggleStyle(.switch)
                // Rows in the grouped Form get a compact switch; this ScrollView sits
                // outside that styling, so match it explicitly.
                .controlSize(.mini)
        }
        .padding(.vertical, 6)
        // Keep the switch clear of the scroll indicator on the right edge.
        .padding(.trailing, 14)
    }

    private func calendarBinding(for calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: {
                calendarOverrides[calendar.id] ?? calendar.selectedInGoogle
            },
            set: { enabled in
                AppSettings.setCalendar(id: calendar.id, enabled: enabled)
                calendarOverrides = AppSettings.calendarOverrides()
                // Re-fetch so alerts and the menu bar reflect the change now.
                Task { await appState.refresh() }
            }
        )
    }

    /// Parses Google's `#RRGGBB` calendar colour; falls back to the accent colour.
    private static func color(fromHex hex: String?) -> Color {
        guard let hex else { return .accentColor }
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else { return .accentColor }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    @ViewBuilder
    private var accountRow: some View {
        switch appState.authState {
        case .signedIn(let email):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Calendar")
                    if let email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Sign Out") {
                    Task { await appState.signOut() }
                }
            }
        case .signedOut:
            HStack {
                Text("Not signed in")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Sign in with Google") {
                    Task { await appState.signIn() }
                }
                .disabled(appState.isSigningIn || !OAuthConfig.isConfigured)
            }
        }
    }
}
