import SwiftUI

/// How a found egg is announced to the player (US-128).
///
/// A light overlay rather than a full ceremony like `EvolutionCeremonyView`: a drop is a gift, not a
/// transformation, and the player is usually mid-action (they just trained or battled) — so it says
/// its piece over the game and steps aside on a tap rather than taking the screen. The egg is drawn
/// with `IdleSpriteView`, which carries the `.interpolation(.none)` every sprite in the game uses.
struct DigitamaDropBanner: View {
    let announcement: DigitamaDropAnnouncement
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            VStack(spacing: 4) {
                Text("Found an egg!")
                    .font(.system(size: 13, weight: .semibold))

                IdleSpriteView(stage: announcement.stage.rawValue, name: announcement.spriteFile)

                Text(announcement.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
