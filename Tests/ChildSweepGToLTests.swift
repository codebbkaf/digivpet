import XCTest

@testable import DigiVPet

/// US-149 — the sixth of Phase E's orphan sweeps, and the G-L third of the Child rung.
///
/// **Which reading of the story's scope this takes.** The acceptance criteria ask for an in-edge AND
/// an out-edge on every Digimon in range, and US-147 left fourteen G-L Children with the first and
/// not the second. So the scope is the RUNG-AND-RANGE, the same reading US-148 recorded: every
/// playable Child whose display name begins G-L gets both edges, whether it was an orphan (eighteen
/// were) or merely a dead end (fourteen were).
///
/// **What that costs one rung down.** A Child's only possible parent is a Baby II, so eighteen
/// orphans meant branching Baby II — fifteen of them, across nine lines. The four-energy ceiling
/// (`BabyIISweepTests.testEachBabyIIsBranchesAskForADifferentEnergy`) is what decided several of
/// the placements rather than flavour, and each one that could not go to its first-choice parent
/// says so in its own `comment`.
///
/// **What it costs one rung UP.** Thirty-two Children need a Champion each and a junk fallback on
/// their own line, and `xros` and `vital` were the last two lines with no Champion rung at all — so
/// each needed a junk floor invented first. Thirty-three Champions in total, every one a plain
/// roster id, so every one removes an orphan; all thirty-three are leaves until the Adult sweeps.
final class ChildSweepGToLTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The eighteen Children that had no node at all before this story.
    private let authoredChildren = ["gabumon_black", "gabumon_x", "gammamon", "gaossmon", "gasamon",
                                    "gazimon_x", "gomamon_x", "gotsumon", "guilmon_x", "hackmon",
                                    "hanimon", "impmon_x", "jazamon", "keramon_x", "kokabuterimon",
                                    "kokuwamon_x", "lopmon_x", "lucemon"]

    /// The fourteen US-147 opened as leaves and this story wired onward.
    private let wiredOnward = ["gaomon", "ghostmon", "guilmon", "gumdramon", "impmon", "kakamon",
                               "keramon", "koemon", "labramon", "lalamon", "lopmon", "ludomon",
                               "lunamon", "xros_hagurumon"]

    /// The thirty-three Champions this story authored, all of them leaves until US-151..US-153.
    private let authoredAdults = ["allomon_x", "arresterdramon", "betelgammamon", "blackgalgomon",
                                  "dinohumon", "dobermon", "fugamon", "galgomon", "gaogamon",
                                  "garurumon_black", "greymon_2010", "growmon", "gururumon",
                                  "icedevimon", "icemon", "igamon", "jazardmon", "kokeshimon",
                                  "kuwagamon_x", "lekismon", "leomon_x", "lianpumon", "ogremon_x",
                                  "peckmon", "pidmon", "sandyanmamon", "siesamon", "soulmon",
                                  "targetmon", "tialudomon", "tylomon_x", "witchmon", "wizarmon_x"]

    /// The two lines that had no Champion rung before this story, and the junk floor each gained.
    /// Only `adventure02` is left after them, and it is US-150's — see
    /// `testTheLastTwoLinesWithoutAChampionRungGainedAJunkFloor`.
    private let junkFloors: [(line: String, junk: String)] = [
        ("vital", "kokeshimon"),
        ("xros", "targetmon"),
    ]

    /// The fifteen Baby II that gained a way up, and the Child each one bought. Three of them
    /// (Cupimon, Chocomon, Onibimon) bought two, which is why the list is eighteen long.
    private let babyIIBranches: [(babyII: String, child: String)] = [
        ("tsunomon", "gabumon_black"),
        ("tokomon", "gabumon_x"),
        ("hiyarimon", "gammamon"),
        ("pickmon", "gaossmon"),
        ("onibimon", "gasamon"),
        ("pagumon", "gazimon_x"),
        ("upamon", "gomamon_x"),
        ("petimeramon", "gotsumon"),
        ("gigimon", "guilmon_x"),
        ("cupimon", "hackmon"),
        ("onibimon", "hanimon"),
        ("yaamon", "impmon_x"),
        ("chocomon", "jazamon"),
        ("tsumemon", "keramon_x"),
        ("mochimon", "kokabuterimon"),
        ("kozenimon", "kokuwamon_x"),
        ("chocomon", "lopmon_x"),
        ("cupimon", "lucemon"),
    ]

    /// The story's range, derived off the roster rather than listed, so a Child sprite added to the
    /// folder later lands IN scope and fails here. Forty-three playable Children are named G-L;
    /// twelve of them were already wired end to end by a device tree, which is why the range and
    /// `sweptChildren` are different sets — coverage is claimed over the RANGE, and shape only over
    /// what this story authored.
    ///
    /// The range is also two SHORTER than the graph's G-L Child rung, and the reason is the split
    /// US-146 wrote down: `pencvb_gabumon` and `xros_hagurumon` are line-scoped aliases with no
    /// roster entry of their own, so iterating roster entries cannot see them. Hagurumon is one of
    /// the fourteen this story wired onward, which is why `sweptChildren` is not a subset of the
    /// range — `testTheXrosLoadersHagurumonIsSweptEvenThoughItIsAnAlias` covers it directly.
    private var childrenInRange: [RosterEntry] {
        roster.entries.filter {
            $0.stage == .child && !$0.dexOnly
                && ("G"..."L").contains(String($0.displayName.prefix(1)).uppercased())
        }
    }

    /// The thirty-two this story is responsible for.
    private var sweptChildren: [String] { authoredChildren + wiredOnward }

    /// The shared "did everything right" context, the same one US-147 and US-148 use, so an edge
    /// authored against a metric outside it fails here rather than shipping unreachable.
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
    func testEveryPlayableChildGToLIsANodeWithAnInEdgeAndAnOutEdge() throws {
        XCTAssertEqual(childrenInRange.count, 43)
        XCTAssertEqual(sweptChildren.count, 32)
        XCTAssertEqual(Set(childrenInRange.map(\.id)).subtracting(sweptChildren),
                       ["gabumon", "ganimon", "gazimon", "gizamon", "gomamon", "hagurumon",
                        "herissmon", "hyokomon", "jellymon", "junkmon", "kokuwamon", "kunemon"],
                       "the twelve G-L Children a device tree had already wired have changed")

        for entry in childrenInRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
            XCTAssertFalse(node.evolutions.isEmpty,
                           "\(node.id) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The one Child this story swept that the roster cannot see. `xros_hagurumon` is US-146's
    /// line-scoped alias — the Xros Loader line's Hagurumon, on the same art as the Metal Empire
    /// line's — so it has a node and a display name in range but no roster entry, and the
    /// coverage loop above skips it. Checked here directly rather than left to the reader.
    func testTheXrosLoadersHagurumonIsSweptEvenThoughItIsAnAlias() throws {
        let node = try XCTUnwrap(graph.node(id: "xros_hagurumon"))
        XCTAssertNil(roster.entry(id: "xros_hagurumon"), "it is a roster entry after all")
        XCTAssertEqual(node.displayName, "Hagurumon")
        XCTAssertEqual(node.line, "xros")
        XCTAssertFalse(graph.parents(of: node.id).isEmpty)
        XCTAssertFalse(node.evolutions.isEmpty, "the alias was left a leaf")
        // Same for the Virus Busters' Gabumon, which is in range and was NOT this story's: it has
        // been wired since US-143, so the alias split does not hide an unswept Child.
        XCTAssertNil(roster.entry(id: "pencvb_gabumon"))
        XCTAssertFalse(try XCTUnwrap(graph.node(id: "pencvb_gabumon")).evolutions.isEmpty)
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoChildGToLIsStillAnOrphan() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)
        let orphans = childrenInRange.map(\.id).filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "Children G-L still orphaned: \(orphans)")
    }

    /// Every Child in range is fed by a Baby II and nothing else — the half that stops the first
    /// claim from being satisfied by a skipped rung.
    func testEveryChildInRangeIsFedByABabyII() throws {
        for entry in childrenInRange {
            for parent in graph.parents(of: entry.id) {
                XCTAssertEqual(parent.stage, .babyII, "\(entry.id) is fed by a non-Baby II")
            }
        }
    }

    /// The thirty-three Champions this story authored are real, playable, and on the line of the
    /// Child that reaches them.
    func testEveryChampionThisSweepAuthoredIsPlayableAndOnItsParentsLine() throws {
        XCTAssertEqual(authoredAdults.count, 33)
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

    /// **The invariant this story spends, and the proof it had to.** Eighteen Children had no parent
    /// and nothing but a Baby II may point at a Child, so fifteen Baby II gained an extra branch —
    /// three of them two. Every extra branch on those fifteen leads to one of the eighteen, so none
    /// was authored for convenience.
    func testEveryBabyIIThatBranchesForThisSweepDoesSoForAnOrphan() throws {
        for (babyII, child) in babyIIBranches {
            let node = try XCTUnwrap(graph.node(id: babyII), "no node \(babyII)")
            XCTAssertEqual(node.stage, .babyII)
            XCTAssertTrue(node.evolutions.contains { $0.to == child },
                          "\(babyII) does not branch to \(child)")
        }
        let mine = Set(babyIIBranches.map(\.child))
        XCTAssertEqual(mine, Set(authoredChildren),
                       "a Child was authored without an in-edge, or a branch bought nothing")
        XCTAssertEqual(Set(babyIIBranches.map(\.babyII)).count, 15)
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

    /// Every Child this story swept branches: one earned Champion, conditioned and hinted, and one
    /// junk fallback that carries no criteria at all.
    ///
    /// A condition on a fallback would be data that lies — US-020 takes the `isDefault` edge exactly
    /// when nothing else qualifies, so its own criteria are never consulted. That is why "no edge is
    /// unconditional" is read here as "no edge a player has to EARN is unconditional", the reading
    /// US-144 through US-148 recorded for every rung below.
    ///
    /// **Scoped rather than relaxed in US-151.** "Exactly two edges" was a claim about what THIS
    /// story authored, and a later sweep hanging a second Champion off one of these Children
    /// falsifies it without doing anything wrong — US-151 hung BlackGaogamon off Gaomon. So the
    /// count is now a floor plus a named exception list: a Child of this story that grows a third
    /// earned branch nobody wrote down still fails here.
    func testEveryChildInRangeHasOneEarnedBranchAndOneUnconditionedFallback() throws {
        let branchedByALaterSweep = ["gaomon": 3]

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

    /// No edge in the file crosses a line, still. A Champion that could not be put on the line of
    /// the Child below it has been paired with the wrong Child.
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
    /// is NO new lines at all for fifty-one new nodes. An in-edge forces the line, so a Child sits
    /// on its Baby II's line and a Champion on its Child's — flavour never gets a vote.
    func testTheSweepOpenedNoNewLines() {
        let lines = Set(graph.nodes.map(\.line))
        XCTAssertEqual(lines.count, 21)
        for id in authoredChildren + authoredAdults {
            XCTAssertTrue(lines.contains(graph.node(id: id)?.line ?? ""),
                          "\(id) is on a line of its own")
        }
        // Thirteen of the twenty-one grew, and the biggest by sixteen — grouping rather than a
        // chain per Digimon. These are the FILE's sizes and not this story's, so US-150's are in
        // them too: twelve more on `tamers`, three on `dmc-v3` and on `xros`, eleven on `vital`,
        // and two on `palmon`, which this story did not touch at all.
        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 71, "US-151 opened this line's Perfect rung")
        XCTAssertEqual(sizes["dmc-v3"], 46)
        XCTAssertEqual(sizes["xros"], 17)
        XCTAssertEqual(sizes["vital"], 33)
        XCTAssertEqual(sizes["palmon"], 24)
    }

    /// **The variant rule, and the honest version of it.** The criteria say a variant hangs off its
    /// base form's line. Six of the eight X-Antibody Children here do exactly that, on the very
    /// In-Training their base form uses. The other two could not: their base form's In-Training
    /// carries all four energies and a Baby II can hold no fifth, so they went to the X-Antibody
    /// THREAD instead — the dmc-v3 group US-148 opened under Tokomon X — which is the same escape
    /// US-148 took for Dracomon X. All of it is asserted off the file rather than trusted to a
    /// comment.
    func testEveryVariantSitsWithItsBaseFormOrWithItsVariantThread() throws {
        // Six on the base form's own line, and five of those under the base form's own parent.
        for (variant, base) in [("gabumon_black", "gabumon"), ("gazimon_x", "gazimon"),
                                ("guilmon_x", "guilmon"), ("impmon_x", "impmon"),
                                ("keramon_x", "keramon"), ("lopmon_x", "lopmon"),
                                ("kokuwamon_x", "kokuwamon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line,
                           "\(variant) is not on \(base)'s line")
        }

        // The two that could not, and the reason is checkable: the base form's In-Training is full.
        for (variant, fullParent) in [("gabumon_x", "tokomon_x"), ("gomamon_x", "pukamon")] {
            let parent = try XCTUnwrap(graph.node(id: fullParent))
            XCTAssertEqual(Set(parent.evolutions.compactMap { $0.requiredEnergy?.rawValue }).count, 4,
                           "\(fullParent) has a free energy after all, so \(variant) had a choice")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line, "dmc-v3",
                           "\(variant) did not join the X-Antibody thread")
        }
        // Kokuwamon X is the third crowded case and the one that still kept its line: Caprimon is
        // full too, but `penc-me` has a SECOND In-Training, so the variant stayed with its base.
        XCTAssertEqual(
            Set(try XCTUnwrap(graph.node(id: "caprimon")).evolutions
                .compactMap { $0.requiredEnergy?.rawValue }).count, 4)
        XCTAssertTrue(try XCTUnwrap(graph.node(id: "kozenimon")).evolutions
            .contains { $0.to == "kokuwamon_x" })

        // And every variant's own Champion followed it, so no line holds half a thread.
        for (child, adult) in [("gabumon_black", "garurumon_black"), ("gabumon_x", "gururumon"),
                               ("gazimon_x", "leomon_x"), ("gomamon_x", "tylomon_x"),
                               ("guilmon_x", "allomon_x"), ("impmon_x", "ogremon_x"),
                               ("keramon_x", "wizarmon_x"), ("kokuwamon_x", "kuwagamon_x"),
                               ("lopmon_x", "blackgalgomon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: adult)).line,
                           try XCTUnwrap(graph.node(id: child)).line)
        }
    }

    /// The last two lines that had no Champion rung, each floor on the line it serves, each
    /// reachable by doing nothing, and each the fallback of every branching Child of that line.
    func testTheLastTwoLinesWithoutAChampionRungGainedAJunkFloor() throws {
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
        // Before this story neither line had a single Champion. THE HISTORICAL HALF OF THAT CLAIM
        // STOPPED BEING CHECKABLE IN US-150, which put seven more Adults on `vital` and three more
        // on `xros`, so "every Adult here is one US-149 authored" is simply false now — the same
        // rot US-149 itself found in US-148's version. What survives, and is what the claim was
        // really about, is that the junk FLOOR of each line is still this story's.
        for (line, junk) in junkFloors {
            let adults = graph.nodes.filter { $0.line == line && $0.stage == .adult }.map(\.id)
            XCTAssertTrue(adults.contains(junk))
            XCTAssertTrue(authoredAdults.contains(junk),
                          "\(line)'s junk floor is no longer the one this story authored")
        }
        // And this was the last time a sweep pays this cost. US-149 left this as the one-element
        // list `["adventure02"]` for US-150 to empty, and US-150 emptied it with NiseDrimogemon:
        // every line in the file now has a Champion rung, and a twenty-second line opened without
        // one would fail here.
        let withoutAChampionRung = Set(graph.nodes.map(\.line))
            .filter { line in graph.nodes.filter { $0.line == line && $0.stage == .adult }.isEmpty }
        XCTAssertEqual(withoutAChampionRung, [])
    }

    /// The Xros Loader claim US-146 made about `xros` still holds now that the line has a Champion
    /// rung: every Digimon on it names the device in its comment.
    func testTheFiveNewXrosLoaderNodesStillNameTheirDevice() throws {
        for id in graph.nodes.filter({ $0.line == "xros" }).map(\.id) {
            XCTAssertTrue(try authoredComment(on: id).contains("Xros"),
                          "\(id) is on the Xros Loader line without saying so")
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
    /// except the five that have nothing to cite, which say FLAVOUR or REHOME instead. A comment
    /// that cites nothing is the shape of an invented evolution.
    func testEveryNodeThisSweepAddedCitesItsSourceOrSaysItCannot() throws {
        let uncited = ["hackmon", "dinohumon", "sandyanmamon", "wizarmon_x", "targetmon",
                       "kokeshimon"]
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
        // Hackmon and its Champion: Wikimon lists no In-Training at all and Baohackmon, the rung
        // its own thread runs through, has no sheet in this pack.
        XCTAssertNil(roster.entry(id: "baohackmon"), "Baohackmon is on disk after all")
        XCTAssertTrue(try authoredComment(on: "hackmon").contains("Sistermon Blanc"))
        XCTAssertTrue(try authoredComment(on: "dinohumon").contains("Baohackmon"))

        // Kokabuterimon's Champion: every one of its nine Wikimon targets is spent elsewhere,
        // idle-only, or absent. Checked rather than asserted in prose.
        for id in ["kabuterimon", "kuwagamon", "greymon_x", "hanumon", "revolmon",
                   "thunderballmon"] {
            XCTAssertNotNil(graph.node(id: id), "\(id) is not authored elsewhere after all")
        }
        XCTAssertEqual(roster.entry(id: "aquilamon")?.dexOnly, true)
        XCTAssertNil(roster.entry(id: "bladekuwagamon"))
        XCTAssertNil(roster.entry(id: "blitzmon"))
        XCTAssertTrue(try authoredComment(on: "sandyanmamon").contains("Blade Kuwagamon"))

        // Keramon X: Wikimon has it WARP-evolving straight past the Champion rung, and the rung the
        // base thread would use, Chrysalimon, is one of the idle-only Digimon.
        XCTAssertEqual(roster.entry(id: "chrysalimon")?.dexOnly, true,
                       "Chrysalimon is playable after all, so it should be the edge")
        XCTAssertTrue(try authoredComment(on: "wizarmon_x").contains("WARP"))

        // Gomamon X's rehome: Pukamon is the only In-Training on the Deep Savers line at all, which
        // is why a full Pukamon leaves the variant nowhere on its own line to go.
        XCTAssertEqual(graph.nodes.filter { $0.line == "penc-ds" && $0.stage == .babyII }.map(\.id),
                       ["pukamon"])
        XCTAssertTrue(try authoredComment(on: "gomamon_x").contains("Yarmon"))
        XCTAssertNil(graph.node(id: "yarmon"))

        // Gaossmon's one-rung rehome: Wikimon names Chibickmon, which is a Baby I here.
        XCTAssertEqual(roster.entry(id: "chibickmon")?.stage, .babyI)
        XCTAssertEqual(graph.node(id: "chibickmon")?.evolutions.first?.to, "pickmon")
    }

    // MARK: - AC: the orphans this story removed

    /// FIFTY-ONE, counted with Appendix B of the PRD over a regenerated `roster.generated.json`:
    /// 432 before, 381 after. Asserted rather than only noted, because the count is the one claim in
    /// `notes` a later reader cannot re-derive from the diff.
    ///
    /// Every one of the fifty-one carries a plain roster id — not a single line-scoped alias — which
    /// is why new nodes and orphans removed are the same number.
    func testTheFiftyOneOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        let removed = authoredChildren + authoredAdults
        XCTAssertEqual(removed.count, 51)

        for id in removed {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        XCTAssertEqual(graph.nodes.count, 610,
                       "497 before this story, 548 after it, 599 after US-150, 610 after US-151")
    }

    /// The one Child in range whose Champion is NOT a new node. Lalamon's canonical Champion,
    /// Sunflowmon, is already on the palmon line — US-148 hung it over Alraumon — so giving Lalamon
    /// the arrow the source material draws adds a second parent rather than an orphan removed. That
    /// is the honest trade: the alternatives Wikimon offers Lalamon are all non-plant Champions on
    /// other lines, and a coherent line beats one more orphan struck off.
    func testLalamonReachesTheChampionTheSourceDrawsRatherThanANewOne() throws {
        let sunflowmon = try XCTUnwrap(graph.node(id: "sunflowmon"))
        XCTAssertEqual(sunflowmon.line, "palmon")
        XCTAssertFalse(authoredAdults.contains("sunflowmon"))

        let parents = graph.parents(of: "sunflowmon").map(\.id).sorted()
        XCTAssertTrue(parents.contains("lalamon"), "Lalamon does not reach Sunflowmon")
        XCTAssertGreaterThan(parents.count, 1, "Sunflowmon was already reachable before this story")
    }

    // MARK: - The whole file still validates

    func testTheGraphValidatesWithNoFindings() {
        let errors = EvolutionGraph.bundled.validate()
        XCTAssertEqual(errors.map(\.description), [])
    }

    // MARK: - Helpers

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-148 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
