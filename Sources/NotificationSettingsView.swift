import SwiftUI

/// The notification toggles, one row per kind, all on to begin with (AC3) — the reusable content.
///
/// Was the whole of `NotificationSettingsView`, the screen behind the action row's bell, until US-197
/// cleared that row down to the eight game actions and US-198 moved settings behind a top-right gear.
/// Extracted here as `List` rows only — no `List` of its own — so `SettingsView` can drop it into a
/// `Section` without nesting one list in another, and so the toggles keep drawing off the exact same
/// `NotificationSettings` and persist and behave exactly as they did off the bell.
///
/// Driven off `NotificationKind.allCases`, so a new kind gets its row for free — and cannot be added
/// without a way to turn it off. US-100's lights-out nudge is the fifth.
struct NotificationSettingsSection: View {
    @ObservedObject var settings: NotificationSettings

    var body: some View {
        ForEach(NotificationKind.allCases) { kind in
            Toggle(isOn: binding(for: kind)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.displayName)
                        .font(.caption)
                    Text(kind.settingsDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        // Two lines, not one: a 41mm screen truncates "24 hours before an
                        // untreated illness kills it" to nonsense on a single line.
                        .lineLimit(2)
                }
            }
            .id(kind)
        }
    }

    /// A binding onto one toggle.
    ///
    /// Hand-made rather than `@AppStorage`, because the default has to be TRUE for a key that has
    /// never been written and `@AppStorage`'s default cannot be read back through the same object
    /// the dispatcher consults — `NotificationSettings` is the single place that rule lives.
    private func binding(for kind: NotificationKind) -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled(kind) },
            set: { settings.setEnabled($0, for: kind) }
        )
    }
}
