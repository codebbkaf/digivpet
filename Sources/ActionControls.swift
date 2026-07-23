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
    /// The button diameter, and the number US-211's AC2 asks to be documented rather than guessed.
    ///
    /// US-038 caps it at 32pt; it sits at 30 since US-052 added a fifth circle, because five 32pt
    /// buttons plus their gaps come to 184pt and the narrowest supported screen is 176pt wide — the
    /// row would have been clipped at both ends. US-197 split the row into two rows of four, which
    /// briefly made width a non-issue; US-211 puts five back on row 1, so the old constraint binds
    /// again and 30 is re-derived rather than merely inherited:
    ///
    ///   * five circles and their four gaps come to `5 * 30 + 4 * 4 = 166pt`, 10pt inside the 176pt
    ///     of the narrowest supported screen;
    ///   * what a neighbouring button actually has to clear is the RING, not the face —
    ///     `DashRing.diameter` is `diameter + 4`, so two adjacent rings exactly meet at a 4pt gap
    ///     and any larger face would make them overlap;
    ///   * 32 would fit the faces (`5 * 32 + 4 * 4 = 176`) with zero margin and overlapping rings,
    ///     so 30 is the largest diameter this grid can actually carry.
    ///
    /// The ring pitch that gives — 34pt of circle every 34pt of row — is the scale of the leading
    /// control on a watchOS list row, which is what "sized like a list row" buys at five columns; the
    /// list-row FEEL comes from `ActionGridLayout`'s stagger and scrolling rather than from a taller
    /// button. Thirty is also comfortably above the ~28pt where a fingertip starts missing.
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

/// Where the action grid's circles sit (US-211): a five-column grid whose every other row is
/// staggered half a cell, so the lower row's buttons fall into the notches between the upper row's
/// rather than lining up under them — the honeycomb reading a watchOS app list has.
///
/// Free-standing and non-generic, in the same spirit as `DashBarLayout`: the arrangement is
/// arithmetic, and a test should be able to check the row split, the offset and the width against
/// the narrowest screen without standing up a view graph. (`ActionControls` is generic over three
/// destination types, so a static on it would not infer at a test's call site.)
enum ActionGridLayout {
    /// Buttons per row. Five, because that is what fits: see `ActionButtonFace.diameter` for the
    /// arithmetic that ties the column count, the face and the ring together.
    static let columns = 5

    /// The gap between two circles in a row, and between two rows. Four points, which is exactly the
    /// 2pt each neighbouring `DashRing` overhangs its face — so adjacent rings meet and never overlap.
    static let spacing: CGFloat = 4

    /// Centre-to-centre distance between two circles in a row.
    static var cellPitch: CGFloat { ActionButtonFace.diameter + spacing }

    /// The width of a FULL row — what the grid is sized to, so a short row is positioned inside the
    /// same box a five-button row occupies rather than being centred on its own.
    static var width: CGFloat {
        CGFloat(columns) * ActionButtonFace.diameter + CGFloat(columns - 1) * spacing
    }

    /// How the buttons chunk into rows, in order: five to a row until the last, which takes the
    /// remainder. Nine buttons — the eight drawn today plus US-213's Sleep — give `[5, 4]`; a
    /// fourteenth would give `[5, 5, 4]` with no change to anything that draws.
    static func rowCounts(forButtons count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return stride(from: 0, to: count, by: columns).map { min(columns, count - $0) }
    }

    /// How far right row `row` starts. Even rows are flush; odd rows are offset half a cell, which
    /// puts each of their buttons exactly midway between two of the row above's.
    static func staggerOffset(forRow row: Int) -> CGFloat {
        row.isMultiple(of: 2) ? 0 : cellPitch / 2
    }

    /// The natural height of `rows` rows of circles — the cap the scroll view is given, so it takes
    /// no more room than the grid needs and scrolls only once the screen offers it less.
    static func height(forRows rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * ActionButtonFace.diameter + CGFloat(rows - 1) * spacing
    }
}

/// The action grid: Feed, Train, Clean, Battle, Map on the top row and Party, Light, Dex on the
/// staggered bottom row, as circular icon-only buttons (US-038; two rows since US-197; five-column
/// and staggered since US-211).
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

    /// How far the active Digimon has walked the selected map and how long that map is, ringed around
    /// Map in green (US-212) — the last reading that still lived as a bar under the sprite. It is the
    /// same `MapStrip.recordedSteps`/`totalSteps` pair `MainReadingBars` drew, and it rings for the
    /// reason the other four do: a reading belongs on the button it is about. Defaulted to 0/0, which
    /// is also what no map selected gives, so no ring draws.
    var mapRecorded: Int = 0
    var mapTotal: Int = 0

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

    /// What the Map button speaks (US-212). `chargeValue`'s "N of M" with the unit said aloud, because
    /// these two numbers are not a charge count: "1500 of 25000" alone would leave a VoiceOver user to
    /// guess what was being counted, and the bar this replaces named its unit for the same reason.
    /// Clamped and silenced on an absent map exactly as `chargeValue` is — a finished map is not
    /// capped at its finish line, and it must not say "26000 of 25000 steps".
    var mapValue: String {
        guard mapTotal > 0 else { return "" }
        return "\(min(max(mapRecorded, 0), mapTotal)) of \(mapTotal) steps"
    }

    /// How many circles the grid draws. Eight today; US-213 appends Sleep and this becomes 9, which
    /// `ActionGridLayout.rowCounts` chunks into the 5-and-4 US-211 describes with nothing else to
    /// change. Named rather than counted by hand so the scroll view's height cap cannot drift out of
    /// step with the rows below it.
    static var buttonCount: Int { 8 }

    private var rowCounts: [Int] { ActionGridLayout.rowCounts(forButtons: Self.buttonCount) }

    var body: some View {
        VStack(spacing: 4) {
            // Scrollable since US-211, and capped at the grid's own natural height: with room to
            // spare the ScrollView takes exactly `height(forRows:)` and behaves like the plain VStack
            // it replaces — the sprite above loses nothing — and when a screen (or a third row of
            // buttons) leaves it less, it scrolls instead of clipping. `.basedOnSize` so a grid that
            // fits does not rubber-band under a finger.
            ScrollView(.vertical) {
                // Leading-aligned inside a FULL row's width, so the staggered row below is measured
                // against the five-column box rather than being re-centred on its own three buttons.
                VStack(alignment: .leading, spacing: ActionGridLayout.spacing) {
                    careRow
                    // Half a cell right, so Party, Light and Dex sit in the notches between the row
                    // above's circles. Row 0 takes `staggerOffset(forRow: 0)` = 0 and is left flush.
                    placesRow
                        .offset(x: ActionGridLayout.staggerOffset(forRow: 1))
                }
                .frame(width: ActionGridLayout.width, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: ActionGridLayout.height(forRows: rowCounts.count))

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

    /// Row 0 — the things you do FOR the Digimon, plus the map they are done on. Five circles and
    /// their four gaps: 5 * 30 + 4 * 4 = 166pt, inside the 176pt of the narrowest supported screen.
    private var careRow: some View {
        HStack(spacing: ActionGridLayout.spacing) {
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

            // Map moved up from row 2 in US-211: the sequence of buttons is unchanged, it is only
            // chunked five to a row instead of four, so Map is the fifth circle rather than the first
            // of the second row.
            NavigationLink {
                mapDestination()
            } label: {
                ActionButtonFace(systemImage: "map.fill", tint: .green)
            }
            .buttonStyle(.plain)
            // Map progress, green to match the glyph, ringed around the button that chooses the map
            // (US-212) — the reading that used to be a `DashBar` under the sprite. The other four
            // rings count something a tap SPENDS; this one counts what walking has earned towards
            // the far end of the map, which is the same relationship the other way round.
            .overlay { DashRing(filled: mapRecorded, total: mapTotal, tint: .green) }
            .accessibilityLabel("Map")
            .accessibilityValue(mapValue)
        }
    }

    /// Row 1 — the ways out of the room and the switch on its wall, staggered half a cell right so
    /// they sit between the circles above. Three today; US-213's Sleep is the fourth, and lands here
    /// with no change to this row's shape.
    private var placesRow: some View {
        HStack(spacing: ActionGridLayout.spacing) {
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
    }
}
