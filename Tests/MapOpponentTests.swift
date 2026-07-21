import Foundation
import XCTest

@testable import DigiVPet

/// US-122 — opponents come from the selected map and scale with progress in it.
///
/// Two layers, mirroring the code:
/// - `MapOpponentBandTests` — the pure band arithmetic, with no generator involved at all, which is
///   what makes "three quarters of the way across fights the top band" a fact rather than a seed.
/// - `MapMatchmakerTests` — `BattleMatchmaker.choose(in:roster:playerId:map:recorded:using:)` over both a
///   hand-built pool and the SHIPPED maps, plus AC6's no-map-selected path.
///
/// The fixtures build their own pools rather than leaning on `maps.json`, because the claims being
/// made are about the RULE — a retune of a map's pool must not be able to turn a band test green.
/// The shipped catalog is then swept separately, which is the only way to find a map whose authored
/// pool cannot answer the rule.

// MARK: - Fixtures

/// One node per rung, so a pool is written as the rungs it holds.
private func node(rung: Int, suffix: String = "") -> EvolutionNode {
    let stage: Stage
    switch rung {
    case 0: stage = .digitama
    case 1: stage = .babyI
    case 2: stage = .babyII
    case 3: stage = .child
    case 4: stage = .adult
    case 5: stage = .perfect
    default: stage = .ultimate
    }
    return EvolutionNode(id: "r\(rung)\(suffix)", displayName: "R\(rung)\(suffix)",
                         stage: stage, spriteFile: "r\(rung)\(suffix)")
}

private func pool(_ rungs: [Int]) -> [EvolutionNode] {
    rungs.map { node(rung: $0) }
}

private func rungs(of nodes: [EvolutionNode]) -> Set<Int> {
    Set(nodes.map { BattlePower.battleRung($0.stage) })
}

/// A roster holding every fixture node, so the pool resolves. Battles resolve a map's pool through
/// the ROSTER rather than the graph — see `MapOpponentBand.nodes`.
private func roster(_ nodes: [EvolutionNode]) -> Roster {
    Roster(entries: nodes.map {
        RosterEntry(id: $0.id, displayName: $0.displayName, stage: $0.stage,
                    spriteFile: $0.spriteFile, variant: $0.variant, dexOnly: $0.dexOnly)
    })
}

// MARK: - AC2/AC3/AC4: the band arithmetic

final class MapOpponentBandTests: XCTestCase {
    // MARK: The quartile

    /// AC2's boundaries, spelled out rather than derived: `< 0.25`, `< 0.50`, `< 0.75`, `>=`.
    /// Each boundary is pinned from BOTH sides, so an accidental `<=` is a failure.
    func testTheProgressRatioPicksTheBandByQuartile() {
        XCTAssertEqual(MapOpponentBand.index(recorded: 0, total: 1000), 0)
        XCTAssertEqual(MapOpponentBand.index(recorded: 249, total: 1000), 0)
        XCTAssertEqual(MapOpponentBand.index(recorded: 250, total: 1000), 1)
        XCTAssertEqual(MapOpponentBand.index(recorded: 499, total: 1000), 1)
        XCTAssertEqual(MapOpponentBand.index(recorded: 500, total: 1000), 2)
        XCTAssertEqual(MapOpponentBand.index(recorded: 749, total: 1000), 2)
        XCTAssertEqual(MapOpponentBand.index(recorded: 750, total: 1000), 3)
        XCTAssertEqual(MapOpponentBand.index(recorded: 999, total: 1000), 3)
    }

    /// AC3: a finished map is in the highest band and STAYS there. US-118 does not cap the counter,
    /// so this has to hold at ten times the total as well as at exactly it.
    func testAFinishedMapStaysInTheHighestBand() {
        XCTAssertEqual(MapOpponentBand.index(recorded: 1000, total: 1000), MapOpponentBand.count - 1)
        XCTAssertEqual(MapOpponentBand.index(recorded: 10_000, total: 1000), MapOpponentBand.count - 1)
    }

    /// A map with no length has no ratio; it reads as the lowest band rather than dividing by zero.
    /// Negative steps cannot happen — `PlayerProfile.record` refuses them — but the arithmetic must
    /// not depend on that.
    func testAMapWithNoLengthOrNegativeStepsIsTheLowestBand() {
        XCTAssertEqual(MapOpponentBand.index(recorded: 500, total: 0), 0)
        XCTAssertEqual(MapOpponentBand.index(recorded: 500, total: -1), 0)
        XCTAssertEqual(MapOpponentBand.index(recorded: -500, total: 1000), 0)
    }

    // MARK: The tier clamp

    /// The tier table AC2 clamps to: tier 1 Baby II–Child, up to tier 5 Ultimate alone.
    func testEachTierCoversItsOwnRungs() {
        XCTAssertEqual(MapOpponentBand.rungs(forTier: 1), 2...3)
        XCTAssertEqual(MapOpponentBand.rungs(forTier: 2), 3...4)
        XCTAssertEqual(MapOpponentBand.rungs(forTier: 3), 4...5)
        XCTAssertEqual(MapOpponentBand.rungs(forTier: 4), 5...6)
        XCTAssertEqual(MapOpponentBand.rungs(forTier: 5), 6...6)
    }

    /// A tier outside the authored 1...5 clamps rather than trapping — a tier is data.
    func testAnOutOfRangeTierClamps() {
        XCTAssertEqual(MapOpponentBand.rungs(forTier: 0), MapOpponentBand.rungs(forTier: 1))
        XCTAssertEqual(MapOpponentBand.rungs(forTier: 99), MapOpponentBand.rungs(forTier: 5))
    }

    /// A member outside the tier's rungs is dropped, so it neither drags the band down nor is
    /// fought at the top of the map. This is `13_factory_town`'s stray Adult exactly.
    func testTheTierDropsAPoolMemberOutsideItsRungs() {
        let inside = MapOpponentBand.inTier(pool([4, 5, 6]), tier: 4)

        XCTAssertEqual(rungs(of: inside), [5, 6])
    }

    /// If NOBODY is inside the tier the whole pool stands: a mis-tiered map is a validator finding,
    /// and at runtime the player still gets the fight the author meant.
    func testAPoolEntirelyOutsideItsTierIsKept() {
        let inside = MapOpponentBand.inTier(pool([2, 3]), tier: 5)

        XCTAssertEqual(rungs(of: inside), [2, 3])
    }

    // MARK: The band, one test per band

    /// AC2/AC7, all four bands over a pool with a rung per band: index 0 is the pool's lowest and
    /// index 3 its highest, with the two middle bands landing one rung apart between them.
    func testEachBandNamesItsOwnRungInAFourRungPool() {
        let four = pool([3, 4, 5, 6])

        XCTAssertEqual(MapOpponentBand.rung(at: 0, in: four), 3)
        XCTAssertEqual(MapOpponentBand.rung(at: 1, in: four), 4)
        XCTAssertEqual(MapOpponentBand.rung(at: 2, in: four), 5)
        XCTAssertEqual(MapOpponentBand.rung(at: 3, in: four), 6)
    }

    /// The shipped shape: two rungs. The four bands split at halfway rather than collapsing onto
    /// one of them — the first half of the map is the lower stage, the second half the higher.
    func testATwoRungPoolSplitsAtHalfway() {
        let two = pool([5, 6])

        XCTAssertEqual(MapOpponentBand.rung(at: 0, in: two), 5)
        XCTAssertEqual(MapOpponentBand.rung(at: 1, in: two), 5)
        XCTAssertEqual(MapOpponentBand.rung(at: 2, in: two), 6)
        XCTAssertEqual(MapOpponentBand.rung(at: 3, in: two), 6)
    }

    /// A one-rung pool (every tier 5 map) has one band, at every index.
    func testAOneRungPoolIsOneBand() {
        for index in 0..<MapOpponentBand.count {
            XCTAssertEqual(MapOpponentBand.rung(at: index, in: pool([6, 6, 6])), 6)
        }
    }

    func testAnEmptyPoolHasNoBand() {
        XCTAssertNil(MapOpponentBand.rung(at: 0, in: []))
    }

    // MARK: AC4: the nearest populated band

    /// AC4: the computed band is empty, so the NEAREST populated one answers instead of nil. The
    /// pool spans rungs 2 and 5, so band 1 computes rung 3, which nobody is at.
    func testAnEmptyBandFallsBackToTheNearestPopulatedOne() {
        let gapped = pool([2, 5])
        let band = MapOpponentBand.rung(at: 1, in: gapped)

        XCTAssertEqual(band, 3, "the interpolated band is a rung the pool has nobody at")
        XCTAssertEqual(rungs(of: MapOpponentBand.members(of: gapped, nearestTo: band!)), [2],
                       "and rung 2 is one away where rung 5 is two")
    }

    /// The fallback looks UPWARD as readily as downward — nearest is nearest.
    func testTheNearestBandMayBeAboveTheEmptyOne() {
        XCTAssertEqual(rungs(of: MapOpponentBand.members(of: pool([2, 6]), nearestTo: 5)), [6])
    }

    /// A tie breaks downward, which is what keeps AC3's "never above it" true when the top band
    /// itself is empty.
    func testAnEquallyDistantBandBreaksDownward() {
        XCTAssertEqual(rungs(of: MapOpponentBand.members(of: pool([3, 5]), nearestTo: 4)), [3])
    }

    /// A populated band is answered exactly, and with EVERY member of it — the generator picks
    /// among them, so a band that quietly returned one node would make the roll a formality.
    func testAPopulatedBandReturnsAllOfItsMembers() {
        let crowded = [node(rung: 5, suffix: "a"), node(rung: 5, suffix: "b"), node(rung: 6)]

        XCTAssertEqual(Set(MapOpponentBand.members(of: crowded, nearestTo: 5).map(\.id)),
                       ["r5a", "r5b"])
    }
}

// MARK: - AC1/AC5/AC6: the matchmaker

final class MapMatchmakerTests: XCTestCase {
    private let graph = EvolutionGraph(nodes:
        pool([2, 3, 4, 5, 6]) + [node(rung: 4, suffix: "dex"), node(rung: 3, suffix: "player")])

    /// A four-tier-wide pool so a tier 2 map's band and its tier clamp can be seen separately.
    private func map(
        tier: Int = 2,
        total: Int = 1000,
        pool ids: [String] = ["r3", "r4"]
    ) -> AdventureMap {
        AdventureMap(id: "m", displayName: "M", assetName: "01_grassland",
                     tier: tier, totalSteps: total, opponentPool: ids)
    }

    private func opponent(
        in map: AdventureMap?,
        recorded: Double,
        seed: UInt64,
        playerId: String = "r3player"
    ) -> BattleOpponent? {
        var generator = SeededGenerator(seed: seed)
        return BattleMatchmaker.choose(in: graph, roster: roster(graph.nodes), playerId: playerId,
                                       map: map, recorded: recorded, using: &generator)
    }

    /// Every opponent drawn at this much progress, over enough seeds that a band with two members
    /// shows both. Twenty-five is the sweep the existing matchmaker tests use.
    private func drawnIds(in map: AdventureMap?, recorded: Double) -> Set<String> {
        Set((UInt64(0)..<25).compactMap { opponent(in: map, recorded: recorded, seed: $0)?.node.id })
    }

    // MARK: AC1

    /// AC1: the pick comes from the MAP's pool, not the roster. The graph holds five rungs and the
    /// map names two of them; nothing else is ever drawn, at any progress and any seed.
    func testTheOpponentComesFromTheMapsPoolAndNotTheRoster() {
        let selected = map()

        for recorded in [0.0, 300, 600, 900, 5000] {
            XCTAssertTrue(drawnIds(in: selected, recorded: recorded).isSubset(of: ["r3", "r4"]),
                          "drew somebody the map does not hold at \(recorded) steps")
        }
    }

    /// A dexOnly node in a pool is never fought — it has no animated sheet, so the battle would
    /// animate a placeholder. The validator rejects one too; this is the runtime half.
    func testADexOnlyPoolMemberIsNeverFought() {
        let dexOnly = EvolutionNode(id: "onlydex", displayName: "OnlyDex", stage: .adult,
                                    spriteFile: "onlydex", dexOnly: true)
        let graph = EvolutionGraph(nodes: pool([3, 4]) + [dexOnly, node(rung: 3, suffix: "player")])
        let selected = map(pool: ["r4", "onlydex"])

        for seed in UInt64(0)..<25 {
            var generator = SeededGenerator(seed: seed)
            let drawn = BattleMatchmaker.choose(in: graph, roster: roster(graph.nodes),
                                                playerId: "r3player", map: selected,
                                                recorded: 900, using: &generator)
            XCTAssertEqual(drawn?.node.id, "r4")
        }
    }

    /// A Digimon never fights itself, even when the map's pool names it.
    func testThePlayerIsNeverDrawnFromItsOwnMapsPool() {
        let selected = map(pool: ["r3", "r4"])

        XCTAssertFalse(drawnIds(in: selected, recorded: 900).contains("r3"),
                       "r3 is the player here")
        _ = opponent(in: selected, recorded: 900, seed: 0, playerId: "r3")
        XCTAssertFalse(drawnIds(in: selected, recorded: 0).contains("r3player"))
    }

    // MARK: AC2/AC3, one per band

    /// AC7's "one per band": the same map at four progress ratios draws the low stage in the first
    /// half and the high stage in the second, and never the other one.
    func testEachBandDrawsItsOwnStage() {
        let selected = map(total: 1000, pool: ["r3", "r4"])

        XCTAssertEqual(drawnIds(in: selected, recorded: 100), ["r3"], "band 0")
        XCTAssertEqual(drawnIds(in: selected, recorded: 300), ["r3"], "band 1")
        XCTAssertEqual(drawnIds(in: selected, recorded: 600), ["r4"], "band 2")
        XCTAssertEqual(drawnIds(in: selected, recorded: 800), ["r4"], "band 3")
    }

    /// The same four bands over a pool with a rung in each, so the middle two are distinguishable
    /// from the outer two rather than sharing them.
    func testAFourRungPoolDrawsAStagePerBand() {
        let selected = map(tier: 2, total: 1000, pool: ["r3", "r4", "r5", "r6"])

        // Tier 2 is rungs 3...4, so the clamp is doing work here as well as the band.
        XCTAssertEqual(drawnIds(in: selected, recorded: 100), ["r3"])
        XCTAssertEqual(drawnIds(in: selected, recorded: 800), ["r4"])

        // Untiered, the four bands are four stages.
        let wide = map(tier: 99, total: 1000, pool: ["r3", "r4", "r5", "r6"])
        XCTAssertEqual(drawnIds(in: wide, recorded: 800), ["r6"])
    }

    /// AC3: a finished map still picks the highest band, and passing the total again does not push
    /// past it — there is nothing above the top band to push into.
    func testAFinishedMapKeepsFightingTheHighestBand() {
        let selected = map(total: 1000, pool: ["r3", "r4"])

        XCTAssertEqual(drawnIds(in: selected, recorded: 1000), ["r4"])
        XCTAssertEqual(drawnIds(in: selected, recorded: 50_000), ["r4"])
    }

    // MARK: AC4

    /// AC4 through the matchmaker: the band the ratio names is empty, and a fight comes back from
    /// the nearest populated band rather than nil.
    func testAnEmptyBandStillYieldsAnOpponent() {
        let gapped = map(tier: 99, total: 1000, pool: ["r2", "r5"])

        // Band 1 computes rung 3; the pool has nobody there, and rung 2 is nearer than rung 5.
        XCTAssertEqual(drawnIds(in: gapped, recorded: 300), ["r2"])
        XCTAssertNotNil(opponent(in: gapped, recorded: 300, seed: 0))
    }

    /// A pool naming nobody the ROSTER knows is a broken `maps.json`, not a state a player reaches.
    /// It falls back to the roster-wide pick rather than refusing the battle.
    func testAPoolTheRosterDoesNotKnowFallsBackToTheRosterWidePick() {
        let broken = map(pool: ["nobody", "alsonobody"])

        XCTAssertNotNil(opponent(in: broken, recorded: 0, seed: 0))
    }

    // MARK: AC5/AC6

    /// AC5: the pick is seeded. The same seed, map and progress give the same opponent every time.
    func testTheSameSeedGivesTheSameOpponent() {
        let selected = map(tier: 99, pool: ["r3", "r4", "r5", "r6"])

        for seed in UInt64(0)..<10 {
            let first = opponent(in: selected, recorded: 400, seed: seed)
            XCTAssertEqual(first?.node.id, opponent(in: selected, recorded: 400, seed: seed)?.node.id)
            XCTAssertEqual(first?.power, opponent(in: selected, recorded: 400, seed: seed)?.power)
        }
    }

    /// AC6: with no map selected the answer is BYTE-FOR-BYTE the roster-wide pick — the same node
    /// and the same rolled power, at every seed. Asserted against the old call rather than against
    /// a remembered list, so the two can never drift apart.
    func testNoMapSelectedIsExactlyTheRosterWidePick() {
        for seed in UInt64(0)..<50 {
            var old = SeededGenerator(seed: seed)
            let before = BattleMatchmaker.choose(in: graph, playerId: "r3player", using: &old)
            let after = opponent(in: nil, recorded: 0, seed: seed)

            XCTAssertEqual(before?.node, after?.node, "seed \(seed)")
            XCTAssertEqual(before?.power, after?.power, "seed \(seed)")
        }
    }

    /// And the generator is left in the same place, so the battle that draws from it AFTER
    /// matchmaking resolves identically too — `MainScreenModel` carries one generator through both.
    func testNoMapSelectedLeavesTheGeneratorWhereItWas() {
        var old = SeededGenerator(seed: 7)
        _ = BattleMatchmaker.choose(in: graph, playerId: "r3player", using: &old)

        var new = SeededGenerator(seed: 7)
        _ = BattleMatchmaker.choose(in: graph, roster: roster(graph.nodes), playerId: "r3player",
                                    map: nil, recorded: 0, using: &new)

        XCTAssertEqual((0..<5).map { _ in old.next() }, (0..<5).map { _ in new.next() })
    }
}

// MARK: - The shipped maps

final class ShippedMapOpponentTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled
    private let catalog = MapCatalog.bundled

    /// Every shipped map answers with a fight at every band, and always from its OWN pool. A map
    /// whose authored pool cannot serve one of the four bands is a data fault this is the only
    /// thing that would find.
    func testEveryShippedMapFightsFromItsOwnPoolAtEveryBand() {
        for map in catalog.maps {
            let ratios = [0.0, 0.3, 0.6, 0.9, 1.0, 2.0]
            for ratio in ratios {
                let recorded = Double(map.totalSteps) * ratio
                for seed in UInt64(0)..<5 {
                    var generator = SeededGenerator(seed: seed)
                    guard let drawn = BattleMatchmaker.choose(
                        in: graph, roster: roster, playerId: "agumon", map: map,
                        recorded: recorded, using: &generator) else {
                        return XCTFail("\(map.id) offered nobody at \(ratio) of the way across")
                    }
                    XCTAssertTrue(map.opponentPool.contains(drawn.node.id),
                                  "\(map.id) drew \(drawn.node.id), which is not in its pool")
                }
            }
        }
    }

    /// The point of the whole story, over the shipped data: the far end of a map is not easier than
    /// the near end. Compared as the pool's rungs rather than as one draw, because a band is a set.
    func testProgressNeverLowersTheBandOnAShippedMap() {
        for map in catalog.maps {
            let bands = [0.0, 0.3, 0.6, 0.9].map { ratio in
                MapOpponentBand.candidates(in: map, graph: graph, roster: roster, excluding: "agumon",
                                           recorded: Double(map.totalSteps) * ratio)
                    .map { BattlePower.battleRung($0.stage) }.min() ?? 0
            }

            XCTAssertEqual(bands, bands.sorted(),
                           "\(map.id) fights something lower further in: \(bands)")
        }
    }

    /// AC3 over the shipped data: at the far end of a map the opponents are inside its tier's
    /// rungs and never above them.
    func testAFinishedShippedMapNeverFightsAboveItsTier() {
        for map in catalog.maps {
            let top = MapOpponentBand.candidates(in: map, graph: graph, roster: roster, excluding: "agumon",
                                                 recorded: Double(map.totalSteps))
            let ceiling = MapOpponentBand.rungs(forTier: map.tier).upperBound

            XCTAssertFalse(top.isEmpty, "\(map.id) has no top band")
            for node in top {
                XCTAssertLessThanOrEqual(BattlePower.battleRung(node.stage), ceiling,
                                         "\(map.id) fights \(node.id) above tier \(map.tier)")
            }
        }
    }

    /// A tier 1 map really does start on the small Digimon and a tier 5 map really does not — the
    /// tier table is only worth anything if the shipped maps land where it says.
    func testTheFirstMapStartsSmallAndTheLastDoesNot() {
        guard let first = catalog.maps.first, let last = catalog.maps.last else {
            return XCTFail("the shipped catalog is empty")
        }

        let start = MapOpponentBand.candidates(in: first, graph: graph, roster: roster,
                                               excluding: "agumon", recorded: 0)
        let end = MapOpponentBand.candidates(in: last, graph: graph, roster: roster,
                                             excluding: "agumon", recorded: 0)

        XCTAssertEqual(Set(start.map { $0.stage }), [.babyII])
        XCTAssertEqual(Set(end.map { $0.stage }), [.ultimate])
    }
}
