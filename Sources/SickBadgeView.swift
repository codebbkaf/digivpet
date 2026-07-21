import CoreGraphics
import SwiftUI

/// Where the sick badge sits and how much room it takes out of the sprite's slot (US-069).
///
/// Free-standing arithmetic rather than a static on the view, for the same reason `SpriteScale` is:
/// a test should be able to check that the badge and the Digimon cannot collide without building a
/// view graph to do it.
///
/// **The band is RESERVED, not merely drawn over.** The sprite is drawn with `.offset` and walks the
/// full width (US-037), so there is no corner of the slot it cannot reach — placing the badge in one
/// and hoping would put it on top of a moving silhouette, which US-068 made worse by giving sickness
/// two frames that differ around the head. Taking the band out of the height offered to
/// `SpriteScale.fitting` and bottom-aligning what is left is what makes "does not overlap" a fact
/// about the layout rather than a thing that happens to be true at one scale.
enum SickBadgeLayout {
    /// The strip at the top of the sprite's slot the badge owns while the Digimon is ill. Larger
    /// than `iconSize` so the symbol has air around it rather than butting onto the sprite below.
    static let reservedHeight: CGFloat = 18

    /// The symbol's point size. Small: this is a status light, not a control, and every point it
    /// takes comes back out of the Digimon.
    static let iconSize: CGFloat = 13

    /// How far the pulse fades. Not to zero — a badge that vanishes entirely reads as a glitch on a
    /// screen that is already showing something wrong.
    static let dimmestOpacity: Double = 0.25

    /// One half-cycle of the pulse. Slower than the 0.5s sprite cadence and faster than US-068's
    /// 1.5s sick loop, so the badge beats against the art rather than in step with it.
    static let pulseDuration: TimeInterval = 0.7

    /// The shortest slot in which the band is guaranteed clear.
    ///
    /// Below this, `SpriteScale.minimum` is binding — the sprite has stopped shrinking and is
    /// overflowing its slot whether or not it is ill, which is US-039's deliberate choice (a 32pt
    /// Digimon is the smallest one still readable as one). The badge does not cause that and cannot
    /// fix it; what it can do is stop pretending otherwise, so this is stated rather than assumed.
    ///
    /// Verified on the Simulator to be well below the real slot on both watch sizes — see US-069's
    /// note in progress.txt.
    static let clearanceFloor: CGFloat =
        reservedHeight + SpriteScale.minimum * CGFloat(SpriteSheet.frameSize)

    /// The height the sprite may size itself against inside a slot of `slotHeight`.
    ///
    /// Floored at zero so a slot smaller than the band cannot produce a negative height —
    /// `SpriteScale.fitting` already floors the scale itself, so the sprite overflows visibly rather
    /// than disappearing.
    static func spriteHeight(in slotHeight: CGFloat, isSick: Bool) -> CGFloat {
        guard isSick else { return slotHeight }
        return max(slotHeight - reservedHeight, 0)
    }
}

/// The pulsing bandage that says the Digimon is ill (US-069).
///
/// US-068's slow hurt loop is the illness itself, but a cadence is only legible against the healthy
/// one — a user who has never seen their Digimon walk has nothing to compare it to. This is the
/// unambiguous half: a red medical symbol that is either there or not.
///
/// The pulse is a `repeatForever` implicit animation started from `onAppear`, not a one-shot: the
/// badge is up for as long as the illness lasts, which can be days, and a badge that animated once
/// on appearance would be a static icon for every glance after the first.
struct SickBadgeView: View {
    @State private var dimmed = false

    var body: some View {
        Image(systemName: "bandage.fill")
            .font(.system(size: SickBadgeLayout.iconSize))
            .foregroundStyle(.red)
            .opacity(dimmed ? SickBadgeLayout.dimmestOpacity : 1)
            .animation(
                .easeInOut(duration: SickBadgeLayout.pulseDuration).repeatForever(autoreverses: true),
                value: dimmed
            )
            // Set in `onAppear` rather than as the initial value, because an implicit animation only
            // runs on a CHANGE — a state that was already true when the view appeared would draw the
            // dim frame and then never move.
            .onAppear { dimmed = true }
            .frame(height: SickBadgeLayout.reservedHeight)
            .accessibilityLabel("Sick")
    }
}

#Preview {
    SickBadgeView()
}
