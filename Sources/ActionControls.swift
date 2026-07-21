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
    /// The button diameter. US-038 caps it at 32pt; it sits at 30 since US-052 added a fifth
    /// circle, because five 32pt buttons plus their gaps come to 184pt and the narrowest supported
    /// screen is 176pt wide — the row would have been clipped at both ends. Thirty is still
    /// comfortably above the ~28pt where a fingertip starts missing.
    ///
    /// It lives here rather than on `ActionControls` because the face is what applies the frame,
    /// and because `ActionControls` is generic: `ActionControls.buttonDiameter` would not infer.
    static let diameter: CGFloat = 30

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

/// The action row: Feed, Train, Clean, Battle and Notifications as circular icon-only buttons
/// (US-038, with Clean joining in US-052).
///
/// Icon-only, in one row, because the labelled buttons this replaces were three stacked blocks that
/// pushed the Digimon off the top of the screen — the thing the user actually came to look at. The
/// action names survive as accessibility labels, so nothing is lost to VoiceOver.
///
/// The stat readouts that used to sit above each button (hunger pips, STR, PWR/record) are now one
/// `StatsStrip` above the sprite, which is what let US-039 drop the screen's ScrollView.
struct ActionControls<Settings: View>: View {
    /// Whether the Digimon can pay `BattleCost.energy` (US-108, replacing US-032's daily count).
    /// False disables the Battle button and shows why.
    let canAffordBattle: Bool
    /// Poops on screen (US-051). Zero disables the Clean button — there is nothing to clean, and a
    /// tap that did nothing would read as the button being broken.
    let poopCount: Int
    let feed: () -> Void
    let train: () -> Void
    let clean: () -> Void
    let battle: () -> Void
    /// What the bell pushes. A builder rather than a concrete type so this view does not have to
    /// know about `NotificationSettingsView`, and so a test can hand it an `EmptyView`.
    @ViewBuilder let settings: () -> Settings

    /// Whether the Battle button is disabled. Not `private`, like `limitCaption`, so a test can
    /// assert the rule — a `.disabled` modifier inside `body` is unreachable outside a view graph.
    var isBattleDisabled: Bool { !canAffordBattle }

    /// Whether the Clean button is disabled. Derived from the count the pile is DRAWN from, not
    /// from a separate flag, so the button and the mess on screen cannot disagree.
    var isCleanDisabled: Bool { poopCount == 0 }

    /// The caption under the row. Nil while a battle is affordable — a permanent cost label on one of
    /// five buttons would be noise on a 41mm screen. When it is not, it is the model's OWN refusal
    /// string, so what a user reads cannot disagree with what was enforced.
    var limitCaption: String? {
        canAffordBattle ? nil : BattleCost.insufficientEnergyReason
    }

    var body: some View {
        VStack(spacing: 3) {
            // Four points between five circles: 5 * 30 + 4 * 4 = 166pt, which clears the 176pt of
            // the narrowest supported screen with a margin at each end. The spacing came down with
            // the diameter when Clean made this a row of five — see `ActionButtonFace.diameter`.
            HStack(spacing: 4) {
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

                // Beside Feed and Train rather than out at the end, because cleaning up is the
                // third thing you do FOR the Digimon; Battle and the bell are what you do with it.
                Button(action: clean) {
                    ActionButtonFace(systemImage: "sparkles", tint: .teal)
                }
                .buttonStyle(.plain)
                .disabled(isCleanDisabled)
                .accessibilityLabel("Clean")

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
                    // Orange because that is already what "you have run out" looks like here: it is
                    // the colour US-032's caption turned at zero battles left. The condition it was
                    // once conditional ON is gone — the caption now exists only in the run-out
                    // state — so the tint is unconditional rather than newly invented.
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
