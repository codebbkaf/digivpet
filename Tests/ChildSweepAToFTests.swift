import XCTest

@testable import DigiVPet

/// US-148 — the fifth of Phase E's orphan sweeps, and the A-F third of the Child rung.
///
/// **Which reading of the story's scope this takes.** The acceptance criteria ask for an in-edge
/// AND an out-edge on every Digimon in range. US-147 wired the whole Baby II rung and, in doing so,
/// gave thirty-nine Children an in-edge and left every one of them a leaf — so reading the scope as
/// "the orphans still listed when the story started" would have shipped nine A-F Children that lead
/// nowhere. The scope is the RUNG-AND-RANGE: every playable Child whose display name begins A-F
/// gets both edges, whether it was an orphan (fourteen were) or merely a dead end (nine were).
///
/// **What that costs one rung down, stated up front.** A Child's only possible parent is a Baby II,
/// so the only way to give an orphaned Child an in-edge is to branch a Baby II — the same move
/// US-147 had to make at Baby I, and the invariant it spends is the one US-147 wrote down. Nine
/// Baby II gained a second or third way up here.
///
/// **What it costs one rung UP.** Twenty-three Children need twenty-three Champions and, because
/// `EvolutionCriteriaTests` requires every branching Child to fall to a junk Champion on its own
/// line, six lines that had no Champion rung at all needed a junk floor first. All twenty-nine are
/// plain roster ids, so all twenty-nine remove an orphan; all twenty-nine are leaves until the
/// Adult sweeps, which is where the dead-end ledger now points.
final class ChildSweepAToFTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The fourteen Children that had no node at all before this story.
    private let authoredChildren = ["agumon_2006", "agumon_black", "agumon_black_x", "agumon_x",
                                    "alraumon", "armadimon", "clearagumon", "dokunemon", "dracomon",
                                    "dracomon_x", "dracumon", "ekakimon", "elecmon_violet",
                                    "funbeemon"]

    /// The nine US-147 opened as leaves and this story wired onward.
    private let wiredOnward = ["algomon_child", "arkadimon_child", "bearmon", "blackguilmon",
                               "blucomon", "commandramon", "coronamon", "dorumon", "fujamon"]

    /// The twenty-nine Champions this story authored, all of them leaves until US-151..US-153.
    private let authoredAdults = ["algomon_adult", "blackgrowmon", "coredramon_green", "damemon",
                                  "darktyranomon_x", "death-x-dorugamon", "dorugamon", "firamon",
                                  "geogreymon", "ginkakumon", "greymon_blue", "greymon_x",
                                  "growmon_x", "gryzmon", "guardromon_gold", "hi-commandramon",
                                  "madleomon", "manekimon", "mimicmon", "numemon_x", "paledramon",
                                  "sangloupmon", "sunflowmon", "togemon_x", "tortamon", "troopmon",
                                  "tsuchidarumon", "waspmon", "yanmamon"]

    /// The six lines that had no Champion rung before this story, and the junk floor each gained.
    /// A junk floor is not decoration: `EvolutionCriteriaTests` fails any branching Child whose
    /// `isDefault` edge does not land on a junk Champion, and `testNoEdgeCrossesALine` means it has
    /// to be one of the Child's OWN line.
    private let junkFloors: [(line: String, junk: String)] = [
        ("algomon", "mimicmon"),
        ("commandramon", "damemon"),
        ("diablomon", "troopmon"),
        ("penc-sw", "tsuchidarumon"),
        ("tamers", "numemon_x"),
        ("wanyamon", "manekimon"),
    ]

    /// The nine Baby II that gained a way up, and the Child each one bought.
    private let babyIIBranches: [(babyII: String, child: String)] = [
        ("wanyamon", "agumon_2006"),
        ("koromon", "agumon_black"),
        ("koromon", "dracomon"),
        ("tsunomon", "elecmon_violet"),
        ("tokomon_x", "agumon_x"),
        ("tokomon_x", "agumon_black_x"),
        ("tokomon_x", "dracomon_x"),
        ("upamon", "armadimon"),
        ("tanemon", "alraumon"),
        ("tanemon", "funbeemon"),
        ("budmon", "dokunemon"),
        ("budmon", "ekakimon"),
        ("gummymon", "clearagumon"),
        ("tsumemon", "dracumon"),
    ]

    /// The story's range, derived off the roster rather than listed, so a Child sprite added to the
    /// folder later lands IN scope and fails here. Twenty-nine playable Children are named A-F; six
    /// of them (Agumon, Angoramon, Bakumon, Candmon, Elecmon, Floramon) were already wired by a
    /// device tree, which is why the range and `sweptChildren` are different sets — coverage is
    /// claimed over the range, and SHAPE only over what this story authored.
    private var childrenInRange: [RosterEntry] {
        roster.entries.filter {
            $0.stage == .child && !$0.dexOnly
                && ("A"..."F").contains(String($0.displayName.prefix(1)).uppercased())
        }
    }

    /// The twenty-three this story is responsible for.
    private var sweptChildren: [String] { authoredChildren + wiredOnward }

    /// The shared "did everything right" context. The same one US-147 uses, so an edge authored
    /// against a metric outside it fails rather than shipping unreachable.
    private let met = ConditionContext(
        stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                           "health.activeEnergy": 50_000,
                                           "health.exerciseMinutes": 5_000,
                                           "health.sleep": 100_000]),
        trainingSessionsThisStage: 30,
        overfeedsThisStage: 0,
        sleepDisturbancesThisStage: 0,
        battlesLifetime: 20)

    // MARK: - AC1/AC2: every Digimon in range has an in-edge and an out-edge

    /// The headline claim, counted off the ROSTER rather than off the lists above.
    func testEveryPlayableChildAToFIsANodeWithAnInEdgeAndAnOutEdge() throws {
        XCTAssertEqual(childrenInRange.count, 29)
        XCTAssertEqual(sweptChildren.count, 23)
        XCTAssertEqual(Set(childrenInRange.map(\.id)).subtracting(sweptChildren),
                       ["agumon", "angoramon", "bakumon", "candmon", "elecmon", "floramon"],
                       "the six A-F Children a device tree had already wired have changed")

        for entry in childrenInRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
            XCTAssertFalse(node.evolutions.isEmpty,
                           "\(node.id) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoChildAToFIsStillAnOrphan() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)
        let orphans = childrenInRange.map(\.id).filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "Children A-F still orphaned: \(orphans)")
    }

    /// Every Child in range is fed by a Baby II and nothing else. The second half is what stops the
    /// first from being satisfied by a skipped rung: a Child fed by a Baby I would have a parent,
    /// and `EvolutionGraphValidator`'s stage check would report it — but only if anyone ran it over
    /// a graph where such an edge existed, which is the point of asserting it here.
    func testEveryChildInRangeIsFedByABabyII() throws {
        for entry in childrenInRange {
            for parent in graph.parents(of: entry.id) {
                XCTAssertEqual(parent.stage, .babyII, "\(entry.id) is fed by a non-Baby II")
            }
        }
    }

    /// The twenty-nine Champions this story authored are real, playable, and on the line of the
    /// Child that reaches them.
    func testEveryChampionThisSweepAuthoredIsPlayableAndOnItsParentsLine() throws {
        XCTAssertEqual(authoredAdults.count, 29)
        for id in authoredAdults {
            let node = try XCTUnwrap(graph.node(id: id), "no node \(id)")
            XCTAssertEqual(node.stage, .adult, "\(id) is authored at the wrong rung")
            let entry = try XCTUnwrap(roster.entry(id: id), "\(id) is not a roster id")
            XCTAssertEqual(node.spriteFile, entry.spriteFile, "\(id) names art the roster does not")
            XCTAssertFalse(entry.dexOnly, "\(id) is one of the idle-only Digimon")

            let parents = graph.parents(of: id)
            XCTAssertFalse(parents.isEmpty, "\(id) was authored with no in-edge")
            for parent in parents {
                XCTAssertEqual(parent.line, node.line, "\(id) is not on \(parent.id)'s line")
                XCTAssertEqual(parent.stage, .child, "\(id) is fed by something that is not a Child")
            }
        }
    }

    // MARK: - AC: the in-edges, which cost a Baby II its shape

    /// **The invariant this story spends, and the proof it had to.** Fourteen Children had no parent
    /// and nothing but a Baby II may point at a Child, so nine Baby II gained an extra branch. This
    /// test is what keeps that from becoming a habit: every extra branch on one of those nine leads
    /// to one of the fourteen, so none was authored for convenience.
    func testEveryBabyIIThatBranchesForThisSweepDoesSoForAnOrphan() throws {
        for (babyII, child) in babyIIBranches {
            let node = try XCTUnwrap(graph.node(id: babyII), "no node \(babyII)")
            XCTAssertEqual(node.stage, .babyII)
            XCTAssertTrue(node.evolutions.contains { $0.to == child },
                          "\(babyII) does not branch to \(child)")
        }
        // Nothing outside the fourteen was hung on a Baby II by this story: every target of every
        // branch these nine carry is either one of the fourteen or a Child that was already there.
        let mine = Set(babyIIBranches.map(\.child))
        XCTAssertEqual(mine, Set(authoredChildren),
                       "a Child was authored without an in-edge, or a branch bought nothing")
    }

    /// A branch into a new Child is EARNED and hinted, and the Baby II's fallback is untouched.
    func testEveryNewBabyIIBranchIsEarnedAndLeavesTheFallbackAlone() throws {
        for (babyII, child) in babyIIBranches {
            let node = try XCTUnwrap(graph.node(id: babyII))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == child })
            XCTAssertFalse(edge.isDefault, "\(babyII) -> \(child) is the fallback")
            XCTAssertFalse(edge.conditions.isEmpty, "\(babyII) -> \(child) is unconditional")
            for condition in edge.conditions {
                XCTAssertFalse(condition.hint.isEmpty,
                               "\(babyII) -> \(child) has a criterion the player cannot discover")
            }
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(babyII) no longer has exactly one fallback")
        }
    }

    /// The engine's view of the same thing: a Baby II that met the branch's energy AND its criteria
    /// really reaches the new Child, rather than the edge merely existing.
    func testEachNewBabyIIBranchIsTakenByTheEngineWhenItIsEarned() throws {
        for (babyII, child) in babyIIBranches {
            let node = try XCTUnwrap(graph.node(id: babyII))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == child })
            let energy = try XCTUnwrap(edge.requiredEnergy, "\(babyII) -> \(child) has no energy")
            var totals = EnergyTotals()
            totals[energy] = edge.minEnergy
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals, dominant: energy,
                                                careMistakes: 0, battleWins: 0, conditions: met),
                child,
                "a well-raised \(energy.rawValue) \(babyII) does not reach \(child)")
        }
    }

    // MARK: - AC: the out-edges

    /// Every Child in range branches: one earned Champion, conditioned and hinted, and one junk
    /// fallback that carries no criteria at all.
    ///
    /// A condition on a fallback would be data that lies — US-020 takes the `isDefault` edge exactly
    /// when nothing else qualifies, so its own criteria are never consulted. That is why "no edge is
    /// unconditional" is read here as "no edge a player has to EARN is unconditional", the same
    /// reading US-144, US-146 and US-147 recorded for the rungs below.
    ///
    /// **Scoped rather than relaxed in US-152**, the way US-151 scoped the same claim in the G-L and
    /// M-Z files: "exactly two edges" was a claim about what THIS story authored, and a later sweep
    /// hanging a second Champion off one of these Children falsifies it without doing anything
    /// wrong — US-152 hung FlareLizamon off ClearAgumon, an arrow Wikimon draws. So the count is a
    /// named exception list: a Child of this story that grows a third earned branch nobody wrote
    /// down still fails here.
    func testEveryChildInRangeHasOneEarnedBranchAndOneUnconditionedFallback() throws {
        let branchedByALaterSweep = ["agumon_x": 3, "blucomon": 3, "clearagumon": 3, "dorumon": 3]

        for id in sweptChildren {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(node.evolutions.count, branchedByALaterSweep[id] ?? 2,
                           "\(node.id) is not a branch plus a fallback")
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(node.id) has no single fallback")

            let fallback = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertEqual(fallback.conditions, [], "\(node.id)'s fallback carries criteria")
            XCTAssertEqual(fallback.minEnergy, 0, "\(node.id)'s fallback demands energy")

            let earned = try XCTUnwrap(node.evolutions.first { !$0.isDefault })
            XCTAssertFalse(earned.conditions.isEmpty,
                           "\(node.id) -> \(earned.to) is gated on energy alone")
            for condition in earned.conditions {
                XCTAssertFalse(condition.hint.isEmpty,
                               "\(node.id) -> \(earned.to) has an undiscoverable criterion")
            }
            XCTAssertGreaterThan(earned.minEnergy, fallback.minEnergy,
                                 "\(node.id)'s junk edge would win the branch outright")
        }
    }

    /// Every earned branch out of a Child in range is really reachable through the engine, criteria
    /// and all — the check that separates an authored edge from a taken one.
    func testEveryEarnedChildBranchIsTakenByTheEngineWhenItIsEarned() throws {
        for id in sweptChildren {
            let node = try XCTUnwrap(graph.node(id: id))
            let edge = try XCTUnwrap(node.evolutions.first { !$0.isDefault })
            let energy = try XCTUnwrap(edge.requiredEnergy)
            var totals = EnergyTotals()
            totals[energy] = edge.minEnergy
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals, dominant: energy,
                                                careMistakes: 0, battleWins: 0, conditions: met),
                edge.to,
                "\(node.id) does not reach \(edge.to) on the energy its own edge asks for")
        }
    }

    /// And a neglected one falls to junk instead. Read through `scheduledEvolutionTarget` with the
    /// gate open and an EMPTY context, which is what "the owner did nothing" actually looks like.
    func testANeglectedChildInRangeFallsToItsLinesJunkChampion() throws {
        for entry in childrenInRange {
            let node = try XCTUnwrap(graph.node(id: entry.id))
            let fallback = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertEqual(
                EvolutionEngine.scheduledEvolutionTarget(
                    for: node, stageEnergy: EnergyTotals(), dominant: nil, careMistakes: 9,
                    battleWins: 0, stageEnteredAt: .distantPast, now: Date(),
                    conditions: .unknown),
                fallback.to,
                "a neglected \(node.id) does not fall to \(fallback.to)")
        }
    }

    // MARK: - AC: lines are grouped coherently

    /// No edge in the file crosses a line, still. It held for all 454 nodes before this story:
    /// a Champion that could not be put on the line of the Child below it has been paired with the
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

    /// The criterion is that a sweep must not produce dozens of one-node lines, and the answer here
    /// is NO new lines at all for forty-three new nodes. An in-edge forces the line, so a Child sits
    /// on its Baby II's line and a Champion on its Child's — flavour never gets a vote.
    func testTheSweepOpenedNoNewLines() {
        let lines = Set(graph.nodes.map(\.line))
        XCTAssertEqual(lines.count, 21)
        for id in authoredChildren + authoredAdults {
            XCTAssertTrue(lines.contains(graph.node(id: id)?.line ?? ""),
                          "\(id) is on a line of its own")
        }
        // Eleven of the twenty-one grew, and the two biggest by six and eight — the shape of
        // grouping rather than of a chain per Digimon. The sizes are the FILE's, not this story's,
        // so US-149's sixteen new `tamers` nodes and eight new `dmc-v3` ones are in them.
        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        // These are the FILE's sizes, not this story's, so every later sweep is in them too:
        // US-150 added ten to `tamers`, three to `dmc-v3`, eleven to `vital`, three to `xros`
        // and two to `palmon`.
        XCTAssertEqual(sizes["tamers"], 99,
                       "US-152 put FlareLizamon and Growmon Orange under this line's Perfect rung, "
                           + "US-156 Youkomon and BlackRapidmon, plus US-158's four, plus US-159's five")
        XCTAssertEqual(sizes["dmc-v3"], 48)
        XCTAssertEqual(sizes["palmon"], 28, "US-159's Lilamon and Lilimon X")
    }

    /// **The variant rule, and the honest version of it.** The criteria say a variant hangs off its
    /// base form's line. That is what happened wherever the base form's In-Training had a free
    /// energy — but a Baby II can carry at most four branches, one per energy, so where it did not
    /// the variant went to the variant THREAD instead: the three X-Antibody Children all hang off
    /// the Tokomon X that US-147 opened on dmc-v3. Either way no variant is alone, which is what
    /// the rule is protecting. All of it is asserted off the file rather than trusted to a comment.
    func testEveryVariantSitsWithItsBaseFormOrWithItsVariantThread() throws {
        // Base form's own line, wherever the base form's In-Training had room.
        for (variant, base) in [("agumon_black", "agumon"), ("elecmon_violet", "elecmon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line,
                           "\(variant) is not on \(base)'s line")
        }

        // The X-Antibody thread: all three X-Antibody Children hang off Tokomon X together rather
        // than being scattered one per line, and Tokomon X is now full at four energies.
        let tokomonX = try XCTUnwrap(graph.node(id: "tokomon_x"))
        XCTAssertEqual(Set(tokomonX.evolutions.map(\.to)),
                       ["sistermon_blanc", "agumon_x", "agumon_black_x", "dracomon_x"])
        XCTAssertEqual(Set(tokomonX.evolutions.compactMap { $0.requiredEnergy?.rawValue }).count, 4)
        for id in ["agumon_x", "agumon_black_x", "dracomon_x"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "dmc-v3")
        }
        // Dracomon X is the case that proves the thread beat the base form: its own base, Dracomon,
        // went to dmc-v1 in this same story, and Wikimon names Tokomon (X-Antibody) as its parent.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "dracomon")).line, "dmc-v1")
        XCTAssertTrue(try authoredComment(on: "dracomon_x").contains("Tokomon (X-Antibody)"))

        // Agumon 2006 is the third case: Koromon is full, so it went to the line of the
        // In-Training Wikimon actually names for it.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "agumon_2006")).line, "wanyamon")
        XCTAssertTrue(try XCTUnwrap(graph.node(id: "wanyamon")).evolutions
            .contains { $0.to == "agumon_2006" })

        // And every variant's own Champion followed it, so no line holds half a thread.
        for (child, adult) in [("agumon_x", "greymon_x"), ("agumon_black_x", "darktyranomon_x"),
                               ("dracomon_x", "growmon_x"), ("agumon_black", "greymon_blue"),
                               ("agumon_2006", "geogreymon"), ("elecmon_violet", "madleomon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: adult)).line,
                           try XCTUnwrap(graph.node(id: child)).line)
        }
    }

    /// The six junk floors, each on the line it serves, each reachable by doing nothing, and each
    /// the fallback of every branching Child of that line — which is what makes it the line's junk
    /// branch rather than one more Champion.
    func testEachLineThatHadNoChampionRungGainedAJunkFloor() throws {
        for (line, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: junk), "no node \(junk)")
            XCTAssertEqual(node.line, line, "\(junk) is not on \(line)")
            XCTAssertEqual(node.stage, .adult)

            let branching = graph.nodes.filter {
                $0.line == line && $0.stage == .child && !$0.evolutions.isEmpty
            }
            XCTAssertFalse(branching.isEmpty, "\(line) has no branching Child to need a floor")
            for child in branching {
                XCTAssertEqual(child.evolutions.first(where: \.isDefault)?.to, junk,
                               "\(child.id) does not fall to \(line)'s junk Champion")
            }
        }
        // Before this story none of the six lines had a single Champion; that is why each needed
        // one. That claim WAS checkable from the shipped file — every Adult on each of the six was
        // one this story authored — and it stopped being so in US-149, which hung sixteen more
        // Champions on `tamers` and more on four of the other five. A historical claim cannot be
        // re-derived from a file a later story has written to, so what is asserted now is the half
        // that stays true of the data: each floor is one THIS story authored, and it is an Adult of
        // the line it serves. The "there was nothing here before" half lives in the notes.
        for (line, junk) in junkFloors {
            let adults = graph.nodes.filter { $0.line == line && $0.stage == .adult }.map(\.id)
            XCTAssertTrue(adults.contains(junk))
            XCTAssertTrue(authoredAdults.contains(junk),
                          "\(line)'s junk floor is not one this story authored")
        }
    }

    /// The Saiyu Warriors claim US-146 made about `penc-sw` still holds now that the rung above its
    /// Children exists: every Digimon on the line names the device in its comment.
    func testTheTwoNewSaiyuWarriorsChampionsStillNameTheirDevice() throws {
        for id in graph.nodes.filter({ $0.line == "penc-sw" }).map(\.id) {
            XCTAssertTrue(try authoredComment(on: id).contains("Saiyu Warriors"),
                          "\(id) is on the Saiyu Warriors line without saying so")
        }
    }

    // MARK: - AC: the data the story rests on

    /// Every node this story added names art that exists, at the stage the ROSTER files it under.
    /// The validator checks the first half; this checks the second, which is the one that bites —
    /// `import_roster.py` reads a Digimon's rung off its sprite FOLDER, so a node authored at the
    /// wrong stage resolves to no art at all.
    func testEveryNodeThisSweepAddedAgreesWithTheRoster() throws {
        for id in authoredChildren + authoredAdults {
            let node = try XCTUnwrap(graph.node(id: id), "no node \(id)")
            let entry = try XCTUnwrap(roster.entry(id: id), "\(id) is not a roster id")
            XCTAssertEqual(node.stage, entry.stage, "\(id) is authored at the wrong rung")
            XCTAssertEqual(node.displayName, entry.displayName)
            XCTAssertEqual(node.spriteFile, entry.spriteFile, "\(id) names art the roster does not")
            XCTAssertFalse(entry.dexOnly, "\(id) is one of the 157 idle-only Digimon")
        }
    }

    /// Every node slices as a real 48x64 sheet. Stronger than "the file exists": an idle-only 16x16
    /// sprite fails here rather than shipping as a Digimon that cannot animate.
    func testEveryNodeThisSweepAddedIsASliceableSheet() throws {
        for id in authoredChildren + authoredAdults {
            let node = try XCTUnwrap(graph.node(id: id))
            let sheet = try XCTUnwrap(
                SpriteSheetCache.shared.sheet(stage: node.stage.rawValue, name: node.spriteFile),
                "\(id): \(node.stage.rawValue)/\(node.spriteFile) is not a sliceable sheet")
            XCTAssertEqual(sheet.kind, .stage, id)
        }
    }

    /// The sweep had no document to copy, so every node it added cites Wikimon in its `comment` —
    /// except the seven that have nothing to cite, which say FLAVOUR or REHOME instead. A comment
    /// that cites nothing is the shape of an invented evolution.
    func testEveryNodeThisSweepAddedCitesItsSourceOrSaysItCannot() throws {
        let uncited = ["ekakimon", "elecmon_violet", "agumon_black_x", "sunflowmon", "manekimon",
                       "mimicmon", "troopmon", "damemon", "tsuchidarumon", "numemon_x",
                       "death-x-dorugamon"]
        for id in authoredChildren + authoredAdults {
            let comment = try authoredComment(on: id)
            if uncited.contains(id) {
                XCTAssertTrue(comment.contains("FLAVOUR") || comment.contains("REHOME"),
                              "\(id) has nothing to cite and does not say so")
            } else {
                XCTAssertTrue(comment.contains("Wikimon"),
                              "\(id) is authored without naming where the arrow comes from")
            }
        }
    }

    /// The pairings that are NOT a Wikimon arrow are the story's weak spot — a stand-in is the one
    /// thing a later reader cannot tell from a shortcut — so each says what it could not use, and
    /// each stated fact about the roster or the graph is CHECKED here rather than merely read.
    func testEveryUncitedPairingSaysWhatItCouldNotUse() throws {
        // Elecmon Violet's one cited parent is full: Pyocomon already carries all four energies,
        // and there is no fifth.
        let pyocomon = try XCTUnwrap(graph.node(id: "pyocomon"))
        XCTAssertEqual(Set(pyocomon.evolutions.compactMap { $0.requiredEnergy?.rawValue }).count, 4,
                       "Pyocomon has a free energy after all, so Elecmon Violet had a choice")
        XCTAssertTrue(try authoredComment(on: "elecmon_violet").contains("Pyocomon"))

        // BlackAgumon X's two cited In-Training are Koromon, whose four energies are spent, and
        // Yarmon, which has no node.
        let koromon = try XCTUnwrap(graph.node(id: "koromon"))
        XCTAssertEqual(Set(koromon.evolutions.compactMap { $0.requiredEnergy?.rawValue }).count, 4)
        XCTAssertNil(graph.node(id: "yarmon"))
        XCTAssertTrue(try authoredComment(on: "agumon_black_x").contains("Yarmon"))

        // Arkadimon's own Champion rung exists on disk but is idle-only, which is the whole reason
        // its Child needed a stand-in.
        XCTAssertEqual(roster.entry(id: "arkadimon_adult")?.dexOnly, true,
                       "Arkadimon Adult is playable after all, so it should be the edge")
        XCTAssertTrue(try authoredComment(on: "death-x-dorugamon").contains("idle-only"))

        // Ekakimon is the one Digimon here with no named partner in either direction on its own
        // page, and its Champion inherits that.
        for id in ["ekakimon", "sunflowmon"] {
            XCTAssertTrue(try authoredComment(on: id).contains("Digimon Card Game"),
                          "\(id) does not say why nothing could be cited")
        }
    }

    // MARK: - The dead-end ledger, moved up one rung

    /// **The handover to US-149, and the list it should edit.** Before US-144 the file had ZERO
    /// nodes below Ultimate with no way onward; a sweep that authors one rung at a time cannot keep
    /// that, because a rung has to exist before the rung above it does. US-147 left the ledger at
    /// Child; US-148 pays off the A-F ninth of it and refills it at Adult, so the ledger moves here.
    ///
    /// It fails in BOTH directions on purpose: a ninety-sixth dead end fails it, and so does wiring
    /// one of the ninety-five onward. US-149 paid off its fourteen Children and refilled the Adult
    /// half with thirty-three more; **US-150 emptied the Child half entirely** — there is no Child
    /// anywhere in the file with no way onward any more — and refilled the Adult half with
    /// thirty-three of its own. US-151..US-156 shrink what is left, and each is told to edit this
    /// rather than having to notice.
    func testTheOnlyDeadEndsBelowUltimateAreTheOnesTheSweepsHaveOpened() throws {
        let deadEnds = graph.nodes
            .filter { $0.evolutions.isEmpty && $0.stage != .ultimate }
            .map(\.id)
            .sorted()

        // US-150 wired all sixteen of the Children that stood here, so the Child half is gone.
        // It is kept as an empty list rather than deleted because the ledger's other direction
        // still matters: a Child left as a leaf by a later story lands here.
        let childrenLeftForUS150: [String] = []
        XCTAssertEqual(deadEnds.filter { graph.node(id: $0)?.stage == .child }, [],
                       "no Child anywhere in the file may lead nowhere after US-150")

        // The thirty-three Champions US-149 authored, all leaves until the Adult sweeps.
        let championsFromUS149 =
            ["allomon_x", "arresterdramon", "betelgammamon", "blackgalgomon", "dinohumon",
             "dobermon", "fugamon", "galgomon", "gaogamon", "garurumon_black", "greymon_2010",
             "growmon", "gururumon", "icedevimon", "icemon", "igamon", "jazardmon", "kokeshimon",
             "kuwagamon_x", "lekismon", "leomon_x", "lianpumon", "ogremon_x", "peckmon", "pidmon",
             "sandyanmamon", "siesamon", "soulmon", "targetmon", "tialudomon", "tylomon_x",
             "witchmon", "wizarmon_x"]

        // The thirty-three Champions US-150 authored, all leaves until the Adult sweeps.
        let championsFromUS150 =
            [
             "baboongamon", "chamblemon", "cockatrimon", "coredramon_blue", "dogmon",
             "dorulumon", "gekomon", "ginryumon", "hakubamon", "hookmon", "hyougamon",
             "junglemojyamon", "kyubimon", "kyubimon_silver", "lavorvomon", "mantaraymon_x",
             "meicoomon", "nisedrimogemon", "omekamon", "parasaurmon", "porcupamon",
             "raptordramon", "reppamon", "rhinomon_x", "seadramon_x", "shoutmon_king",
             "sorcerymon", "starmon", "tailmon_x", "tenkomon", "tobiumon", "tobucatmon",
             "xv-mon"
            ]

        // US-151 wired none of the ninety-five onward — its range was the seven Champions with
        // NO edge at all, which are not on this list because they never were dead ends. What it
        // DID add is the rung above: four Perfect leaves, two of them the junk floors `wanyamon`
        // and `tamers` needed before any Champion of either could branch at all. They are held
        // here rather than in a list of their own so that the ledger stays the file's single
        // answer to "what leads nowhere", and so that wiring one of them onward fails here.
        //
        // US-152 moved this ledger not at all, and that is the check rather than a footnote: its
        // five Champions were orphans rather than leaves, and every one of them landed on a Perfect
        // that already existed, so it neither cleared a dead end nor opened one.
        let perfectsFromUS151 =
            ["blackmachgaogamon", "catchmamemon", "karakurumon", "megalogrowmon"]

        // US-154 is the first Adult sweep since US-151 to move it, and it moves it UP: four of its
        // nine Champions are X-Antibody Digimon whose every cited Perfect was a sheet with no node,
        // so two had to be opened — and each serves TWO of the four, which is why the bill is two
        // rather than four. Grademon is cited by Meramon X and Pegasmon X off Digital Monster X
        // Ver.3; Mametyramon by Monochromon X and Pteranomon X off the two sides of Bx-43. Neither
        // needed a junk floor: US-151 already put CatchMamemon under `tamers`.
        let perfectsFromUS154 = ["grademon", "mametyramon"]

        // US-155 moves it up by ONE, and the one is the cheapest a rung above can be: four of its
        // five Champions landed on a Perfect that already existed, and only Tyranomon X had no
        // cited Perfect its own line could reach. Metal Greymon X is drawn from Tyranomon X alone —
        // Greymon X, the obvious second parent, is itself still on this list and stays there.
        let perfectsFromUS155 = ["metalgreymon_x"]

        // US-156 finished the Adult rung and moves the ledger up by three, one per line that had
        // no node for the Champion's cited Perfect: Canoweissmon for WezenGammamon, Huankunmon for
        // Xiquemon, BlackRapidmon for Youkomon. Its other two Champions cost nothing at all —
        // both Black V-dramon landed on AeroV-dramon, which has had parents since US-141. Each of
        // the three is drawn from exactly one Champion, and the obvious second parent of each is
        // itself still on this list (Gammamon's own arrow to Canoweissmon cannot be drawn — it is
        // full — while Galgomon and the `penc-sw` reading of Xiquemon are the Perfect sweeps').
        let perfectsFromUS156 = ["blackrapidmon", "canoweissmon", "huankunmon"]

        // **US-157 IS THE FIRST STORY TO MOVE THIS LEDGER DOWN, AND THAT IS WHAT A PERFECT SWEEP
        // IS FOR.** Every Perfect it authored needed a Champion beneath it, and nine of the
        // nineteen it chose were LEAVES sitting on this list — so wiring them onward paid off nine
        // of the debts the Champion sweeps ran up. It adds exactly one back: Pandamon, the junk
        // floor `penc-sw` needed before Hakubamon could branch at all. Net 105 -> 97.
        let clearedByUS157 = ["blackgrowmon", "hakubamon", "icedevimon", "lekismon", "paledramon",
                              "porcupamon", "raptordramon", "tailmon_x", "waspmon"]
        let perfectsFromUS157 = ["pandamon"]

        // **US-158 MOVES IT DOWN AGAIN AND ADDS NOTHING BACK**, which US-157 could not manage: it
        // needed a junk floor for `penc-sw` and this story needed none, because all seven of its
        // leaf Champions fall to a junk Perfect that already existed. Seven more of the Champion
        // sweeps' debts paid off, net 97 -> 90. Two of the seven are `wanyamon`'s last leaf
        // Champions, which is what let that line's first Ultimates be authored over them.
        let clearedByUS158 = ["cockatrimon", "dorugamon", "firamon", "gaogamon", "ginkakumon",
                              "gryzmon", "starmon"]

        // **US-159 IS THE BIGGEST FALL YET AND IT ALSO ADDS NOTHING BACK**: NINE of its eleven
        // Perfects hang off a leaf Champion, and every junk floor those nine needed already existed
        // (Locomon, Darumamon twice, CatchMamemon three times, Karakurumon, Jyagamon twice), so
        // `EvolutionCriteriaTests.junkIds` did not move for the second story running. Net 90 -> 81.
        // Two of the nine are JUNK Champions with an earned branch — Numemon X and, one rung down
        // the same idea, the Scumon US-133 recorded — which is the arrangement that let the Terrier
        // Digitama reach a Mega at last.
        let clearedByUS159 = ["icemon", "igamon", "jazardmon", "kyubimon", "lavorvomon",
                              "numemon_x", "omekamon", "sunflowmon", "togemon_x"]
        let cleared = clearedByUS157 + clearedByUS158 + clearedByUS159

        XCTAssertEqual(deadEnds,
                       (childrenLeftForUS150 + authoredAdults + championsFromUS149
                           + championsFromUS150 + perfectsFromUS151 + perfectsFromUS154
                           + perfectsFromUS155 + perfectsFromUS156 + perfectsFromUS157)
                           .filter { !cleared.contains($0) }.sorted(),
                       "the dead-end ledger has drifted")
        XCTAssertEqual(deadEnds.count, 81)

        // And the twenty-five really did leave because they lead somewhere now, not because they
        // vanished.
        for id in cleared {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: id)).evolutions.isEmpty,
                           "\(id) is a dead end again — then it belongs back on the ledger")
        }
    }

    // MARK: - AC: the orphans this story removed

    /// FORTY-THREE, counted with Appendix B of the PRD over a regenerated `roster.generated.json`:
    /// 475 before, 432 after. Asserted rather than only noted, because the count is the one claim in
    /// `notes` a later reader cannot re-derive from the diff.
    ///
    /// Every one of the forty-three carries a plain roster id — there is not a single line-scoped
    /// alias in this story, which is why new nodes and orphans removed are the same number for the
    /// first time since US-135.
    func testTheFortyThreeOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        let removed = authoredChildren + authoredAdults
        XCTAssertEqual(removed.count, 43)

        for id in removed {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 709,
                       "454 before this story, 497 after it, 548 after US-149, 599 after US-150, "
                           + "610 after US-151, 615 after US-152, 618 after US-153, "
                           + "635 after US-155, 643 after US-156, 672 after US-157, "
                           + "693 after US-158, 709 after US-159")
    }

    // MARK: - The whole file still validates

    func testTheGraphValidatesWithNoFindings() {
        let errors = EvolutionGraph.bundled.validate()
        XCTAssertEqual(errors.map(\.description), [])
    }

    // MARK: - Helpers

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-147 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
