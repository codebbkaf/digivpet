import XCTest

@testable import DigiVPet

/// US-169 — the twenty-seventh and LAST of Phase E's orphan sweeps, and the only one over the
/// off-ladder Armor-Hybrid stage. All sixteen playable Armor-Hybrid Digimon were orphans: no Armor
/// or Hybrid evolution existed anywhere in the graph. This story wires each one in.
///
/// Armor-Hybrid has no `ladderIndex`, so `EvolutionGraphValidator` never treats an edge into one as a
/// stage transition — a Child may reach it. Each orphan takes an EARNED in-edge from an existing,
/// Digitama-reachable Child on that Child's line, so **no edge crosses a line boundary** (the invariant
/// `UltimateSweepSToZTests.testNoEdgeCrossesALine` pins over the whole graph) and every new form is
/// genuinely obtainable, not a Dex entry behind a stranded parent.
///
/// **AN ARMOR-HYBRID SWEEP IS AN IN-EDGE SWEEP AND NOTHING ELSE**, exactly as the six terminal-Ultimate
/// sweeps US-163..US-168 recorded: Armor-Hybrid is the top of its own side branch, there is no rung
/// above, and a fallback out-edge would have to be an unconditional junk edge to nowhere. So every one
/// of the sixteen is terminal — an in-edge and nothing above.
final class ArmorHybridSweepTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The sixteen orphans this story wired, each with the existing Child that now reaches it and the
    /// `requiredEnergy` of the new earned edge. Every one is a plain roster id, so every one removes
    /// an orphan.
    private let swept: [(node: String, parent: String, energy: EnergyType)] = [
        ("goldv-dramon", "v-mon", .vitality),
        ("submarimon", "v-mon", .spirit),
        ("rapidmon_armor", "v-mon", .stamina),
        ("daipenmon", "wormmon", .strength),
        ("manbomon", "wormmon", .vitality),
        ("shadramon", "wormmon", .spirit),
        ("bitmon", "commandramon", .vitality),
        ("raihimon", "commandramon", .spirit),
        ("rhinomon", "commandramon", .stamina),
        ("beowolfmon", "pulsemon", .strength),
        ("kaisergreymon", "pulsemon", .spirit),
        ("duskmon", "pulsemon", .stamina),
        ("velgrmon", "kokabuterimon", .vitality),
        ("lynxmon", "kokabuterimon", .spirit),
        ("kaiserleomon", "sunarizamon", .strength),
        ("sheepmon", "sunarizamon", .spirit),
    ]

    // MARK: - AC1: the range, counted off the roster rather than off the list above

    /// The headline claim. The range is derived from the ROSTER, so an Armor-Hybrid sheet added to
    /// the folder later lands in scope and fails here instead of being quietly missed.
    func testEveryPlayableArmorHybridIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter { $0.stage == .armorHybrid && !$0.dexOnly }
        XCTAssertEqual(inRange.count, 16, "the Armor-Hybrid range changed size")
        XCTAssertEqual(Set(inRange.map(\.id)), Set(swept.map(\.node)),
                       "the range no longer matches this story's sixteen")

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id), "\(entry.id) is not a node at all")
            XCTAssertEqual(node.stage, .armorHybrid)
            XCTAssertFalse(graph.parents(of: entry.id).isEmpty, "\(entry.id) is evolved into by nothing")
        }
    }

    /// The whole-file form: no playable Armor-Hybrid is an orphan any more.
    func testTheArmorHybridOrphanBucketIsEmpty() {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let orphans = roster.entries
            .filter { $0.stage == .armorHybrid && !$0.dexOnly && !connected.contains($0.id) }
            .map(\.id)
        XCTAssertEqual(orphans, [], "Armor-Hybrid still has orphans: \(orphans)")
    }

    /// The last sweep: the only playable orphans left in the whole roster are the two Chaos Ultimates
    /// their device trees pin to no node — the state `UltimateSweepSToZTests` recorded.
    func testThisWasTheLastSweepAndOnlyTheTwoChaosNodesRemain() {
        let connected = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
            .union(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let orphans = roster.entries
            .filter { !$0.dexOnly && !connected.contains($0.id) }
            .map(\.id)
        XCTAssertEqual(Set(orphans), ["chaosdramon", "chaosmon"],
                       "the whole-roster orphan bucket is not down to the two pinned Chaos nodes")
    }

    // MARK: - AC2/AC3: line grouping, terminality, and no edge leaving a line

    func testEveryNewNodeSitsOnItsParentsLine() throws {
        for (node, parent, _) in swept {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: node)).line,
                           try XCTUnwrap(graph.node(id: parent)).line,
                           "\(node) is not on \(parent)'s line")
        }
    }

    /// No new lines: every one of the sixteen joined a line that already existed, so the sweep made
    /// no one-node lines.
    func testTheSweepOpenedNoNewLines() throws {
        XCTAssertEqual(Set(swept.map(\.node)).count, 16)
        for (node, _, _) in swept {
            let line = try XCTUnwrap(graph.node(id: node)).line
            XCTAssertTrue(["adventure02", "commandramon", "vital"].contains(line),
                          "\(node) landed on unexpected line \(line)")
        }
    }

    /// Every one of the sixteen is terminal, exactly as the terminal Ultimates were: an in-edge and
    /// nothing above.
    func testEverySweptNodeIsTerminal() throws {
        for (node, _, _) in swept {
            let n = try XCTUnwrap(graph.node(id: node))
            XCTAssertEqual(n.stage, .armorHybrid)
            XCTAssertTrue(n.evolutions.isEmpty, "\(node) leads somewhere; an Armor-Hybrid apex may not")
        }
    }

    // MARK: - AC4: the shape of every in-edge this story authored

    /// Every earned in-edge names its energy, carries at least one hinted criterion, and is NOT the
    /// fallback — so it is a branch a player earns, never the junk one taken when nothing qualifies.
    func testEveryEarnedInEdgeIsConditionedAndHinted() throws {
        for (node, parent, energy) in swept {
            let p = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(p.evolutions.first { $0.to == node },
                                     "\(parent) does not reach \(node)")
            XCTAssertEqual(edge.requiredEnergy, energy)
            XCTAssertFalse(edge.isDefault, "\(node)'s in-edge displaced its parent's fallback")
            XCTAssertGreaterThan(edge.minEnergy, 0, "\(node)'s earned edge demands no energy")
            XCTAssertFalse(edge.conditions.isEmpty, "\(node) is gated on energy alone")
            for condition in edge.conditions {
                XCTAssertNotNil(condition.knownMetric, "\(node) names an unknown metric")
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(node) has a criterion with no hint")
            }
        }
    }

    /// Each forked parent keeps exactly one fallback, still last and still the parent's own climb —
    /// never one of this story's Armor-Hybrid nodes.
    func testEveryForkedParentKeepsItsOwnClimbAsItsFallback() throws {
        for parent in Set(swept.map(\.parent)) {
            let node = try XCTUnwrap(graph.node(id: parent))
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(parent) no longer has exactly one fallback")
            XCTAssertTrue(try XCTUnwrap(node.evolutions.last).isDefault,
                          "\(parent)'s fallback is no longer last")
            XCTAssertFalse(swept.map(\.node)
                            .contains(try XCTUnwrap(node.evolutions.first(where: \.isDefault)).to),
                           "\(parent)'s fallback is one of this story's own nodes")
        }
    }

    /// `EvolutionEngine.qualifies` requires `dominant == requiredEnergy`, so two earned edges off one
    /// parent sharing an energy would leave the lower-`minEnergy` one unreachable. Each new branch
    /// takes an energy the parent had free.
    func testNoParentOffersTwoEarnedEdgesOnOneEnergy() throws {
        for parent in Set(swept.map(\.parent)) {
            let earned = try XCTUnwrap(graph.node(id: parent)).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two earned edges on the same energy")
        }
    }

    /// The window trap: `care.battleCount`/`care.battleWinRatio` answer only over `lifetime`, every
    /// other `care.*` counter only over `stage`. A branch this story authored on the wrong window
    /// would be a silently dead edge.
    func testNoCriterionThisStoryAuthoredAsksForAWindowTheContextCannotAnswer() throws {
        for (_, parent, _) in swept {
            for edge in try XCTUnwrap(graph.node(id: parent)).evolutions {
                for condition in edge.conditions {
                    guard let metric = condition.knownMetric, !metric.isHealthMetric else { continue }
                    XCTAssertTrue(metric.canBeAnswered(over: condition.window),
                                  "\(parent) -> \(edge.to): \(metric.rawValue) over \(condition.window)")
                }
            }
        }
    }

    // MARK: - AC: no dexOnly on any edge, and the whole file validates

    func testNoEdgeThisStoryAddedTouchesADexOnlyNode() throws {
        for (node, parent, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: node)).dexOnly, "\(node) is dexOnly")
            XCTAssertFalse(try XCTUnwrap(graph.node(id: parent)).dexOnly, "\(parent) is dexOnly")
        }
    }

    func testTheGraphValidatesWithNoFindings() {
        XCTAssertEqual(EvolutionGraph.bundled.validate().map(\.description), [])
    }

    func testTheSweepAddedSixteenNodes() {
        XCTAssertEqual(graph.nodes.count, 931, "915 before this story, 931 after its sixteen")
    }
}
