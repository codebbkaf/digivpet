import SwiftUI

/// The Settings screen, behind the main screen's top-right gear (US-198).
///
/// Two `Section`s: the notification toggles, which lived behind a bell in the action row until
/// US-197 cleared that row down to the eight game actions, and US-215's read-only health status.
/// The toggle rows are reused whole from the old notification settings screen via
/// `NotificationSettingsSection`, so they persist and behave exactly as they did off the bell.
struct SettingsView: View {
    @ObservedObject var settings: NotificationSettings
    /// What the app is doing with health data right now. Handed down from
    /// `HealthAuthorizationGate`, which is where the real state machine lives — this screen only
    /// reports, and has no way to ask HealthKit anything itself.
    let healthStatus: HealthCollectionStatus

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // Health first: it is the one thing on this screen the player cannot change here,
                // so it reads as a status line above the switches rather than as another setting.
                Section("Health") {
                    healthRow
                }

                Section("Notifications") {
                    NotificationSettingsSection(settings: settings)
                }
            }
            #if DEBUG
            // Screenshot hook, the same reason as every other one in this project: `simctl` can
            // neither tap nor scroll, and the notification toggles run past the fold on every watch
            // size. Without this the last row cannot be photographed at all. It moves the scroll
            // position and nothing else — no toggle, no default, no rule.
            .task {
                guard CommandLine.arguments.contains("-settingsBottomDemo"),
                      let last = NotificationKind.allCases.last else { return }
                // After a beat, not immediately: `.task` runs before the rows have been measured,
                // and scrolling to an item whose height is not settled lands short of it.
                try? await Task.sleep(nanoseconds: 500_000_000)
                proxy.scrollTo(last, anchor: .bottom)
            }
            #endif
        }
        .navigationTitle("Settings")
    }

    /// The status row. One element to VoiceOver — "Collecting health data, steps, calories, sleep
    /// and exercise feed your Digimon, never leaves this watch" is one fact, not three stops.
    private var healthRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            // An HStack rather than a `Label`: a `Label`'s title will not wrap inside a list row no
            // matter what line limit it is given, and "Collecting health data" is a couple of
            // characters too wide for a 42mm row — it truncated to "Collecting health…", losing the
            // one word that says what is being collected.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: healthStatus.symbolName)
                Text(healthStatus.title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(healthStatus.tint)

            Text(healthStatus.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                // Two lines, like the notification rows below: a 41mm screen truncates the
                // collecting line to nonsense on one.
                .lineLimit(2)

            // The same string the pre-prompt screen promised, from `HealthCopy` so the two cannot
            // drift. Said in every state, including the ones reading nothing — the promise is about
            // the build (there is no network code at all), not about today's authorization.
            Text(HealthCopy.neverLeavesTheWatch)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Collecting") {
    NavigationStack {
        SettingsView(settings: NotificationSettings(), healthStatus: .collecting)
    }
}

#Preview("Not collecting") {
    NavigationStack {
        SettingsView(settings: NotificationSettings(), healthStatus: .notCollecting)
    }
}
