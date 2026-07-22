import XCTest

@testable import DigiVPet

/// US-151 — the eighth of Phase E's orphan sweeps, and the first at the Adult rung: the seven
/// playable Champions whose display name begins A-D that no device tree and no Child sweep reached.
///
/// **Which reading of the story's scope this takes.** NOT the rung-and-range reading US-148 through
/// US-150 took one rung down. The criteria ask for coverage of "every remaining orphan at stage
/// Adult whose displayName starts with A-D", and the ninety-five Champions US-149 and US-150 left
/// as leaves are not orphans — they have an in-edge. Wiring those onward is US-152..US-156's, and
/// the ledger in `ChildSweepAToFTests` is where they are counted. What this story owns is the seven
/// with NO edge at all, each of which gets both.
///
/// **What that costs one rung UP.** An Adult's out-edge has to land on a Perfect on its own line,
/// and that rung is where the file runs out: two of the six lines these seven land on had no
/// Perfect at all. So this story opens the Perfect rung on `wanyamon` and on `tamers` — the same
/// problem US-148 and US-149 solved at the Champion rung, one rung later — and each needs a junk
/// floor invented before any Champion of the line can branch. Four new Perfect nodes in total, all
/// four plain roster ids, all four leaves until the Perfect sweeps.
///
/// **What it does NOT do.** It authors no new line, moves no existing node, and takes no Digimon
/// out of a later story's range except the four Perfects it needed.
final class AdultSweepAToDTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The seven orphaned Champions this story wired, with the Child that now reaches each and the
    /// Perfect each now reaches. Every one is a plain roster id, so every one removes an orphan.
    private let swept: [(adult: String, parent: String, child: String)] = [
        ("akatorimon", "floramon", "garudamon"),
        ("blackgaogamon", "gaomon", "blackmachgaogamon"),
        ("blacktailmon", "plotmon", "holyangemon"),
        ("burgermon_papa", "muchomon", "digitamamon"),
        ("burgermon_mama", "muchomon", "digitamamon"),
        ("darklizamon", "monodramon", "megalogrowmon"),
        ("deckerdramon", "hagurumon", "pencme_andromon"),
    ]

    /// The four Perfects this story authored, and why each exists. Two are the earned branch out of
    /// a Champion on a line that had no Perfect rung; two are the junk floor under it.
    private let authoredPerfects = ["blackmachgaogamon", "karakurumon", "megalogrowmon",
                                    "catchmamemon"]

    /// The two lines that had no Perfect rung before this story, and the junk floor each gained.
    private let junkFloors: [(line: String, junk: String)] = [
        ("wanyamon", "karakurumon"),
        ("tamers", "catchmamemon"),
    ]

    /// The shared "did everything right" context. Wider than the Child sweeps' — this rung asks for
    /// stand hours, climbed flights and walked distance, and an edge authored against a metric
    /// outside this fails HERE rather than shipping unreachable.
    private let met = ConditionContext(
        stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                           "health.activeEnergy": 50_000,
                                           "health.exerciseMinutes": 5_000,
                                           "health.standHours": 1_000,
                                           "health.flightsClimbed": 5_000,
                                           "health.distanceWalkingRunning": 500_000,
                                           "health.sleep": 100_000]),
        trainingSessionsThisStage: 30,
        overfeedsThisStage: 0,
        sleepDisturbancesThisStage: 0,
        battlesLifetime: 40,
        battleWinRatioLifetime: 1.0)

    // MARK: - AC1: the range, counted off the roster rather than off the list above

    /// The headline claim. `adultsInRange` is derived from the ROSTER, so an Adult sheet added to
    /// the folder later lands in scope and fails here instead of being quietly missed.
    func testEveryPlayableAdultAToDIsANodeWithAnInEdgeAndAnOutEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .adult && !$0.dexOnly
                && ("A"..."D").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 41)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The seven this story owns lead somewhere too. The other thirty-four are US-149's and
        // US-150's leaves, which US-152..US-156 wire onward — see the ledger in
        // `ChildSweepAToFTests.testTheOnlyDeadEndsBelowUltimateAreTheOnesTheSweepsHaveOpened`.
        for (adult, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: adult)).evolutions.isEmpty,
                           "\(adult) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoAdultAToDIsStillAnOrphan() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)

        let orphans = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly
                && ("A"..."D").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "Adults A-D still orphaned: \(orphans)")
    }

    // MARK: - AC2/AC3: the shape of every edge this story authored

    /// Each swept Champion is one earned branch plus one unconditioned fallback, and the fallback is
    /// its own line's junk Perfect. A condition on a fallback would be data that lies — US-020 takes
    /// the `isDefault` edge exactly when nothing else qualifies — which is the reading of "no edge
    /// is unconditional" every rung below recorded.
    func testEverySweptChampionIsOneEarnedBranchAndOneUnconditionedFallback() throws {
        for (adult, _, child) in swept {
            let node = try XCTUnwrap(graph.node(id: adult))
            XCTAssertEqual(node.evolutions.count, 2, "\(adult) is not a branch plus a fallback")

            let fallback = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertEqual(fallback.conditions, [], "\(adult)'s fallback carries criteria")
            XCTAssertEqual(fallback.minEnergy, 0, "\(adult)'s fallback demands energy")
            XCTAssertGreaterThanOrEqual(fallback.maxCareMistakes, 99)

            let earned = try XCTUnwrap(node.evolutions.first { !$0.isDefault })
            XCTAssertEqual(earned.to, child)
            XCTAssertFalse(earned.conditions.isEmpty,
                           "\(adult) -> \(child) is gated on energy alone")
            for condition in earned.conditions {
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(adult) -> \(child) has an undiscoverable criterion")
            }
            XCTAssertGreaterThan(earned.minEnergy, fallback.minEnergy,
                                 "\(adult)'s junk edge would win the branch outright")
        }
    }

    /// The in-edges are earned too, and none of them displaces the fallback of the Child it hangs
    /// off — the guard every sweep below this one needed.
    func testEveryNewChildBranchIsEarnedAndLeavesTheFallbackAlone() throws {
        for (adult, parent, _) in swept {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == adult },
                                     "\(parent) does not reach \(adult)")
            XCTAssertFalse(edge.isDefault, "\(parent) -> \(adult) took over the junk branch")
            XCTAssertFalse(edge.conditions.isEmpty, "\(parent) -> \(adult) is gated on nothing")
            for condition in edge.conditions {
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(parent) -> \(adult) has an undiscoverable criterion")
            }
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(parent) no longer has a single fallback")
        }
    }

    /// `EvolutionEngine` picks on the dominant energy first, so two branches out of one node sharing
    /// an energy would make the second dead data. Checked on every Child this story branched, not
    /// only on the new edge, because the collision would be with an edge somebody else authored.
    func testEveryChildThisStoryBranchedStillUsesDistinctEnergies() throws {
        for parent in Set(swept.map(\.parent)) {
            let earned = try XCTUnwrap(graph.node(id: parent)).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(parent) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two branches on the same energy")
        }
    }

    /// Every edge this story authored is really reachable through the engine, criteria and all —
    /// the check that separates an authored edge from a taken one. Both directions: the Child's new
    /// branch, and the Champion's own.
    func testEveryNewBranchIsTakenByTheEngineWhenItIsEarned() throws {
        for (adult, parent, child) in swept {
            for (from, to) in [(parent, adult), (adult, child)] {
                let node = try XCTUnwrap(graph.node(id: from))
                let edge = try XCTUnwrap(node.evolutions.first { $0.to == to })
                let energy = try XCTUnwrap(edge.requiredEnergy)
                var totals = EnergyTotals()
                totals[energy] = edge.minEnergy

                XCTAssertEqual(
                    EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals,
                                                    dominant: energy, careMistakes: 0,
                                                    battleWins: 40, conditions: context(for: edge)),
                    to,
                    "\(from) does not reach \(to) on the energy its own edge asks for")
            }
        }
    }

    /// And a neglected one falls to junk instead. Read through `scheduledEvolutionTarget` with the
    /// gate open and an EMPTY context, which is what "the owner did nothing" actually looks like.
    func testANeglectedSweptChampionFallsToItsLinesJunkPerfect() throws {
        for (adult, _, _) in swept {
            let node = try XCTUnwrap(graph.node(id: adult))
            let fallback = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertEqual(
                EvolutionEngine.scheduledEvolutionTarget(
                    for: node, stageEnergy: EnergyTotals(), dominant: nil, careMistakes: 9,
                    battleWins: 0, stageEnteredAt: .distantPast, now: Date(),
                    conditions: .unknown),
                fallback.to,
                "a neglected \(adult) does not fall to \(fallback.to)")
        }
    }

    // MARK: - AC: lines are grouped coherently

    /// No edge in the file crosses a line, still — the rule that decides every placement here. An
    /// Adult that could not be put on the line of the Child below it has been paired with the
    /// wrong Child.
    func testNoEdgeCrossesALine() {
        for node in graph.nodes {
            for edge in node.evolutions {
                guard let target = graph.node(id: edge.to) else { continue }
                XCTAssertEqual(node.line, target.line,
                               "\(node.id) (\(node.line)) -> \(edge.to) (\(target.line)) crosses a line")
            }
        }
    }

    /// No new lines for eleven new nodes, and the count is the file's rather than this story's.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 116, "US-151 added DarkLizamon, MegaloGrowmon, CatchMamemon; "
                           + "US-152 added FlareLizamon and Growmon Orange; "
                           + "US-156 added Youkomon and BlackRapidmon, plus US-158's four, plus US-159's five" + ", plus US-160's four, plus US-161's Rapidmon and SaintGalgomon, plus US-163's eight Ultimates")
        XCTAssertEqual(sizes["wanyamon"], 29,
                       "US-151 added BlackGaogamon, BlackMachGaogamon, Karakurumon, "
                           + "plus US-158's four, plus US-159's two" + ", plus US-160's one, plus US-161's RizeGreymon and Ravmon")
        XCTAssertEqual(sizes["dmc-v4"], 31, "US-151 added the two Burgermon, US-156 Xiquemon and Huankunmon")
        XCTAssertEqual(sizes["penc-wg"], 43,
                       "US-151 added Akatorimon, US-153 Kougamon, US-154 RedV-dramon, "
                           + "US-156 the two Black V-dramon, plus US-158's two, plus US-161's Paildramon")
        XCTAssertEqual(sizes["penc-vb"], 60,
                       "US-151 added BlackTailmon, US-152 GulusGammamon, US-153 KausGammamon, "
                           + "US-156 WezenGammamon and Canoweissmon, plus US-158's Entmon, plus US-161's Regulusmon, plus US-163's two Ultimates")
        XCTAssertEqual(sizes["penc-me"], 70, "US-151 added Deckerdramon, US-157 five Perfects and Kazuchimon, plus US-158's Duramon, plus US-159's two" + ", plus US-160's one, plus US-161's both Okuwamon, RizeGreymon X and two Kuwagamon Megas, plus US-163's four Ultimates")
    }

    /// **The variant rule.** Four of the seven are variants — Black, and nothing else at this rung —
    /// and every one sits on its base form's line rather than on a line of its own.
    func testEveryVariantSitsWithItsBaseForm() throws {
        for (variant, base) in [("blackgaogamon", "gaogamon"),
                                ("blacktailmon", "pencvb_tailmon"),
                                ("blackmachgaogamon", "blackgaogamon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line,
                           "\(variant) is not on \(base)'s line")
        }
        // BlackGaogamon went further than the rule asks: its base form's line ALSO holds the
        // parent Wikimon names for it, so no rehome was needed and no citation was traded away.
        XCTAssertTrue(graph.parents(of: "blackgaogamon").map(\.id).contains("gaomon"))
    }

    // MARK: - The two lines that gained a Perfect rung

    /// Each junk floor is on the line it serves, is a Perfect, is reachable by doing nothing, and is
    /// the fallback of every Champion of that line that branches at all. The last clause is scoped
    /// to branching Champions on purpose: `tamers` has twenty-two more leaves that US-152..US-156
    /// will hang off this same floor.
    func testTheTwoLinesWithoutAPerfectRungGainedAJunkFloor() throws {
        for (line, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: junk), "no node \(junk)")
            XCTAssertEqual(node.line, line, "\(junk) is not on \(line)")
            XCTAssertEqual(node.stage, .perfect)
            XCTAssertNotNil(roster.entry(id: junk), "\(junk) is an alias, so it removes no orphan")

            let branching = graph.nodes.filter {
                $0.line == line && $0.stage == .adult && !$0.evolutions.isEmpty
            }
            XCTAssertFalse(branching.isEmpty, "\(line) has no branching Champion to need a floor")
            for adult in branching {
                XCTAssertEqual(adult.evolutions.first(where: \.isDefault)?.to, junk,
                               "\(adult.id) does not fall to \(line)'s junk Perfect")
            }
        }

        // Before this story neither line had a Perfect at all; each gained exactly two, the earned
        // branch and the floor under it.
        //
        // **Scoped rather than relaxed in US-154.** A count was the wrong claim: US-154 opened two
        // MORE Perfects on `tamers` — Grademon and Mametyramon, each cited by two of its four
        // X-Antibody Champions — without touching this story's pair, and a bare count of two would
        // have failed on work that did nothing wrong. What stays true is that the four this story
        // authored are still here and are still the only ones IT authored, so the claim is now the
        // pair by name plus the floor's exclusivity.
        // **Scoped the same way again in US-158**, which hung Gogmamon and Grappleomon on this
        // line's two remaining leaf Champions and gave `wanyamon` its first Ultimates. Neither
        // touched this story's pair, so the claim stays "the two US-151 authored are still here and
        // the floor is still the only fallback" rather than a count that a later sweep must edit.
        XCTAssertTrue(Set(graph.nodes.filter { $0.line == "wanyamon" && $0.stage == .perfect }
                              .map(\.id)).isSuperset(of: ["blackmachgaogamon", "karakurumon"]))
        XCTAssertTrue(Set(graph.nodes.filter { $0.line == "tamers" && $0.stage == .perfect }
                              .map(\.id)).isSuperset(of: ["megalogrowmon", "catchmamemon"]))
        XCTAssertTrue(Set(graph.nodes.map(\.id)).isSuperset(of: authoredPerfects))
    }

    /// The junk floors are inventions, so the whole-file grep US-140's notes insist on writing
    /// BEFORE authoring is written down here as a test: neither name is anywhere in the tree
    /// markdown, so neither steals a node a later device-tree story would have drawn as earned.
    func testNeitherInventedJunkPerfectIsDrawnAnywhereInTheDocument() throws {
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: "Digimon_Color_And_Pendulum_Color_Evolution_Trees", withExtension: "md"))
        let text = try String(contentsOf: url, encoding: .utf8)
        for name in ["Karakurumon", "Karakuru", "CatchMamemon", "Catch Mamemon"] {
            XCTAssertFalse(text.contains(name), "\(name) IS in the document after all")
        }
    }

    // MARK: - AC: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate.
    func testEveryNodeThisStoryAddedIsASliceableSheet() throws {
        for id in swept.map(\.adult) + authoredPerfects {
            let node = try XCTUnwrap(graph.node(id: id))
            let entry = try XCTUnwrap(roster.entry(id: id), "\(id) has no roster entry")
            XCTAssertFalse(entry.dexOnly, "\(id) is idle-only and must not be on an edge")
            XCTAssertEqual(node.spriteFile, entry.spriteFile)
            XCTAssertEqual(node.stage, entry.stage)

            let sheet = try XCTUnwrap(
                SpriteSheetCache.shared.sheet(stage: node.stage.rawValue, name: node.spriteFile),
                "\(id): \(node.stage.rawValue)/\(node.spriteFile) is not a sliceable sheet")
            XCTAssertEqual(sheet.kind, .stage, id)
        }
    }

    // MARK: - AC: every choice is recorded in the data file

    /// Every node this story added carries a comment, and each one either cites Wikimon or says in
    /// as many words that it could not — the rule US-146 set and every sweep since has kept.
    func testEveryNodeThisStoryAddedCitesItsSourceOrSaysItCannot() throws {
        for id in swept.map(\.adult) + authoredPerfects {
            let comment = try authoredComment(on: id)
            XCTAssertTrue(comment.contains("Wikimon") || comment.contains("NO CITATION")
                            || comment.contains("no citation") || comment.contains("junk floor"),
                          "\(id)'s comment neither cites a source nor says it has none")
        }
    }

    /// The two uncited pairings name exactly what they could not use, so a later reader can check
    /// the claim instead of trusting it. Both are checkable against the roster.
    func testEveryUncitedPairingSaysWhatItCouldNotUse() throws {
        // Burgermon: all three of Burgamon Adult's Wikimon parents are unusable, and the one that
        // is on disk is idle-only — the case `edgeToDexOnlyNode` exists to forbid.
        XCTAssertTrue(try authoredComment(on: "burgermon_papa").contains("NO CITATION"))
        XCTAssertEqual(roster.entry(id: "burgermon")?.dexOnly, true,
                       "Burgamon has an animated sheet after all, so it should be the parent")
        XCTAssertNil(roster.entry(id: "ebiburgamon"), "Ebi Burgamon has a sheet after all")
        XCTAssertEqual(roster.entry(id: "tyumon")?.dexOnly, true)
        // And the rehome's argument really is on this line: Torikara Ballmon, whose only canon
        // relatives are the two Burgamon Adult, and Digitamamon, a cited Evolves To.
        for id in ["torikaraballmon", "digitamamon", "muchomon"] {
            XCTAssertEqual(graph.node(id: id)?.line, "dmc-v4")
        }

        // Deckerdramon: Wikimon's Evolves From is a card-game colour class and nothing else, and
        // Decker Greymon — the one named Perfect — is not on disk at all.
        XCTAssertTrue(try authoredComment(on: "deckerdramon").contains("Blue Lv.3"))
        XCTAssertNil(roster.entry(id: "deckergreymon"), "Decker Greymon has a sheet after all")
        XCTAssertEqual(roster.entry(id: "mugendramon")?.stage, .ultimate,
                       "Deckerdramon's other named target is a rung too far")
        // The out-edge's clause is checkable: Andromon really is reached from this line's Cyborg.
        XCTAssertTrue(graph.parents(of: "pencme_andromon").map(\.id).contains("guardromon"))
    }

    /// MegaloGrowmon has two cited parents and only one of them could be wired here, because the
    /// other was still an orphan this story did not own. It was written down so US-152 would find it
    /// rather than rediscover it, and US-152 DID: the claim flipped from "FlareLizamon has no node"
    /// to "FlareLizamon is the second parent", which is the same fact from the other side and is
    /// what a handover claim is supposed to do rather than rot. See
    /// `AdultSweepEToGTests.testFlareLizamonClosesTheArrowUS151CouldOnlyDrawOneEndOf`.
    func testMegaloGrowmonsOtherCitedParentWasPickedUpByTheEToGSweep() throws {
        XCTAssertTrue(try authoredComment(on: "megalogrowmon").contains("Flare Lizamon"))
        XCTAssertEqual(roster.entry(id: "flarelizamon")?.stage, .adult)
        XCTAssertEqual(Set(graph.parents(of: "megalogrowmon").map(\.id)),
                       ["darklizamon", "flarelizamon", "growmon_orange"],
                       "US-152 wired FlareLizamon and Growmon Orange onto this Perfect")
    }

    // MARK: - AC: the orphan count, and the whole file still validates

    /// ELEVEN, counted with Appendix B of the PRD over a regenerated `roster.generated.json`:
    /// 330 before, 319 after; the Adult bucket falls 34 -> 27 and the Perfect one 114 -> 110.
    /// Asserted rather than only noted, because the count is the one claim in `notes` a later
    /// reader cannot re-derive from the diff.
    ///
    /// Every one of the eleven carries a plain roster id — not a single line-scoped alias — which is
    /// why new nodes and orphans removed are the same number.
    func testTheElevenOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        let removed = swept.map(\.adult) + authoredPerfects
        XCTAssertEqual(removed.count, 11)

        for id in removed {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 837,
                       "599 before this story, 615 after US-152, 618 after US-153, 629 after US-154, "
                           + "635 after US-155, 643 after US-156, 672 after US-157, "
                           + "693 after US-158, 709 after US-159, 736 after US-160, 760 after US-161, 787 after US-162, 817 after US-163")
    }

    func testTheGraphValidatesWithNoFindings() {
        XCTAssertEqual(EvolutionGraph.bundled.validate().map(\.description), [])
    }

    // MARK: - Helpers

    /// A context that satisfies `edge`'s criteria, derived FROM the edge rather than shared.
    ///
    /// Two of this story's edges carry an `atMost` criterion — Burgermon Mama's in-edge wants few
    /// training sessions, BlackGaogamon's wants short nights — and a blanket "did everything
    /// right" context is the one thing that cannot take either. Deriving the context edge by edge
    /// says that out loud instead of quietly loosening the criterion to fit the fixture.
    private func context(for edge: EvolutionEdge) -> ConditionContext {
        var values = met.stageTotals?.values ?? [:]
        var training = 30

        for condition in edge.conditions where condition.comparison == .atMost {
            switch condition.knownMetric {
            case .careTrainingSessions: training = 0
            case .some(let metric) where metric.isHealthMetric: values[metric.rawValue] = 0
            default: break
            }
        }

        return ConditionContext(
            stageTotals: MetricTotals(values: values),
            trainingSessionsThisStage: training,
            overfeedsThisStage: 0,
            sleepDisturbancesThisStage: 0,
            battlesLifetime: 40,
            battleWinRatioLifetime: 1.0)
    }

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-150 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
