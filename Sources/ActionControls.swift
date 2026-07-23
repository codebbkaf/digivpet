import SwiftUI

/// The circular face shared by every button in the action grid (US-038).
///
/// Shared rather than duplicated because the grid mixes `Button`s (Feed, Train, Clean, Battle,
/// Light) with `NavigationLink`s (Map, Party, Dex) — different containers that must nevertheless
/// look like one grid of eight identical circles.
///
/// It reads `isEnabled` from the environment rather than taking a flag: the disabled Battle button
/// is disabled by the `.disabled` modifier on the `Button` that wraps this, and a second source of
/// truth for the same fact could disagree with it.
struct ActionButtonFace: View {
    /// The button diameter. US-038 caps it at 32pt; it sits at 30 since US-052 added a fifth
    /// circle, because five 32pt buttons plus their gaps come to 184pt and the narrowest supported
    /// screen is 176pt wide — the row would have been clipped at both ends. Thirty is still
    /// comfortably above the ~28pt where a fingertip starts missing. US-197 split the row into two
    /// rows of four, so the width is no longer the binding constraint, but the size stays put so the
    /// eight circles match the diameter every earlier story built against.
    ///
    /// It lives here rather than on `ActionControls` because the face is what applies the frame,
    /// and because `ActionControls` is generic: `ActionControls.buttonDiameter` would not infer.
    static let diameter: CGFloat = 30

    @Environment(\.isEnabled) private var isEnabled

    /// The SF Symbol the circle holds. All eight buttons name one again as of US-209: the drawn
    /// `ActionGlyph.waste` coil US-197 put on Clean lost its only caller when Clean went back to its
    /// sparkle, so the enum and its `WasteGlyph` went with it.
    let systemImage: String
    let tint: Color

    var body: some View {
        let colour = isEnabled ? tint : Color.secondary

        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(colour)
            // The frame is the whole button: an exact size, not padding around a glyph whose
            // metrics differ per symbol, so all eight circles match and none exceeds the 32pt cap.
            .frame(width: Self.diameter, height: Self.diameter)
            .background(Circle().fill(colour.opacity(0.2)))
            .contentShape(Circle())
    }
}

/// The two glyph names US-209 reverted, named rather than inlined so the revert is auditable and a
/// test can hold them still.
///
/// A separate, non-generic enum for the same reason `ActionButtonFace.diameter` lives where it does:
/// `ActionControls` is generic over three destination types, so `ActionControls.cleanSymbol` would
/// not infer at a test's call site.
enum ActionSymbol {
    /// Clean. Was `"sparkles"` before US-197, `ActionGlyph.waste` (a drawn coil of droppings) from
    /// US-197, and `"sparkles"` again from US-209.
    static let clean = "sparkles"
    /// Battle. Was `"bolt.fill"` before US-197, `"figure.martial.arts"` from US-197, and
    /// `"bolt.fill"` again from US-209.
    static let battle = "bolt.fill"
}

/// The action grid: Feed, Train, Clean, Battle on the top row and Map, Party, Light, Dex on the
/// bottom, as circular icon-only buttons (US-038, split into two rows in US-197).
///
/// Icon-only, in rows, because the labelled buttons this replaces were stacked blocks that pushed
/// the Digimon off the top of the screen — the thing the user actually came to look at. The action
/// names survive as accessibility labels, so nothing is lost to VoiceOver.
///
/// US-197 pulled Light out of the toolbar and Dex too, and brought Map and Party in beside them, so
/// every way out of the room is one consistent circle in this grid rather than scattered between the
/// toolbar, a strip and a row.
struct ActionControls<MapDestination: View, PartyDestination: View, DexDestination: View>: View {
    /// Whether the Digimon can pay `BattleCost.energy` (US-108, replacing US-032's daily count).
    /// False disables the Battle button and shows why.
    let canAffordBattle: Bool
    /// Poops on screen (US-051). Zero disables the Clean button — there is nothing to clean, and a
    /// tap that did nothing would read as the button being broken.
    let poopCount: Int
    /// What the light is doing now (US-114), so the Light button's glyph names the state it is IN.
    let lightState: LightState

    /// The three spendable charges drawn as segmented rings AROUND their own buttons (US-199): Train
    /// red, Battle purple, Clean blue. Each pair is the same count/cap a straight `DashBar` used to
    /// read on the currency row before this story moved the reading onto the button that spends it.
    /// Defaulted to 0/0 so a ring is simply absent — every test call site that predates the rings
    /// compiles unchanged and draws no ring.
    var trainCharges: Int = 0
    var trainChargeCap: Int = 0
    var battleCharges: Int = 0
    var battleChargeCap: Int = 0
    var cleanCharges: Int = 0
    var cleanChargeCap: Int = 0

    /// The meat larder, ringed around Feed in orange (US-208). It joined the other three a story
    /// late: US-199 left meat as a lone `DashBar` on the currency row because it is a POOL rather
    /// than a per-tap charge, which made it the one reading a player had to look somewhere else for.
    /// A pool still has a count and a cap, so it rings the same way — and the row it was alone on is
    /// gone. Defaulted to 0/0 like the rest, so no ring draws for a call site that says nothing.
    var meat: Int = 0
    var meatCap: Int = 0

    let feed: () -> Void
    let train: () -> Void
    let clean: () -> Void
    let battle: () -> Void
    /// One tap of the Light button; cycles on -> semi -> off -> on like the old toolbar switch did.
    let cycleLight: () -> Void
    /// The three destinations the navigation buttons push. Builders rather than concrete types so
    /// this view need not know about `MapListView`, `PartyView` or `DexView`, and so a test can hand
    /// each an `EmptyView`; lazy so the store a `DexView` opens is not built on every body pass.
    @ViewBuilder let mapDestination: () -> MapDestination
    @ViewBuilder let partyDestination: () -> PartyDestination
    @ViewBuilder let dexDestination: () -> DexDestination

    /// Whether the Battle button is disabled. Not `private`, like `limitCaption`, so a test can
    /// assert the rule — a `.disabled` modifier inside `body` is unreachable outside a view graph.
    var isBattleDisabled: Bool { !canAffordBattle }

    /// Whether the Clean button is disabled. Derived from the count the pile is DRAWN from, not
    /// from a separate flag, so the button and the mess on screen cannot disagree.
    var isCleanDisabled: Bool { poopCount == 0 }

    /// The caption under the grid. Nil while a battle is affordable — a permanent cost label on one of
    /// eight buttons would be noise on a 41mm screen. When it is not, it is the model's OWN refusal
    /// string, so what a user reads cannot disagree with what was enforced.
    var limitCaption: String? {
        canAffordBattle ? nil : BattleCost.insufficientEnergyReason
    }

    /// What a charge ring speaks for VoiceOver — the "N of M" a `DashBar` would have spoken, now voiced
    /// on the button rather than on the (silent, decorative) ring around it. `filled` is bounded by the
    /// cap so a mid-tick overshoot never says "11 of 10". An empty economy (`total <= 0`) speaks
    /// nothing so the button reads as just its label.
    func chargeValue(_ filled: Int, _ total: Int) -> String {
        guard total > 0 else { return "" }
        return "\(min(max(filled, 0), total)) of \(total)"
    }

    var body: some View {
        VStack(spacing: 4) {
            // Row 1 — the things you do FOR the Digimon. Four points between four circles:
            // 4 * 30 + 3 * 4 = 132pt, well inside the 176pt of the narrowest supported screen.
            HStack(spacing: 4) {
                Button(action: feed) {
                    ActionButtonFace(systemImage: "fork.knife", tint: .orange)
                }
                .buttonStyle(.plain)
                // The larder, orange, ringed around the button that spends it (US-208) — the same
                // overlay the other three carry, so meat reads where it is used like they do.
                .overlay { DashRing(filled: meat, total: meatCap, tint: .orange) }
                .accessibilityLabel("Feed")
                .accessibilityValue(chargeValue(meat, meatCap))

                Button(action: train) {
                    ActionButtonFace(systemImage: "dumbbell", tint: .red)
                }
                .buttonStyle(.plain)
                // Training progress, red, ringed around the button that spends it (US-199).
                .overlay { DashRing(filled: trainCharges, total: trainChargeCap, tint: .red) }
                .accessibilityLabel("Train")
                .accessibilityValue(chargeValue(trainCharges, trainChargeCap))

                // Back to the sparkle (US-209). US-197 had drawn `ActionGlyph.waste` — a coil of
                // droppings — on the argument that the button should show the mess rather than what
                // follows it; the sparkle is preferred, so the glyph reverts. Only the GLYPH does:
                // the tint stays the `.brown` US-197 gave it, and the ring, the disabled rule and the
                // label are untouched.
                Button(action: clean) {
                    ActionButtonFace(systemImage: ActionSymbol.clean, tint: .brown)
                }
                .buttonStyle(.plain)
                .disabled(isCleanDisabled)
                // Handwash/clean progress, blue, ringed around the Clean button (US-199). Drawn even
                // when the button is disabled at zero poop — the ring reads banked washes, not whether
                // there is a mess to spend them on.
                .overlay { DashRing(filled: cleanCharges, total: cleanChargeCap, tint: .blue) }
                .accessibilityLabel("Clean")
                .accessibilityValue(chargeValue(cleanCharges, cleanChargeCap))

                // Back to the bolt (US-209), for the same reason Clean went back to its sparkle.
                // US-197 had made this `figure.martial.arts` on the argument that a bolt reads as the
                // energy Battle spends rather than the fight it buys; the bolt is preferred. The
                // `.purple` tint never changed, so this is a glyph-only revert too.
                Button(action: battle) {
                    ActionButtonFace(systemImage: ActionSymbol.battle, tint: .purple)
                }
                .buttonStyle(.plain)
                .disabled(isBattleDisabled)
                // Battle-time progress, purple, ringed around the Battle button (US-199).
                .overlay { DashRing(filled: battleCharges, total: battleChargeCap, tint: .purple) }
                .accessibilityLabel("Battle")
                .accessibilityValue(chargeValue(battleCharges, battleChargeCap))
            }

            // Row 2 — the ways out of the room and the switch on its wall.
            HStack(spacing: 4) {
                NavigationLink {
                    mapDestination()
                } label: {
                    ActionButtonFace(systemImage: "map.fill", tint: .green)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Map")

                NavigationLink {
                    partyDestination()
                } label: {
                    ActionButtonFace(systemImage: "person.2.fill", tint: .teal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Party")

                // The room light (US-114), now a circle in the grid rather than a toolbar switch
                // (US-197). The glyph names the state the light is IN, not the one a tap moves to —
                // see `LightState.symbolName` — so it reads as an indicator that happens to be
                // tappable, exactly as the toolbar version did.
                Button(action: cycleLight) {
                    ActionButtonFace(systemImage: lightState.symbolName, tint: .yellow)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Light")
                .accessibilityValue(lightState.displayName)
                .accessibilityHint("Cycles the room light")

                NavigationLink {
                    dexDestination()
                } label: {
                    ActionButtonFace(systemImage: "book.fill", tint: .blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dex")
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
