import SwiftUI

/// The circular face shared by every button in the action grid (US-038, generalised in US-197).
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

    /// What the circle holds. Most buttons name an SF Symbol; Clean draws a coil of droppings, for
    /// which SF Symbols has no glyph (US-197) — see `ActionGlyph`.
    let glyph: ActionGlyph
    let tint: Color

    /// The common case: a tinted SF Symbol. Kept as a distinct initialiser so the seven symbol
    /// buttons read `ActionButtonFace(systemImage:tint:)` exactly as they did before US-197.
    init(systemImage: String, tint: Color) {
        self.init(glyph: .symbol(systemImage), tint: tint)
    }

    init(glyph: ActionGlyph, tint: Color) {
        self.glyph = glyph
        self.tint = tint
    }

    var body: some View {
        let colour = isEnabled ? tint : Color.secondary

        glyphView(colour)
            // The frame is the whole button: an exact size, not padding around a glyph whose
            // metrics differ per symbol, so all eight circles match and none exceeds the 32pt cap.
            .frame(width: Self.diameter, height: Self.diameter)
            .background(Circle().fill(colour.opacity(0.2)))
            .contentShape(Circle())
    }

    @ViewBuilder private func glyphView(_ colour: Color) -> some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colour)
        case .waste:
            WasteGlyph(colour: colour)
        }
    }
}

/// What an `ActionButtonFace` draws inside its circle.
///
/// An enum rather than a generic label so `ActionButtonFace.diameter` stays a plain static that the
/// layout tests can read without specialising the type.
enum ActionGlyph {
    /// A tinted SF Symbol, named by string.
    case symbol(String)
    /// A little heap of droppings, for the Clean button. **SF Symbols has no poop glyph** — every
    /// attempt to name one renders a blank square — so Clean draws the same three-ellipse coil
    /// `PoopShape` puts on the ground.
    case waste
}

/// The coil of droppings on the Clean button (US-197).
///
/// Three stacked ellipses widest at the base, the classic V-Pet heap `PoopShape` draws, sized up to
/// read inside a 30pt circle. Tinted with the button's own colour rather than a fixed brown so it
/// greys out with the rest of the face when there is nothing to clean.
struct WasteGlyph: View {
    let colour: Color

    var body: some View {
        // Negative spacing so the coils overlap into one solid heap instead of three separate blobs.
        VStack(spacing: -2) {
            Ellipse().frame(width: 5, height: 3.5)
            Ellipse().frame(width: 8, height: 4)
            Ellipse().frame(width: 11, height: 4.5)
        }
        .foregroundStyle(colour)
    }
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
                .accessibilityLabel("Feed")

                Button(action: train) {
                    ActionButtonFace(systemImage: "dumbbell", tint: .red)
                }
                .buttonStyle(.plain)
                // Training progress, red, ringed around the button that spends it (US-199).
                .overlay { DashRing(filled: trainCharges, total: trainChargeCap, tint: .red) }
                .accessibilityLabel("Train")
                .accessibilityValue(chargeValue(trainCharges, trainChargeCap))

                // A coil of droppings, not sparkles: the button that clears the mess should show the
                // mess, not the sparkle that follows it (US-197).
                Button(action: clean) {
                    ActionButtonFace(glyph: .waste, tint: .brown)
                }
                .buttonStyle(.plain)
                .disabled(isCleanDisabled)
                // Handwash/clean progress, blue, ringed around the Clean button (US-199). Drawn even
                // when the button is disabled at zero poop — the ring reads banked washes, not whether
                // there is a mess to spend them on.
                .overlay { DashRing(filled: cleanCharges, total: cleanChargeCap, tint: .blue) }
                .accessibilityLabel("Clean")
                .accessibilityValue(chargeValue(cleanCharges, cleanChargeCap))

                // A fighter, not a lightning bolt (US-197): a bolt reads as energy, which is what
                // Battle spends, not the fight it buys.
                Button(action: battle) {
                    ActionButtonFace(systemImage: "figure.martial.arts", tint: .purple)
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
