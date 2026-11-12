import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppSettings.alertLeadTimeMinutesKey) private var leadTimeMinutes = 1
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var calendarOverrides = AppSettings.calendarOverrides()

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
            ForEach(appState.calendars) { calendar in
                Toggle(isOn: calendarBinding(for: calendar)) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Self.color(fromHex: calendar.colorHex))
                            .frame(width: 10, height: 10)
                        Text(calendar.name)
                    }
                }
            }
        }
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
