import SwiftUI

/// The settings screen: one switch per kind of notification, all on to begin with (AC3).
///
/// A plain `List` of toggles rather than anything cleverer, because there are exactly three of them
/// and they are the whole screen. Driven off `NotificationKind.allCases`, so a fourth kind gets its
/// row for free — and cannot be added without a way to turn it off.
struct NotificationSettingsView: View {
    @ObservedObject var settings: NotificationSettings

    var body: some View {
        ScrollViewReader { proxy in
            List {
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
            #if DEBUG
            // Screenshot hook, and the same reason as every other one in this project: `simctl` can
            // neither tap nor scroll, and since US-054 there is a fourth toggle that starts below
            // the fold on every watch size. Without this the last row cannot be photographed at all.
            // It moves the scroll position and nothing else — no toggle, no default, no rule.
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
        .navigationTitle("Notifications")
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
