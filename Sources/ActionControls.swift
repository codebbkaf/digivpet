import SwiftUI

/// The circular face shared by the action row's buttons and its one navigation link.
///
/// Shared rather than duplicated because the bell is a `NavigationLink` and the other three are
/// `Button`s — two different containers that must nevertheless look like one row of four.
///
/// It reads `isEnabled` from the environment rather than taking a flag: the disabled Battle button
/// is disabled by the `.disabled` modifier on the `Button` that wraps this, and a second source of
/// truth for the same fact could disagree with it.
struct ActionButtonFace: View {
    /// The button diameter. The AC caps it at 32pt, which is also about the smallest circle a
    /// fingertip hits reliably on a 41mm screen — so this is both the ceiling and the right value.
    /// It lives here rather than on `ActionControls` because the face is what applies the frame,
    /// and because `ActionControls` is generic: `ActionControls.buttonDiameter` would not infer.
    static let diameter: CGFloat = 32

    @Environment(\.isEnabled) private var isEnabled

    let systemImage: String
    let tint: Color

    var body: some View {
        let colour = isEnabled ? tint : Color.secondary

        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(colour)
            // The frame is the whole button: an exact size, not padding around a glyph whose
            // metrics differ per symbol, so all four circles match and none exceeds the 32pt cap.
            .frame(width: Self.diameter, height: Self.diameter)
            .background(Circle().fill(colour.opacity(0.2)))
            .contentShape(Circle())
    }
}

/// The action row: Feed, Train, Battle and Notifications as circular icon-only buttons (US-038).
///
/// Icon-only, in one row, because the labelled buttons this replaces were three stacked blocks that
/// pushed the Digimon off the top of the screen — the thing the user actually came to look at. The
/// action names survive as accessibility labels, so nothing is lost to VoiceOver.
///
/// The stat readouts that used to sit above each button (hunger pips, STR, PWR/record) are now one
/// `StatsStrip` above the sprite, which is what let US-039 drop the screen's ScrollView.
struct ActionControls<Settings: View>: View {
    /// Battles still allowed today (US-032). Zero disables the Battle button and shows why.
    let battlesLeft: Int
    let feed: () -> Void
    let train: () -> Void
    let battle: () -> Void
    /// What the bell pushes. A builder rather than a concrete type so this view does not have to
    /// know about `NotificationSettingsView`, and so a test can hand it an `EmptyView`.
    @ViewBuilder let settings: () -> Settings

    /// Whether the Battle button is disabled. Not `private`, like `limitCaption`, so a test can
    /// assert the rule — a `.disabled` modifier inside `body` is unreachable outside a view graph.
    var isBattleDisabled: Bool { battlesLeft == 0 }

    /// The caption under the row. Nil on a full allowance — a permanent "5 left" would be noise;
    /// the count only earns its space once it is running out. At zero it is the model's OWN refusal
    /// string, so what a user reads cannot disagree with what was enforced.
    var limitCaption: String? {
        if battlesLeft == 0 { return MainScreenModel.battleLimitReason }
        if battlesLeft < BattleLimits.perDay { return "\(battlesLeft) left today" }
        return nil
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Button(action: feed) {
                    ActionButtonFace(systemImage: "fork.knife", tint: .orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Feed")

                Button(action: train) {
                    ActionButtonFace(systemImage: "dumbbell", tint: .red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Train")

                Button(action: battle) {
                    ActionButtonFace(systemImage: "bolt.fill", tint: .purple)
                }
                .buttonStyle(.plain)
                .disabled(isBattleDisabled)
                .accessibilityLabel("Battle")

                NavigationLink(destination: settings) {
                    ActionButtonFace(systemImage: "bell", tint: .blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")
            }

            if let limitCaption {
                Text(limitCaption)
                    .font(.system(size: 9))
                    .foregroundStyle(battlesLeft == 0 ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
