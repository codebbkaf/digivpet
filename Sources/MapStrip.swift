import Foundation

/// What the main screen knows about the map the Digimon is walking: which one it is, and how far
/// across it the player has got.
///
/// It was a VIEW's backing value until US-210 — the thin row above the energy bars that named the
/// map and held the way through to the box (US-120). That row is gone: US-197 gave the action grid
/// its own Map and Party circles, so the strip was a second door to a screen the grid already
/// opened, plus a name floating under the sprite. The value outlived it because the Map button's
/// green `DashRing` (US-212) is built from `recordedSteps`/`totalSteps`, and because
/// what it SAYS — which map it names when nothing is selected, how the counter is spelled — is
/// arithmetic, and arithmetic belongs somewhere a test can reach without a Simulator.
struct MapStrip: Equatable {
    /// The selected map's name, or — with nothing selected — the first map's, which is the one the
    /// player would choose (US-120 AC6).
    ///
    /// No longer DRAWN anywhere since US-210 took the map's name off the main screen; kept for
    /// `progressText`'s reason, that it is the single place this feature decides which map a save
    /// with no selection is invited towards, and what `MapStripTests` pins that rule against.
    let mapName: String

    /// `recorded / total`, spelled exactly as `MapListRow.progressText` spells it: space, slash,
    /// space, no abbreviation, no rounding up and no grouping separator. The same string on both
    /// screens is the point — a figure that reads `1222 / 25000` in the list and `1.2k` here would
    /// be two answers to one question.
    ///
    /// No longer drawn since US-196 moved the step reading into a bar, and US-212 that bar onto the
    /// Map button's ring; kept because it is still this feature's single spelled counter and what
    /// `MapStripTests` pins the counter's exact wording against.
    let progressText: String

    /// The floored step counter and the map's length, the raw numbers the Map button's `DashRing`
    /// fills (US-196, ringed in US-212). The same values `progressText` spells, exposed as integers
    /// so the ring can draw the fraction rather than re-parse the string.
    let recordedSteps: Int
    let totalSteps: Int

    /// The map this is about, or nil when the player has chosen nowhere yet.
    let mapId: String?

    /// Whether this is naming a map the player has NOT chosen.
    ///
    /// Nothing is gated on having chosen (US-120 AC6): the game is fully playable with this true.
    let isPrompt: Bool
}

extension MapStrip {
    /// The strip for a save, or the prompt when the save names nowhere.
    ///
    /// - Parameters:
    ///   - catalog: the sixteen maps, injected as everywhere else in this feature so a test drives
    ///     a two-map fixture rather than whatever `maps.json` currently says a map is worth.
    ///   - progress: the save. Nil — the moment before `start()` finishes — reads as a player who
    ///     has chosen nowhere, so the reading prompts rather than disappearing.
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
