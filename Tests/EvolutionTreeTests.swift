import XCTest
@testable import DigiVPet

/// US-041: one evolution line laid out as a stage-ordered tree.
///
/// What is asserted here is the arithmetic — which cell each node lands in, and which pairs of
/// cells get a connecting line. That the connectors are actually VISIBLE on a watch is a Simulator
/// screenshot, recorded in progress.txt.
final class EvolutionTreeLayoutTests: XCTestCase {
    private func node(_ id: String, _ stage: Stage, to: [String] = []) -> EvolutionNode {
        EvolutionNode(
            id: id,
            displayName: id.capitalized,
            stage: stage,
            line: "test",
            spriteFile: id.capitalized,
            evolutions: to.map { EvolutionEdge(to: $0, minEnergy: 0, maxCareMistakes: 99) }
        )
    }

    // MARK: - AC: columns ordered by stage

    func testColumnsAreOrderedByStageRegardlessOfNodeOrder() {
        let layout = EvolutionTreeLayout(nodes: [
            node("d", .adult),
            node("a", .digitama),
            node("c", .babyII),
            node("b", .babyI),
        ])

        XCTAssertEqual(layout.columns.map(\.stage), [.digitama, .babyI, .babyII, .adult])
    }

    /// A line that never reaches Ultimate gets no Ultimate column — an empty one would be dead
    /// width on a 42mm screen, which is the narrowest this has to scroll on.
    func testStagesTheLineNeverReachesAreNotColumns() {
        let layout = EvolutionTreeLayout(nodes: [node("a", .digitama), node("b", .child)])

        XCTAssertEqual(layout.columns.map(\.stage), [.digitama, .child])
    }

    /// Armor-Hybrid has no `ladderIndex`, so it is not a rung and must not become a column after
    /// Ultimate. No shipped line has one yet; this pins the behaviour before one does.
    func testAnOffLadderStageIsNotGivenAColumn() {
        let layout = EvolutionTreeLayout(nodes: [node("a", .child), node("x", .armorHybrid)])

        XCTAssertEqual(layout.columns.map(\.stage), [.child])
        XCTAssertEqual(layout.rowCount, 1)
    }

    // MARK: - AC: nodes at the same stage stack vertically

    func testSiblingsAtOneStageShareAColumnAndStackInAuthoredOrder() {
        let layout = EvolutionTreeLayout(nodes: [
            node("agumon", .child, to: ["greymon", "meramon"]),
            node("greymon", .adult),
            node("meramon", .adult),
        ])

        XCTAssertEqual(layout.columns.count, 2)
        XCTAssertEqual(layout.columns[1].nodes.map(\.id), ["greymon", "meramon"])
        XCTAssertEqual(layout.rowCount, 2, "The branch is what makes the grid two rows tall.")
    }

    // MARK: - AC: edges are drawn as connecting lines

    func testABranchProducesOneConnectorPerEdge() {
        let layout = EvolutionTreeLayout(nodes: [
            node("agumon", .child, to: ["greymon", "meramon"]),
            node("greymon", .adult),
            node("meramon", .adult),
        ])

        XCTAssertEqual(layout.connectors, [
            .init(from: .init(column: 0, row: 0), to: .init(column: 1, row: 0)),
            .init(from: .init(column: 0, row: 0), to: .init(column: 1, row: 1)),
        ])
    }

    /// Two Adults evolving into one Perfect is the shape the Agumon line actually ships, and it is
    /// the case a naive "one line per node" drawing would lose.
    func testAConvergingPairKeepsBothConnectors() {
        let layout = EvolutionTreeLayout(nodes: [
            node("greymon", .adult, to: ["metalgreymon"]),
            node("meramon", .adult, to: ["metalgreymon"]),
            node("metalgreymon", .perfect),
        ])

        XCTAssertEqual(layout.connectors, [
            .init(from: .init(column: 0, row: 0), to: .init(column: 1, row: 0)),
            .init(from: .init(column: 0, row: 1), to: .init(column: 1, row: 0)),
        ])
    }

    /// `line` is a grouping key the evolution engine does not read, so an edge is free to leave
    /// the line. The tree has no second endpoint for one and must drop it rather than draw to a
    /// cell it never placed.
    func testAnEdgeLeavingTheLineIsNotDrawn() {
        let layout = EvolutionTreeLayout(nodes: [
            node("agumon", .child, to: ["greymon", "somebody_elses_adult"]),
            node("greymon", .adult),
        ])

        XCTAssertEqual(layout.connectors.count, 1)
        XCTAssertEqual(layout.connectors.first?.to, .init(column: 1, row: 0))
    }

    // MARK: - The shipped Digital Monster Ver.1 line, end to end

    /// The bundled line is what the screenshot shows, so its shape is worth pinning: seven columns,
    /// and the branch at Adult that makes it a tree rather than a row.
    ///
    /// US-061 grew it from eight nodes by adding the junk branch — Numemon at Adult, reached by
    /// inaction out of Agumon, then BlackKingNumemon and PlatinumNumemon, the Perfect and Ultimate
    /// every Adult on the line falls to. US-133 completed the V1 tree on top of that, taking it to
    /// twenty-one nodes and six Adults.
    func testTheBundledVersionOneLineIsABranchingTree() {
        let nodes = EvolutionGraph.bundled.nodes.filter { $0.line == "dmc-v1" }
        let layout = EvolutionTreeLayout(nodes: nodes)

        // Twenty-two since US-144, which hung `agu2006_digitama` on this line as a second egg —
        // Agumon (2006) being Agumon under another sheet — and twenty-five since US-145 added
        // three more onto Botamon: Swimmon's, and PawnChessmon's two colours. Every one of them
        // adds a node and a connector in the Digitama column and nothing else: the branch shape
        // below was untouched by all four.
        //
        // Twenty-nine since US-148, and that one DID move the shape: the Child sweep hung
        // BlackAgumon and Dracomon off Koromon, each with a Champion of its own, so the Adult
        // column went from six to eight and the tree from six rows to eight.
        //
        // Thirty since US-155, which moved the shape again: Tyrannomon is Agumon's fourth earned
        // branch and its last free energy, so the Adult column went from eight to nine.
        // Thirty-two since US-157, which hung Chimairamon off Airdramon and Millenniumon over
        // it: two more nodes and two more connectors, in the Perfect and Ultimate columns, so the
        // Adult column and the row count are untouched.
        // Thirty-five since US-160, which hung three more Perfects on Champions this line already
        // had — Mamemon X off the leaf Greymon (Blue), MetalGreymon Virus X off Devimon and
        // Monzaemon X off the junk Numemon — so again only the Perfect column grew.
        // Thirty-six since US-161, which hung NeoDevimon off that same Devimon — its sole bolded
        // parent — climbing the Blitz Greymon this line already had, so the Perfect column grew by
        // one and nothing else moved. The row count is UP one all the same: Devimon now carries
        // three earned branches plus its fall, and the Perfect column is the widest in the tree.
        // Thirty-nine since US-163, the first sweep at the top rung: Agumon YnK over MetalGreymon
        // (Virus), BlackWarGreymon X over MetalGreymon (Virus) X and Armagemon over Chimairamon,
        // so only the Ultimate column grew. The row count does NOT move — the Perfect column is
        // ten deep and the Ultimate one is nine, so the widest column is still the Perfect one.
        XCTAssertEqual(nodes.count, 42)
        XCTAssertEqual(layout.columns.map(\.stage),
                       [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate])
        XCTAssertEqual(layout.columns.first { $0.stage == .adult }?.nodes.map(\.id),
                       ["greymon", "meramon", "numemon", "devimon", "airdramon", "seadramon",
                        "greymon_blue", "coredramon_green", "tyrannomon"])
        XCTAssertEqual(layout.rowCount, 12)
        // Every one of the line's edges is drawn, because none of them leaves the line — which is
        // the whole reason US-133 renamed this line rather than adding a second one beside it.
        let edges = nodes.flatMap(\.evolutions).count
        XCTAssertEqual(layout.connectors.count, edges)
        XCTAssertEqual(layout.connectors.count, 61)
    }
}
