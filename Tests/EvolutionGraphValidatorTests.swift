import Foundation
import XCTest

@testable import DigiVPet

/// Tests the validator itself against hand-built broken graphs, plus the AC's run against the
/// REAL shipped `evolutions.json`.
///
/// Two different jobs, deliberately in one file: the fixtures prove each rule FIRES (a validator
/// that returns [] always would pass a green-roster test), and the real-file test is what fails
/// the build on a broken graph.
final class EvolutionGraphValidatorTests: XCTestCase {
    /// Art existence is stubbed for fixture graphs — they name Digimon that need not exist on
    /// disk, and the other rules must not fail on that. The real-file tests use the real check.
    private let allSpritesExist: EvolutionGraph.SpriteExistsCheck = { _ in true }

    /// A minimal SOUND graph: egg -> baby I -> baby II. Every fixture below is this with exactly
    /// one thing broken, so a reported error can only be the thing that was broken.
    private func soundGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(
                id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                evolutions: [EvolutionEdge(to: "baby", minEnergy: 50, maxCareMistakes: 99, isDefault: true)]),
            EvolutionNode(
                id: "baby", displayName: "Baby", stage: .babyI, spriteFile: "Botamon",
                evolutions: [EvolutionEdge(
                    to: "toddler", requiredEnergy: .strength, minEnergy: 20, maxCareMistakes: 5,
                    isDefault: true)]),
            EvolutionNode(id: "toddler", displayName: "Toddler", stage: .babyII, spriteFile: "Koromon"),
        ])
    }

    private func errors(_ graph: EvolutionGraph) -> [GraphValidationError] {
        graph.validate(spriteExists: allSpritesExist)
    }

    /// The control. Without this, every "exactly one error" assertion below could be passing
    /// because the validator flags something unrelated in the baseline.
    func testASoundGraphHasNoErrors() {
        XCTAssertEqual(errors(soundGraph()), [])
    }

    // MARK: - AC: reports edges whose 'to' references an unknown node id

    func testReportsEdgeToUnknownNodeId() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(
                id: "baby", displayName: "Baby", stage: .babyI, spriteFile: "Botamon",
                evolutions: [EvolutionEdge(
                    to: "nosuchmon", requiredEnergy: .strength, minEnergy: 20, maxCareMistakes: 5,
                    isDefault: true)]),
        ])

        XCTAssertEqual(errors(graph), [.unknownEdgeTarget(from: "baby", to: "nosuchmon")])
    }

    // MARK: - AC: reports nodes whose spriteFile does not exist on disk

    func testReportsMissingSprite() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(id: "ghost", displayName: "Ghost", stage: .child, spriteFile: "NotADigimon"),
        ])

        // The REAL disk check, not the stub — this AC is specifically about what is on disk.
        XCTAssertEqual(graph.validate(spriteExists: EvolutionGraph.spriteExists(in: .main)),
                       [.missingSprite(node: "ghost", path: "Child/NotADigimon.png")])
    }

    /// The same check must PASS for art that is really there, or "reports missing sprites" is
    /// satisfied by a check that reports every sprite.
    func testDoesNotReportSpriteThatExistsOnDisk() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(id: "agumon", displayName: "Agumon", stage: .child, spriteFile: "Agumon"),
        ])

        XCTAssertEqual(graph.validate(spriteExists: EvolutionGraph.spriteExists(in: .main)), [])
    }

    /// A dexOnly node's art is in the flat `Idle Frame Only` folder, so resolving it under its
    /// stage folder would report every one of the 157 as missing.
    func testDexOnlyNodeResolvesItsSpriteInIdleFrameOnly() {
        // Poyomon is confirmed idle-only: it has no sheet in Baby I/.
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(
                id: "poyomon", displayName: "Poyomon", stage: .babyI, spriteFile: "Poyomon",
                dexOnly: true),
        ])

        XCTAssertEqual(graph.validate(spriteExists: EvolutionGraph.spriteExists(in: .main)), [])

        // And the same node NOT marked dexOnly is an error, since Baby I/Poyomon.png is exactly
        // what does not exist. This pins that dexOnly changes where art is looked for.
        let asPlayable = EvolutionGraph(nodes: [
            EvolutionNode(id: "poyomon", displayName: "Poyomon", stage: .babyI, spriteFile: "Poyomon"),
        ])
        XCTAssertEqual(asPlayable.validate(spriteExists: EvolutionGraph.spriteExists(in: .main)),
                       [.missingSprite(node: "poyomon", path: "Baby I/Poyomon.png")])
    }

    /// An empty spriteFile is reported as its own error rather than left to a nil load: a check
    /// that does not guard the empty name would "find" an arbitrary png and pass (see
    /// `SpriteLoader.url`). Stubbing existence to TRUE is the point — the rule must not depend on
    /// the loader happening to guard.
    func testReportsEmptySpriteFileEvenWhenTheLoaderWouldFindArt() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(id: "blank", displayName: "Blank", stage: .child, spriteFile: ""),
        ])

        XCTAssertEqual(errors(graph), [.emptySpriteFile(node: "blank")])
    }

    // MARK: - AC: reports a node with no line

    /// A blank line is not a missing key — the decoder rejects those — so this rule exists only
    /// for `""`, which decodes cleanly and then groups the node under a nameless tree nobody
    /// looks at. Art existence is stubbed true so the ONLY thing wrong here is the line.
    func testReportsEmptyLine() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(id: "stray", displayName: "Stray", stage: .child, line: "", spriteFile: "Agumon"),
        ])

        XCTAssertEqual(errors(graph), [.emptyLine(node: "stray")])
    }

    func testANonEmptyLineIsNotReported() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(id: "ok", displayName: "OK", stage: .child, line: "agumon", spriteFile: "Agumon"),
        ])

        XCTAssertEqual(errors(graph), [])
    }

    // MARK: - AC: reports stage transitions that skip a stage

    func testReportsStageSkip() {
        var graph = soundGraph()
        // Baby I -> Child skips Baby II.
        graph = EvolutionGraph(nodes: graph.nodes.map { node in
            node.id == "toddler"
                ? EvolutionNode(id: "toddler", displayName: "Toddler", stage: .child, spriteFile: "Koromon")
                : node
        })

        XCTAssertEqual(errors(graph), [.invalidStageTransition(
            from: "baby", to: "toddler", fromStage: .babyI, toStage: .child)])
    }

    /// Sideways and backwards edges are just as broken as a skip, and the same rung arithmetic
    /// catches them — assert it rather than leaving it to chance.
    func testReportsSidewaysAndBackwardsTransitions() {
        for (stage, name) in [(Stage.babyI, "sideways"), (Stage.digitama, "backwards")] {
            let graph = EvolutionGraph(nodes: [
                EvolutionNode(
                    id: "baby", displayName: "Baby", stage: .babyI, spriteFile: "Botamon",
                    evolutions: [EvolutionEdge(
                        to: "other", requiredEnergy: .strength, minEnergy: 20, maxCareMistakes: 5,
                        isDefault: true)]),
                EvolutionNode(id: "other", displayName: "Other", stage: stage, spriteFile: "Punimon"),
            ])

            XCTAssertEqual(errors(graph), [.invalidStageTransition(
                from: "baby", to: "other", fromStage: .babyI, toStage: stage)], "\(name) edge")
        }
    }

    /// Armor-Hybrid is a side branch with no rung (`ladderIndex` nil). Rung arithmetic cannot
    /// judge it, so it must be left alone rather than treated as the rung after Ultimate.
    func testDoesNotReportTransitionsInvolvingArmorHybrid() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(
                id: "child", displayName: "Child", stage: .child, spriteFile: "Agumon",
                evolutions: [EvolutionEdge(
                    to: "armor", requiredEnergy: .strength, minEnergy: 20, maxCareMistakes: 5,
                    isDefault: true)]),
            EvolutionNode(
                id: "armor", displayName: "Armor", stage: .armorHybrid, spriteFile: "Beowolfmon",
                evolutions: [EvolutionEdge(
                    to: "perfect", requiredEnergy: .strength, minEnergy: 30, maxCareMistakes: 3,
                    isDefault: true)]),
            EvolutionNode(id: "perfect", displayName: "Perfect", stage: .perfect, spriteFile: "MetalGreymon"),
        ])

        XCTAssertEqual(errors(graph), [])
    }

    // MARK: - AC: reports non-terminal nodes with no isDefault edge

    func testReportsNonTerminalNodeWithNoDefaultEdge() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(
                id: "baby", displayName: "Baby", stage: .babyI, spriteFile: "Botamon",
                evolutions: [EvolutionEdge(
                    to: "toddler", requiredEnergy: .strength, minEnergy: 20, maxCareMistakes: 5)]),
            EvolutionNode(id: "toddler", displayName: "Toddler", stage: .babyII, spriteFile: "Koromon"),
        ])

        XCTAssertEqual(errors(graph), [.noDefaultEdge(node: "baby")])
    }

    /// A TERMINAL node has no edges and so needs no default — the rule must not fire on the three
    /// Ultimates, which would make the real-file test fail on a correct roster.
    func testDoesNotReportTerminalNodeWithNoEdges() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(id: "wargreymon", displayName: "WarGreymon", stage: .ultimate, spriteFile: "WarGreymon"),
        ])

        XCTAssertEqual(errors(graph), [])
    }

    func testReportsMultipleDefaultEdges() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(
                id: "baby", displayName: "Baby", stage: .babyI, spriteFile: "Botamon",
                evolutions: [
                    EvolutionEdge(to: "a", requiredEnergy: .strength, minEnergy: 20, maxCareMistakes: 5, isDefault: true),
                    EvolutionEdge(to: "b", requiredEnergy: .spirit, minEnergy: 20, maxCareMistakes: 5, isDefault: true),
                ]),
            EvolutionNode(id: "a", displayName: "A", stage: .babyII, spriteFile: "Koromon"),
            EvolutionNode(id: "b", displayName: "B", stage: .babyII, spriteFile: "Tsunomon"),
        ])

        XCTAssertEqual(errors(graph), [.multipleDefaultEdges(node: "baby", count: 2)])
    }

    // MARK: - Rules handed to US-009 by earlier stories

    /// `byId` keeps the FIRST of a duplicate pair, so the second is unreachable and every edge
    /// naming that id silently resolves to the wrong Digimon.
    func testReportsDuplicateNodeIds() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(id: "twin", displayName: "First", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: "twin", displayName: "Second", stage: .child, spriteFile: "Gabumon"),
        ])

        XCTAssertEqual(errors(graph), [.duplicateId("twin", count: 2)])
    }

    /// Only a Digitama's hatch edge may omit requiredEnergy (US-018 hatches on total energy).
    func testReportsMissingRequiredEnergyOnANonHatchEdge() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(
                id: "baby", displayName: "Baby", stage: .babyI, spriteFile: "Botamon",
                evolutions: [EvolutionEdge(to: "toddler", minEnergy: 20, maxCareMistakes: 5, isDefault: true)]),
            EvolutionNode(id: "toddler", displayName: "Toddler", stage: .babyII, spriteFile: "Koromon"),
        ])

        XCTAssertEqual(errors(graph), [.missingRequiredEnergy(from: "baby", to: "toddler")])
    }

    /// The other half of the same rule: naming an energy on a hatch is data that lies, since
    /// US-018 ignores it.
    func testReportsTypeGatedHatchEdge() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(
                id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                evolutions: [EvolutionEdge(
                    to: "baby", requiredEnergy: .strength, minEnergy: 50, maxCareMistakes: 99,
                    isDefault: true)]),
            EvolutionNode(id: "baby", displayName: "Baby", stage: .babyI, spriteFile: "Botamon"),
        ])

        XCTAssertEqual(errors(graph), [.typeGatedHatch(from: "egg", to: "baby", energy: .strength)])
    }

    /// The 157 idle-only Digimon have no animated sheet, so an edge naming one would make a
    /// Digimon playable that cannot be animated.
    func testReportsEdgeToDexOnlyNode() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(
                id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                evolutions: [EvolutionEdge(to: "poyomon", minEnergy: 50, maxCareMistakes: 99, isDefault: true)]),
            EvolutionNode(
                id: "poyomon", displayName: "Poyomon", stage: .babyI, spriteFile: "Poyomon", dexOnly: true),
        ])

        XCTAssertEqual(errors(graph), [.edgeToDexOnlyNode(from: "egg", to: "poyomon")])
    }

    // MARK: - Reporting every error, not just the first

    /// Fixing a roster one error per test run would be miserable, so errors accumulate.
    func testReportsEveryErrorAtOnce() {
        let graph = EvolutionGraph(nodes: [
            EvolutionNode(
                id: "baby", displayName: "Baby", stage: .babyI, spriteFile: "",
                evolutions: [EvolutionEdge(to: "nosuchmon", minEnergy: 20, maxCareMistakes: 5)]),
        ])

        XCTAssertEqual(Set(errors(graph).map(\.description)), Set([
            GraphValidationError.emptySpriteFile(node: "baby"),
            .noDefaultEdge(node: "baby"),
            .missingRequiredEnergy(from: "baby", to: "nosuchmon"),
            .unknownEdgeTarget(from: "baby", to: "nosuchmon"),
        ].map(\.description)))
    }

    // MARK: - AC: runs against the real evolutions.json and fails the build on any error

    /// THE acceptance criterion: the shipped roster is validated on every test run, with the real
    /// on-disk sprite check. A broken graph fails the build here instead of the app at runtime.
    func testShippedEvolutionsJsonIsValid() throws {
        let graph = try EvolutionGraph.load()
        let errors = graph.validate()

        XCTAssertEqual(
            errors, [],
            "evolutions.json is invalid:\n" + errors.map { "  - \($0.description)" }.joined(separator: "\n"))
    }

    /// Guards the test above from passing vacuously: if `load()` ever returned an empty graph, or
    /// the seed shrank to nothing, validating it would trivially find no errors.
    func testTheValidatedGraphIsTheRealNonEmptyRoster() throws {
        let graph = try EvolutionGraph.load()

        XCTAssertEqual(graph.nodes.count, 760,
                       "the US-008 seed roster is 22 nodes, plus 15 for US-044's Patamon line, 15 for US-045's Piyomon line, 17 for US-046's Gazimon line, 19 for US-061's junk branches and extra Children, 10 for US-133 completing the Digital Monster Ver.1 tree, 13 for US-134 completing the Version 2 tree, 3 for US-135 completing the Version 3 tree, 1 for US-136 completing the Version 4 tree, 30 for US-138's Pendulum Color V1 Nature Spirits tree, 31 for US-139's Pendulum Color V2 Deep Savers tree, 31 for US-140's Pendulum Color V3 Nightmare Soldiers tree 31 for US-141's Pendulum Color V4 Wind Guardians tree 32 for US-142's Pendulum Color V5 Metal Empire tree 30 for US-143's Pendulum Color V0 Virus Busters / ZERO tree, which is the last of the eleven device trees, 30 for US-144's first orphan sweep - 22 Digitama whose displayName starts A-K plus the 8 Baby I they hatch into - 35 for US-145's second, the 23 Digitama whose displayName starts L-Z plus the 12 Baby I they open, 38 for US-146's third - the 13 Baby I no egg can reach plus the 25 Baby II the whole rung now evolves into - and 51 for US-147's fourth, the 12 Baby II nobody had wired plus the 39 Children the whole rung now evolves into, then 43/51/51 for the three Child sweeps US-148..US-150 11 for US-151's Adult A-D sweep and 5 for US-152's Adult E-G one, and 3 for US-153's Adult H-L one, then 11/6/8 for the last three Adult sweeps US-154..US-156, and 29 for US-157's Perfect A-C sweep - 19 Perfects, the 9 Ultimates they climb into and one junk floor, 709 after US-159, 736 after US-160, 760 after US-161")
        XCTAssertNotNil(graph.node(id: "agumon"), "the real roster should contain Agumon")
    }
}
