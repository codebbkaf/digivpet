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
    private static let junkIds: Set<String> = [
        // Adult
        "numemon", "scumon", "geremon", "karatsukinumemon", "goldnumemon", "raremon",
        // Perfect
        "blackkingnumemon", "gerbemon", "jyagamon", "greatkingscumon", "vademon", "etemon",
        // Ultimate
        "kingetemon",
    ]

    private var branchingNodes: [EvolutionNode] {
        graph.nodes.filter { ($0.stage == .child || $0.stage == .adult) && !$0.evolutions.isEmpty }
    }

    // MARK: - AC1/AC2: a real choice, with a junk floor under it

    func testEveryNonTerminalChildAndAdultHasTwoOrThreeOutgoingEdges() {
        XCTAssertFalse(branchingNodes.isEmpty)
        for node in branchingNodes {
            XCTAssertTrue((2...3).contains(node.evolutions.count),
                          "\(node.id) has \(node.evolutions.count) outgoing edges, not two or three")
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
