import XCTest
@testable import DigiVPet

/// US-061: the shipped `evolutions.json` really branches, and neglect really costs something.
///
/// Every test here reads the REAL file. A fixture graph could satisfy all of it while the shipped
/// roster still marched every Digimon down a single line, which is the exact thing this story
/// exists to end.
final class EvolutionCriteriaTests: XCTestCase {
    private let graph = EvolutionGraph.bundled

    /// The junk destinations, named explicitly rather than inferred. A rule like "the default edge
    /// points at a node nothing else points at" would pass for a perfectly good Digimon that
    /// happens to be reached one way, and the whole claim here is about WHICH Digimon.
    ///
    /// `vegimon` and the line-scoped `dmcv2_vademon` joined the list in US-134: the device trees
    /// name their own junk Champion, and it is the one both of a version's Rookies fall to —
    /// Numemon in Ver.1, Vegimon in Ver.2, Scumon in Ver.3. Vegimon replaced Geremon as the Ver.2
    /// fallback for exactly that reason; Geremon is still reachable, as Elecmon's overfeeding
    /// branch.
    /// `platinumscumon` and `pumpmon` joined in US-138, and they are the first two that no source
    /// document names: the Pendulum Color V1 Nature Spirits section draws no junk branch at all,
    /// while every Child and Adult here needs one. US-138 chose them off the unused sheets — see
    /// their `comment`s in `evolutions.json`.
    /// `diginorimon` and `piranimon` joined in US-139 for the same reason as US-138's pair: the
    /// Pendulum Color V2 Deep Savers section draws no junk branch either, so this app chose a
    /// water-flavoured one off unused sheets — digital seaweed under a shoal of piranha.
    /// `gokimon` and `darumamon` joined in US-140, third time the same way: the Pendulum Color V3
    /// Nightmare Soldiers section draws no junk branch either. WaruMonzaemon was the first choice
    /// for the Perfect rung and had to be dropped — the Version 5 Metal Empire section draws it as
    /// an earned Ultimate, so it belongs to US-142. Grep the document before choosing a junk node.
    /// `turuiemon` and `andiramon_virus` joined in US-143, the last of the eleven device trees and
    /// the sixth to have to invent a junk branch. They are the Lopmon line's fall as Wikimon draws
    /// it, and they end at Cherubimon (Vice) — the counterpart of the Cherubimon (Virtue) the V0
    /// document puts over Wizardmon, so neglecting a Virus Buster turns it into what it was raised
    /// to fight.
    /// US-148 added SIX at once, and for a reason none of the earlier six had: the Child sweep is
    /// the first story to give an out-edge to a Child on a line that had no Champion rung at all.
    /// `algomon`, `commandramon`, `diablomon`, `penc-sw`, `tamers` and `wanyamon` were opened by
    /// US-144/US-145/US-146 as Digitama-to-Child threads, so each needed a junk floor before any of
    /// its Children could branch. Every one is a plain roster id off an unused sheet rather than a
    /// line-scoped alias, so each also removes an orphan: Numemon X is the franchise's junk
    /// Champion under its X-Antibody name (`numemon` is dmc-v1's), Manekimon a beckoning-cat
    /// figurine, Mimicmon a chest that pretends to be treasure, Troopmon a faceless mook, Damemon
    /// the washout its name says it is, and Tsuchidarumon a mud daruma. See their `comment`s.
    /// US-151 added TWO more, and they are the same problem one rung later: `wanyamon` and
    /// `tamers` had no PERFECT rung at all when the Adult A-D sweep needed an out-edge for
    /// BlackGaogamon and DarkLizamon, so each needed a junk floor before either could branch.
    /// Karakurumon is a clockwork puppet (following Manekimon, `wanyamon`'s beckoning-cat junk
    /// Champion) and CatchMamemon a crane-game cabinet (following Numemon X, the franchise's
    /// prize-junk Champion, on `tamers`); both are plain roster ids off unused sheets, so both
    /// remove an orphan. Neither name is anywhere in the tree markdown — the grep US-140 insists on.
    /// US-149 added the last TWO of that kind: `xros` and `vital` were the only lines still without
    /// a Champion rung when the Child G-L sweep reached them. Targetmon is a Xros Wars gag Digimon
    /// shaped like a shooting-gallery target and Kokeshimon a limbless painted doll; both are plain
    /// roster ids off unused sheets, so both remove an orphan rather than being aliases.
    /// US-157 added ONE, the first at the PERFECT rung since US-151: opening `penc-sw`'s Perfect
    /// rung for Cho-Hakkaimon meant Hakubamon became a branching Champion, and a branching Champion
    /// needs a floor. Pandamon is a stuffed-panda puppet off an unused sheet — a Chinese toy beside
    /// a Journey to the West line, following Tsuchidarumon the mud daruma, which US-148 chose as
    /// that same line's junk CHAMPION. It is a plain roster id, so it removes an orphan, and it is
    /// in no tree markdown — the grep US-140 insists on.
    /// US-160 added ONE, and it is the first junk floor in this list that is a LINE-SCOPED ALIAS
    /// rather than a plain roster id: `diablomon` had no Perfect rung at all when the M sweep put
    /// the two Meicrackmon over Meicoomon, and not one of the fifty-eight Perfect still orphaned
    /// when that story ran is junk-flavoured — so there was no unused sheet to spend the way
    /// CatchMamemon, Karakurumon and Pandamon were spent. `diablomon_gerbemon` draws the Gerbemon
    /// sheet under a line-scoped id, the `dmcv2_vademon` pattern, and so removes no orphan; a bag
    /// of rubbish is the right floor under Troopmon, the faceless mook US-148 chose as this line's
    /// junk CHAMPION. It is in no tree markdown either.
    /// US-161 added TWO more of exactly that kind, for exactly that reason: it opened the Perfect
    /// rung on `vital` (for Oboromon and RaijiLudomon) and on `xros` (for both OmegaShoutmon), and
    /// not one of the thirty-seven Perfect still orphaned when THAT story ran is junk-flavoured
    /// either — so `vital_darumamon` draws the Darumamon sheet and `xros_etemon` the Etemon sheet,
    /// both line-scoped, and neither removes an orphan. Both are cited rather than picked: Wikimon
    /// gives Darumamon on Kokeshimon's own `Evolves To` (a kokeshi doll falling into a daruma doll)
    /// and Etemon on Targetmon's, `xros`'s own junk CHAMPION. Neither is in any tree markdown.
    private static let junkIds: Set<String> = [
        // Adult
        "numemon", "scumon", "geremon", "karatsukinumemon", "goldnumemon", "raremon", "vegimon",
        "platinumscumon", "diginorimon", "gokimon", "zassoumon", "pencme_raremon", "turuiemon",
        "numemon_x", "manekimon", "mimicmon", "troopmon", "damemon", "tsuchidarumon",
        "targetmon", "kokeshimon", "nisedrimogemon",
        // Perfect
        "blackkingnumemon", "gerbemon", "jyagamon", "greatkingscumon", "vademon", "dmcv2_vademon",
        "etemon", "pumpmon", "piranimon", "darumamon", "tonosamagekomon", "locomon",
        "andiramon_virus", "karakurumon", "catchmamemon", "pandamon", "diablomon_gerbemon",
        "vital_darumamon", "xros_etemon", "commandramon_karakurumon", "adventure02_jyagamon",
        // Ultimate
        "kingetemon",
    ]

    private var branchingNodes: [EvolutionNode] {
        graph.nodes.filter { ($0.stage == .child || $0.stage == .adult) && !$0.evolutions.isEmpty }
    }

    // MARK: - AC1/AC2: a real choice, with a junk floor under it

    /// Two is the half that matters: a single outgoing edge is not a choice at all.
    ///
    /// The ceiling was three until US-133 — two earned branches plus the junk fallback — and four
    /// until US-134. It is now five, and the reason is data rather than taste: the Version 2 tree
    /// gives Gabumon five Champions (Kabuterimon, Garurumon, Angemon, Yukidarumon, Vegimon) and
    /// every one of them has a playable sheet, so nothing prunes it the way an undrawable Tyranomon
    /// pruned Agumon's fifth in US-133. Splitting them across the two Rookies is not open either:
    /// the document draws all five arrows out of Gabumon.
    ///
    /// US-133's note that "four is what the whole source document fits in" was simply wrong — V4's
    /// Palmon and V5's Gizamon are SIX wide in the document, and both US-134 and US-135 expected
    /// US-136 and US-137 to raise this again. NEITHER DID, and the reason is the same both times:
    /// each of those rows contains names with no animated sheet — Kokatorimon and Nanimon in
    /// Palmon's, Flymon in Gizamon's — so the DRAWABLE row is four earned branches plus the junk
    /// fallback. Price a ceiling raise off the drawable row, never off the document's. Five is also
    /// where this stops on its own: `SeedRosterTests`' distinct-energy rule allows four earned
    /// branches and there are only four energy types.
    ///
    /// It is raised one step at a time on purpose: the ceiling should never be looser than the file
    /// it guards. The Dex agrees at five — `DexRow.evolutionCandidates` draws a three-column grid,
    /// so five candidates are still two rows inside a sheet that scrolls.
    func testEveryNonTerminalChildAndAdultHasTwoToFiveOutgoingEdges() {
        XCTAssertFalse(branchingNodes.isEmpty)
        for node in branchingNodes {
            XCTAssertTrue((2...5).contains(node.evolutions.count),
                          "\(node.id) has \(node.evolutions.count) outgoing edges, not two to five")
        }
    }

    func testEveryNonTerminalChildAndAdultFallsToAJunkEvolution() throws {
        for node in branchingNodes {
            let fallback = try XCTUnwrap(EvolutionEngine.defaultEdge(of: node),
                                         "\(node.id) has no isDefault edge")
            XCTAssertTrue(Self.junkIds.contains(fallback.to),
                          "\(node.id) falls back to '\(fallback.to)', which is not a junk evolution")
        }
    }

    /// The junk edge has to be reachable by doing NOTHING — no energy threshold, no care-mistake
    /// ceiling that neglect would breach, and no criterion to satisfy. US-020's fallback ignores an
    /// edge's gates anyway, so a gated junk edge would be data that lies about how it is taken.
    func testEveryJunkFallbackIsReachableByInaction() throws {
        for node in branchingNodes {
            let fallback = try XCTUnwrap(EvolutionEngine.defaultEdge(of: node))
            XCTAssertEqual(fallback.minEnergy, 0, "\(node.id)'s junk edge demands energy")
            XCTAssertEqual(fallback.conditions, [], "\(node.id)'s junk edge carries criteria")
            XCTAssertNil(fallback.minBattleWins, "\(node.id)'s junk edge demands battle wins")
            XCTAssertGreaterThanOrEqual(fallback.maxCareMistakes, 99,
                                        "\(node.id)'s junk edge closes on care mistakes")
        }
    }

    /// The point of the story, stated as behaviour rather than as data: a Digimon whose owner did
    /// nothing at all still evolves once the time gate opens, and what it evolves into is junk.
    func testAnAgumonThatDidNothingBecomesNumemon() throws {
        let agumon = try XCTUnwrap(graph.node(id: "agumon"))
        let enteredAt = Date(timeIntervalSince1970: 0)
        let wellPastTheGate = enteredAt.addingTimeInterval(60 * 24 * 60 * 60)

        let target = EvolutionEngine.scheduledEvolutionTarget(
            for: agumon,
            stageEnergy: .zero,
            dominant: nil,
            careMistakes: 0,
            battleWins: 0,
            stageEnteredAt: enteredAt,
            now: wellPastTheGate,
            conditions: .unknown)

        XCTAssertEqual(target, "numemon")
    }

    // MARK: - AC3: the junk sprites exist

    /// Numemon and Scumon by name, because AC3 names them. Every other node's art is covered by
    /// `EvolutionGraphValidatorTests.testShippedEvolutionsJsonIsValid`, which resolves the whole
    /// roster against the real bundle.
    func testNumemonAndScumonAreRealNodesWithRealArt() throws {
        for id in ["numemon", "scumon"] {
            let node = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(node.stage, .adult)
            XCTAssertFalse(node.dexOnly)
            XCTAssertNotNil(SpriteLoader.url(stage: node.stage.rawValue, name: node.spriteFile),
                            "\(id): no art at \(node.stage.rawValue)/\(node.spriteFile).png")
        }
    }

    // MARK: - AC4: the Digital Monster Color band

    /// Greymon is the band node: training in the middle earns it, and BOTH ends fall to junk.
    /// Asserted through the engine rather than by reading the JSON back, because a band is only a
    /// band if `qualifies` treats the two conditions as a closed interval.
    func testGreymonIsEarnedByABandOfTrainingAndLostAtBothEnds() throws {
        let greymon = try XCTUnwrap(graph.node(id: "greymon"))
        let bandEdge = try XCTUnwrap(greymon.evolutions.first { $0.to == "metalgreymon" })
        let sessions = bandEdge.conditions.filter { $0.metric == "care.trainingSessions" }

        XCTAssertEqual(Set(sessions.map(\.comparison)), [.atLeast, .atMost],
                       "a band is an atLeast and an atMost on one metric")

        func qualifies(trainingSessions: Int) -> Bool {
            EvolutionEngine.qualifies(
                bandEdge,
                stageEnergy: EnergyTotals(strength: 999),
                dominant: .strength,
                careMistakes: 0,
                battleWins: 0,
                conditions: ConditionContext(
                    stageTotals: MetricTotals(values: ["health.exerciseMinutes": 100_000]),
                    trainingSessionsThisStage: trainingSessions))
        }

        XCTAssertTrue(qualifies(trainingSessions: 20), "the middle of the band earns Greymon's line")
        XCTAssertFalse(qualifies(trainingSessions: 0), "never training must fall to junk")
        XCTAssertFalse(qualifies(trainingSessions: 400),
                       "overtraining must be punished exactly as hard as undertraining")
    }

    // MARK: - AC5: a Perfect gated on battle performance as a RATIO

    /// Fifteen battles at eighty percent, following the real device. The ratio is what a win COUNT
    /// cannot say: fifteen wins out of two hundred battles must NOT open this branch.
    func testAPerfectEdgeIsGatedOnTheBattleWinRatioAndNotOnWinsAlone() throws {
        let etemon = try XCTUnwrap(graph.node(id: "etemon"))
        XCTAssertEqual(etemon.stage, .perfect)

        let edge = try XCTUnwrap(etemon.evolutions.first { $0.to == "bancholeomon" })
        XCTAssertFalse(edge.isDefault,
                       "a criterion on the isDefault edge never runs — US-020's fallback ignores gates")
        XCTAssertTrue(edge.conditions.contains { $0.metric == "care.battleWinRatio" })
        XCTAssertTrue(edge.conditions.contains { $0.metric == "care.battleCount" })

        func qualifies(battles: Int, winRatio: Double) -> Bool {
            EvolutionEngine.qualifies(
                edge,
                stageEnergy: EnergyTotals(vitality: 999),
                dominant: .vitality,
                careMistakes: 0,
                battleWins: 999,
                conditions: ConditionContext(battlesLifetime: battles,
                                             battleWinRatioLifetime: winRatio))
        }

        XCTAssertTrue(qualifies(battles: 20, winRatio: 0.9))
        XCTAssertFalse(qualifies(battles: 200, winRatio: 0.075),
                       "fifteen wins in two hundred battles is not an eighty percent record")
        XCTAssertFalse(qualifies(battles: 3, winRatio: 1.0), "a perfect record over nothing is nothing")
    }

    // MARK: - AC6: eight distinct metrics, from both families

    func testAtLeastEightDistinctMetricsAreAuthoredAcrossBothFamilies() {
        let metrics = Set(graph.nodes.flatMap(\.evolutions).flatMap(\.conditions).map(\.metric))

        XCTAssertGreaterThanOrEqual(metrics.count, 8, "authored metrics: \(metrics.sorted())")
        XCTAssertFalse(metrics.filter { $0.hasPrefix("health.") }.isEmpty)
        XCTAssertFalse(metrics.filter { $0.hasPrefix("care.") }.isEmpty)
    }

    // MARK: - AC9: the validator passes on the whole file

    func testTheAuthoredGraphPassesTheValidator() throws {
        let errors = try EvolutionGraph.load().validate()
        XCTAssertEqual(errors, [],
                       errors.map { "  - \($0.description)" }.joined(separator: "\n"))
    }

    // MARK: - AC10: no hint states a number

    /// A threshold printed into a hint goes stale the instant the edge is retuned, and the stale
    /// copy is worse than no copy — it tells the player a number the game no longer uses. US-065
    /// and US-066 own how a criterion's progress is actually shown.
    func testNoConditionHintContainsADigit() {
        for node in graph.nodes {
            for edge in node.evolutions {
                for condition in edge.conditions {
                    XCTAssertFalse(
                        condition.hint.contains(where: \.isNumber),
                        "\(node.id) -> \(edge.to): hint '\(condition.hint)' states a number")
                }
            }
        }
    }

    // MARK: - AC11: only metrics US-055 probed as usable

    /// Every authored `health.*` metric resolves to a HealthKit type the app can actually ask for.
    /// A metric with no `readObjectType` would never be granted, and HealthKit answers an
    /// unauthorized read with no samples — indistinguishable from a user who did not do the thing —
    /// so the edge would silently never fire.
    func testEveryAuthoredHealthMetricIsOneTheAppCanAskToRead() {
        let authored = graph.conditionHealthMetrics
        XCTAssertFalse(authored.isEmpty)

        for metric in authored {
            XCTAssertNotNil(metric.readObjectType, "\(metric.rawValue) has no HealthKit type to grant")
            XCTAssertTrue(HealthReadSet.bundled.objectTypes.contains(metric.readObjectType!),
                          "\(metric.rawValue) is authored but not in the read set")
        }
    }

    /// Every authored `health.*` metric accumulates, so a `window: .stage` total of it means
    /// something. A standing measurement like a resting heart rate is answerable only from a live
    /// reading, and nothing passes one today — an edge gated on one would be dead on arrival.
    func testEveryAuthoredHealthMetricAccumulatesOverTime() {
        for metric in graph.conditionHealthMetrics {
            XCTAssertTrue(metric.accumulatesOverTime,
                          "\(metric.rawValue) is a standing measurement and cannot be totalled")
        }
    }

    // MARK: - Every branch is reachable

    /// No authored Digimon is stranded. An orphan is invisible in play and shows up in the Dex tree
    /// as a node floating beside the ladder, which reads as a rendering bug rather than as content.
    ///
    /// **This was a zero until US-146, and the thirty below are the price of a fixed budget of
    /// eggs — not an oversight, and not something a later story can author away.** A Baby I's only
    /// possible parent is a Digitama; `EggHatcher.hatchTarget` reads `node.evolutions.first`, so an
    /// egg carries exactly ONE hatch edge; and there are 57 playable Digitama for 45 Baby I nodes
    /// but the pairing is not free — an egg can only open a Baby I on the thread its own species
    /// sits on. US-144 and US-145 spent all 57 and proved (`DigitamaSweepLToZTests`) that twelve
    /// was the most the last twenty-three could open, leaving THIRTEEN Baby I no egg can reach.
    /// US-146 authored them anyway, for their out-edges: a Digimon that evolves into something is a
    /// Dex entry with a tree, while one that does neither is a dead sprite. The next eight are the
    /// Baby II those thirteen open, unreachable for exactly the same reason and no other, and the
    /// last nine are the Children US-147 hung off those eight — the same thread, one rung further.
    ///
    /// US-148 added two Champions above those Children and US-149 seven more nodes for the same
    /// reason, so the list is now thirty-nine — but not one of them is a node nobody wired: every
    /// addition hangs off something already on the list, which is what the parent loops below check.
    ///
    /// The list is pinned rather than the check being relaxed, so a FORTIETH stranded node —
    /// which would be a real bug, at a rung where eggs are not the constraint — still fails here.
    /// Each of the two derived groups is also checked to be stranded ONLY through its parent, so
    /// the list cannot quietly absorb a node nobody bothered to wire.
    func testEveryNonEggNodeIsReachableFromSomeDigitama() {
        var reached = Set(graph.nodes(at: .digitama).map(\.id))
        var frontier = Array(reached)

        while let id = frontier.popLast() {
            for edge in graph.node(id: id)?.evolutions ?? [] where !reached.contains(edge.to) {
                reached.insert(edge.to)
                frontier.append(edge.to)
            }
        }

        let strandedBabyI = ["bombmon", "chibickmon", "curimon", "fufumon", "fukamon", "pafumon",
                             "paomon", "petitmon", "pupumon", "pururumon", "pusumon", "puyomon",
                             "pyonmon"]
        let strandedBabyII = ["babydmon", "mococomon", "monimon", "pickmon", "poromon",
                              "puroromon", "pusurimon", "xiaomon"]
        // Gaossmon is US-149's one addition, and it is inherited rather than chosen: Wikimon gives
        // it exactly one parent, Chibickmon, whose Baby II is Pickmon — and all three Baby II of
        // the `xros` line are already stranded, because that line has no Digitama and no egg is
        // left to give it one.
        // Starmon 2010 is US-150's one addition, and it is inherited for the same reason Gaossmon
        // was: Wikimon gives it exactly one Evolves From, Pickmon, and all three `xros` Baby II
        // are stranded because that line has no Digitama.
        let strandedChild = ["fujamon", "gaossmon", "gumdramon", "kakamon", "labramon", "ryudamon",
                             "shoutmon", "starmon_2010", "takinmon", "tinkermon", "xros_hagurumon"]
        // US-148's two: the Champions it hung over Fujamon, which is itself stranded. `penc-sw` has
        // no Digitama at all, so the whole Saiyu Warriors line is unreachable from the top of the
        // ladder down and always was — wiring the rung above Fujamon inherits that and cannot fix
        // it. Every other Child US-148 wired sits on a thread an egg reaches, which is why the list
        // grows by exactly two rather than by the twenty-three Champions the story authored.
        //
        // US-149's six are the same arithmetic one rung up, and the parent list below proves it:
        // every one hangs off a Child that was ALREADY on the list before this story, or off
        // Gaossmon. The Champion sweeps could not have chosen otherwise — a Child's Champion has to
        // sit on the Child's own line, and `xros` and `penc-sw` have no reachable Child at all.
        // US-150's five are the same arithmetic one rung up again, and the parent loop below
        // proves it: Dorulumon hangs off Starmon 2010, Shoutmon King off Shoutmon, Ginryumon off
        // Ryudamon, Hakubamon off Takinmon and Parasaurmon off Tinkermon — every one a Child that
        // was ALREADY on the list. The thirty-three Champions US-150 authored over a REACHABLE
        // Child are not here, which is what makes the list a claim rather than a dumping ground.
        let strandedAdult = ["arresterdramon", "dobermon", "dorulumon", "ginkakumon", "ginryumon",
                             "greymon_2010", "hakubamon", "lianpumon", "parasaurmon",
                             "shoutmon_king", "siesamon", "targetmon", "tsuchidarumon"]
        // US-157's THREE, and they are the same arithmetic two rungs further up: it opened
        // `penc-sw`'s Perfect rung over Hakubamon, which was ALREADY on the list above, so
        // Cho-Hakkaimon, the junk floor Pandamon under it and Shakamon over it inherit Hakubamon's
        // strandedness exactly. `penc-sw` has no Digitama — US-144 and US-145 spent all 57 — so no
        // story at this rung or any rung above it can fix that, and the parent loops below prove
        // this is inheritance rather than three nodes nobody bothered to wire. Every OTHER Perfect
        // US-157 authored sits on a line an egg reaches, which is what makes the list a claim.
        // US-158's two are the same inheritance again, one thread over: it hung Gokuwmon on
        // Ginkakumon — ALREADY on the Champion list above — and Seiten Gokuwmon over that, so both
        // inherit Ginkakumon's strandedness exactly and the parent loops below prove it.
        // US-161's FOUR are the same inheritance on the OTHER egg-less line: it opened `xros`'s
        // Perfect rung over Shoutmon King, which is ALREADY on the Champion list above, so both
        // OmegaShoutmon, the Etemon floor under them and ZekeGreymon over them inherit Shoutmon
        // King's strandedness exactly. `xros` has no Digitama — US-144 and US-145 spent all 57 —
        // so no story at this rung or above can fix it, and the parent loops below prove this is
        // inheritance rather than four nodes nobody wired. The other eleven Perfects that story
        // authored, INCLUDING the five that opened `vital`, all sit on lines an egg reaches, which
        // is what keeps this list a claim rather than a dumping ground.
        // US-162's FIVE are the last of this arithmetic, and they close the Perfect rung with it:
        // Sagomon and Sanzomon over Lianpumon and Hakubamon, Shawujinmon over Tsuchidarumon and
        // Xingtianmon over Ginkakumon — all four `penc-sw` Champions ALREADY on the list above —
        // and Triceramon X over Ginryumon, which has been on it since US-150. Their Megas, Shakamon
        // and Seiten Gokuwmon, were already stranded. Chaosdramon X is NOT here, because
        // SkullBaluchimon hangs off Damemon, which V-mon's own thread reaches; the `commandramon`
        // line is stranded down one branch and raisable down the other, and that is exactly the
        // distinction the parent loops below enforce.
        let strandedPerfect = ["chohakkaimon", "gokuwmon", "omegashoutmon", "omegashoutmon_x",
                               "pandamon", "sagomon", "sanzomon", "shawujinmon", "triceramon_x",
                               "xingtianmon", "xros_etemon"]
        // US-163's ONE, and it is the same inheritance a fourth time: Armamon's only cited parent
        // at the Perfect rung anywhere is OmegaShoutmon, which is on the list above because `xros`
        // has no Digitama. Its two other cited parents are an Adult and an Ultimate, so there was
        // never a second reading. The other twenty-nine Ultimates that story authored all sit on
        // lines an egg reaches, which is what keeps this a claim rather than a dumping ground.
        // US-165's Enmamon and Erlangmon join the stranded `penc-sw` list: Erlangmon climbs from
        // Pandamon and Enmamon from Gokuwmon, both already stranded because `penc-sw` (Saiyu
        // Warriors) has no Digitama in this pack. Every cited parent Enmamon has is an Ultimate, so
        // there was never an egg-reachable reading.
        let strandedUltimate = ["armamon", "enmamon", "erlangmon", "seitengokuwmon", "shakamon",
                                "zekegreymon"]

        let stranded = graph.nodes.map(\.id).filter { !reached.contains($0) }.sorted()
        XCTAssertEqual(stranded,
                       (strandedBabyI + strandedBabyII + strandedChild + strandedAdult
                           + strandedPerfect + strandedUltimate).sorted(),
                       "unreachable nodes: \(stranded)")

        // Every stranded Baby II is stranded ONLY because its single parent is one of the thirteen,
        // and every stranded Child ONLY because ITS parents are all among those eight. Without this
        // the list above could absorb a node that was simply never wired.
        for id in strandedBabyII {
            XCTAssertEqual(graph.parents(of: id).map(\.id).filter { !strandedBabyI.contains($0) }, [],
                           "\(id) has a reachable parent and should not be stranded")
        }
        for id in strandedChild {
            XCTAssertEqual(graph.parents(of: id).map(\.id).filter { !strandedBabyII.contains($0) }, [],
                           "\(id) has a reachable parent and should not be stranded")
        }
        for id in strandedAdult {
            XCTAssertEqual(graph.parents(of: id).map(\.id).filter { !strandedChild.contains($0) }, [],
                           "\(id) has a reachable parent and should not be stranded")
        }
        for id in strandedPerfect {
            XCTAssertEqual(graph.parents(of: id).map(\.id).filter { !strandedAdult.contains($0) }, [],
                           "\(id) has a reachable parent and should not be stranded")
        }
        for id in strandedUltimate {
            XCTAssertEqual(graph.parents(of: id).map(\.id).filter { !strandedPerfect.contains($0) }, [],
                           "\(id) has a reachable parent and should not be stranded")
        }
    }
}
