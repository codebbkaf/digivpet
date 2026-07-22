import XCTest

@testable import DigiVPet

/// US-161 — the eighteenth of Phase E's orphan sweeps and the fifth at the Perfect rung: the fifteen
/// playable Perfect whose display name begins N-R that no device tree, Champion sweep or earlier
/// Perfect sweep reached.
///
/// **Fifteen orphans, twenty-four nodes, and TWO lines gained a Perfect rung.** `vital` had to open —
/// RaijiLudomon's only two drawable parents, Tia Ludomon and Reppamon, are both on it — and `xros`
/// opened because OmegaShoutmon's bolded parent, Shoutmon (King Ver.), is `xros`'s and had been a
/// leaf since US-150. US-158's rule made each cost a junk floor and a Mega in the same story, so the
/// bill is five nodes for `vital` and four for `xros`. 193 -> 171.
///
/// **Six leaf Champions came off the dead-end ledger and two floors went back on**, 77 -> 73. Both
/// floors are line-scoped ALIASES on sheets another line already owns — `vital_darumamon` and
/// `xros_etemon` — for the reason US-160 recorded when it authored `diablomon_gerbemon`: not one of
/// the thirty-seven Perfect still orphaned when this story ran is junk-flavoured, so there is no
/// unused gag sheet left to spend. Both are cited rather than picked: Wikimon puts Darumamon on
/// Kokeshimon's own `Evolves To` and Etemon on Targetmon's, `xros`'s own junk Champion.
///
/// **`adventure02` was left closed ON PURPOSE, and that is the most interesting decision here.**
/// XV-mon is a cited parent for Paildramon and was that line's last leaf, so the arrow was there for
/// the taking — but `adventure02` carries two eggs and only V Digitama descends through XV-mon. Worm
/// Digitama descends through Wormmon to Sorcerymon, which has no Perfect above it and no orphan in
/// this band it could take, so opening the rung would have left an egg unraisable on a line that HAS
/// one. Paildramon went to XV-mon Black on `penc-wg` instead — the variant of the very Champion the
/// citation names, with the cited Ulforce V-dramon already above it.
///
/// **`vital`'s whole egg list was promoted**, five at once, because every `vital` Child falls to
/// Kokeshimon and Kokeshimon now carries Oboromon and Zanbamon. `xros` promoted nothing, because it
/// has no Digitama at all: its four new nodes join `penc-sw`'s three on
/// `EvolutionCriteriaTests`' stranded list, inheriting Shoutmon King's strandedness exactly.
final class PerfectSweepNToRTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The fifteen orphaned Perfects this story wired, with the Champion that now reaches each and
    /// the Ultimate each now climbs into. Every one is a plain roster id, so every one removes an
    /// orphan.
    private let swept: [(perfect: String, parent: String, ultimate: String)] = [
        ("neodevimon", "devimon", "blitzgreymon"),
        ("oboromon", "kokeshimon", "zanbamon"),
        ("okuwamon", "kuwagamon_x", "grankuwagamon"),
        ("okuwamon_x", "kuwagamon_x", "grandiskuwagamon"),
        ("omegashoutmon", "shoutmon_king", "zekegreymon"),
        ("omegashoutmon_x", "shoutmon_king", "zekegreymon"),
        ("orochimon", "dokugumon", "pencnso_metalgarurumon"),
        ("paildramon", "xv-mon_black", "ulforcev-dramon"),
        ("panjyamon", "pencnsp_leomon", "holydramon"),
        ("panjyamon_x", "pencnsp_leomon", "saberleomon"),
        ("raijiludomon", "tialudomon", "bryweludramon"),
        ("rapidmon", "galgomon", "saintgalgomon"),
        ("regulusmon", "gulusgammamon", "pencvb_metalgarurumon"),
        ("rizegreymon", "geogreymon", "ravmon"),
        ("rizegreymon_x", "omekamon", "ouryumon"),
    ]

    /// The seven Ultimates this story authored, and the line each landed on. All seven are leaves,
    /// as every Ultimate in this file is; none is on the dead-end ledger, which stops below the top
    /// rung. ZekeGreymon is the one with two parents, and deliberately: OmegaShoutmon X has no cited
    /// climb anywhere on `xros`, so converging on its base form's Mega is the variant rule's answer.
    private let authoredUltimates: [(ultimate: String, parents: Set<String>, line: String)] = [
        // US-162 hung Shishimamon under this one — a cited climb on that page, over the leaf
        // Reppamon. Named rather than the check being loosened to a superset.
        ("zanbamon", ["oboromon", "shishimamon"], "vital"),
        ("bryweludramon", ["raijiludomon"], "vital"),
        ("grankuwagamon", ["okuwamon"], "penc-me"),
        ("grandiskuwagamon", ["okuwamon_x"], "penc-me"),
        ("zekegreymon", ["omegashoutmon", "omegashoutmon_x"], "xros"),
        ("saintgalgomon", ["rapidmon"], "tamers"),
        ("ravmon", ["rizegreymon"], "wanyamon"),
    ]

    /// The six Champions that were LEAVES before this story, and the junk Perfect each now falls to.
    /// Four floors already existed; `vital_darumamon` and `xros_etemon` are this story's, and both
    /// are aliases — see `testTheTwoNewJunkFloorsAreAliasesBecauseNoOrphanIsJunk`.
    private let junkFloors: [(parent: String, junk: String)] = [
        ("kuwagamon_x", "locomon"),
        ("shoutmon_king", "xros_etemon"),
        ("galgomon", "catchmamemon"),
        ("geogreymon", "karakurumon"),
        ("kokeshimon", "vital_darumamon"),
        ("tialudomon", "vital_darumamon"),
    ]

    /// The two junk floors this story had to author, with the sheet each draws and the line that
    /// already owns that sheet under the plain id.
    private let authoredFloors: [(id: String, sprite: String, line: String, plainOwner: String)] = [
        ("vital_darumamon", "Darumamon", "vital", "darumamon"),
        ("xros_etemon", "Etemon", "xros", "etemon"),
    ]

    /// The shared "did everything right" context, US-151's through US-160's exactly.
    private let met = ConditionContext(
        stageTotals: MetricTotals(values: ["health.steps": 500_000,
                                           "health.activeEnergy": 50_000,
                                           "health.exerciseMinutes": 5_000,
                                           "health.standHours": 1_000,
                                           "health.flightsClimbed": 5_000,
                                           "health.distanceSwimming": 500_000,
                                           "health.mindfulMinutes": 5_000,
                                           "health.daylight": 5_000,
                                           "health.water": 500_000,
                                           "health.distanceWalkingRunning": 500_000,
                                           "health.sleep": 100_000]),
        trainingSessionsThisStage: 30,
        overfeedsThisStage: 0,
        sleepDisturbancesThisStage: 0,
        battlesLifetime: 40,
        battleWinRatioLifetime: 1.0)

    // MARK: - AC1/AC2: the range, counted off the roster rather than off the list above

    /// The headline claim. The range is derived from the ROSTER, so a Perfect sheet added to the
    /// folder later lands in scope and fails here instead of being quietly missed.
    func testEveryPlayablePerfectNToRIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .perfect && !$0.dexOnly
                && ("N"..."R").contains(String($0.displayName.prefix(1)).uppercased())
        }
        // Twenty-two, not the twenty-three nodes the graph holds in this band: `Roster.bundled`
        // reads `Resources/roster.json`, one entry per SHEET on disk, while the graph also carries
        // the line-scoped ALIASES — `pencnso_pumpmon` is the only one in this band. The roster
        // count is the right denominator for "every Digimon on disk is obtainable"; Appendix B's
        // script reads `roster.generated.json` and so counts the alias too.
        XCTAssertEqual(inRange.count, 22)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The fifteen this story owns lead somewhere too.
        for (perfect, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: perfect)).evolutions.isEmpty,
                           "\(perfect) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the range this story owns.
    func testNoPerfectNToRIsStillAnOrphan() {
        let orphans = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && ("N"..."R").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { !connectedIds.contains($0) }
        XCTAssertEqual(orphans, [], "Perfects N-R still orphaned: \(orphans)")
    }

    /// The one Perfect in range this story deliberately did NOT wire onward, named rather than
    /// counted. Pandamon was a JUNK Perfect rather than an orphan — `penc-sw`'s floor, US-157's — so
    /// it had an in-edge and sat on the dead-end ledger in `ChildSweepAToFTests` waiting for an
    /// Ultimate sweep. **US-165 was that sweep**: it climbs to Erlangmon now, so the N-R leaves are
    /// empty. This story's own two floors are NOT in this band.
    func testTheOnePerfectNToRLeftAsALeafIsTheDeadEndLedgersOwn() throws {
        let leaves = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && ("N"..."R").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { graph.node(id: $0)?.evolutions.isEmpty == true }
            .sorted()

        XCTAssertEqual(leaves, [],
                       "the N-R leaves have moved without the ledger moving with them")
        XCTAssertFalse(graph.parents(of: "pandamon").isEmpty,
                       "Pandamon is an orphan rather than a leaf, so it WAS in this story's scope")
        XCTAssertEqual(graph.node(id: "pandamon")?.evolutions.map(\.to), ["erlangmon"],
                       "US-165 gave Pandamon its Ultimate climb, clearing this leaf")
    }

    // MARK: - AC2/AC4: the shape of every edge this story authored

    /// Each swept Perfect climbs by exactly one `isDefault` edge, gated on energy and on care but
    /// carrying no criteria — the shape every Perfect in this file has had since US-134. US-020
    /// takes the `isDefault` edge exactly when nothing else qualifies, so a condition on one would
    /// be data that lies about how it is taken. What the criterion binds is the EARNED edges.
    func testEverySweptPerfectClimbsByOneGatedDefaultEdge() throws {
        // **US-163 IS THE FIRST STORY TO FORK A PERFECT, AND THESE ARE THE ONES IT FORKED.** The
        // Ultimate sweep's in-edges come from this rung, so a Perfect that already had its climb
        // gained an EARNED branch beside it — a different `requiredEnergy`, two criteria, and the
        // climb untouched and still `isDefault`, which is the whole of what this test checks. Each
        // is NAMED with its new edge count rather than the count being loosened to a `>=`.
        let branchedByUS163: [String: Int] = ["omegashoutmon": 2]
        for (perfect, _, ultimate) in swept {
            let node = try XCTUnwrap(graph.node(id: perfect))
            XCTAssertEqual(node.evolutions.count, branchedByUS163[perfect] ?? 1,
                           "\(perfect) is not a single climb")

            let climb = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertTrue(climb.isDefault, "\(perfect)'s climb is not its fallback")
            XCTAssertEqual(climb.to, ultimate)
            XCTAssertEqual(climb.conditions, [], "\(perfect)'s fallback carries criteria")
            XCTAssertNotNil(climb.requiredEnergy, "\(perfect) climbs on no energy at all")
            XCTAssertEqual(climb.minEnergy, 150, "the Perfect rung's gate is 150 since US-134")
            XCTAssertEqual(climb.maxCareMistakes, 2)
        }
    }

    /// The in-edges are earned, conditioned and hinted, and none of them displaces the fallback of
    /// the Champion it hangs off — the guard every sweep below this one needed.
    func testEveryNewChampionBranchIsEarnedAndLeavesTheFallbackAlone() throws {
        for (perfect, parent, _) in swept {
            let node = try XCTUnwrap(graph.node(id: parent))
            let edge = try XCTUnwrap(node.evolutions.first { $0.to == perfect },
                                     "\(parent) does not reach \(perfect)")
            XCTAssertFalse(edge.isDefault, "\(parent) -> \(perfect) took over the junk branch")
            XCTAssertEqual(edge.conditions.count, 2,
                           "\(parent) -> \(perfect) is not one HealthKit and one care criterion")
            for condition in edge.conditions {
                XCTAssertFalse(condition.hint.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(parent) -> \(perfect) has an undiscoverable criterion")
            }
            XCTAssertEqual(edge.conditions.filter { $0.metric.hasPrefix("health.") }.count, 1)
            XCTAssertEqual(edge.conditions.filter { $0.metric.hasPrefix("care.") }.count, 1)
            XCTAssertEqual(node.evolutions.filter(\.isDefault).count, 1,
                           "\(parent) no longer has a single fallback")
            XCTAssertGreaterThan(edge.minEnergy, 0,
                                 "\(parent)'s junk edge would win the branch outright")
        }
    }

    /// **SIX Champions came off the dead-end ledger, and TWO of the six needed a junk node that did
    /// not exist.** A leaf Champion has no fallback because it has no edges at all; the moment it
    /// gains an earned branch, `EvolutionCriteriaTests` requires an `isDefault` edge onto a junk
    /// Perfect of its OWN line. `vital` and `xros` had no Perfect rung at all, so this story paid
    /// the bill US-157 paid for `penc-sw` and US-160 for `diablomon` — twice.
    func testTheSixLeafChampionsGainedTheirLinesJunkFloor() throws {
        for (parent, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: parent))
            // Two for five of them; Kuwagamon X and Shoutmon King are three, because each carries
            // a base form and its X.
            // Kuwagamon X is FOUR since US-162 hung Scorpiomon on it beside the pair this story
            // gave it. Named exception rather than a loosened `>=`, the shape US-160 established.
            let expected = parent == "kuwagamon_x" ? 4
                : (parent == "shoutmon_king" ? 3 : 2)
            XCTAssertEqual(node.evolutions.count, expected,
                           "\(parent) is not its earned branches plus a fallback")
            XCTAssertEqual(node.evolutions.first(where: \.isDefault)?.to, junk,
                           "\(parent) does not fall to its line's junk Perfect")

            let floor = try XCTUnwrap(graph.node(id: junk))
            XCTAssertEqual(floor.line, node.line, "\(junk) is not on \(parent)'s line")
            XCTAssertEqual(floor.stage, .perfect)

            let fallback = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            XCTAssertEqual(fallback.minEnergy, 0, "\(parent)'s junk edge demands energy")
            XCTAssertEqual(fallback.conditions, [], "\(parent)'s junk edge carries criteria")
            XCTAssertGreaterThanOrEqual(fallback.maxCareMistakes, 99)
        }

        // Two floors are this story's; the other THREE pre-dated it — `locomon` among them, which
        // is the only floor here that is not a leaf itself (it climbs to GrandLocomon), so reusing
        // it cost `penc-me` nothing at all.
        XCTAssertEqual(Set(junkFloors.map(\.junk)).intersection(authoredFloors.map(\.id)),
                       ["vital_darumamon", "xros_etemon"])
        XCTAssertEqual(Set(junkFloors.map(\.junk)).subtracting(authoredFloors.map(\.id)),
                       ["catchmamemon", "karakurumon", "locomon"])

        // The other six Champions were ALREADY branching, so none needed a floor and none touched
        // one.
        let alreadyBranching = Set(swept.map(\.parent)).subtracting(junkFloors.map(\.parent))
        XCTAssertEqual(alreadyBranching,
                       ["devimon", "dokugumon", "gulusgammamon", "omekamon", "pencnsp_leomon",
                        "xv-mon_black"])
        for parent in alreadyBranching {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(graph.node(id: parent)).evolutions.count, 3,
                                        "\(parent) was a leaf after all, so it needed a floor")
        }
    }

    /// **BOTH NEW JUNK FLOORS ARE LINE-SCOPED ALIASES, AND THAT IS A CLAIM ABOUT THE POOL RATHER
    /// THAN A SHORTCUT.** CatchMamemon, Karakurumon and Pandamon were each an unused sheet, so each
    /// also removed an orphan; by US-160 not one of the Perfect sheets still orphaned was
    /// junk-flavoured, and that is still true here — Sagomon, Scorpiomon, Triceramon, Yatagaramon
    /// and the rest of the S-Z band are all real Digimon. So these two draw art another line already
    /// owns, the `dmcv2_vademon` pattern, and remove no orphan.
    func testTheTwoNewJunkFloorsAreAliasesBecauseNoOrphanIsJunk() throws {
        for (id, sprite, line, plainOwner) in authoredFloors {
            let floor = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(floor.line, line)
            XCTAssertEqual(floor.stage, .perfect)
            XCTAssertEqual(floor.spriteFile, sprite)
            XCTAssertTrue(floor.evolutions.isEmpty, "a junk floor is a leaf until an Ultimate sweep")
            XCTAssertNil(roster.entry(id: id),
                         "\(id) has a roster entry, so it is not an alias and DID remove an orphan")

            // The plain id really does exist elsewhere, on the same art and another line.
            let plain = try XCTUnwrap(graph.node(id: plainOwner))
            XCTAssertEqual(plain.spriteFile, sprite)
            XCTAssertNotEqual(plain.line, line)
        }

        // And the pool claim itself: no Perfect still orphaned is one of the gag Digimon a floor
        // could have been spent on.
        let stillOrphaned = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly && !connectedIds.contains($0.id) }
            .map(\.id)
        XCTAssertEqual(Set(stillOrphaned).intersection(["gerbemon", "etemon", "vademon", "jyagamon",
                                                        "darumamon", "pumpmon", "locomon",
                                                        "piranimon", "tonosamagekomon"]), [])
    }

    /// **TWO LINES GAINED A PERFECT RUNG AND A MEGA IN ONE STORY**, which is US-158's rule: a sweep
    /// that opens a Perfect rung on a line with none owes an Ultimate over it in the same story, or
    /// it re-opens the gap it just closed one rung lower.
    func testVitalAndXrosGainedBothOfTheirMissingRungsAtOnce() throws {
        for line in ["vital", "xros"] {
            let perfects = graph.nodes.filter { $0.line == line && $0.stage == .perfect }
            let ultimates = graph.nodes.filter { $0.line == line && $0.stage == .ultimate }
            XCTAssertFalse(perfects.isEmpty, "`\(line)` has no Perfect rung")
            XCTAssertFalse(ultimates.isEmpty, "`\(line)` has Perfects and no Mega above them")
        }

        // US-162 added Shishimamon and Sirenmon to the rung this story opened — over Reppamon and
        // Hookmon, two more of `vital`'s leaf Champions — so the claim is a superset of this
        // story's own three rather than the rung's whole census.
        XCTAssertTrue(Set(graph.nodes.filter { $0.line == "vital" && $0.stage == .perfect }
            .map(\.id)).isSuperset(of: ["oboromon", "raijiludomon", "vital_darumamon"]))
        XCTAssertEqual(Set(graph.nodes.filter { $0.line == "xros" && $0.stage == .perfect }
            .map(\.id)), ["omegashoutmon", "omegashoutmon_x", "xros_etemon"])

        // Three lines were left with no Perfect rung at all; US-162 opened two of them and
        // `algomon` is the one that cannot be opened — see
        // `PerfectSweepSToZTests.testAlgomonCouldNotBeOpenedBecauseItsEggCannotReachSiesamon`.
        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertEqual(Set(graph.nodes.map(\.line)).subtracting(linesWithAPerfect),
                       ["algomon"])
    }

    /// **RAIJILUDOMON IS WHY `vital` HAD TO OPEN AT ALL**: its bolded `Evolves From` is Tia Ludomon
    /// and the only other drawable one is Reppamon, and BOTH are on `vital`. That is the Meicoomon
    /// shape US-160 recorded — a Digimon with no home anywhere else forces the rung rather than the
    /// rung being chosen. Oboromon then cost one node instead of three, because the floor and the
    /// line were already paid for.
    func testRaijiLudomonHadNoHomeOffVitalAndOboromonRodeAlong() throws {
        for id in ["tialudomon", "reppamon"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "vital",
                           "\(id) moved line — RaijiLudomon's forcing argument moves with it")
        }
        XCTAssertEqual(graph.parents(of: "raijiludomon").map(\.id), ["tialudomon"])

        // Oboromon's own citations reach five lines, four of which already had a Perfect rung —
        // so it did NOT force `vital` and is on it by choice, which the comment argues.
        for id in ["dokugumon", "fugamon", "ginryumon", "musyamon"] {
            XCTAssertNotEqual(try XCTUnwrap(graph.node(id: id)).line, "vital",
                              "\(id) is on `vital` now, so Oboromon's alternatives moved")
        }
        XCTAssertEqual(graph.parents(of: "oboromon").map(\.id), ["kokeshimon"])
        XCTAssertTrue(try authoredComment(on: "oboromon").contains("Kokeshimon"))
    }

    /// **`vital`'s WHOLE EGG LIST AT ONCE**, the third time a Perfect sweep has promoted a line's
    /// eggs by opening the rung rather than by lengthening a thread — after US-158's four `wanyamon`
    /// eggs and US-160's two `diablomon` ones. Every `vital` Child falls to Kokeshimon when
    /// neglected, so one of the two threads promotes all five. `EggHatchingTests` moves with this.
    func testVitalsFiveDigitamaWereAllPromotedAtOnce() throws {
        let eggs = graph.nodes(at: .digitama).filter { $0.line == "vital" }.map(\.id).sorted()
        XCTAssertEqual(eggs, ["ludo_digitama", "morpho_digitama", "pulse_digitama",
                              "sunariza_digitama", "zuba_digitama"])
        for id in eggs {
            XCTAssertTrue(graph.reachesUltimate(from: id),
                          "\(id) no longer reaches an Ultimate — `EggHatchingTests` moves with it")
        }

        // US-159's claim, restated where it still holds: no egg on a line that HAS a Perfect rung
        // is unraisable. `adventure02` is the reason Paildramon went elsewhere — see below.
        let unraisableLines = Set(graph.nodes(at: .digitama)
            .filter { !$0.dexOnly && !graph.reachesUltimate(from: $0.id) }
            .map(\.line))
        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertTrue(unraisableLines.isDisjoint(with: linesWithAPerfect),
                      "an egg is unraisable on a line that HAS a Perfect rung — a sweep can fix it")
    }

    /// **`xros` PROMOTED NOTHING AND COULD NOT HAVE**, and the four nodes this story put on it are
    /// unreachable from any egg — which is inherited from Shoutmon King rather than chosen. The line
    /// has no Digitama at all: US-144 and US-145 spent all fifty-seven, so no story at this rung or
    /// any rung above it can fix that. The nodes are worth authoring anyway, for the same reason
    /// US-157's `penc-sw` three were: a Digimon that evolves into something is a Dex entry with a
    /// tree, while one that does neither is a dead sprite.
    func testTheFourNewXrosNodesAreStrandedByInheritanceRatherThanByChoice() throws {
        XCTAssertEqual(graph.nodes(at: .digitama).filter { $0.line == "xros" }, [],
                       "`xros` has an egg now — then its whole line can be raised")

        var reached = Set(graph.nodes(at: .digitama).map(\.id))
        var frontier = Array(reached)
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        for id in ["omegashoutmon", "omegashoutmon_x", "xros_etemon", "zekegreymon"] {
            XCTAssertFalse(reached.contains(id), "\(id) is reachable — `EvolutionCriteriaTests`' "
                            + "stranded list moves with it")
            // Stranded ONLY through a parent that was already stranded, which is what makes this
            // inheritance rather than a node nobody wired.
            XCTAssertFalse(graph.parents(of: id).isEmpty, "\(id) has no in-edge at all")
            for parent in graph.parents(of: id) {
                XCTAssertFalse(reached.contains(parent.id),
                               "\(id) has a reachable parent and should not be stranded")
            }
        }
    }

    /// **PAILDRAMON DID NOT OPEN `adventure02`, AND THE REASON IS AN EGG.** XV-mon is a cited parent
    /// and was that line's last leaf, so the arrow was available — but `adventure02` carries two
    /// Digitama and only V Digitama descends through XV-mon. Worm Digitama descends through Wormmon
    /// to Sorcerymon, which has no Perfect above it and no orphan in this band that could give it
    /// one, so opening the rung would have broken the invariant
    /// `testVitalsFiveDigitamaWereAllPromotedAtOnce` checks. The node went to XV-mon Black on
    /// `penc-wg` instead: a cited parent, the variant of the very Champion the citation names, with
    /// the cited Ulforce V-dramon already above it.
    ///
    /// **US-162 FOUND THE ARROW THIS STORY COULD NOT**, and it is the one Champion this story did
    /// not consider: Nise Drimogemon, the line's JUNK Adult, which takes the `isDefault` fall of
    /// V-mon, Wormmon AND Tinkermon. Branching it promotes BOTH eggs at once, so the rung opened
    /// without stranding anything. The claim below therefore flips rather than dying — what is
    /// still checked is that Paildramon did NOT move there with it, and that XV-mon, the Champion
    /// this story rejected, is still the leaf that made the rejection right.
    func testPaildramonLeftAdventure02ClosedBecauseOfWormDigitama() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "paildramon")).line, "penc-wg")
        XCTAssertEqual(graph.parents(of: "paildramon").map(\.id), ["xv-mon_black"])
        XCTAssertFalse(graph.nodes.filter { $0.line == "adventure02" && $0.stage == .perfect }
            .isEmpty, "`adventure02` lost the Perfect rung US-162 opened under its junk Champion")

        // XV-mon really is still the leaf it was, and Sorcerymon really does still lead nowhere —
        // which is what makes US-162's answer the junk Champion rather than either of these.
        for id in ["xv-mon", "sorcerymon"] {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(node.line, "adventure02")
            XCTAssertTrue(node.evolutions.isEmpty,
                          "\(id) was wired onward — then `adventure02` wants re-arguing whole")
        }
        XCTAssertTrue(graph.reachesUltimate(from: "worm_digitama"),
                      "Worm Digitama stopped reaching a Mega — US-162's Vermillimon carries it")

        // The rejected reading is written into the node, so the story that opens `adventure02` is
        // told Paildramon is its rehome candidate rather than having to notice.
        let comment = try authoredComment(on: "paildramon")
        XCTAssertTrue(comment.contains("XV-mon"), "the rejected `adventure02` reading is not named")
        XCTAssertTrue(comment.contains("Worm Digitama"), "the reason it was rejected is not given")
    }

    // MARK: - AC3: lines are grouped coherently

    /// No edge in the file crosses a line, still — the rule that decides every placement here.
    func testNoEdgeCrossesALine() {
        for node in graph.nodes {
            for edge in node.evolutions {
                guard let target = graph.node(id: edge.to) else { continue }
                XCTAssertEqual(node.line, target.line,
                               "\(node.id) (\(node.line)) -> \(edge.to) (\(target.line)) crosses a line")
            }
        }
    }

    /// Twenty-one lines, exactly as before: this story opened a RUNG on two of them, not a line.
    func testTheSweepOpenedNoNewLines() {
        XCTAssertEqual(Set(graph.nodes.map(\.line)).count, 21)

        let sizes = Dictionary(grouping: graph.nodes, by: \.line).mapValues(\.count)
        XCTAssertEqual(sizes["vital"], 42, "Oboromon, RaijiLudomon, their two Megas and the floor, plus US-163's one Ultimate")
        XCTAssertEqual(sizes["xros"], 22, "both OmegaShoutmon, ZekeGreymon and the Etemon floor, plus US-163's one Ultimate")
        XCTAssertEqual(sizes["penc-me"], 71,
                       "both Okuwamon, their two Megas and RizeGreymon X, plus US-163's four Ultimates")
        XCTAssertEqual(sizes["penc-nsp"], 43, "both Panjyamon, plus US-163's one Ultimate")
        XCTAssertEqual(sizes["tamers"], 117, "Rapidmon and SaintGalgomon, plus US-163's eight Ultimates")
        XCTAssertEqual(sizes["wanyamon"], 29, "RizeGreymon and Ravmon")
        XCTAssertEqual(sizes["dmc-v1"], 39, "NeoDevimon, plus US-163's three Ultimates")
        XCTAssertEqual(sizes["penc-nso"], 75, "Orochimon, plus US-163's seven Ultimates")
        XCTAssertEqual(sizes["penc-vb"], 60, "Regulusmon, plus US-163's two Ultimates")
        XCTAssertEqual(sizes["penc-wg"], 45, "Paildramon")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.perfect)?.line }).count, 10)
    }

    /// **ALL FOUR VARIANTS SIT WITH THEIR BASE FORM AND THREE OF THE FOUR ON ITS OWN PARENT** — the
    /// strongest reading the variant rule has, and the one US-160 recorded as usually free at this
    /// rung. The fourth, RizeGreymon X, follows a cited parent instead: `wanyamon` holds the plain
    /// RizeGreymon and offers the X form neither a cited parent nor a cited climb, so honouring the
    /// line would have meant inventing an arrow at both ends. That is the escape hatch
    /// `ChildSweepMToZTests.testEveryVariantSitsWithItsBaseFormOrFollowsACitedParent` opened.
    func testEveryVariantSitsWithItsBaseFormOrFollowsACitedParent() throws {
        for (variant, base) in [("okuwamon_x", "okuwamon"),
                                ("omegashoutmon_x", "omegashoutmon"),
                                ("panjyamon_x", "panjyamon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line,
                           "\(variant) is not on \(base)'s line")
            XCTAssertEqual(Set(graph.parents(of: variant).map(\.id)),
                           Set(graph.parents(of: base).map(\.id)),
                           "\(variant) no longer hangs off \(base)'s own parent")
        }

        // And the one that does not, with the reason pinned at both ends.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "rizegreymon")).line, "wanyamon")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "rizegreymon_x")).line, "penc-me")
        XCTAssertEqual(graph.parents(of: "rizegreymon_x").map(\.id), ["omekamon"])
        XCTAssertEqual(graph.nodes.filter { $0.line == "wanyamon" && $0.stage == .ultimate }
            .map(\.id).sorted(), ["ancientvolcamon", "dinotigermon", "ravmon", "tengumon"],
                       "`wanyamon` gained a Mega — then RizeGreymon X's exile wants re-arguing")
        XCTAssertTrue(try authoredComment(on: "rizegreymon_x").contains("Omekamon"))

        // Each variant is on a distinct energy from its base form where they share a Champion —
        // the distinct-energy rule, which is what makes both branches reachable.
        for parent in ["kuwagamon_x", "shoutmon_king", "pencnsp_leomon"] {
            let earned = try XCTUnwrap(graph.node(id: parent)).evolutions.filter { !$0.isDefault }
            XCTAssertEqual(Set(earned.compactMap(\.requiredEnergy)).count, earned.count,
                           "\(parent) offers two branches on the same energy")
        }
    }

    /// **BOTH OKUWAMON HANG OFF ONE LEAF CHAMPION, AND THAT IS WHY THE BOLDED PARENT WENT UNSPENT.**
    /// Kuwagamon on `dmc-v4` is the bolded `Evolves From` for the base form and holds a cited climb
    /// of its own — but `dmc-v4` holds NO cited climb for Okuwamon (X-Antibody), so taking the bold
    /// would have split the pair across two lines. Kuwagamon (X-Antibody) is cited on BOTH pages and
    /// was a leaf, so one arrow apiece clears a dead end and keeps the pair together.
    func testBothOkuwamonTookTheLeafKuwagamonXRatherThanTheBoldedKuwagamon() throws {
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "kuwagamon_x")).line, "penc-me")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "kuwagamon")).line, "dmc-v4")
        for id in ["okuwamon", "okuwamon_x"] {
            XCTAssertEqual(graph.parents(of: id).map(\.id), ["kuwagamon_x"])
        }
        XCTAssertFalse(try XCTUnwrap(graph.node(id: "kuwagamon")).evolutions.map(\.to)
            .contains(where: ["okuwamon", "okuwamon_x"].contains),
                       "the bolded Kuwagamon took one after all — then this claim wants rewriting")

        // Each got its OWN bolded Mega rather than converging, which is what the two pages draw.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "okuwamon")).evolutions.map(\.to),
                       ["grankuwagamon"])
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "okuwamon_x")).evolutions.map(\.to),
                       ["grandiskuwagamon"])
        XCTAssertTrue(try authoredComment(on: "okuwamon").contains("Kuwagamon"),
                      "the bolded parent that was not taken is not named")
    }

    /// **THREE CANONICAL CLIMBS IN THIS STORY ARE IDLE-ONLY, WHICH IS THE MACHGAOGAMON SHAPE
    /// US-160 RECORDED.** Done Devimon over NeoDevimon, and Shine Greymon and Victory Greymon over
    /// RizeGreymon, are all bolded on their Wikimon pages and all dexOnly in this pack, so
    /// `edgeToDexOnlyNode` forbids the edge and the cited alternative is taken instead. The day one
    /// gains an animated sheet this test says so and the climb is worth revisiting.
    func testTheThreeBoldedClimbsThisStoryCouldNotDrawAreStillIdleOnly() throws {
        for id in ["donedevimon", "shinegreymon", "victorygreymon"] {
            XCTAssertEqual(roster.entry(id: id)?.dexOnly, true,
                           "\(id) is animated now — the canonical climb became drawable")
            XCTAssertNil(graph.node(id: id), "a dexOnly Digimon may not be a node")
        }
        XCTAssertTrue(try authoredComment(on: "neodevimon").contains("Done Devimon"))
        XCTAssertTrue(try authoredComment(on: "rizegreymon").contains("Shine Greymon"))
    }

    // MARK: - the engine really takes these edges

    /// No Champion offers two earned branches on one energy — `EvolutionEngine` picks on the
    /// dominant energy first, so a second branch sharing an energy would be dead data.
    func testNoChampionThisStoryBranchedOffersTwoBranchesOnOneEnergy() throws {
        for parent in Set(swept.map(\.parent)) {
            let node = try XCTUnwrap(graph.node(id: parent))
            let earned = node.evolutions.filter { !$0.isDefault }
            let energies = earned.compactMap(\.requiredEnergy)
            XCTAssertEqual(energies.count, earned.count, "\(parent) has an ungated earned branch")
            XCTAssertEqual(Set(energies).count, energies.count,
                           "\(parent) offers two branches on the same energy")
            XCTAssertLessThanOrEqual(node.evolutions.count, 5,
                                     "five is the ceiling `EvolutionCriteriaTests` sets")
        }

        // **DEVIMON ON `dmc-v1` IS NOW THREE EARNED BRANCHES PLUS ITS FALL, AND ITS LAST FREE
        // ENERGY IS THE ONE THE FALL ALREADY USES.** MetalGreymon (Virus) took spirit in the seed
        // roster, its X form strength in US-160 and NeoDevimon takes stamina here; vitality is what
        // is left, and the fall to BlackKingNumemon asks for spirit. So a fourth earned branch here
        // is possible but the node is effectively full, and the next `dmc-v1` Perfect should expect
        // a different Champion — the same note US-160 left on Wizarmon.
        let devimon = try XCTUnwrap(graph.node(id: "devimon"))
        XCTAssertEqual(Set(devimon.evolutions.filter { !$0.isDefault }.compactMap(\.requiredEnergy)),
                       [.spirit, .stamina, .strength])
        XCTAssertEqual(devimon.evolutions.first(where: \.isDefault)?.requiredEnergy, .spirit)
    }

    /// Every edge this story authored is really reachable through the engine, criteria and all —
    /// the check that separates an authored edge from a taken one.
    func testEveryNewBranchIsTakenByTheEngineWhenItIsEarned() throws {
        for (perfect, parent, ultimate) in swept {
            for (from, to) in [(parent, perfect), (perfect, ultimate)] {
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

    /// And a neglected Champion falls to junk instead. Read through `scheduledEvolutionTarget` with
    /// the gate open and an EMPTY context, which is what "the owner did nothing" actually looks
    /// like — `evolutionTarget` matches on the dominant energy and a neglected Digimon has none.
    func testANeglectedChampionFallsToItsLinesJunkPerfect() throws {
        for (parent, junk) in junkFloors {
            XCTAssertEqual(
                EvolutionEngine.scheduledEvolutionTarget(
                    for: try XCTUnwrap(graph.node(id: parent)), stageEnergy: EnergyTotals(),
                    dominant: nil, careMistakes: 9, battleWins: 0,
                    stageEnteredAt: .distantPast, now: Date(), conditions: .unknown),
                junk,
                "a neglected \(parent) does not fall to \(junk)")
        }
    }

    /// The window trap US-150 shipped into a first draft: `care.battleCount` and
    /// `care.battleWinRatio` are answerable only over `lifetime` and every other `care.*` counter
    /// only over `stage`, so an edge that asks the other way is UNREACHABLE rather than merely hard.
    func testNoCriterionThisStoryAuthoredAsksForAWindowTheContextCannotAnswer() throws {
        for id in Set(swept.map(\.perfect) + swept.map(\.parent)) {
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

    // MARK: - AC5/AC6: the sprites are real, and nothing on an edge is dexOnly

    /// Stronger than "the file exists": an idle-only 16x16 sprite fails here rather than shipping as
    /// a Digimon that cannot animate. Applied to all twenty-four new nodes — the two junk floors
    /// separately, because they are aliases and so have no roster entry of their own.
    func testEveryNodeThisStoryAddedIsASliceableSheet() throws {
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) {
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

        for (id, _, _, _) in authoredFloors {
            let floor = try XCTUnwrap(graph.node(id: id))
            let sheet = try XCTUnwrap(
                SpriteSheetCache.shared.sheet(stage: floor.stage.rawValue, name: floor.spriteFile))
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

    /// AC7: every new node has a line, and a line the file already knew. A blank one would trap
    /// `EvolutionGraph.bundled` at launch through `emptyLine`; a typo'd one would silently make a
    /// nameless Dex group, which is what the count in `testTheSweepOpenedNoNewLines` catches.
    func testEveryNodeThisStoryAddedHasAKnownLine() throws {
        let known = Set(graph.nodes.map(\.line))
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate)
            + authoredFloors.map(\.id) {
            let line = try XCTUnwrap(graph.node(id: id)).line
            XCTAssertFalse(line.isEmpty, "\(id) has no line")
            XCTAssertTrue(known.contains(line), "\(id) is on the unknown line \(line)")
        }
    }

    // MARK: - AC: every choice is recorded in the data file

    /// Every node this story added carries a comment, and each one either cites Wikimon or says in
    /// as many words that it could not — the rule US-146 set and every sweep since has kept.
    func testEveryNodeThisStoryAddedCitesItsSourceOrSaysItCannot() throws {
        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate)
            + authoredFloors.map(\.id) {
            let comment = try authoredComment(on: id)
            XCTAssertTrue(comment.contains("Wikimon") || comment.contains("NO CITATION")
                            || comment.contains("no citation") || comment.contains("FLAVOUR"),
                          "\(id)'s comment neither cites a source nor says it has none")
        }

        // The rejected and undrawable readings are written down too, so the story that revisits one
        // is told which arrow was considered and why it lost rather than having to re-derive it.
        XCTAssertTrue(try authoredComment(on: "orochimon").contains("Deltamon"),
                      "Orochimon's better-flavoured rejected parent is not named")
        XCTAssertTrue(try authoredComment(on: "rapidmon").contains("Black Rapidmon"),
                      "Rapidmon's other bolded climb is not named")
        XCTAssertTrue(try authoredComment(on: "regulusmon").contains("Siriusmon"),
                      "Regulusmon's flavour-perfect climbs are not named")
        XCTAssertTrue(try authoredComment(on: "panjyamon").contains("Gankoomon"),
                      "Panjyamon's rejected `dmc-v4` reading is not named")
    }

    /// **OMEGASHOUTMON X HAS NO CITED PARENT AND NO CITED CLIMB ON ANY ONE LINE, AND THE COMMENT
    /// SAYS SO RATHER THAN IMPLYING ONE.** Its four drawable `Evolves From` are on `tamers`,
    /// `penc-me` and `dmc-v3`, and its `Evolves To` reach `wanyamon` and `palmon` — so no line
    /// anywhere holds both ends. The variant rule decided it, and the node admits it.
    func testOmegaShoutmonXHadNoLineWithBothEndsCitedAndSaysSo() throws {
        let comment = try authoredComment(on: "omegashoutmon_x")
        XCTAssertTrue(comment.contains("NO CITED PARENT AND NO CITED CLIMB"),
                      "the dead end is not admitted")

        // Its cited parents really are all elsewhere, and none of their lines holds a cited climb.
        for (parent, line) in [("meramon_x", "tamers"), ("siesamon_x", "tamers"),
                               ("omekamon", "penc-me"), ("scumon", "dmc-v3")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: parent)).line, line)
            XCTAssertFalse(try XCTUnwrap(graph.node(id: parent)).evolutions.map(\.to)
                .contains("omegashoutmon_x"),
                           "\(parent) took OmegaShoutmon X after all — then the comment is stale")
        }
        for (climb, line) in [("dinotigermon", "wanyamon"), ("tigervespamon", "palmon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: climb)).line, line)
        }
        XCTAssertEqual(graph.parents(of: "omegashoutmon_x").map(\.id), ["shoutmon_king"])
    }

    // MARK: - the handover

    /// **The handover to US-162, in the shape US-151 through US-160 established: a claim, not a
    /// note.** What the S-Z Perfect sweep inherits is seven brand-new Ultimate leaves of this
    /// story's own, THREE lines with no Perfect rung rather than five, and a dead-end ledger four
    /// lower. Pinned so the next sweep is told the shape of its job rather than having to count it.
    func testWhatThisSweepHandsToTheRestOfThePerfectRung() throws {
        for id in authoredUltimates.map(\.ultimate) {
            XCTAssertTrue(try XCTUnwrap(graph.node(id: id)).evolutions.isEmpty,
                          "\(id) leads somewhere, which nothing at the top rung may")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).stage, .ultimate)
        }

        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertEqual(Set(graph.nodes.map(\.line)).subtracting(linesWithAPerfect),
                       ["algomon"],
                       "a line gained or lost its Perfect rung; the remaining sweeps' bill changed")

        let linesWithAnUltimate = Set(graph.nodes.filter { $0.stage == .ultimate }.map(\.line))
        XCTAssertEqual(linesWithAPerfect.subtracting(linesWithAnUltimate), [],
                       "a line has Perfects and no Mega above them again — US-158 closed the last")

        XCTAssertEqual(graph.nodes.filter { $0.evolutions.isEmpty && $0.stage != .ultimate }.count,
                       59, "the dead-end ledger in `ChildSweepAToFTests` has moved")

        // The three Saiyu Warriors Perfects US-157 pinned were still owed here, and all three are
        // S-Z, so they were US-162's — which took all three onto `penc-sw`, closing the pin US-157
        // opened. Same claim, other side.
        for id in ["sagomon", "sanzomon", "shawujinmon"] {
            XCTAssertNotNil(roster.entry(id: id), "\(id) is on disk, which is why it was owed")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "penc-sw",
                           "\(id) left the Saiyu Warriors line US-157 opened the rung on")
        }
    }

    // MARK: - AC8/AC7: the orphan count, and the whole file still validates

    /// FIFTEEN Perfects plus SEVEN Ultimates, counted with Appendix B of the PRD over a regenerated
    /// `roster.generated.json`: **193 before, 171 after; the Perfect bucket falls 37 -> 22 and the
    /// Ultimate bucket 140 -> 133**. Twenty-two rather than twenty-four, because `vital_darumamon`
    /// and `xros_etemon` are aliases and remove no orphan. Asserted rather than only noted, because
    /// the count is the one claim in `notes` a later reader cannot re-derive from the diff.
    func testTheTwentyTwoOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 15)
        XCTAssertEqual(authoredUltimates.count, 7)

        for id in swept.map(\.perfect) + authoredUltimates.map(\.ultimate) {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertNotNil(roster.entry(id: id),
                            "\(id) has no roster entry, so it cannot have been an orphan")
            XCTAssertFalse(graph.parents(of: id).isEmpty && node.evolutions.isEmpty,
                           "\(id) is still an orphan")
        }
        for (id, _, _, _) in authoredFloors {
            XCTAssertNil(roster.entry(id: id), "\(id) removed an orphan after all")
        }

        XCTAssertEqual(graph.nodes.count, 851, "736 before this story")
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189, "148 before this story")
        XCTAssertEqual(graph.nodes(at: .ultimate).count, 172, "98 before this story, 138 after US-163")
    }

    /// Every Ultimate this story opened serves exactly the Perfects named here, so a parent hung on
    /// one later fails this rather than passing quietly — the `Set(graph.parents(of:))` equality
    /// shape every sweep since US-151 has established.
    func testTheSevenUltimatesThisStoryOpenedServeExactlyTheNamedPerfects() throws {
        for (ultimate, parents, line) in authoredUltimates {
            let node = try XCTUnwrap(graph.node(id: ultimate))
            XCTAssertEqual(node.stage, .ultimate)
            XCTAssertEqual(node.line, line, "\(ultimate) is not on its Perfect's line")
            XCTAssertEqual(Set(graph.parents(of: ultimate).map(\.id)), parents,
                           "\(ultimate)'s parents changed without this claim changing with them")
        }
        XCTAssertEqual(Set(authoredUltimates.map(\.ultimate)).count, authoredUltimates.count)
    }

    func testTheGraphValidatesWithNoFindings() {
        XCTAssertEqual(EvolutionGraph.bundled.validate().map(\.description), [])
    }

    // MARK: - Helpers

    /// Appendix B's "connected" set: everything with an out-edge, plus everything anybody points at.
    private var connectedIds: Set<String> {
        Set(graph.nodes.filter { !$0.evolutions.isEmpty }.map(\.id))
            .union(graph.nodes.flatMap { $0.evolutions.map(\.to) })
    }

    /// A context that satisfies `edge`'s criteria, derived FROM the edge rather than shared — the
    /// helper US-151 wrote, kept because several of this story's edges ask for FEW overfeeds, FEW
    /// daylight minutes, or MANY sleep disturbances, and a blanket "did everything right" context
    /// is the one thing that cannot take an `atMost`.
    ///
    /// Orochimon is why it also handles an `atLeast` on `care.overfeeds`, which no earlier sweep
    /// needed: the eight-headed serpent is earned by letting all eight heads eat past full, which
    /// is the same "reward the neglect every other edge punishes" shape US-159's Lucemon Falldown
    /// and US-160's Meicrackmon: Vicious Mode had on sleep disturbances.
    private func context(for edge: EvolutionEdge) -> ConditionContext {
        var values = met.stageTotals?.values ?? [:]
        var training = 30
        var overfeeds = 0
        var disturbances = 0

        for condition in edge.conditions {
            switch (condition.knownMetric, condition.comparison) {
            case (.careTrainingSessions, .atMost): training = 0
            case (.careOverfeeds, .atMost): overfeeds = 0
            case (.careOverfeeds, .atLeast): overfeeds = Int(condition.value) + 1
            case (.careSleepDisturbances, .atMost): disturbances = 0
            case (.careSleepDisturbances, .atLeast): disturbances = Int(condition.value) + 1
            case (.some(let metric), .atMost) where metric.isHealthMetric:
                values[metric.rawValue] = 0
            default: break
            }
        }

        return ConditionContext(
            stageTotals: MetricTotals(values: values),
            trainingSessionsThisStage: training,
            overfeedsThisStage: overfeeds,
            sleepDisturbancesThisStage: disturbances,
            battlesLifetime: 40,
            battleWinRatioLifetime: 1.0)
    }

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-160 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) has no comment")
    }
}
