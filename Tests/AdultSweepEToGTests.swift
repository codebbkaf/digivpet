import XCTest

@testable import DigiVPet

/// US-152 — the ninth of Phase E's orphan sweeps and the second at the Adult rung: the five playable
/// Champions whose display name begins E-G that no device tree and no Child sweep reached.
///
/// **The scope reading is US-151's.** The criteria ask for coverage of "every remaining orphan at
/// stage Adult whose displayName starts with E-G", so the ninety-five Champions US-149 and US-150
/// left as leaves are NOT in range — they have an in-edge and are therefore not orphans. They stay
/// in `ChildSweepAToFTests.testTheOnlyDeadEndsBelowUltimateAreTheOnesTheSweepsHaveOpened`, which
/// this story leaves at ninety-nine.
///
/// **What it costs one rung UP: nothing, and that is the whole shape of the story.** US-151 had to
/// open the Perfect rung on two lines before its Champions could branch. Every one of these five
/// lands on a line that already has a Perfect — `penc-ds` from the device tree, `tamers` and
/// `penc-vb` from US-151 and US-143 — and in four of the five cases the Perfect Wikimon names is
/// the one already there. So five new nodes remove five orphans and no Perfect is spent.
///
/// **FlareLizamon closes a thread US-151 opened and could not finish.** MegaloGrowmon's `comment`
/// names Flare Lizamon as its second cited parent and says it was left for this story;
/// `AdultSweepAToDTests.testMegaloGrowmonsOtherCitedParentIsLeftForTheEToGSweep` asserted the gap.
/// That test now fails unless this story is the one that closed it, which is the point of writing a
/// missing rung down as a claim rather than as a comment.
final class AdultSweepEToGTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The five orphaned Champions this story wired, with the Child that now reaches each and the
    /// Perfect each now reaches. Every one is a plain roster id, so every one removes an orphan.
    private let swept: [(adult: String, parent: String, perfect: String)] = [
        ("ebidramon", "shakomon", "anomalocarimon"),
        ("gawappamon", "gomamon", "pencds_megaseadramon"),
        ("flarelizamon", "clearagumon", "megalogrowmon"),
        ("growmon_orange", "guilmon", "megalogrowmon"),
        ("gulusgammamon", "gammamon", "holyangemon"),
    ]

    /// The junk Perfect each of the three lines this story touched already had, and which of the
    /// five falls to it. Nothing here is new: `piranimon` is US-139's, `catchmamemon` US-151's and
    /// `andiramon_virus` US-143's.
    private let junkFloors: [(adult: String, junk: String)] = [
        ("ebidramon", "piranimon"),
        ("gawappamon", "piranimon"),
        ("flarelizamon", "catchmamemon"),
        ("growmon_orange", "catchmamemon"),
        ("gulusgammamon", "andiramon_virus"),
    ]

    /// The shared "did everything right" context, US-151's exactly: this rung asks for stand hours,
    /// climbed flights and walked distance, and an edge authored against a metric outside it fails
    /// HERE rather than shipping unreachable.
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

    /// The headline claim. The range is derived from the ROSTER, so an Adult sheet added to the
    /// folder later lands in scope and fails here instead of being quietly missed.
    func testEveryPlayableAdultEToGIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .adult && !$0.dexOnly
                && ("E"..."G").contains(String($0.displayName.prefix(1)).uppercased())
        }
        XCTAssertEqual(inRange.count, 31)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The five this story owns lead somewhere too. The rest are US-149's and US-150's leaves,
        // counted in `ChildSweepAToFTests`' dead-end ledger and wired onward by the Perfect sweeps.
        for (adult, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: adult)).evolutions.isEmpty,
                           "\(adult) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoAdultEToGIsStillAnOrphan() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)

        let orphans = roster.entries
            .filter { $0.stage == .adult && !$0.dexOnly
                && ("E"..."G").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "Adults E-G still orphaned: \(orphans)")
    }

    // MARK: - AC2/AC3: the shape of every edge this story authored

    /// Each swept Champion still has THIS story's earned branch plus exactly one unconditioned
    /// fallback, and the fallback is its own line's junk Perfect. A condition on a fallback would be
    /// data that lies — US-020 takes the `isDefault` edge exactly when nothing else qualifies —
    /// which is the reading of "no edge is unconditional" every rung below recorded.
    ///
    /// The edge COUNT was pinned at two until US-157, which hung Anomalocarimon X off Ebidramon; a
    /// later sweep adding a second earned branch to a Champion is the system working, not drift, so
    /// what is pinned now is the single fallback and this story's own arrow rather than the total.
    func testEverySweptChampionIsOneEarnedBranchAndOneUnconditionedFallback() throws {
        for (adult, _, perfect) in swept {
            let node = try XCTUnwrap(graph.node(id: adult))
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(adult) no longer has exactly one fallback")

            let fallback = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertEqual(fallback.conditions, [], "\(adult)'s fallback carries criteria")
            XCTAssertEqual(fallback.minEnergy, 0, "\(adult)'s fallback demands energy")
            XCTAssertGreaterThanOrEqual(fallback.maxCareMistakes, 99)

            let earned = try XCTUnwrap(node.evolutions.first { $0.to == perfect },
                                       "\(adult) no longer reaches \(perfect)")
            XCTAssertFalse(earned.isDefault, "\(adult) -> \(perfect) took over the junk branch")
            XCTAssertFalse(earned.conditions.isEmpty,
                           "\(adult) -> \(perfect) is gated on energy alone")
            for condition in earned.conditions {
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(adult) -> \(perfect) has an undiscoverable criterion")
            }
            XCTAssertGreaterThan(earned.minEnergy, fallback.minEnergy,
                                 "\(adult)'s junk edge would win the branch outright")
        }
    }

    /// Nothing new was invented at the Perfect rung, and that is a claim worth pinning: US-151 had
    /// to author four Perfects for seven Champions, and a later reader comparing the two stories
    /// should be able to see that this one spent none.
    func testTheSweepAuthoredNoNewPerfectAndEveryFallbackIsAnExistingJunkFloor() throws {
        for (adult, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: adult))
            XCTAssertEqual(node.evolutions.first(where: \.isDefault)?.to, junk,
                           "\(adult) does not fall to its line's junk Perfect")

            let floor = try XCTUnwrap(graph.node(id: junk))
            XCTAssertEqual(floor.line, node.line, "\(junk) is not on \(adult)'s line")
            XCTAssertEqual(floor.stage, .perfect)
        }

        // Every node this story added is an Adult. Stated over the five rather than over the file
        // so that authoring a Perfect here later has to be written down rather than slipped in.
        for (adult, _, _) in swept {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: adult)).stage, .adult)
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
    /// only on the new edge, because the collision would be with an edge somebody else authored —
    /// and two of these five hang off a Child that already had TWO earned branches.
    func testEveryChildThisStoryBranchedStillUsesDistinctEnergies() throws {
        for parent in Set(swept.map(\.parent)) {
            let earned = try XCTUnwrap(graph.node(id: parent)).evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(parent) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two branches on the same energy")
        }

        // Shakomon and Gomamon now carry THREE earned branches apiece, one short of the ceiling the
        // four energy types impose. Said out loud so the next sweep prices a fourth honestly.
        for parent in ["shakomon", "gomamon"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent))
                               .evolutions.filter { !$0.isDefault }.count, 3)
        }
    }

    /// Every edge this story authored is really reachable through the engine, criteria and all —
    /// the check that separates an authored edge from a taken one. Both directions: the Child's new
    /// branch, and the Champion's own.
    func testEveryNewBranchIsTakenByTheEngineWhenItIsEarned() throws {
        for (adult, parent, perfect) in swept {
            for (from, to) in [(parent, adult), (adult, perfect)] {
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
        for (adult, junk) in junkFloors {
            XCTAssertEqual(
                EvolutionEngine.scheduledEvolutionTarget(
                    for: try XCTUnwrap(graph.node(id: adult)), stageEnergy: EnergyTotals(),
                    dominant: nil, careMistakes: 9, battleWins: 0,
                    stageEnteredAt: .distantPast, now: Date(), conditions: .unknown),
                junk,
                "a neglected \(adult) does not fall to \(junk)")
        }
    }

    /// The window trap US-150 shipped into a first draft and `ChildSweepMToZTests` pinned over the
    /// whole file: `care.battleCount` is answerable only over `lifetime` and every other `care.*`
    /// counter only over `stage`, so an edge that asks the other way is UNREACHABLE rather than
    /// merely hard. Restated over this story's ten new edges because it is cheap and because the
    /// engine, not the validator, is the only thing that catches it.
    func testNoCriterionThisStoryAuthoredAsksForAWindowTheContextCannotAnswer() throws {
        let touched = swept.map(\.adult) + swept.map(\.parent)
        for id in Set(touched) {
            for edge in try XCTUnwrap(graph.node(id: id)).evolutions {
                for condition in edge.conditions {
                    guard let metric = condition.knownMetric, !metric.isHealthMetric else { continue }
                    XCTAssertEqual(condition.window == .lifetime, metric == .careBattleCount
                                       || metric == .careBattleWinRatio,
                                   "\(id) -> \(edge.to): \(metric.rawValue) over \(condition.window)")
                }
            }
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

    /// No new lines for five new nodes, and three lines is as wide as five Champions spread.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["penc-ds"], 46,
                       "US-152 added Ebidramon and Gawappamon, US-153 Kinkakumon, "
                           + "plus US-158's Gusokumon, plus US-159's Hangyomon" + ", plus US-160's two, plus US-163's one Ultimate")
        XCTAssertEqual(sizes["tamers"], 117,
                       "US-152 added FlareLizamon and Growmon Orange; US-154 six more; "
                           + "US-156 two; plus US-158's four, plus US-159's five" + ", plus US-160's four, plus US-161's Rapidmon and SaintGalgomon, plus US-163's eight Ultimates")
        XCTAssertEqual(sizes["penc-vb"], 60,
                       "US-152 added GulusGammamon, US-153 KausGammamon, US-154 two more, "
                           + "US-156 two more, plus US-158's Entmon, plus US-161's Regulusmon, plus US-163's two Ultimates")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.adult)?.line }).count, 3)
    }

    /// **The variant rule.** Growmon Orange is the only variant among the five, and it needed no
    /// rehome at all: Wikimon draws it out of Guilmon and into Megalo Growmon, which is the plain
    /// Growmon's own thread, so the variant sits under its base form's own parent rather than
    /// merely on its base form's line.
    func testTheOneVariantSitsWithItsBaseForm() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "growmon_orange")).line,
                       try XCTUnwrap(graph.node(id: "growmon")).line)
        XCTAssertEqual(Set(graph.parents(of: "growmon_orange").map(\.id)),
                       Set(graph.parents(of: "growmon").map(\.id)),
                       "the variant does not hang off the same parent as its base form")
    }

    // MARK: - AC: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate.
    func testEveryNodeThisStoryAddedIsASliceableSheet() throws {
        for (id, _, _) in swept {
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

    /// Nothing on either end of a new edge is a Dex-only Digimon — the whole-file form of the check,
    /// since the validator's `edgeToDexOnlyNode` finding is what would fire.
    func testNoEdgeInTheFileTouchesADexOnlyDigimon() {
        for node in graph.nodes {
            for edge in node.evolutions {
                XCTAssertNotEqual(roster.entry(id: edge.to)?.dexOnly, true,
                                  "\(node.id) -> \(edge.to) reaches an idle-only Digimon")
            }
        }
    }

    // MARK: - AC: every choice is recorded in the data file

    /// Every node this story added carries a comment, and each one either cites Wikimon or says in
    /// as many words that it could not — the rule US-146 set and every sweep since has kept.
    func testEveryNodeThisStoryAddedCitesItsSourceOrSaysItCannot() throws {
        for (id, _, _) in swept {
            let comment = try authoredComment(on: id)
            XCTAssertTrue(comment.contains("Wikimon") || comment.contains("NO CITATION")
                            || comment.contains("no citation"),
                          "\(id)'s comment neither cites a source nor says it has none")
        }
    }

    /// The thread US-151 opened and left half-drawn, closed. MegaloGrowmon's own comment says Flare
    /// Lizamon was the second cited parent and that this story would be the one to wire it, so the
    /// claim is checked from BOTH ends: the arrow exists, and the node it comes from is the one the
    /// comment named.
    func testFlareLizamonClosesTheArrowUS151CouldOnlyDrawOneEndOf() throws {
        XCTAssertTrue(try authoredComment(on: "megalogrowmon").contains("Flare Lizamon"))
        XCTAssertTrue(graph.parents(of: "megalogrowmon").map(\.id).contains("flarelizamon"))
        XCTAssertTrue(graph.parents(of: "megalogrowmon").map(\.id).contains("darklizamon"),
                      "the other half of the same Wikimon arrow is gone")
        XCTAssertTrue(try authoredComment(on: "flarelizamon").contains("Dark Lizamon"))
    }

    /// Gawappamon's first-choice parent could not be used, and the reason is checkable rather than
    /// asserted: Kamemon is the bolded name in its Evolves From and is idle-only in this pack, which
    /// `edgeToDexOnlyNode` forbids. The fallback was the NEXT CITED parent rather than a rehome —
    /// the move US-150's notes prefer over inventing an argument from flavour.
    func testGawappamonTookTheNextCitedParentRatherThanARehome() throws {
        let comment = try authoredComment(on: "gawappamon")
        XCTAssertTrue(comment.contains("Kamemon"))
        XCTAssertEqual(roster.entry(id: "kamemon")?.dexOnly, true,
                       "Kamemon has an animated sheet after all, so it should be the parent")
        XCTAssertNil(graph.node(id: "kamemon"), "Kamemon is a node now, so this claim is stale")
        XCTAssertTrue(graph.parents(of: "gawappamon").map(\.id).contains("gomamon"))
    }

    /// Both ends of Ebidramon's and GulusGammamon's placements are arrows a DEVICE the app already
    /// models draws — Pendulum COLOR 2 Deep Savers and Pendulum COLOR ZERO Virus Busters — which is
    /// why neither needed a line argument at all. Asserted as the shape it produced: the parent and
    /// the target were BOTH already on the line before this story touched it.
    func testTheTwoDeviceCitedPlacementsLandedOnLinesThatAlreadyHeldBothEnds() throws {
        for (adult, parent, perfect) in swept where ["ebidramon", "gulusgammamon"].contains(adult) {
            let line = try XCTUnwrap(graph.node(id: adult)).line
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).line, line)
            XCTAssertEqual(try XCTUnwrap(graph.node(id: perfect)).line, line)
            XCTAssertTrue(try authoredComment(on: adult).contains("Pendulum COLOR"))
        }
    }

    // MARK: - AC: the orphan count, and the whole file still validates

    /// FIVE, counted with Appendix B of the PRD over a regenerated `roster.generated.json`:
    /// 319 before, 314 after; the Adult bucket falls 27 -> 22 and no other bucket moves, because
    /// this story spent no Perfect. Asserted rather than only noted, because the count is the one
    /// claim in `notes` a later reader cannot re-derive from the diff.
    func testTheFiveOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 5)

        for (id, _, _) in swept {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 851,
                       "610 before this story, 615 after it, 618 after US-153, 629 after US-154, "
                           + "635 after US-155, 643 after US-156, 672 after US-157, "
                           + "693 after US-158, 709 after US-159, 736 after US-160, 760 after US-161, 787 after US-162, 817 after US-163")
    }

    func testTheGraphValidatesWithNoFindings() {
        XCTAssertEqual(EvolutionGraph.bundled.validate().map(\.description), [])
    }

    // MARK: - Helpers

    /// A context that satisfies `edge`'s criteria, derived FROM the edge rather than shared — the
    /// helper US-151 wrote, kept because one of this story's edges asks for FEW overfeeds and a
    /// blanket "did everything right" context is the one thing that cannot take an `atMost`.
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
    /// helper US-144 through US-151 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
