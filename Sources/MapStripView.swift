import SwiftUI

/// The one thin row above the energy bars: where you are adventuring, and the way through to the
/// box of Digimon (US-120).
///
/// A value type rather than a view reading the catalog and the save itself, for the same reason
/// `MapListRow` is one: what the strip SAYS — which map it names when nothing is selected, how the
/// counter is spelled, whether the party button is live yet — is arithmetic, and arithmetic belongs
/// somewhere a test can reach without a Simulator.
struct MapStrip: Equatable {
    /// The name shown on the leading control. The selected map's, or — with nothing selected — the
    /// first map's, which is the one the player would choose (US-120 AC6).
    let mapName: String

    /// `recorded / total`, spelled exactly as `MapListRow.progressText` spells it: space, slash,
    /// space, no abbreviation, no rounding up and no grouping separator. The same string on both
    /// screens is the point — a figure that reads `1222 / 25000` in the list and `1.2k` here would
    /// be two answers to one question.
    ///
    /// No longer drawn on the strip itself since US-196 moved the step reading into the map-step
    /// `DashBar` (`MainReadingBars`); kept because it is still the strip's single spelled counter and
    /// what `MapStripTests` pins the counter's exact wording against.
    let progressText: String

    /// The floored step counter and the map's length, the raw numbers the map-step `DashBar` fills
    /// (US-196). The same values `progressText` spells, exposed as integers so `MainReadingBars` can
    /// draw them as a proportional bar rather than re-parse the string.
    let recordedSteps: Int
    let totalSteps: Int

    /// The map this strip is about, or nil when the player has chosen nowhere yet. What the strip's
    /// own tap does NOT depend on — the list is always reachable — but what the label means does.
    let mapId: String?

    /// Whether the strip is naming a map the player has NOT chosen, as an invitation.
    ///
    /// Nothing is gated on having chosen (AC6): the game is fully playable with this true, and the
    /// only difference is that the row reads as a prompt rather than as a report.
    let isPrompt: Bool

    /// The glyph in front of the name. Different in the two states on purpose: a player glancing at
    /// this row has to be able to tell "you are walking here" from "pick somewhere to walk" without
    /// reading the counter, and the counter says `0 / 3000` in both cases on a fresh save.
    var symbol: String { isPrompt ? MapStripMarks.promptSymbol : MapStripMarks.travellingSymbol }

    /// What VoiceOver reads. Spelled out, because "Grassland, 0 / 3000" is not a sentence.
    var accessibilityLabel: String {
        isPrompt ? "Choose a map. \(mapName)" : "Adventuring in \(mapName)"
    }
}

/// The glyphs the strip marks its two states with (US-120).
///
/// Free-standing for the reason `MapListMarks` is: "the strip says which state it is in" is a thing
/// a test can only check if the names are reachable without building a view graph.
enum MapStripMarks {
    /// Travelling. The same walking figure the map list marks the selected row with, so the two
    /// screens agree about what "you are here" looks like.
    static let travellingSymbol = "figure.walk"

    /// Nowhere chosen yet — a folded map, which is what an unchosen map looks like.
    static let promptSymbol = "map"

    /// The way to the box of Digimon (US-126).
    static let partySymbol = "person.2.fill"
}

extension MapStrip {
    /// The strip for a save, or the prompt when the save names nowhere.
    ///
    /// - Parameters:
    ///   - catalog: the sixteen maps, injected as everywhere else in this feature so a test drives
    ///     a two-map fixture rather than whatever `maps.json` currently says a map is worth.
    ///   - progress: the save. Nil — the moment before `start()` finishes — reads as a player who
    ///     has chosen nowhere, so the strip prompts rather than disappearing.
    ///   - Returns: nil only for an EMPTY catalog, which the US-117 validator makes impossible in
    ///     the shipped file but which a fixture can still build.
    static func make(in catalog: MapCatalog = .bundled, progress: PlayerProfile?) -> MapStrip? {
        let selected = progress?.selectedMapId.flatMap { catalog.map(id: $0) }
        // The FIRST map rather than the first UNLOCKED one: with nothing selected nothing has been
        // finished either, so map one is the only unlocked map there is — and if a save somehow
        // reaches here with progress and no selection, map one is still the honest suggestion,
        // because it is the one that is always open.
        guard let map = selected ?? catalog.maps.first else { return nil }
        let recorded = Int((progress?.recorded(forMap: map.id) ?? 0).rounded(.down))
        return MapStrip(
            mapName: map.displayName,
            // Floored, never rounded, for `MapListRow.recordedSteps`' reason: a counter must not
            // read as a step the player has not taken.
            progressText: "\(recorded) / \(map.totalSteps)",
            recordedSteps: recorded,
            totalSteps: map.totalSteps,
            mapId: selected?.id,
            isPrompt: selected == nil
        )
    }
}

/// The strip's sizes, and the one fact about it that is an acceptance criterion.
///
/// `AC3: the row costs at most one line of height`, so the font is stated here rather than inline:
/// a test can assert the row is a single line at a legible size, and cannot assert anything about a
/// literal buried in a `body`.
enum MapStripLayout {
    /// Small, and deliberately smaller than the name line above it. Every point this row takes comes
    /// straight out of the Digimon — the sprite is the one flexible row on this screen — so it is as
    /// tight as legibility allows rather than as comfortable as it could be.
    static let fontSize: CGFloat = 10

    /// The party button's glyph. Matched to the text rather than to the action row's 30pt circles:
    /// this is a way through, not one of the five things you DO to the Digimon.
    static let iconSize: CGFloat = 11

    /// How far the party button is faded while it has nowhere to go (AC2). Well below the 0.55 a
    /// locked map list row uses, because this is not "shut for now" but "not built yet", and a
    /// control at full strength that does nothing when tapped is worse than one that looks off.
    static let disabledOpacity: Double = 0.3

    /// Whether the party button leads anywhere. TRUE since US-126 built `PartyView`; it was false
    /// while the button was drawn but inert, so the row's shape would not change under the player
    /// the day the box landed.
    ///
    /// It stays as a constant rather than being deleted with the fade it used to gate, because it is
    /// what the "not a dead tap target that looks live" test turns on: the button is at full
    /// strength exactly while it leads somewhere, and both halves move together or not at all.
    static let isPartyReachable = true
}

/// Where you are adventuring, and the way to the box (US-120).
///
/// Two controls in one line above the energy bars, which is where they are rather than in the
/// toolbar because watchOS gives a screen two toolbar slots and US-114 spent the second one on the
/// room light, and rather than in the action row because that row is the five things you do TO the
/// Digimon and neither of these is one of them.
struct MapStripView<Destination: View, Party: View>: View {
    let strip: MapStrip

    /// What the leading control pushes — `MapListView` in the app, an `EmptyView` in a test that
    /// only cares what the row says.
    @ViewBuilder let destination: () -> Destination

    /// What the trailing control pushes — `PartyView` in the app (US-126). Injected on the same
    /// footing as `destination` rather than built here, so this row still knows nothing about either
    /// screen and a preview can stand one up without a model.
    @ViewBuilder let party: () -> Party

    var body: some View {
        HStack(spacing: 4) {
            NavigationLink(destination: destination) {
                HStack(spacing: 3) {
                    // Just the map's name now (US-196): the `figure.walk` travelling icon and the
                    // "recorded / total" step-count wording both left the strip, because the step
                    // reading moved into the map-step `DashBar` below (`MainReadingBars`) and a
                    // counter spelled in two places is two answers to one question. The name still
                    // carries the two states in its colour — orange when adventuring, secondary as a
                    // prompt — and to VoiceOver through `accessibilityLabel`.
                    Text(strip.mapName)
                        .font(.system(size: MapStripLayout.fontSize, weight: .semibold))
                        .foregroundStyle(strip.isPrompt ? Color.secondary : Color.primary)

                    Spacer(minLength: 0)
                }
                // One line, shrinking rather than wrapping: a second line here would come straight
                // out of the Digimon, and the widest this row ever reads — "Factory Town" — is what
                // the 41mm screenshot was taken to settle.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strip.accessibilityLabel)

            NavigationLink(destination: party) {
                Image(systemName: MapStripMarks.partySymbol)
                    .font(.system(size: MapStripLayout.iconSize))
                    .foregroundStyle(.secondary)
                    // At full strength since US-126, because it now leads somewhere. The fade is
                    // kept in the expression rather than deleted with the story: what it says is
                    // "bright exactly while it is live", which is the rule, and a literal 1 would
                    // say nothing.
                    .opacity(MapStripLayout.isPartyReachable ? 1 : MapStripLayout.disabledOpacity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!MapStripLayout.isPartyReachable)
            .accessibilityLabel("Party")
        }
    }
}

#Preview {
    NavigationStack {
        VStack {
            MapStripView(strip: MapStrip.make(progress: PlayerProfile(selectedMapId: "01_grassland"))!,
                         destination: { EmptyView() },
                         party: { EmptyView() })
            MapStripView(strip: MapStrip.make(progress: nil)!,
                         destination: { EmptyView() },
                         party: { EmptyView() })
        }
    }
}
