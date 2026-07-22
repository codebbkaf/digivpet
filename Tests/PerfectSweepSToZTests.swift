import XCTest

@testable import DigiVPet

/// US-162 — the nineteenth of Phase E's orphan sweeps and the sixth at the Perfect rung: the
/// twenty-two playable Perfect whose display name begins S-Z that no device tree, Champion sweep or
/// earlier Perfect sweep reached. **They were every Perfect still orphaned anywhere, so this story
/// closes the rung: the Perfect bucket goes 22 -> 0 and no later sweep can add to it.**
///
/// **Twenty-two orphans, twenty-seven nodes, and TWO more lines gained a Perfect rung.**
/// `commandramon` opened because Ginryumon and Damemon are the cited parents of Triceramon
/// (X-Antibody) and SkullBaluchimon and both were leaves, and the two X-Antibody Perfects share one
/// cited Mega — Chaosdramon (X-Antibody) — so the line cost four nodes rather than six.
/// `adventure02` opened under Nise Drimogemon, which is the answer to the problem US-161 could not
/// solve: it is that line's JUNK Champion and takes the `isDefault` fall of V-mon, Wormmon AND
/// Tinkermon, so branching it promotes BOTH eggs at once where branching XV-mon would have promoted
/// one. 171 -> 146.
///
/// **`algomon` STAYS CLOSED, and that is this story's one unfinished thing.** Siesamon is the only
/// Champion on it that any orphan in this band cites, and Siesamon sits on the Labramon thread,
/// which descends from `paomon` — one of the thirteen Baby I no Digitama can reach since US-145
/// spent all fifty-seven eggs. Ghost Digitama, `algomon`'s only egg, reaches Algomon (Adult),
/// Mimicmon and Witchmon and nothing else, so opening the rung under Siesamon would have left an
/// egg unraisable on a line that HAS a Perfect rung — the invariant US-159 set and
/// `testNoEggIsUnraisableOnALineThatHasAPerfectRung` below still enforces. Shishimamon went to
/// `vital` under Reppamon instead, with the cited Zanbamon already above it, and `algomon` is
/// handed on to the Ultimate sweeps.
///
/// **Six of the eight leaf Champions this story branched are now off the dead-end ledger**, 73 ->
/// 67. Both new floors are line-scoped ALIASES, and both are UNCITED — the first junk floors in
/// this series Wikimon does not draw, because neither Damemon nor Ginryumon nor Nise Drimogemon
/// cites a junk Perfect at all. Their comments say so rather than implying a source.
final class PerfectSweepSToZTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled

    /// The twenty-two orphaned Perfects this story wired, with the Champion that now reaches each
    /// and the Ultimate each now climbs into. Every one is a plain roster id, so every one removes
    /// an orphan.
    private let swept: [(perfect: String, parent: String, ultimate: String)] = [
        ("sagomon", "lianpumon", "shakamon"),
        ("sanzomon", "hakubamon", "shakamon"),
        ("saviorhackmon", "firamon", "pencnso_boltmon"),
        ("scorpiomon", "kuwagamon_x", "pencme_mugendramon"),
        ("sekkamon", "shellmon", "ryugumon"),
        ("shawujinmon", "tsuchidarumon", "shakamon"),
        ("shishimamon", "reppamon", "zanbamon"),
        ("shootmon", "minotaurmon", "kazuchimon"),
        ("sirenmon", "hookmon", "regalecusmon"),
        ("skullbaluchimon", "damemon", "chaosdramon_x"),
        ("superstarmon", "omekamon", "princemamemon"),
        ("tekkamon", "guardromon", "pencme_hiandromon"),
        ("triceramon", "monochromon", "darkdramon"),
        ("triceramon_x", "ginryumon", "chaosdramon_x"),
        ("vamdemon_x", "musyamon", "venomvamdemon"),
        ("vermillimon", "nisedrimogemon", "blackwargreymon"),
        ("waruseadramon", "pencds_seadramon", "leviamon"),
        ("weregarurumon_black", "garurumon_black", "cresgarurumon"),
        ("weregarurumon_x", "pencnso_garurumon", "pencnso_metalgarurumon"),
        ("xingtianmon", "ginkakumon", "seitengokuwmon"),
        ("yatagaramon", "xv-mon_black", "hououmon"),
        ("yatagaramon_2006", "pencwg_birdramon", "griffomon"),
    ]

    /// The three Ultimates this story authored, and the line each landed on. All three are leaves,
    /// as every Ultimate in this file is. Chaosdramon X is the one with two parents, and
    /// deliberately: it is cited on BOTH SkullBaluchimon's and Triceramon (X-Antibody)'s pages,
    /// which is what made `commandramon` cost four nodes rather than six.
    private let authoredUltimates: [(ultimate: String, parents: Set<String>, line: String)] = [
        ("chaosdramon_x", ["skullbaluchimon", "triceramon_x"], "commandramon"),
        ("blackwargreymon", ["vermillimon"], "adventure02"),
        ("regalecusmon", ["sirenmon"], "vital"),
    ]

    /// The eight Champions that were LEAVES before this story, and the junk Perfect each now falls
    /// to. Six floors already existed; `commandramon_karakurumon` and `adventure02_jyagamon` are
    /// this story's, and both are aliases — see
    /// `testTheTwoNewJunkFloorsAreAliasesAndTheFirstUncitedOnesInThisSeries`.
    private let junkFloors: [(parent: String, junk: String)] = [
        ("lianpumon", "pandamon"),
        ("tsuchidarumon", "pandamon"),
        ("reppamon", "vital_darumamon"),
        ("hookmon", "vital_darumamon"),
        ("damemon", "commandramon_karakurumon"),
        ("ginryumon", "commandramon_karakurumon"),
        ("nisedrimogemon", "adventure02_jyagamon"),
        ("garurumon_black", "gerbemon"),
    ]

    /// The two junk floors this story had to author, with the sheet each draws and the line that
    /// already owns that sheet under the plain id.
    private let authoredFloors: [(id: String, sprite: String, line: String, plainOwner: String)] = [
        ("commandramon_karakurumon", "Karakurumon", "commandramon", "karakurumon"),
        ("adventure02_jyagamon", "Jyagamon", "adventure02", "jyagamon"),
    ]

    /// The shared "did everything right" context, US-151's through US-161's exactly.
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
    func testEveryPlayablePerfectSToZIsANodeWithAnInEdge() throws {
        let inRange = roster.entries.filter {
            $0.stage == .perfect && !$0.dexOnly
                && ("S"..."Z").contains(String($0.displayName.prefix(1)).uppercased())
        }
        // Thirty-three, not the thirty-eight nodes the graph holds in this band: `Roster.bundled`
        // reads `Resources/roster.json`, one entry per SHEET on disk, while the graph also carries
        // the line-scoped ALIASES — five of them here (`dmcv2_vademon`, `pencds_whamon` and the
        // three extra Were Garurumon). The roster count is the right denominator for "every
        // Digimon on disk is obtainable"; Appendix B's script reads `roster.generated.json` and so
        // counts the aliases too.
        XCTAssertEqual(inRange.count, 33)

        for entry in inRange {
            let node = try XCTUnwrap(graph.node(id: entry.id),
                                     "\(entry.id) (\(entry.displayName)) is not in evolutions.json")
            XCTAssertFalse(graph.parents(of: node.id).isEmpty, "\(node.id) has no in-edge")
        }

        // The twenty-two this story owns lead somewhere too.
        for (perfect, _, _) in swept {
            XCTAssertFalse(try XCTUnwrap(graph.node(id: perfect)).evolutions.isEmpty,
                           "\(perfect) leads nowhere — a Dex entry with no tree")
        }
    }

    /// The Appendix B orphan rule rerun over the whole rung rather than only over this story's
    /// range: **this is the sweep that closes the Perfect stage, so the assertion is global.**
    func testNoPlayablePerfectAnywhereIsStillAnOrphan() {
        let orphans = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly }
            .map(\.id)
            .filter { !connectedIds.contains($0) }
        XCTAssertEqual(orphans, [], "Perfects still orphaned after the rung closed: \(orphans)")
    }

    /// And no Perfect in range is a leaf either — unlike US-161's band, which handed Pandamon on.
    /// Every S-Z Perfect leads somewhere, including the ones earlier stories wired.
    func testNoPerfectSToZIsALeaf() throws {
        let leaves = roster.entries
            .filter { $0.stage == .perfect && !$0.dexOnly
                && ("S"..."Z").contains(String($0.displayName.prefix(1)).uppercased()) }
            .map(\.id)
            .filter { graph.node(id: $0)?.evolutions.isEmpty == true }
            .sorted()
        XCTAssertEqual(leaves, [], "S-Z Perfects that lead nowhere: \(leaves)")
    }

    // MARK: - AC2/AC4: the shape of every edge this story authored

    /// Each swept Perfect climbs by exactly one `isDefault` edge, gated on energy and on care but
    /// carrying no criteria — the shape every Perfect in this file has had since US-134. US-020
    /// takes the `isDefault` edge exactly when nothing else qualifies, so a condition on one would
    /// be data that lies about how it is taken. What the criterion binds is the EARNED edges.
    func testEverySweptPerfectClimbsByOneGatedDefaultEdge() throws {
        for (perfect, _, ultimate) in swept {
            let node = try XCTUnwrap(graph.node(id: perfect))
            XCTAssertEqual(node.evolutions.count, 1, "\(perfect) is not a single climb")

            let climb = try XCTUnwrap(node.evolutions.first)
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

    /// **EIGHT Champions came off the dead-end ledger, and TWO LINES needed a junk node that did
    /// not exist.** A leaf Champion has no fallback because it has no edges at all; the moment it
    /// gains an earned branch, `EvolutionCriteriaTests` requires an `isDefault` edge onto a junk
    /// Perfect of its OWN line. `commandramon` and `adventure02` had no Perfect rung at all, so
    /// this story paid the bill US-157 paid for `penc-sw`, US-160 for `diablomon` and US-161 for
    /// `vital` and `xros` — and the floor is per-LINE, so Damemon and Ginryumon share one exactly
    /// as Kokeshimon and Tia Ludomon shared `vital_darumamon`.
    func testTheEightLeafChampionsGainedTheirLinesJunkFloor() throws {
        for (parent, junk) in junkFloors {
            let node = try XCTUnwrap(graph.node(id: parent))
            XCTAssertEqual(node.evolutions.count, 2,
                           "\(parent) is not one earned branch plus a fallback")
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

        // Two floors are this story's; the other TWO in use here pre-dated it. Written from the
        // finished `junkFloors` table rather than from the plan, which is the mistake US-161
        // recorded when its own bookkeeping line went stale mid-authoring.
        XCTAssertEqual(Set(junkFloors.map(\.junk)).intersection(authoredFloors.map(\.id)),
                       ["adventure02_jyagamon", "commandramon_karakurumon"])
        XCTAssertEqual(Set(junkFloors.map(\.junk)).subtracting(authoredFloors.map(\.id)),
                       ["gerbemon", "pandamon", "vital_darumamon"])

        // The other fourteen Champions were ALREADY branching, so none needed a floor.
        let alreadyBranching = Set(swept.map(\.parent)).subtracting(junkFloors.map(\.parent))
        XCTAssertEqual(alreadyBranching,
                       ["firamon", "ginkakumon", "guardromon", "hakubamon", "kuwagamon_x",
                        "minotaurmon", "monochromon", "musyamon", "omekamon", "pencds_seadramon",
                        "pencnso_garurumon", "pencwg_birdramon", "shellmon", "xv-mon_black"])
        for parent in alreadyBranching {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(graph.node(id: parent)).evolutions.count, 3,
                                        "\(parent) was a leaf after all, so it needed a floor")
        }
    }

    /// **BOTH NEW JUNK FLOORS ARE ALIASES, AND BOTH ARE UNCITED — THE FIRST IN THIS SERIES WIKIMON
    /// DOES NOT DRAW.** `vital_darumamon` and `xros_etemon` were each on their Champion's own
    /// `Evolves To`; Damemon's runs Andromon, Cerberumon X, Cho·Hakkaimon, Lilimon X and
    /// MegaloGrowmon X, Ginryumon's twenty names hold no junk Perfect either, and Nise
    /// Drimogemon's runs Atlur Kabuterimon (Blue), Digitamamon, DORUguremon, Drimogemon, Insekimon
    /// and Tortamon. So the argument is shape rather than citation, and each comment says the word
    /// FLAVOUR rather than implying a source.
    func testTheTwoNewJunkFloorsAreAliasesAndTheFirstUncitedOnesInThisSeries() throws {
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

            XCTAssertTrue(try authoredComment(on: id).contains("FLAVOUR"),
                          "\(id) implies a citation it does not have")
        }
    }

    /// **TWO MORE LINES GAINED A PERFECT RUNG AND A MEGA IN ONE STORY**, which is US-158's rule: a
    /// sweep that opens a Perfect rung on a line with none owes an Ultimate over it in the same
    /// story, or it re-opens the gap it just closed one rung lower.
    func testCommandramonAndAdventure02GainedBothOfTheirMissingRungsAtOnce() throws {
        for line in ["commandramon", "adventure02"] {
            let perfects = graph.nodes.filter { $0.line == line && $0.stage == .perfect }
            let ultimates = graph.nodes.filter { $0.line == line && $0.stage == .ultimate }
            XCTAssertFalse(perfects.isEmpty, "`\(line)` has no Perfect rung")
            XCTAssertFalse(ultimates.isEmpty, "`\(line)` has Perfects and no Mega above them")
        }

        XCTAssertEqual(Set(graph.nodes.filter { $0.line == "commandramon" && $0.stage == .perfect }
            .map(\.id)), ["skullbaluchimon", "triceramon_x", "commandramon_karakurumon"])
        XCTAssertEqual(Set(graph.nodes.filter { $0.line == "adventure02" && $0.stage == .perfect }
            .map(\.id)), ["vermillimon", "adventure02_jyagamon"])

        // `algomon` alone is left, and the next test says why it could not be this story's.
        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertEqual(Set(graph.nodes.map(\.line)).subtracting(linesWithAPerfect), ["algomon"])
    }

    /// **`adventure02` OPENED UNDER ITS JUNK CHAMPION, WHICH IS THE ANSWER US-161 WAS LOOKING FOR.**
    /// That story left the line closed because XV-mon carries only V Digitama and opening the rung
    /// there would have stranded Worm Digitama. Nise Drimogemon takes the `isDefault` fall of all
    /// THREE Children — V-mon, Wormmon and Tinkermon — so one earned branch off it promotes both
    /// eggs at once, and Vermillimon is cited off it three times over.
    func testAdventure02OpenedUnderTheJunkChampionSoBothEggsWerePromoted() throws {
        let nise = try XCTUnwrap(graph.node(id: "nisedrimogemon"))
        XCTAssertEqual(nise.line, "adventure02")
        XCTAssertEqual(Set(graph.parents(of: "nisedrimogemon").map(\.id)),
                       ["v-mon", "wormmon", "tinkermon"],
                       "the junk Champion no longer catches all three Children — both eggs move")
        XCTAssertEqual(graph.parents(of: "vermillimon").map(\.id), ["nisedrimogemon"])

        for id in ["v_digitama", "worm_digitama"] {
            XCTAssertTrue(graph.reachesUltimate(from: id),
                          "\(id) is unraisable — `EggHatchingTests` moves with it")
        }

        // XV-mon and Sorcerymon really are still the leaves US-161 described, so the reason this
        // worked is the junk Champion rather than anything having changed under them.
        for id in ["xv-mon", "sorcerymon", "parasaurmon"] {
            XCTAssertTrue(try XCTUnwrap(graph.node(id: id)).evolutions.isEmpty,
                          "\(id) was wired onward — then this argument wants re-checking")
        }
        XCTAssertTrue(try authoredComment(on: "vermillimon").contains("Worm Digitama"),
                      "the reason this Champion was chosen is not written into the node")
    }

    /// **`algomon` IS THE ONE LINE THIS STORY COULD NOT FINISH, AND THE REASON IS PERMANENT.**
    /// Siesamon is the only `algomon` Champion any Perfect orphan cites, and it descends from
    /// Labramon <- Xiaomon <- Paomon — a Baby I with no in-edge, one of the thirteen US-145 left
    /// unreachable when the fifty-seventh Digitama was spent. Ghost Digitama reaches Algomon
    /// (Adult), Mimicmon and Witchmon and stops. So opening the rung under Siesamon would have
    /// broken US-159's invariant, and no Perfect sweep can open it any other way, because the
    /// Perfect rung is closed as of this story.
    func testAlgomonCouldNotBeOpenedBecauseItsEggCannotReachSiesamon() throws {
        XCTAssertEqual(graph.nodes.filter { $0.line == "algomon" && $0.stage == .perfect }, [],
                       "`algomon` has a Perfect rung now — then Ghost Digitama needs one too")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "siesamon")).line, "algomon")
        XCTAssertTrue(try XCTUnwrap(graph.node(id: "siesamon")).evolutions.isEmpty,
                      "Siesamon was branched after all — say which Perfect took it")

        // Paomon really has no in-edge, which is what makes the thread unreachable.
        XCTAssertTrue(graph.parents(of: "paomon").isEmpty,
                      "Paomon gained an egg — then `algomon` can be opened after all")

        var reached: Set<String> = ["ghost_digitama"]
        var frontier = ["ghost_digitama"]
        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }
        XCTAssertFalse(reached.contains("siesamon"),
                       "Ghost Digitama reaches Siesamon now — then `algomon` can be opened")
        XCTAssertEqual(reached.intersection(["algomon_adult", "mimicmon", "witchmon"]).count, 3,
                       "the three Adults the egg does reach have changed")

        // And Shishimamon says so in its own comment, so the Ultimate sweep that revisits
        // `algomon` is told the shape of the problem rather than having to re-derive it.
        let comment = try authoredComment(on: "shishimamon")
        XCTAssertTrue(comment.contains("Siesamon"), "the parent that was not taken is not named")
        XCTAssertTrue(comment.contains("Ghost Digitama"), "the reason it was not taken is not given")
    }

    /// US-159's invariant, restated as the general rule this story had to obey rather than as a
    /// claim about one line: no egg is unraisable on a line that HAS a Perfect rung. `algomon` is
    /// the only line where an egg cannot climb, and it is also the only line with no Perfect rung,
    /// which is exactly why the two facts sit together.
    func testNoEggIsUnraisableOnALineThatHasAPerfectRung() {
        let unraisable = graph.nodes(at: .digitama)
            .filter { !$0.dexOnly && !graph.reachesUltimate(from: $0.id) }
        XCTAssertEqual(unraisable.map(\.id), ["ghost_digitama"],
                       "the unraisable-egg list moved; `EggHatchingTests` moves with it")

        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertTrue(Set(unraisable.map(\.line)).isDisjoint(with: linesWithAPerfect),
                      "an egg is unraisable on a line that HAS a Perfect rung")
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
        XCTAssertEqual(sizes["penc-sw"], 18, "Sagomon, Sanzomon, Shawujinmon and Xingtianmon")
        XCTAssertEqual(sizes["penc-me"], 63, "Scorpiomon, Shootmon, Superstarmon and Tekkamon")
        XCTAssertEqual(sizes["penc-nso"], 62,
                       "SaviorHackmon, Vamdemon X and WereGarurumon X")
        XCTAssertEqual(sizes["penc-wg"], 42, "both Yatagaramon")
        XCTAssertEqual(sizes["commandramon"], 15,
                       "SkullBaluchimon, Triceramon X, Chaosdramon X and the Karakurumon floor")
        XCTAssertEqual(sizes["adventure02"], 18,
                       "Vermillimon, BlackWarGreymon and the Jyagamon floor")
        XCTAssertEqual(sizes["vital"], 41, "Shishimamon, Sirenmon and Regalecusmon")
        XCTAssertEqual(sizes["dmc-v2"], 30, "WereGarurumon Black")
        XCTAssertEqual(sizes["dmc-v3"], 52, "Sekkamon")
        XCTAssertEqual(sizes["dmc-v4"], 30, "Triceramon")
        XCTAssertEqual(sizes["penc-ds"], 44, "WaruSeadramon")
        XCTAssertEqual(sizes["algomon"], 12, "unchanged — see the Siesamon test above")

        XCTAssertEqual(Set(swept.map { graph.node(id: $0.perfect)?.line }).count, 11)
    }

    /// **THE SAIYU WARRIORS QUARTET IS FINALLY WHOLE, WHICH IS THE PIN US-157 LEFT AND EVERY SWEEP
    /// SINCE HAS CARRIED.** Sagomon, Sanzomon and Shawujinmon join Gokuwmon and Cho·Hakkaimon on
    /// `penc-sw`, and Xingtianmon with them; Sagomon and Shawujinmon are Sha Wujing twice, under the
    /// Japanese and the Chinese spelling, which is why they are on one line rather than split.
    func testTheThreeSaiyuWarriorsPerfectsUS157PinnedAreAllOnPencSw() throws {
        for id in ["sagomon", "sanzomon", "shawujinmon", "xingtianmon"] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).line, "penc-sw",
                           "\(id) left the Saiyu Warriors line")
        }
        XCTAssertEqual(Set(graph.nodes.filter { $0.line == "penc-sw" && $0.stage == .perfect }
            .map(\.id)),
                       ["chohakkaimon", "gokuwmon", "pandamon", "sagomon", "sanzomon",
                        "shawujinmon", "xingtianmon"])

        // Three of the four converge on Shakamon, which the pages draw as the party fusing.
        XCTAssertEqual(Set(graph.parents(of: "shakamon").map(\.id)),
                       ["chohakkaimon", "sagomon", "sanzomon", "shawujinmon"])
        XCTAssertEqual(Set(graph.parents(of: "seitengokuwmon").map(\.id)),
                       ["gokuwmon", "xingtianmon"])
    }

    /// **SHAWUJINMON HAS NO CITED PARENT ON ITS LINE AND TOOK THE JUNK CHAMPION, AND THE COMMENT
    /// SAYS BOTH.** Its bolded `Evolves From` is Gawappamon on `penc-ds`, and none of its eleven
    /// other cited parents is on `penc-sw` either — but Shakamon, its BOLDED `Evolves To`, exists
    /// only there. So the climb decided the line and Tsuchidarumon, `penc-sw`'s junk Adult, carries
    /// the branch: the Scumon arrangement US-133 recorded, where a junk Champion holds an earned
    /// arrow as well as the fall.
    func testShawujinmonTookThePencSwJunkChampionAndSaysWhy() throws {
        XCTAssertEqual(graph.parents(of: "shawujinmon").map(\.id), ["tsuchidarumon"])
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "gawappamon")).line, "penc-ds",
                       "Gawappamon moved to `penc-sw` — then the bolded arrow is drawable")
        XCTAssertFalse(try XCTUnwrap(graph.node(id: "gawappamon")).evolutions.map(\.to)
            .contains("shawujinmon"))

        // Tsuchidarumon is really the junk Adult: all three `penc-sw` Children fall into it.
        let tsuchi = try XCTUnwrap(graph.node(id: "tsuchidarumon"))
        XCTAssertEqual(tsuchi.line, "penc-sw")
        for parent in graph.parents(of: "tsuchidarumon") {
            XCTAssertEqual(parent.evolutions.first { $0.to == "tsuchidarumon" }?.isDefault, true,
                           "\(parent.id) reaches Tsuchidarumon by an earned branch now")
        }

        let comment = try authoredComment(on: "shawujinmon")
        XCTAssertTrue(comment.contains("NO CITED PARENT"), "the dead end is not admitted")
        XCTAssertTrue(comment.contains("Gawappamon"), "the bolded parent is not named")
    }

    /// **BOTH VARIANTS THAT COULD SIT WITH THEIR BASE FORM DO, AND THE TWO THAT COULD NOT SAY SO.**
    /// Were Garurumon X hangs off the very Champion the plain Were Garurumon hangs off on
    /// `penc-nso` and climbs its Mega, and Yatagaramon 2006 shares a line and a Mega-family with
    /// the plain Yatagaramon. Vamdemon X shares its base form's line and one of its two Champions.
    /// Triceramon X is the exception and follows a cited parent instead — `dmc-v4`, where the plain
    /// Triceramon goes, offers it a parent and NO cited climb whatever, which is the escape hatch
    /// `ChildSweepMToZTests.testEveryVariantSitsWithItsBaseFormOrFollowsACitedParent` opened.
    func testEveryVariantSitsWithItsBaseFormOrFollowsACitedParent() throws {
        for (variant, base) in [("weregarurumon_x", "pencnso_weregarurumon"),
                                ("yatagaramon_2006", "yatagaramon"),
                                ("vamdemon_x", "vamdemon")] {
            XCTAssertEqual(try XCTUnwrap(graph.node(id: variant)).line,
                           try XCTUnwrap(graph.node(id: base)).line,
                           "\(variant) is not on \(base)'s line")
        }

        // The strongest form — same parent — holds for Were Garurumon X and for Vamdemon X.
        XCTAssertEqual(Set(graph.parents(of: "weregarurumon_x").map(\.id)),
                       Set(graph.parents(of: "pencnso_weregarurumon").map(\.id)))
        XCTAssertTrue(Set(graph.parents(of: "vamdemon_x").map(\.id))
            .isSubset(of: Set(graph.parents(of: "vamdemon").map(\.id))),
                      "Vamdemon X no longer hangs off one of its base form's own Champions")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "vamdemon_x")).evolutions.map(\.to),
                       try XCTUnwrap(graph.node(id: "vamdemon")).evolutions.map(\.to),
                       "Vamdemon X no longer converges on its base form's own Mega")

        // And the one that does not, with the reason pinned at both ends.
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "triceramon")).line, "dmc-v4")
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "triceramon_x")).line, "commandramon")
        XCTAssertEqual(graph.parents(of: "triceramon_x").map(\.id), ["ginryumon"])
        XCTAssertTrue(try authoredComment(on: "triceramon_x").contains("Ginryumon"))

        // Each variant is on a distinct energy from anything else its Champion carries.
        for parent in Set(swept.map(\.parent)) {
            let earned = try XCTUnwrap(graph.node(id: parent)).evolutions.filter { !$0.isDefault }
            XCTAssertEqual(Set(earned.compactMap(\.requiredEnergy)).count, earned.count,
                           "\(parent) offers two branches on the same energy")
        }
    }

    /// **THREE NODES IN THIS STORY HAVE NO DRAWABLE CITED PARENT AT ALL, AND EACH ADMITS IT.**
    /// Shootmon is the worst of them — Exermon, Namakemon and Runnermon have no sheet in this pack
    /// whatever, so unlike US-160's Mephismon X there is not even a parent the file knows. In every
    /// case the CLIMB chose the line and a flavour argument chose the Champion.
    func testTheNodesWithNoDrawableCitedParentSayItInAsManyWords() throws {
        for id in ["shootmon", "shawujinmon", "vamdemon_x"] {
            let comment = try authoredComment(on: id)
            XCTAssertTrue(comment.uppercased().contains("NO CITED PARENT")
                            || comment.uppercased().contains("NO DRAWABLE CITED PARENT"),
                          "\(id) does not admit that its parent is uncited")
        }

        // Shootmon's three cited parents really are absent from the roster, not merely dexOnly.
        for id in ["exermon", "namakemon", "runnermon"] {
            XCTAssertNil(roster.entry(id: id), "\(id) is on disk now — Shootmon can be re-argued")
        }
        XCTAssertEqual(graph.parents(of: "shootmon").map(\.id), ["minotaurmon"])
        XCTAssertEqual(try XCTUnwrap(graph.node(id: "kazuchimon")).line, "penc-me",
                       "Shootmon's only cited climb moved line — the whole placement moves with it")
    }

    /// **FALCOMON IS IDLE-ONLY, WHICH IS THE MACHGAOGAMON SHAPE FOR THE FOURTH TIME.** It is
    /// Yatagaramon's sole BOLDED `Evolves From` and its 2006 counterpart is the 2006 form's, and
    /// both are dexOnly in this pack, so `edgeToDexOnlyNode` forbids the canonical arrow. The day
    /// either gains an animated sheet this test says so and the placement is worth revisiting.
    func testBothFalcomonAreStillIdleOnlySoTheBoldedArrowStaysUndrawable() throws {
        for id in ["falcomon", "falcomon_2006"] {
            XCTAssertEqual(roster.entry(id: id)?.dexOnly, true,
                           "\(id) is animated now — Yatagaramon's canonical parent became drawable")
            XCTAssertNil(graph.node(id: id), "a dexOnly Digimon may not be a node")
        }
        XCTAssertTrue(try authoredComment(on: "yatagaramon").contains("FALCOMON"))
    }

    // MARK: - the engine really takes these edges

    /// No Champion offers two earned branches on one energy — `EvolutionEngine` picks on the
    /// dominant energy first, so a second branch sharing an energy would be dead data — and none
    /// is over the five-edge ceiling.
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

        // **REVOLMON AND THUNDERBALLMON ARE FULL, AND THAT IS WHY OMEKAMON CARRIES SUPERSTARMON.**
        // Wikimon cites all three as `penc-me` parents; the first two spend all four energies
        // across three earned branches and a fall, so a fourth branch on either would have to
        // share an energy with an existing EARNED one, which `EvolutionEngine` cannot resolve.
        for id in ["revolmon", "thunderballmon"] {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(node.evolutions.filter { !$0.isDefault }.count, 3,
                           "\(id) is no longer full — Superstarmon could go there after all")
        }

        // And Ebidramon, which is why Sirenmon left `penc-ds` for `vital`: four earned branches,
        // one on every energy there is.
        let ebidramon = try XCTUnwrap(graph.node(id: "ebidramon"))
        XCTAssertEqual(Set(ebidramon.evolutions.filter { !$0.isDefault }
            .compactMap(\.requiredEnergy)).count, EnergyType.allCases.count,
                       "Ebidramon has a free energy now — Sirenmon's exile wants re-arguing")
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
    /// a Digimon that cannot animate. Applied to all twenty-seven new nodes — the two junk floors
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
        XCTAssertTrue(try authoredComment(on: "sekkamon").contains("Yukinamon"),
                      "Sekkamon's bolded-but-rejected `tamers` reading is not named")
        XCTAssertTrue(try authoredComment(on: "superstarmon").contains("STARMON, THE BOLDED"),
                      "Superstarmon's bolded parent is not named")
        XCTAssertTrue(try authoredComment(on: "sirenmon").contains("KIWIMON, THE BOLDED"),
                      "Sirenmon's bolded parent is not named")
        XCTAssertTrue(try authoredComment(on: "saviorhackmon").contains("JESmon"),
                      "SaviorHackmon's bolded climb is not named")
        XCTAssertTrue(try authoredComment(on: "scorpiomon").contains("Anomalocarimon"),
                      "the Scorpiomon/Anomalocarimon dub collision is not recorded")
        XCTAssertTrue(try authoredComment(on: "weregarurumon_black").contains("inverted"),
                      "WereGarurumon Black's inverted care gate is not explained")
    }

    /// **WEREGARURUMON BLACK IS EARNED BY LOSING, WHICH NO OTHER EDGE IN THIS STORY IS.** It is the
    /// Digimon a WereGarurumon becomes when it is beaten, so the care criterion asks for a losing
    /// record — the Lucemon Falldown shape US-159 recorded. Proven through the engine in both
    /// directions rather than argued: a winner does not reach it, a loser does.
    func testWereGarurumonBlackIsEarnedByLosingRatherThanByWinning() throws {
        let node = try XCTUnwrap(graph.node(id: "garurumon_black"))
        let edge = try XCTUnwrap(node.evolutions.first { $0.to == "weregarurumon_black" })
        let ratio = try XCTUnwrap(edge.conditions.first { $0.metric == "care.battleWinRatio" })
        XCTAssertEqual(ratio.comparison, .atMost, "the losing gate became a winning one")

        var totals = EnergyTotals()
        totals[try XCTUnwrap(edge.requiredEnergy)] = edge.minEnergy
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals,
                                            dominant: edge.requiredEnergy, careMistakes: 0,
                                            battleWins: 40, conditions: met),
            nil,
            "a Garurumon (Black) that won everything still becomes WereGarurumon Black")
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: node, stageEnergy: totals,
                                            dominant: edge.requiredEnergy, careMistakes: 0,
                                            battleWins: 40, conditions: context(for: edge)),
            "weregarurumon_black",
            "a Garurumon (Black) that lost most of its fights does not turn")
    }

    // MARK: - the handover

    /// **The handover to the Ultimate sweeps, in the shape US-151 through US-161 established: a
    /// claim, not a note.** What US-163 onward inherit is a CLOSED Perfect rung, three brand-new
    /// Ultimate leaves of this story's own, one line still without a Perfect rung and a reason it
    /// cannot gain one, and a dead-end ledger six lower.
    func testWhatThisSweepHandsToTheUltimateRung() throws {
        for id in authoredUltimates.map(\.ultimate) {
            XCTAssertTrue(try XCTUnwrap(graph.node(id: id)).evolutions.isEmpty,
                          "\(id) leads somewhere, which nothing at the top rung may")
            XCTAssertEqual(try XCTUnwrap(graph.node(id: id)).stage, .ultimate)
        }

        let linesWithAPerfect = Set(graph.nodes.filter { $0.stage == .perfect }.map(\.line))
        XCTAssertEqual(Set(graph.nodes.map(\.line)).subtracting(linesWithAPerfect), ["algomon"],
                       "a line gained or lost its Perfect rung; the remaining sweeps' bill changed")

        let linesWithAnUltimate = Set(graph.nodes.filter { $0.stage == .ultimate }.map(\.line))
        XCTAssertEqual(linesWithAPerfect.subtracting(linesWithAnUltimate), [],
                       "a line has Perfects and no Mega above them again — US-158 closed the last")

        XCTAssertEqual(graph.nodes.filter { $0.evolutions.isEmpty && $0.stage != .ultimate }.count,
                       67, "the dead-end ledger in `ChildSweepAToFTests` has moved")

        // Ogudomon is still the one US-159 pinned in Lucemon Falldown's comment, and it is an
        // Ultimate, so it belongs to the sweeps after this one rather than to this one.
        XCTAssertNotNil(roster.entry(id: "ogudomon"))
        XCTAssertNil(graph.node(id: "ogudomon"), "Ogudomon is wired now — say which arrow it is")
    }

    // MARK: - AC8/AC7: the orphan count, and the whole file still validates

    /// TWENTY-TWO Perfects plus THREE Ultimates, counted with Appendix B of the PRD over a
    /// regenerated `roster.generated.json`: **171 before, 146 after; the Perfect bucket falls
    /// 22 -> 0 and the Ultimate bucket 133 -> 130**. Twenty-five rather than twenty-seven, because
    /// `commandramon_karakurumon` and `adventure02_jyagamon` are aliases and remove no orphan.
    /// Asserted rather than only noted, because the count is the one claim in `notes` a later
    /// reader cannot re-derive from the diff.
    func testTheTwentyFiveOrphansThisStoryRemovedAreAllPlainRosterIds() throws {
        XCTAssertEqual(swept.count, 22)
        XCTAssertEqual(authoredUltimates.count, 3)

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

        XCTAssertEqual(graph.nodes.count, 787, "760 before this story")
        XCTAssertEqual(graph.nodes(at: .perfect).count, 189, "165 before this story")
        XCTAssertEqual(graph.nodes(at: .ultimate).count, 108, "105 before this story")
    }

    /// Every Ultimate this story opened serves exactly the Perfects named here, so a parent hung on
    /// one later fails this rather than passing quietly — the `Set(graph.parents(of:))` equality
    /// shape every sweep since US-151 has established.
    func testTheThreeUltimatesThisStoryOpenedServeExactlyTheNamedPerfects() throws {
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
    /// helper US-151 wrote, kept because several of this story's edges ask for FEW overfeeds, LITTLE
    /// daylight, LITTLE sleep or MANY sleep disturbances, and a blanket "did everything right"
    /// context is the one thing that cannot take an `atMost`.
    ///
    /// WereGarurumon Black is why it also handles an `atMost` on `care.battleWinRatio`, which no
    /// earlier sweep needed: the black wolf is what a WereGarurumon becomes when it loses.
    private func context(for edge: EvolutionEdge) -> ConditionContext {
        var values = met.stageTotals?.values ?? [:]
        var training = 30
        var overfeeds = 0
        var disturbances = 0
        var winRatio = 1.0

        for condition in edge.conditions {
            switch (condition.knownMetric, condition.comparison) {
            case (.careTrainingSessions, .atMost): training = 0
            case (.careOverfeeds, .atMost): overfeeds = 0
            case (.careOverfeeds, .atLeast): overfeeds = Int(condition.value) + 1
            case (.careSleepDisturbances, .atMost): disturbances = 0
            case (.careSleepDisturbances, .atLeast): disturbances = Int(condition.value) + 1
            case (.careBattleWinRatio, .atMost): winRatio = 0
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
            battleWinRatioLifetime: winRatio)
    }

    /// `comment` is documentation the decoder drops, so it is read out of the raw JSON — the same
    /// helper US-144 through US-161 use.
    private func authoredComment(on id: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let node = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no node \(id)")
        return try XCTUnwrap(node["comment"] as? String, "\(id) has no comment")
    }
}
