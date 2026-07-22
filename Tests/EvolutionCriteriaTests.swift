import XCTest
@testable import DigiVPet

/// US-061: the shipped `evolutions.json` really branches, and neglect really costs something.
///
/// Every test here reads the REAL file. A fixture graph could satisfy all of it while the shipped
/// roster still marched every Digimon down a single line, which is the exact thing this story
/// exists to end.
final class EvolutionCriteriaTests: XCTestCase {
    private let graph = EvolutionGraph.bundled

    /// The junk destinations, named explicitly rather than inferred. A rule like "the default edge
    /// points at a node nothing else points at" would pass for a perfectly good Digimon that
    /// happens to be reached one way, and the whole claim here is about WHICH Digimon.
    ///
    /// `vegimon` and the line-scoped `dmcv2_vademon` joined the list in US-134: the device trees
    /// name their own junk Champion, and it is the one both of a version's Rookies fall to —
    /// Numemon in Ver.1, Vegimon in Ver.2, Scumon in Ver.3. Vegimon replaced Geremon as the Ver.2
    /// fallback for exactly that reason; Geremon is still reachable, as Elecmon's overfeeding
    /// branch.
    /// `platinumscumon` and `pumpmon` joined in US-138, and they are the first two that no source
    /// document names: the Pendulum Color V1 Nature Spirits section draws no junk branch at all,
    /// while every Child and Adult here needs one. US-138 chose them off the unused sheets — see
    /// their `comment`s in `evolutions.json`.
    /// `diginorimon` and `piranimon` joined in US-139 for the same reason as US-138's pair: the
    /// Pendulum Color V2 Deep Savers section draws no junk branch either, so this app chose a
    /// water-flavoured one off unused sheets — digital seaweed under a shoal of piranha.
    /// `gokimon` and `darumamon` joined in US-140, third time the same way: the Pendulum Color V3
    /// Nightmare Soldiers section draws no junk branch either. WaruMonzaemon was the first choice
    /// for the Perfect rung and had to be dropped — the Version 5 Metal Empire section draws it as
    /// an earned Ultimate, so it belongs to US-142. Grep the document before choosing a junk node.
    private static let junkIds: Set<String> = [
        // Adult
        "numemon", "scumon", "geremon", "karatsukinumemon", "goldnumemon", "raremon", "vegimon",
        "platinumscumon", "diginorimon", "gokimon", "zassoumon", "pencme_raremon",
        // Perfect
        "blackkingnumemon", "gerbemon", "jyagamon", "greatkingscumon", "vademon", "dmcv2_vademon",
        "etemon", "pumpmon", "piranimon", "darumamon", "tonosamagekomon", "locomon",
        // Ultimate
        "kingetemon",
    ]

    private var branchingNodes: [EvolutionNode] {
        graph.nodes.filter { ($0.stage == .child || $0.stage == .adult) && !$0.evolutions.isEmpty }
    }

    // MARK: - AC1/AC2: a real choice, with a junk floor under it

    /// Two is the half that matters: a single outgoing edge is not a choice at all.
    ///
    /// The ceiling was three until US-133 — two earned branches plus the junk fallback — and four
    /// until US-134. It is now five, and the reason is data rather than taste: the Version 2 tree
    /// gives Gabumon five Champions (Kabuterimon, Garurumon, Angemon, Yukidarumon, Vegimon) and
    /// every one of them has a playable sheet, so nothing prunes it the way an undrawable Tyranomon
    /// pruned Agumon's fifth in US-133. Splitting them across the two Rookies is not open either:
    /// the document draws all five arrows out of Gabumon.
    ///
    /// US-133's note that "four is what the whole source document fits in" was simply wrong — V4's
    /// Palmon and V5's Gizamon are SIX wide in the document, and both US-134 and US-135 expected
    /// US-136 and US-137 to raise this again. NEITHER DID, and the reason is the same both times:
    /// each of those rows contains names with no animated sheet — Kokatorimon and Nanimon in
    /// Palmon's, Flymon in Gizamon's — so the DRAWABLE row is four earned branches plus the junk
    /// fallback. Price a ceiling raise off the drawable row, never off the document's. Five is also
    /// where this stops on its own: `SeedRosterTests`' distinct-energy rule allows four earned
    /// branches and there are only four energy types.
    ///
    /// It is raised one step at a time on purpose: the ceiling should never be looser than the file
    /// it guards. The Dex agrees at five — `DexRow.evolutionCandidates` draws a three-column grid,
    /// so five candidates are still two rows inside a sheet that scrolls.
    func testEveryNonTerminalChildAndAdultHasTwoToFiveOutgoingEdges() {
        XCTAssertFalse(branchingNodes.isEmpty)
        for node in branchingNodes {
            XCTAssertTrue((2...5).contains(node.evolutions.count),
                          "\(node.id) has \(node.evolutions.count) outgoing edges, not two to five")
        }
    }

    func testEveryNonTerminalChildAndAdultFallsToAJunkEvolution() throws {
        for node in branchingNodes {
            let fallback = try XCTUnwrap(EvolutionEngine.defaultEdge(of: node),
                                         "\(node.id) has no isDefault edge")
            XCTAssertTrue(Self.junkIds.contains(fallback.to),
                          "\(node.id) falls back to '\(fallback.to)', which is not a junk evolution")
        }
    }

    /// The junk edge has to be reachable by doing NOTHING — no energy threshold, no care-mistake
    /// ceiling that neglect would breach, and no criterion to satisfy. US-020's fallback ignores an
    /// edge's gates anyway, so a gated junk edge would be data that lies about how it is taken.
    func testEveryJunkFallbackIsReachableByInaction() throws {
        for node in branchingNodes {
            let fallback = try XCTUnwrap(EvolutionEngine.defaultEdge(of: node))
            XCTAssertEqual(fallback.minEnergy, 0, "\(node.id)'s junk edge demands energy")
            XCTAssertEqual(fallback.conditions, [], "\(node.id)'s junk edge carries criteria")
            XCTAssertNil(fallback.minBattleWins, "\(node.id)'s junk edge demands battle wins")
            XCTAssertGreaterThanOrEqual(fallback.maxCareMistakes, 99,
                                        "\(node.id)'s junk edge closes on care mistakes")
        }
    }

    /// The point of the story, stated as behaviour rather than as data: a Digimon whose owner did
    /// nothing at all still evolves once the time gate opens, and what it evolves into is junk.
    func testAnAgumonThatDidNothingBecomesNumemon() throws {
        let agumon = try XCTUnwrap(graph.node(id: "agumon"))
        let enteredAt = Date(timeIntervalSince1970: 0)
        let wellPastTheGate = enteredAt.addingTimeInterval(60 * 24 * 60 * 60)

        let target = EvolutionEngine.scheduledEvolutionTarget(
            for: agumon,
            stageEnergy: .zero,
            dominant: nil,
            careMistakes: 0,
            battleWins: 0,
            stageEnteredAt: enteredAt,
            now: wellPastTheGate,
            conditions: .unknown)

        XCTAssertEqual(target, "numemon")
    }

    // MARK: - AC3: the junk sprites exist

    /// Numemon and Scumon by name, because AC3 names them. Every other node's art is covered by
    /// `EvolutionGraphValidatorTests.testShippedEvolutionsJsonIsValid`, which resolves the whole
    /// roster against the real bundle.
    func testNumemonAndScumonAreRealNodesWithRealArt() throws {
        for id in ["numemon", "scumon"] {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(node.stage, .adult)
            XCTAssertFalse(node.dexOnly)
            XCTAssertNotNil(SpriteLoader.url(stage: node.stage.rawValue, name: node.spriteFile),
                            "\(id): no art at \(node.stage.rawValue)/\(node.spriteFile).png")
        }
    }

    // MARK: - AC4: the Digital Monster Color band

    /// Greymon is the band node: training in the middle earns it, and BOTH ends fall to junk.
    /// Asserted through the engine rather than by reading the JSON back, because a band is only a
    /// band if `qualifies` treats the two conditions as a closed interval.
    func testGreymonIsEarnedByABandOfTrainingAndLostAtBothEnds() throws {
        let greymon = try XCTUnwrap(graph.node(id: "greymon"))
        let bandEdge = try XCTUnwrap(greymon.evolutions.first { $0.to == "metalgreymon" })
        let sessions = bandEdge.conditions.filter { $0.metric == "care.trainingSessions" }

        XCTAssertEqual(Set(sessions.map(\.comparison)), [.atLeast, .atMost],
                       "a band is an atLeast and an atMost on one metric")

        func qualifies(trainingSessions: Int) -> Bool {
            EvolutionEngine.qualifies(
                bandEdge,
                stageEnergy: EnergyTotals(strength: 999),
                dominant: .strength,
                careMistakes: 0,
                battleWins: 0,
                conditions: ConditionContext(
                    stageTotals: MetricTotals(values: ["health.exerciseMinutes": 100_000]),
                    trainingSessionsThisStage: trainingSessions))
        }

        XCTAssertTrue(qualifies(trainingSessions: 20), "the middle of the band earns Greymon's line")
        XCTAssertFalse(qualifies(trainingSessions: 0), "never training must fall to junk")
        XCTAssertFalse(qualifies(trainingSessions: 400),
                       "overtraining must be punished exactly as hard as undertraining")
    }

    // MARK: - AC5: a Perfect gated on battle performance as a RATIO

    /// Fifteen battles at eighty percent, following the real device. The ratio is what a win COUNT
    /// cannot say: fifteen wins out of two hundred battles must NOT open this branch.
    func testAPerfectEdgeIsGatedOnTheBattleWinRatioAndNotOnWinsAlone() throws {
        let etemon = try XCTUnwrap(graph.node(id: "etemon"))
        XCTAssertEqual(etemon.stage, .perfect)

        let edge = try XCTUnwrap(etemon.evolutions.first { $0.to == "bancholeomon" })
        XCTAssertFalse(edge.isDefault,
                       "a criterion on the isDefault edge never runs — US-020's fallback ignores gates")
        XCTAssertTrue(edge.conditions.contains { $0.metric == "care.battleWinRatio" })
        XCTAssertTrue(edge.conditions.contains { $0.metric == "care.battleCount" })

        func qualifies(battles: Int, winRatio: Double) -> Bool {
            EvolutionEngine.qualifies(
                edge,
                stageEnergy: EnergyTotals(vitality: 999),
                dominant: .vitality,
                careMistakes: 0,
                battleWins: 999,
                conditions: ConditionContext(battlesLifetime: battles,
                                             battleWinRatioLifetime: winRatio))
        }

        XCTAssertTrue(qualifies(battles: 20, winRatio: 0.9))
        XCTAssertFalse(qualifies(battles: 200, winRatio: 0.075),
                       "fifteen wins in two hundred battles is not an eighty percent record")
        XCTAssertFalse(qualifies(battles: 3, winRatio: 1.0), "a perfect record over nothing is nothing")
    }

    // MARK: - AC6: eight distinct metrics, from both families

    func testAtLeastEightDistinctMetricsAreAuthoredAcrossBothFamilies() {
        let metrics = Set(graph.nodes.flatMap(\.evolutions).flatMap(\.conditions).map(\.metric))

        XCTAssertGreaterThanOrEqual(metrics.count, 8, "authored metrics: \(metrics.sorted())")
        XCTAssertFalse(metrics.filter { $0.hasPrefix("health.") }.isEmpty)
        XCTAssertFalse(metrics.filter { $0.hasPrefix("care.") }.isEmpty)
    }

    // MARK: - AC9: the validator passes on the whole file

    func testTheAuthoredGraphPassesTheValidator() throws {
        let errors = try EvolutionGraph.load().validate()
        XCTAssertEqual(errors, [],
                       errors.map { "  - \($0.description)" }.joined(separator: "\n"))
    }

    // MARK: - AC10: no hint states a number

    /// A threshold printed into a hint goes stale the instant the edge is retuned, and the stale
    /// copy is worse than no copy — it tells the player a number the game no longer uses. US-065
    /// and US-066 own how a criterion's progress is actually shown.
    func testNoConditionHintContainsADigit() {
        for node in graph.nodes {
            for edge in node.evolutions {
                for condition in edge.conditions {
                    XCTAssertFalse(
                        condition.hint.contains(where: \.isNumber),
                        "\(node.id) -> \(edge.to): hint '\(condition.hint)' states a number")
                }
            }
        }
    }

    // MARK: - AC11: only metrics US-055 probed as usable

    /// Every authored `health.*` metric resolves to a HealthKit type the app can actually ask for.
    /// A metric with no `readObjectType` would never be granted, and HealthKit answers an
    /// unauthorized read with no samples — indistinguishable from a user who did not do the thing —
    /// so the edge would silently never fire.
    func testEveryAuthoredHealthMetricIsOneTheAppCanAskToRead() {
        let authored = graph.conditionHealthMetrics
        XCTAssertFalse(authored.isEmpty)

        for metric in authored {
            XCTAssertNotNil(metric.readObjectType, "\(metric.rawValue) has no HealthKit type to grant")
            XCTAssertTrue(HealthReadSet.bundled.objectTypes.contains(metric.readObjectType!),
                          "\(metric.rawValue) is authored but not in the read set")
        }
    }

    /// Every authored `health.*` metric accumulates, so a `window: .stage` total of it means
    /// something. A standing measurement like a resting heart rate is answerable only from a live
    /// reading, and nothing passes one today — an edge gated on one would be dead on arrival.
    func testEveryAuthoredHealthMetricAccumulatesOverTime() {
        for metric in graph.conditionHealthMetrics {
            XCTAssertTrue(metric.accumulatesOverTime,
                          "\(metric.rawValue) is a standing measurement and cannot be totalled")
        }
    }

    // MARK: - Every branch is reachable

    /// No authored Digimon is stranded. An orphan is invisible in play and shows up in the Dex tree
    /// as a node floating beside the ladder, which reads as a rendering bug rather than as content.
    func testEveryNonEggNodeIsReachableFromSomeDigitama() {
        var reached = Set(graph.nodes(at: .digitama).map(\.id))
        var frontier = Array(reached)

        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        let stranded = graph.nodes.map(\.id).filter { !reached.contains($0) }
        XCTAssertEqual(stranded, [], "unreachable nodes: \(stranded)")
    }
}
