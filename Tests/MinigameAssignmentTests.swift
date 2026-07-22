import XCTest
@testable import DigiVPet

/// US-082 — which training minigame each Digimon gets.
final class MinigameAssignmentTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// Every `line` key the shipped graph actually uses.
    private var shippedLines: Set<String> { Set(graph.nodes.map(\.line)) }

    // MARK: - The lines, of which there are now more than there are games

    /// Every shipped line resolves to a game and all six games are reached.
    ///
    /// This asserted a BIJECTION until US-138 — six lines, six games, none shared — which held only
    /// because the roster happened to have exactly six lines. US-138's `penc-nsp` is the seventh,
    /// and Phase E adds five more Pendulum trees after it, so from here on lines share games and the
    /// claim worth making is the one that still means something: no line falls through to the stage
    /// floor (which would change a Digimon's game as it evolved), and no game is stranded with
    /// nobody who plays it.
    func testEveryShippedLineGetsAGameAndAllSixGamesAreReached() {
        let assigned = shippedLines.map { MinigameAssignment.game(line: $0, stage: nil) }
        XCTAssertGreaterThan(assigned.count, 6, "the shipped roster has outgrown one line per game")
        XCTAssertEqual(Set(assigned), Set(MinigameKind.allCases),
                       "a game no shipped line plays: \(Set(MinigameKind.allCases).subtracting(assigned))")
    }

    /// Exactly which lines share a game, spelled out so that a line landing on a shared game by
    /// accident reads as a slip rather than as the pattern. Three pairs since US-140: the two
    /// nature-flavoured trees on the timing bar, Deep Savers beside Ver.3 on the sprint, and
    /// Nightmare Soldiers beside Ver.5 on sequence recall. Written as the whole game -> [lines]
    /// dictionary rather than as a list of pairs, so the next Pendulum tree costs one literal.
    func testTheSharedGamesAreExactlyTheAuthoredPairs() {
        let sharers = Dictionary(grouping: MinigameAssignment.byLine.keys,
                                 by: { MinigameAssignment.byLine[$0]! })
            .filter { $0.value.count > 1 }
            .mapValues { $0.sorted() }

        XCTAssertEqual(sharers, [.timingBar: ["palmon", "penc-nsp"],
                                 .crownSprint: ["dmc-v3", "penc-ds"],
                                 .sequenceRecall: ["dmc-v5", "penc-nso"]])
    }

    /// The table is keyed on strings the JSON owns, so a renamed line would silently drop that whole
    /// line to the stage floor and still build. This is the test that catches it.
    func testTheTableNamesExactlyTheShippedLines() {
        XCTAssertEqual(Set(MinigameAssignment.byLine.keys), shippedLines)
    }

    /// The game must not change under the player as their Digimon evolves — one line, one game, all
    /// the way from Digitama to Ultimate.
    func testEveryDigimonInALineGetsThatLinesGameAtEveryStage() {
        for node in graph.nodes {
            let expected = MinigameAssignment.byLine[node.line]
            XCTAssertNotNil(expected, "\(node.line) is unassigned")
            XCTAssertEqual(MinigameAssignment.game(for: node.id, in: graph, roster: roster), expected,
                           "\(node.id) (\(node.stage.rawValue)) left its line's game")
        }
    }

    func testTheLineTierWinsOverTheStageFloor() {
        // The Ver.1 line is Button Masher; a Child would fall back to Power Meter without the line.
        XCTAssertEqual(MinigameAssignment.fallback(for: .child), .powerMeter)
        XCTAssertEqual(MinigameAssignment.game(line: "dmc-v1", stage: .child), .buttonMasher)
    }

    // MARK: - Fallback

    func testEveryStageFallsBackToAGame() {
        // Non-optional return, so the assertion is that all six games are REACHABLE this way — a
        // fallback that answered "Button Masher" for everything would compile and pass a nil check.
        let byStage = Stage.allCases.map { MinigameAssignment.fallback(for: $0) }
        XCTAssertEqual(byStage.count, Stage.allCases.count)
        XCTAssertEqual(Set(byStage), Set(MinigameKind.allCases),
                       "some game is unreachable through the stage fallback: \(byStage)")
    }

    func testARosterOnlyDigimonFallsBackByItsStage() {
        // poyomon exists only in the roster — no graph node, so no line.
        XCTAssertNil(graph.node(id: "poyomon"), "test assumes poyomon has no graph node")
        XCTAssertEqual(roster.entry(id: "poyomon")?.stage, .babyI)
        XCTAssertEqual(MinigameAssignment.game(for: "poyomon", in: graph, roster: roster),
                       MinigameAssignment.fallback(for: .babyI))
    }

    func testEveryDigimonInTheRosterResolvesToAGame() {
        // The point of the story's "never to 'no game'": all 1,022 of them, not just the authored 88.
        XCTAssertGreaterThan(roster.entries.count, 1000)
        for entry in roster.entries {
            let kind = MinigameAssignment.game(for: entry.id, in: graph, roster: roster)
            let expected = graph.node(id: entry.id).flatMap { MinigameAssignment.byLine[$0.line] }
                ?? MinigameAssignment.fallback(for: entry.stage)
            XCTAssertEqual(kind, expected, "\(entry.id) resolved unexpectedly")
        }
    }

    func testAnUnknownLineAndAnUnknownIdStillGetAGame() {
        XCTAssertEqual(MinigameAssignment.game(line: "no_such_line", stage: .adult),
                       MinigameAssignment.fallback(for: .adult))
        // Neither in the graph nor in the roster: no line, no stage, still a game.
        XCTAssertNil(graph.node(id: "no_such_digimon"))
        XCTAssertNil(roster.entry(id: "no_such_digimon"))
        XCTAssertEqual(MinigameAssignment.game(for: "no_such_digimon", in: graph, roster: roster),
                       MinigameAssignment.fallback(for: nil))
    }

    // MARK: - Stability

    /// "The same Digimon ALWAYS gets the same game" — the guard against someone reaching for
    /// `randomElement()` or a per-launch shuffle.
    func testTheSameDigimonAlwaysGetsTheSameGame() {
        for id in ["agumon", "metalgarurumon", "poyomon", "gazimon", "no_such_digimon"] {
            let first = MinigameAssignment.game(for: id, in: graph, roster: roster)
            for _ in 0..<200 {
                XCTAssertEqual(MinigameAssignment.game(for: id, in: graph, roster: roster), first,
                               "\(id)'s game is not stable")
            }
        }
    }

    /// A freshly decoded graph and roster — a different process's worth of objects — must assign the
    /// same games as the shared bundled ones, so the answer is a property of the Digimon and not of
    /// whichever instance happened to be asked.
    func testAssignmentDoesNotDependOnWhichGraphInstanceAsks() throws {
        let freshGraph = try EvolutionGraph.load()
        let freshRoster = try Roster.load()
        for entry in freshRoster.entries {
            XCTAssertEqual(MinigameAssignment.game(for: entry.id, in: freshGraph, roster: freshRoster),
                           MinigameAssignment.game(for: entry.id, in: graph, roster: roster))
        }
    }

    // MARK: - Naming

    func testEveryKindNamesItsGame() {
        XCTAssertEqual(MinigameKind.timingBar.title, TimingBarGame.title)
        XCTAssertEqual(MinigameKind.buttonMasher.title, ButtonMasherGame.title)
        XCTAssertEqual(MinigameKind.powerMeter.title, PowerMeterGame.title)
        XCTAssertEqual(MinigameKind.crownSprint.title, CrownSprintGame.title)
        XCTAssertEqual(MinigameKind.reflexStrike.title, ReflexStrikeGame.title)
        XCTAssertEqual(MinigameKind.sequenceRecall.title, SequenceRecallGame.title)
        XCTAssertEqual(Set(MinigameKind.allCases.map(\.title)).count, MinigameKind.allCases.count,
                       "two games share a title")
        XCTAssertFalse(MinigameKind.allCases.contains { $0.title.isEmpty })
    }
}
