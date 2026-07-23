import Foundation

/// Which slice of a map's opponent pool the player is fighting right now (US-122).
///
/// A map is a place you walk ACROSS, so the further across it you are the tougher what lives there
/// gets: `p = recorded / totalSteps` picks one of four bands, lowest to highest. The bands are the
/// **pool's own** rungs rather than a fixed stage ladder — a map is authored with the Digimon that
/// belong in it, and a band that named a stage the author never put there would be an empty fight.
///
/// PURE and free of the generator: the band is decided here and `BattleMatchmaker` rolls inside it,
/// which is what makes "p = 0.9 fights an Ultimate" testable without a seed at all.
enum MapOpponentBand {
    /// How many bands a map's progress is cut into. Four, because the quartile boundaries are
    /// 0.25 / 0.50 / 0.75 and a player should feel the map change three times crossing it.
    static let count = 4

    /// Tiers the catalog authors. `maps.json` uses 1...5; anything outside is clamped rather than
    /// trapped, because a tier is data and a mis-authored one should still produce a fight.
    static let tiers = 1...5

    /// The band index 0...3 for a progress ratio, per AC2: `p < 0.25` lowest, `< 0.50` second,
    /// `< 0.75` third, `>= 0.75` highest.
    ///
    /// A finished map is `p >= 1`, which is already `>= 0.75`, so it lands in the highest band and
    /// stays there however far past the total the counter climbs (US-118 does not cap it). A map
    /// with no length has no ratio at all; it reads as the lowest band, the gentler of the two
    /// answers, rather than dividing by zero.
    static func index(recorded: Double, total: Int) -> Int {
        guard total > 0 else { return 0 }
        let ratio = max(0, recorded) / Double(total)
        switch ratio {
        case ..<0.25: return 0
        case ..<0.50: return 1
        case ..<0.75: return 2
        default: return 3
        }
    }

    /// The battle rungs a tier covers.
    ///
    /// Tier 1 is Baby II–Child and each tier steps one rung up the ladder, so tier N covers rungs
    /// N+1 ... N+2: tier 4 is Perfect–Ultimate and tier 5 is Ultimate alone, there being no rung
    /// above it. This is what "clamped to the map's own tier band" means — a pool member outside it
    /// (`13_factory_town` carries one Adult among its Perfects and Ultimates) neither drags the
    /// band down nor is fought at three quarters of the way across a tier 4 map.
    static func rungs(forTier tier: Int) -> ClosedRange<Int> {
        let tier = min(max(tier, tiers.lowerBound), tiers.upperBound)
        let ultimate = BattlePower.battleRung(.ultimate)
        return (tier + 1)...min(tier + 2, ultimate)
    }

    /// The pool members inside the tier's rungs, or the whole pool if none are.
    ///
    /// Falling back to the whole pool rather than to nothing: a mis-tiered map is a data finding
    /// for the US-117 validator, and at runtime the player should still get the fight the author
    /// clearly meant rather than a silent "Nobody to fight."
    static func inTier(_ pool: [EvolutionNode], tier: Int) -> [EvolutionNode] {
        let rungs = rungs(forTier: tier)
        let inside = pool.filter { rungs.contains(BattlePower.battleRung($0.stage)) }
        return inside.isEmpty ? pool : inside
    }

    /// The rung band `index` names, spread over the rungs the pool actually spans.
    ///
    /// Interpolated between the pool's lowest and highest rung, so index 0 IS the pool's lowest band
    /// and index 3 IS its highest whatever the pool holds — a two-stage pool (which every shipped
    /// map has) splits at halfway, and a four-stage one gives a band per stage. Nil only for an
    /// empty pool.
    static func rung(at index: Int, in pool: [EvolutionNode]) -> Int? {
        let rungs = pool.map { BattlePower.battleRung($0.stage) }
        guard let lowest = rungs.min(), let highest = rungs.max() else { return nil }
        let index = min(max(index, 0), count - 1)
        let offset = (Double(index) / Double(count - 1) * Double(highest - lowest)).rounded()
        return lowest + Int(offset)
    }

    /// The pool members at `rung`, or — when the pool has nobody there — the members at the nearest
    /// rung it does populate (AC4).
    ///
    /// Ties break DOWNWARD, which is also what keeps AC3's "never above it": if the highest band
    /// is empty and the pool has a member equally far above and below the tier's top, the fight is
    /// the one the map's tier promised rather than the one above it.
    static func members(of pool: [EvolutionNode], nearestTo rung: Int) -> [EvolutionNode] {
        let exact = pool.filter { BattlePower.battleRung($0.stage) == rung }
        guard exact.isEmpty else { return exact }

        let populated = Set(pool.map { BattlePower.battleRung($0.stage) })
        guard let nearest = populated.sorted().min(by: {
            (abs($0 - rung), $0) < (abs($1 - rung), $1)
        }) else { return [] }
        return pool.filter { BattlePower.battleRung($0.stage) == nearest }
    }

    /// The line a roster-only opponent carries: none.
    ///
    /// `EvolutionNode.line` is a grouping key for the Dex's trees, and a Digimon that is only in the
    /// roster is in no tree — so this is honestly empty rather than a made-up line. Both catalogs
    /// that read a line (`MoveCatalog`, `ElementCatalog`) miss on it and fall through to their stage
    /// and keyword tiers, which is exactly the answer "no line known" should produce.
    static let unauthoredLine = ""

    /// A map's opponent pool as nodes: the graph's node where there is one, otherwise the roster
    /// entry promoted to one.
    ///
    /// **The pool is authored and validated against the ROSTER** (US-116, US-117), and it has to be
    /// resolved against the roster too. `evolutions.json` authors 88 nodes of the 868 playable
    /// Digimon, so resolving a pool through the graph alone drops nearly every opponent a map names
    /// and quietly hands the fight back to the roster-wide pick — which is US-122 doing nothing at
    /// all. An opponent needs a name, a stage and a sheet; it does not need outgoing edges.
    ///
    /// The graph's node still wins where both exist, because it carries the `line` that gives the
    /// opponent its authored move and element rather than the keyword fallback.
    static func nodes(
        for ids: [String],
        graph: EvolutionGraph,
        roster: Roster
    ) -> [EvolutionNode] {
        ids.compactMap { id in
            if let node = graph.node(id: id) { return node }
            guard let entry = roster.entry(id: id) else { return nil }
            return EvolutionNode(id: entry.id, displayName: entry.displayName, stage: entry.stage,
                                 line: unauthoredLine, spriteFile: entry.spriteFile,
                                 variant: entry.variant, dexOnly: entry.dexOnly)
        }
    }

    /// Everyone the player can be matched against in this map at this much progress.
    ///
    /// Empty only if the map's pool names nobody the roster knows — a data fault the US-117
    /// validator catches, and one `BattleMatchmaker` answers by falling back to the roster-wide
    /// pick rather than by refusing the battle.
    static func candidates(
        in map: AdventureMap,
        graph: EvolutionGraph,
        roster: Roster,
        excluding playerId: String,
        recorded: Double
    ) -> [EvolutionNode] {
        // `dexOnly` is excluded here as well as by the validator: a dexOnly Digimon has no animated
        // sheet, so a battle against one would animate two placeholders attacking each other.
        let pool = nodes(for: map.opponentPool, graph: graph, roster: roster)
            .filter { !$0.dexOnly && $0.id != playerId }
        guard !pool.isEmpty else { return [] }

        let banded = inTier(pool, tier: map.tier)
        guard let rung = rung(at: index(recorded: recorded, total: map.totalSteps), in: banded) else {
            return banded
        }
        return members(of: banded, nearestTo: rung)
    }
}

extension MapOpponentBand {
    /// Every playable resident of a map the player can actually MEET (US-203): the opponent pool
    /// resolved to nodes, minus the `dexOnly` (no animated sheet, so a wild encounter never surfaces
    /// one) and the player's own Digimon (you do not walk into yourself), de-duplicated in pool order.
    ///
    /// This is the set the boss gate asks "have you met all of?", and it is deliberately the same
    /// universe `candidates` draws a wild foe from — so every resident this returns is one a 500-step
    /// meeting or a wild battle can turn from a "?" into met. A resident that could never be met would
    /// gate the boss shut forever, which is why the two filters match.
    static func residents(
        of map: AdventureMap,
        graph: EvolutionGraph,
        roster: Roster,
        excluding playerId: String
    ) -> [EvolutionNode] {
        var seen: Set<String> = []
        return nodes(for: map.opponentPool, graph: graph, roster: roster)
            .filter { !$0.dexOnly && $0.id != playerId && seen.insert($0.id).inserted }
    }

    /// The map's BOSS (US-203): the highest-stage resident, ties broken by pool order — the first the
    /// author placed at that top rung, so the boss is a fixed Digimon and not a roll.
    ///
    /// Highest STAGE is measured with `BattlePower.battleRung`, the same ladder banding uses, so an
    /// Armor-Hybrid boss is ranked by the rung it fights at rather than dropping out. Nil only for a
    /// map with no meetable resident at all — a fully `dexOnly` or self-only pool, which the US-117
    /// validator already rules out of the shipped catalog.
    static func boss(
        of map: AdventureMap,
        graph: EvolutionGraph,
        roster: Roster,
        excluding playerId: String
    ) -> EvolutionNode? {
        let residents = residents(of: map, graph: graph, roster: roster, excluding: playerId)
        guard let topRung = residents.map({ BattlePower.battleRung($0.stage) }).max() else {
            return nil
        }
        return residents.first { BattlePower.battleRung($0.stage) == topRung }
    }
}

extension BattleMatchmaker {
    /// Picks an opponent from the SELECTED map's pool, banded by how far across it the player is
    /// (US-122), or from the whole roster when they have chosen nowhere to go.
    ///
    /// The nil-map path is `choose(in:playerId:using:)` verbatim — the same call, on the same
    /// generator, drawing in the same order — so a save with no map selected fights exactly what it
    /// fought before this story, which is AC6.
    ///
    /// A map whose pool resolves to nobody falls back the same way. That is a broken `maps.json`
    /// rather than a state the player can reach, and the roster-wide pick is a better answer to it
    /// than "Nobody to fight."
    static func choose<G: RandomNumberGenerator>(
        in graph: EvolutionGraph,
        roster: Roster,
        playerId: String,
        map: AdventureMap?,
        recorded: Double,
        using generator: inout G
    ) -> BattleOpponent? {
        guard let map else {
            return choose(in: graph, playerId: playerId, using: &generator)
        }
        let candidates = MapOpponentBand.candidates(in: map, graph: graph, roster: roster,
                                                    excluding: playerId, recorded: recorded)
        guard let node = candidates.randomElement(using: &generator) else {
            return choose(in: graph, playerId: playerId, using: &generator)
        }
        return rolled(node, using: &generator)
    }
}
