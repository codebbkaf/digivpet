import XCTest

@testable import DigiVPet

/// US-150 — the seventh of Phase E's orphan sweeps, the M-Z third of the Child rung, and the story
/// that finishes that rung: after this there is no Child anywhere in `evolutions.json` without a
/// parent and without a way onward.
///
/// **Which reading of the story's scope this takes.** The same one US-148 and US-149 recorded: the
/// acceptance criteria ask for an in-edge AND an out-edge on every Digimon in range, and US-147
/// left sixteen M-Z Children with the first and not the second. So the scope is the RUNG-AND-RANGE
/// — every playable Child whose display name begins M-Z gets both edges, whether it was an orphan
/// (eighteen were) or merely a dead end (sixteen were).
///
/// **What that costs one rung down.** A Child's only possible parent is a Baby II, so eighteen
/// orphans meant branching fourteen Baby II. The four-energy ceiling
/// (`BabyIISweepTests.testEachBabyIIsBranchesAskForADifferentEnergy`) decided several placements
/// rather than flavour, and each Child that could not go to its first-choice parent says so in its
/// own `comment`.
///
/// **What it costs one rung UP.** Thirty-four Children need a Champion each on their own line.
/// Thirty-two of the thirty-four take a NEW node — every one a plain roster id, so every one
/// removes an orphan — and two take an existing Champion the source material draws for them, which
/// is the honest trade US-149 recorded for Lalamon. `adventure02` was the last line in the file
/// with no Adult rung at all, so it needed a junk floor invented first: thirty-three new Champions
/// in total, all leaves until the Adult sweeps.
final class ChildSweepMToZTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The eighteen Children that had no node at all before this story.
    private let authoredChildren = ["otamamon", "otamamon_red", "otamamon_red_ver2", "otamamon_x",
                                    "palmon_x", "petitmamon", "phascomon", "plotmon_x", "renamon_x",
                                    "sangomon", "shakomon_x", "solarmon", "starmon_2010",
                                    "terriermon_x", "toyagumon_black", "vorvomon", "wankomon",
                                    "yukiagumon"]

    /// The sixteen US-147 opened as leaves and this story wired onward.
    private let wiredOnward = ["meicoochild", "monodramon", "morphomon", "penmon", "pulsemon",
                              "renamon", "ryudamon", "shoutmon", "sistermon_blanc", "sunarizamon",
                              "takinmon", "terriermon", "tinkermon", "v-mon", "wormmon", "zenimon"]

    /// The thirty-three Champions this story authored, all of them leaves until US-151..US-156.
    private let authoredAdults = ["baboongamon", "chamblemon", "cockatrimon", "coredramon_blue",
                                  "dogmon", "dorulumon", "gekomon", "ginryumon", "hakubamon",
                                  "hookmon", "hyougamon", "junglemojyamon", "kyubimon",
                                  "kyubimon_silver", "lavorvomon", "mantaraymon_x", "meicoomon",
                                  "nisedrimogemon", "omekamon", "parasaurmon", "porcupamon",
                                  "raptordramon", "reppamon", "rhinomon_x", "seadramon_x",
                                  "shoutmon_king", "sorcerymon", "starmon", "tailmon_x", "tenkomon",
                                  "tobiumon", "tobucatmon", "xv-mon"]

    /// The two Children whose Champion is NOT a new node, and the Champion each reaches. Both are
    /// arrows Wikimon draws, and taking them adds a second parent instead of removing an orphan —
    /// see `testTheTwoChildrenWhoseChampionWasAlreadyAuthoredTakeTheArrowTheSourceDraws`.
    private let reusedAdults: [(child: String, adult: String)] = [
        ("petitmamon", "pencnso_devimon"),
        ("terriermon_x", "galgomon"),
    ]

    /// The fourteen Baby II that gained a way up, and the Child each branch bought. Four of them
    /// (Mochimon, Kakkinmon, Sunmon, Kozenimon) bought two, which is why the list is eighteen long.
    private let babyIIBranches: [(babyII: String, child: String)] = [
        ("mochimon", "otamamon"),
        ("mochimon", "otamamon_red"),
        ("kakkinmon", "otamamon_red_ver2"),
        ("kakkinmon", "otamamon_x"),
        ("budmon", "palmon_x"),
        ("sunmon", "petitmamon"),
        ("kozenimon", "phascomon"),
        ("hiyarimon", "plotmon_x"),
        ("pokomon", "renamon_x"),
        ("upamon", "sangomon"),
        ("chocomon", "shakomon_x"),
        ("gigimon", "solarmon"),
        ("pickmon", "starmon_2010"),
        ("gummymon", "terriermon_x"),
        ("kozenimon", "toyagumon_black"),
        ("sunmon", "vorvomon"),
        ("onibimon", "wankomon"),
        ("pencnsp_koromon", "yukiagumon"),
    ]

    /// The story's range, derived off the roster rather than listed, so a Child sprite added to the
    /// folder later lands IN scope and fails here. Forty-eight playable Children are named M-Z;
    /// fourteen of them were already wired end to end by a device tree, which is why the range and
    /// `sweptChildren` are different sets — coverage is claimed over the RANGE, and shape only over
    /// what this story authored.
    private var childrenInRange: [RosterEntry] {
        roster.entries.filter {
            $0.stage == .child && !$0.dexOnly
                && ("M"..."Z").contains(String($0.displayName.prefix(1)).uppercased())
        }
    }

    /// The thirty-four this story is responsible for.
    private var sweptChildren: [String] { authoredChildren + wiredOnward }

    /// The shared "did everything right" context, the same one US-147 through US-149 use, so an
    /// edge authored against a metric outside it fails here rather than shipping unreachable.
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
    func testEveryPlayableChildMToZIsANodeWithAnInEdgeAndAnOutEdge() throws {
        XCTAssertEqual(childrenInRange.count, 48)
        XCTAssertEqual(sweptChildren.count, 34)
        XCTAssertEqual(Set(childrenInRange.map(\.id)).subtracting(sweptChildren),
                       ["muchomon", "mushmon", "palmon", "patamon", "picodevimon", "piyomon",
                        "plotmon", "psychemon", "pteromon", "shakomon", "swimmon", "tentomon",
                        "toyagumon", "tsukaimon"],
                       "the fourteen M-Z Children a device tree had already wired have changed")

        for entry in childrenInRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
            XCTAssertFalse(node.evolutions.isEmpty,
                           "\(node.id) leads nowhere — a Dex entry with no tree")
        }
    }

    /// **The claim the whole Child rung has been building to since US-147.** Not "every Child M-Z",
    /// which the test above already says, but every Child in the FILE — aliases included, which is
    /// what the roster loop above cannot see. US-148, US-149 and US-150 split the rung three ways
    /// and this is the join.
    func testTheWholeChildRungNowHasBothEdges() {
        let children = graph.nodes(at: .child)
        XCTAssertEqual(children.count, 126)
        for node in children {
            XCTAssertFalse(graph.parents(of: node.id).isEmpty,
                           "\(node.id) has no in-edge, and every Child rung above Baby II should")
            XCTAssertFalse(node.evolutions.isEmpty, "\(node.id) leads nowhere")
        }
    }

    /// The two M-Z Children the roster cannot see. `dmcv4_palmon` and `pencwg_piyomon` are the
    /// line-scoped aliases US-135/US-141 authored — the same art as `palmon` and `piyomon` under a
    /// second id — so they have a display name in range but no roster entry, and the coverage loop
    /// above skips them. Neither is this story's: both have been wired since their device tree,
    /// which is checked here so the alias split cannot hide an unswept Child.
    func testTheTwoAliasesInRangeWereAlreadyWiredBeforeThisStory() throws {
        for (alias, plain, line) in [("dmcv4_palmon", "palmon", "dmc-v4"),
                                     ("pencwg_piyomon", "piyomon", "penc-wg")] {
            let node = try XCTUnwrap(graph.node(id: alias))
            XCTAssertNil(roster.entry(id: alias), "\(alias) is a roster entry after all")
            XCTAssertEqual(node.displayName, graph.node(id: plain)?.displayName)
            XCTAssertEqual(node.spriteFile, graph.node(id: plain)?.spriteFile)
            XCTAssertEqual(node.line, line)
            XCTAssertFalse(graph.parents(of: alias).isEmpty)
            XCTAssertFalse(node.evolutions.isEmpty)
            XCTAssertFalse(sweptChildren.contains(alias), "\(alias) is not this story's")
        }
    }

    /// The Appendix B orphan rule, rerun over the range this story owns.
    func testNoChildMToZIsStillAnOrphan() {
        let sources = Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
        let targets = Set(graph.nodes.flatMap { $0.evolutions.map(\.to) })
        let connected = sources.union(targets)
        let orphans = childrenInRange.map(\.id).filter { !connected.contains($0) }
        XCTAssertEqual(orphans, [], "Children M-Z still orphaned: \(orphans)")
    }

    /// Every Child in range is fed by a Baby II and nothing else — the half that stops the first
    /// claim from being satisfied by a skipped rung.
    func testEveryChildInRangeIsFedByABabyII() {
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
    /// and nothing but a Baby II may point at a Child, so fourteen Baby II gained an extra branch —
    /// four of them two. Every extra branch on those fourteen leads to one of the eighteen, so none
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
        XCTAssertEqual(Set(babyIIBranches.map(\.babyII)).count, 14)
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
    ///
    /// **This is the test that caught the one real authoring bug in this story**, and it is worth
    /// knowing about: `care.battleCount` is answerable ONLY over the lifetime window —
    /// `ConditionContext.careValue` returns `.unknown` for `(.careBattleCount, .stage)` — so four
    /// edges authored with `"window": "stage"` on a battle criterion were unreachable, not merely
    /// hard. Every other `care.*` counter is the other way round and is `.stage` only.
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

    /// The window rule the bug above turned on, pinned directly rather than only through the four
    /// edges that tripped it: no criterion anywhere in the file asks for a battle count over a
    /// window the context cannot answer.
    func testNoBattleCriterionAsksForAWindowTheContextCannotAnswer() {
        for node in graph.nodes {
            for edge in node.evolutions {
                for condition in edge.conditions where condition.metric == "care.battleCount" {
                    XCTAssertNotEqual(condition.window, .stage,
                                      "\(node.id) -> \(edge.to) counts battles over a stage, "
                                          + "which ConditionContext always answers .unknown")
                }
            }
        }
    }

    // MARK: - AC: the out-edges

    /// Every Child this story swept branches: one earned Champion, conditioned and hinted, and one
    /// junk fallback that carries no criteria at all.
    ///
    /// A condition on a fallback would be data that lies — US-020 takes the `isDefault` edge exactly
    /// when nothing else qualifies, so its own criteria are never consulted. That is why "no edge is
    /// unconditional" is read here as "no edge a player has to EARN is unconditional", the reading
    /// US-144 through US-149 recorded for every rung below.
    ///
    /// **Scoped rather than relaxed in US-151.** "Exactly two edges" was a claim about what THIS
    /// story authored, and a later sweep hanging a second Champion off one of these Children
    /// falsifies it without doing anything wrong — US-151 hung DarkLizamon off Monodramon. So the
    /// count is now a named exception list: a Child of this story that grows a third earned branch
    /// nobody wrote down still fails here.
    func testEveryChildInRangeHasOneEarnedBranchAndOneUnconditionedFallback() throws {
        let branchedByALaterSweep = ["monodramon": 4, "plotmon_x": 3, "renamon": 3]

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
        // Thirteen of the twenty-one grew, `tamers` and `vital` by a dozen and eleven. These are
        // the FILE's sizes rather than this story's, so US-148's and US-149's nodes are in them.
        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["tamers"], 113,
                       "US-152 put FlareLizamon and Growmon Orange under this line's Perfect rung, "
                           + "US-156 Youkomon and BlackRapidmon, plus US-158's four, plus US-159's five" + ", plus US-160's four, plus US-161's Rapidmon and SaintGalgomon, plus US-163's eight Ultimates")
        XCTAssertEqual(sizes["vital"], 42, "plus US-163's one Ultimate")
        XCTAssertEqual(sizes["penc-me"], 67, "US-151 hung Deckerdramon on Hagurumon, US-157 six more nodes, plus US-158's Duramon, plus US-159's two" + ", plus US-160's one, plus US-161's both Okuwamon, RizeGreymon X and two Kuwagamon Megas, plus US-163's four Ultimates")
        XCTAssertEqual(sizes["adventure02"], 18)
        XCTAssertEqual(sizes["dmc-v2"], 30, "the dmc-v2 line gained no node here")
    }

    /// **The variant rule, and the honest version of it.** The criteria say a variant hangs off its
    /// base form's line. Eight of the nine variants here do exactly that — four of them on the very
    /// In-Training their base form uses — and the ninth could not: `penc-ds` has exactly ONE
    /// In-Training in the whole line and it carries all four energies, the same trap US-149's
    /// Gomamon X hit. Shakomon X followed a CITED parent instead of being rehomed by flavour, which
    /// is the better of the two escapes and is why it is checked separately.
    func testEveryVariantSitsWithItsBaseFormOrFollowsACitedParent() throws {
        // Eight on the base form's own line.
        for (variant, base) in [("otamamon_red", "otamamon"), ("otamamon_red_ver2", "otamamon"),
                                ("otamamon_x", "otamamon"), ("palmon_x", "palmon"),
                                ("plotmon_x", "plotmon"), ("renamon_x", "renamon"),
                                ("terriermon_x", "terriermon"), ("toyagumon_black", "toyagumon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line,
                           "\(variant) is not on \(base)'s line")
        }
        // Three kept an In-Training the base form itself hangs off; the rest could not, and the
        // reason is checkable in each case — the parent carries all four energies a Baby II can
        // hold. Renamon has TWO parents (Onibimon and Pokomon) and the variant took the free one,
        // which is why this is a subset rather than an equality.
        for (variant, base) in [("otamamon_red", "otamamon"), ("renamon_x", "renamon"),
                                ("terriermon_x", "terriermon")] {
            let shared = Set(graph.parents(of: variant).map(\.id))
            XCTAssertFalse(shared.isEmpty)
            XCTAssertTrue(shared.isSubset(of: Set(graph.parents(of: base).map(\.id))),
                          "\(variant) does not share an In-Training with \(base)")
        }
        for (variant, fullParent) in [("otamamon_red_ver2", "mochimon"), ("otamamon_x", "mochimon"),
                                      ("palmon_x", "tanemon"), ("plotmon_x", "nyaromon"),
                                      ("toyagumon_black", "caprimon")] {
            let parent = try XCTUnwrap(graph.node(id: fullParent))
            XCTAssertEqual(Set(parent.evolutions.compactMap { $0.requiredEnergy?.rawValue }).count, 4,
                           "\(fullParent) has a free energy after all, so \(variant) had a choice")
        }

        // The ninth, and the one that left its base form's line: `penc-ds` has a single
        // In-Training, so a full Pukamon leaves Shakomon X nowhere on its own line to go. Chocomon
        // is one of the two parents Wikimon names for it, which is why this is a citation and not
        // a rehome.
        XCTAssertEqual(graph.nodes.filter { $0.line == "penc-ds" && $0.stage == .babyII }.map(\.id),
                       ["pukamon"])
        XCTAssertEqual(graph.node(id: "shakomon_x")?.line, "tamers")
        XCTAssertTrue(try authoredComment(on: "shakomon_x").contains("Chocomon"))

        // And every variant's own Champion followed it, so no line holds half a thread.
        for (child, adult) in [("otamamon_red", "hookmon"), ("otamamon_red_ver2", "mantaraymon_x"),
                               ("otamamon_x", "seadramon_x"), ("palmon_x", "junglemojyamon"),
                               ("plotmon_x", "tailmon_x"), ("renamon_x", "kyubimon_silver"),
                               ("shakomon_x", "tobucatmon"), ("toyagumon_black", "raptordramon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: adult)).line,
                           try XCTUnwrap(graph.node(id: child)).line)
        }
    }

    /// **The last line in the file to gain a Champion rung.** US-149 left `adventure02` as a
    /// one-element list for this story to empty, and NiseDrimogemon is what emptied it: a floor
    /// every branching Child of the line falls to by doing nothing.
    func testTheLastLineWithoutAChampionRungGainedAJunkFloor() throws {
        let junk = try XCTUnwrap(graph.node(id: "nisedrimogemon"))
        XCTAssertEqual(junk.line, "adventure02")
        XCTAssertEqual(junk.stage, .adult)

        let branching = graph.nodes.filter {
            $0.line == "adventure02" && $0.stage == .child && !$0.evolutions.isEmpty
        }
        XCTAssertEqual(branching.map(\.id).sorted(), ["tinkermon", "v-mon", "wormmon"])
        for child in branching {
            XCTAssertEqual(child.evolutions.first(where: \.isDefault)?.to, "nisedrimogemon",
                           "\(child.id) does not fall to adventure02's junk Champion")
        }
        // Before this story the line had no Adult at all, which is why it needed one; the whole
        // Adult rung of `adventure02` is still this story's, so that stays checkable.
        let adults = graph.nodes.filter { $0.line == "adventure02" && $0.stage == .adult }.map(\.id)
        XCTAssertEqual(adults.sorted(), ["nisedrimogemon", "parasaurmon", "sorcerymon", "xv-mon"])
        XCTAssertTrue(Set(adults).isSubset(of: Set(authoredAdults)))

        // And there is no line left without one.
        let withoutAChampionRung = Set(graph.nodes.map(\.line))
            .filter { line in graph.nodes.filter { $0.line == line && $0.stage == .adult }.isEmpty }
        XCTAssertEqual(withoutAChampionRung, [])
    }

    /// The Xros Loader claim US-146 made about `xros` still holds now that the line has a Starmon
    /// and a Dorulumon on it: every Digimon on it names the device in its comment.
    func testTheThreeNewXrosLoaderNodesStillNameTheirDevice() throws {
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
    /// except the ones with nothing to cite, which say FLAVOUR or REHOME instead. A comment that
    /// cites nothing is the shape of an invented evolution.
    func testEveryNodeThisSweepAddedCitesItsSourceOrSaysItCannot() throws {
        let uncited = ["chamblemon", "reppamon", "omekamon", "dorulumon", "nisedrimogemon",
                       "petitmamon", "vorvomon", "kyubimon_silver"]
        for id in authoredChildren + authoredAdults {
            let comment = try authoredComment(on: id)
            if uncited.contains(id) {
                XCTAssertTrue(comment.contains("FLAVOUR") || comment.contains("REHOME"),
                              "\(id) has nothing to cite and does not say so")
            } else {
                XCTAssertTrue(comment.contains("Wikimon"),
                              "\(id) is authored without naming where the arrow comes from")
                XCTAssertFalse(comment.contains("FLAVOUR") || comment.contains("REHOME"),
                               "\(id) hedges: it is either a cited arrow or it is not")
            }
        }
    }

    /// The pairings that are NOT a Wikimon arrow are the story's weak spot — a stand-in is the one
    /// thing a later reader cannot tell from a shortcut — so each says what it could not use, and
    /// each stated fact about the roster or the graph is CHECKED here rather than merely read.
    func testEveryUncitedPairingSaysWhatItCouldNotUse() throws {
        // Morphomon's Champion: Wikimon gives it four targets and every one is unusable. Checked,
        // not asserted in prose.
        XCTAssertEqual(roster.entry(id: "hudiemon")?.dexOnly, true,
                       "Hudiemon is playable after all, so it should be the edge")
        for id in ["gokimon", "unimon", "waspmon"] {
            XCTAssertNotNil(graph.node(id: id), "\(id) is not authored elsewhere after all")
            XCTAssertNotEqual(graph.node(id: id)?.line, "vital", "\(id) is on Morphomon's line")
        }
        XCTAssertTrue(try authoredComment(on: "chamblemon").contains("Kodokugumon"))

        // Pulsemon's Champion: the one target with a sheet is filed a whole rung too high, which
        // is the sort of claim that rots silently if it is only written down.
        XCTAssertEqual(roster.entry(id: "boutmon")?.stage, .perfect)
        XCTAssertEqual(roster.entry(id: "bulkmon")?.dexOnly, true)
        for id in ["exermon", "namakemon", "runnermon"] {
            XCTAssertNil(roster.entry(id: id), "\(id) has a sheet after all")
        }
        XCTAssertEqual(roster.entry(id: "kudamon")?.dexOnly, true,
                       "Reppamon's own canonical parent is playable, so it should not be free")
        XCTAssertTrue(try authoredComment(on: "reppamon").contains("Boutmon"))

        // Zenimon: Wikimon's Evolves To section is EMPTY, not merely thin, so the Champion is
        // placed by its own parents instead. Both of them really are on penc-me.
        for id in ["hagurumon", "toyagumon"] {
            XCTAssertEqual(graph.node(id: id)?.line, "penc-me")
        }
        XCTAssertTrue(try authoredComment(on: "omekamon").contains("Hagurumon"))

        // Starmon 2010's Champion: its Evolves To list is a DigiXros fusion list, which is the
        // trap US-144 recorded for Bombmon, so the comment says FLAVOUR and names it.
        XCTAssertTrue(try authoredComment(on: "dorulumon").contains("DigiXros"))

        // The three rehomes each name the parent they could not have, and each of those really is
        // full or absent.
        for id in ["koromon", "petimeramon", "caprimon", "pyocomon", "wanyamon", "tokomon_x"] {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(Set(node.evolutions.compactMap { $0.requiredEnergy?.rawValue }).count, 4,
                           "\(id) has a free energy after all")
        }
        XCTAssertTrue(try authoredComment(on: "vorvomon").contains("Peti Meramon"))
        XCTAssertTrue(try authoredComment(on: "phascomon").contains("Caprimon"))
        XCTAssertTrue(try authoredComment(on: "kyubimon_silver").contains("Sangloupmon"))
        XCTAssertTrue(try authoredComment(on: "petitmamon").contains("Devimon"))
    }

    // MARK: - AC: the orphans this story removed

    /// FIFTY-ONE, counted with Appendix B of the PRD over a regenerated `roster.generated.json`:
    /// 381 before, 330 after. Asserted rather than only noted, because the count is the one claim in
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
        XCTAssertEqual(graph.nodes.count, 817,
                       "548 before this story, 599 after it, 610 after US-151, 615 after US-152, "
                           + "618 after US-153, 635 after US-155, 672 after US-157, "
                           + "693 after US-158, 709 after US-159, 736 after US-160, 760 after US-161, 787 after US-162, 817 after US-163")
    }

    /// The two Children in range whose Champion is NOT a new node. Both take the arrow the source
    /// material draws, and both of those Champions were already reachable — so the trade is one
    /// fewer orphan struck off in exchange for the canonical evolution, the same call US-149 made
    /// for Lalamon and Sunflowmon.
    func testTheTwoChildrenWhoseChampionWasAlreadyAuthoredTakeTheArrowTheSourceDraws() throws {
        for (child, adult) in reusedAdults {
            let node = try XCTUnwrap(graph.node(id: adult))
            XCTAssertFalse(authoredAdults.contains(adult), "\(adult) is one this story authored")
            XCTAssertEqual(node.line, graph.node(id: child)?.line)

            let parents = graph.parents(of: adult).map(\.id).sorted()
            XCTAssertTrue(parents.contains(child), "\(child) does not reach \(adult)")
            XCTAssertGreaterThan(parents.count, 1,
                                 "\(adult) was not already reachable before this story")
        }
        // And no other swept Child reuses a Champion, which is what makes 32 + 2 = 34 add up.
        let reusedChildren = Set(reusedAdults.map(\.child))
        for id in sweptChildren where !reusedChildren.contains(id) {
            let target = try XCTUnwrap(graph.node(id: id)?.evolutions.first { !$0.isDefault }?.to)
            XCTAssertTrue(authoredAdults.contains(target),
                          "\(id) reaches \(target), which this story did not author")
        }
    }

    /// **Three eggs collect on a promise US-145 deferred.** `meicoo_digitama`, `phasco_digitama`
    /// and `vorvo_digitama` all doubled up onto an existing Baby I because their own species had
    /// no node at all; this story wired all three, and the placements were chosen so that each
    /// egg's own thread now arrives at the Digimon it is named for. That is what decided
    /// Phascomon's parent in particular — see its `comment`.
    func testTheThreeEggsWhoseSpeciesThisStoryWiredNowArriveAtIt() throws {
        for (egg, species) in [("meicoo_digitama", "meicoomon"),
                               ("phasco_digitama", "phascomon"),
                               ("vorvo_digitama", "vorvomon")] {
            XCTAssertNotNil(graph.node(id: species), "\(species) was not wired after all")
            XCTAssertTrue(reachable(from: egg).contains(species),
                          "\(egg) still does not arrive at \(species)")
        }
    }

    // MARK: - The whole file still validates

    func testTheGraphValidatesWithNoFindings() {
        let errors = EvolutionGraph.bundled.validate()
        XCTAssertEqual(errors.map(\.description), [])
    }

    // MARK: - Helpers

    /// Every node a thread can grow into, the root included.
    private func reachable(from id: String) -> Set<String> {
        var seen: Set<String> = [id]
        var frontier = [id]
        while let next = frontier.popLast() {
            for edge in graph.node(id: next)?.evolutions ?? [] where !seen.contains(edge.to) {
                seen.insert(edge.to)
                frontier.append(edge.to)
            }
        }
        return seen
    }

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-149 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) carries no comment")
    }
}
