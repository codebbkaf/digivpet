import SwiftUI

/// The Settings screen, behind the main screen's top-right gear (US-198).
///
/// One `Section` for now — the notification toggles, which lived behind a bell in the action row until
/// US-197 cleared that row down to the eight game actions. The toggle rows are reused whole from the
/// old notification settings screen via `NotificationSettingsSection`, so they persist and behave
/// exactly as they did off the bell; a `List` with a titled `Section` around them is the only thing
/// added, so a second settings group can join it later without moving anything.
struct SettingsView: View {
    @ObservedObject var settings: NotificationSettings

    var body: some View {
        ScrollViewReader { proxy in
            List {
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
}
