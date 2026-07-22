import Foundation
import XCTest

@testable import DigiVPet

/// Tests the SHIPPED roster data in `Resources/evolutions.json` — not the model that decodes it
/// (`EvolutionGraphTests` owns that, against a fixture). Everything here reads the real file, so
/// a broken seed fails the build rather than the app.
///
/// US-009 owns validating the graph in general (unknown ids, stage skips, missing art, ...).
/// These are the US-008 acceptance criteria specifically: the three lines exist, are complete,
/// are animated, and branch.
final class SeedRosterTests: XCTestCase {
    private var graph: EvolutionGraph!

    /// The seed lines, each as its full Digitama -> Ultimate default path.
    ///
    /// Written out as literals rather than derived from the file: a test that walks whatever the
    /// data says and asserts it matches the data would pass on any roster at all.
    ///
    /// Since US-061 every line's default path is its JUNK path — that is the whole point of the
    /// story: what a Digimon becomes when its owner does nothing is Numemon, not Greymon. US-044's
    /// Patamon line already had this shape through Scumon; US-061 gave the other five one too, and
    /// carried each of them all the way to a junk Ultimate so a neglected line still covers all
    /// seven rungs. Neglect changes WHICH Digimon you get, never whether you get one.
    ///
    /// The earned lines the original acceptance criteria name — Agumon to WarGreymon and so on —
    /// are pinned by `testTheThreeNamedLinesAreTheOnesShipped` instead, which follows the earned
    /// edges rather than the fallbacks.
    private let seedLines: [[String]] = [
        ["agu_digitama", "botamon", "koromon", "agumon", "numemon", "blackkingnumemon", "platinumnumemon"],
        // Since US-134 the Ver.2 junk path is Vegimon's, not Geremon's: a device tree's junk
        // Champion is the one BOTH of its Rookies fall to, and the document hangs Vegimon off
        // Gabumon and Elecmon alike. Geremon is still reachable and still junk — it is Elecmon's
        // overfeeding branch now, so this line moved rather than losing anything.
        ["gabu_digitama", "punimon", "tsunomon", "gabumon", "vegimon", "dmcv2_vademon", "dmcv2_ebemon"],
        ["pal_digitama", "yuramon", "tanemon", "palmon", "karatsukinumemon", "jyagamon", "shinmonzaemon"],
        ["pata_digitama", "puttimon", "tokomon", "patamon", "scumon", "etemon", "kingetemon"],
        ["piyo_digitama", "piyo_yuramon", "piyo_tanemon", "piyomon", "goldnumemon", "greatkingscumon", "boltmon"],
        ["gazi_digitama", "zurumon", "pagumon", "gazimon", "raremon", "vademon", "ebemon"],
        // US-138's Pendulum Color V1 Nature Spirits line. Its junk chain is the only one in the
        // file that no source document supplies: the Pendulum section draws no junk branch, so
        // PlatinumScumon, Pumpmon and NoblePumpmon were chosen off unused sheets (see their
        // `comment`s). Its egg is `tento_digitama` rather than a line-scoped one because maps.json
        // grants a Digitama by ROSTER id and an alias has no roster entry.
        ["tento_digitama", "pencnsp_botamon", "pencnsp_koromon", "pencnsp_agumon",
         "platinumscumon", "pumpmon", "noblepumpmon"],
        // US-139's Pendulum Color V2 Deep Savers line, the same shape: no junk branch in the
        // document, so Diginorimon, Piranimon and MetalPiranimon were chosen off unused sheets,
        // and its egg is `goma_digitama` — Gomamon's own, Gomamon being the Rookie its
        // In-Training falls to.
        ["goma_digitama", "pitchmon", "pukamon", "gomamon",
         "diginorimon", "piranimon", "metalpiranimon"],
        // US-140's Pendulum Color V3 Nightmare Soldiers line, the same shape again: no junk branch
        // in the document, so Gokimon, Darumamon and Deathmon were chosen off unused sheets,
        // and its egg is `baku_digitama` — Bakumon's own, Bakumon being the Rookie its In-Training
        // falls to.
        ["baku_digitama", "mokumon", "petimeramon", "bakumon",
         "gokimon", "darumamon", "deathmon"],
        // US-141's Pendulum Color V4 Wind Guardians line, the same shape once more: no junk branch
        // in the document, so Zassoumon, TonosamaGekomon and ElDoradimon were chosen off unused
        // sheets, and its egg is `flora_digitama` — Floramon's. It is the first Pendulum tree whose
        // egg is NOT its default Rookie's: Pyocomon falls to Piyomon, but Piyomon's own egg went to
        // dmc-v4 in US-136, so the egg is the next Rookie of this tree that has one.
        ["flora_digitama", "nyokimon", "pyocomon", "pencwg_piyomon",
         "zassoumon", "tonosamagekomon", "eldoradimon"],
        // US-142's Pendulum Color V5 Metal Empire line, the same shape a fifth time: no junk branch
        // in the document, so Raremon, Locomon and GrandLocomon were chosen off sheets that were
        // orphans — the best-supported junk chain so far, since Wikimon draws every one of its
        // arrows. Its egg is `funbee_digitama`, and it is the first Pendulum egg belonging to no
        // rung of its own tree at all: none of ToyAgumon, Kokuwamon, Hagurumon and Junkmon has an
        // egg on disk, so the rule that survives is only "a real roster Digitama that a map drops"
        // — 06_industrial drops this one.
        ["funbee_digitama", "choromon", "caprimon", "toyagumon",
         "pencme_raremon", "locomon", "grandlocomon"],
        // US-143's Pendulum Color V0 Virus Busters / ZERO line, the last of the eleven device
        // trees and the same shape a sixth time: no junk branch in the document, so Turuiemon,
        // Andiramon (Virus) and Cherubimon (Vice) were chosen off orphan sheets — a chain Wikimon
        // draws whole, and one that ends at the dark counterpart of a Mega the document itself
        // puts in this tree. Its egg is `heriss_digitama`, Herissmon's own: Agumon is the Rookie
        // its In-Training falls to, but `agu_digitama` roots dmc-v1, so the egg is the next Rookie
        // of this tree that has one — US-141's case exactly.
        ["heriss_digitama", "yukimibotamon", "nyaromon", "pencvb_agumon",
         "turuiemon", "andiramon_virus", "cherubimon_vice"],
    ]

    /// The seven rungs a complete line must cover, in order.
    private let ladder: [Stage] = [.digitama, .babyI, .babyII, .child, .adult, .perfect, .ultimate]

    override func setUpWithError() throws {
        try super.setUpWithError()
        graph = try EvolutionGraph.load()
    }

    override func tearDown() {
        graph = nil
        super.tearDown()
    }

    /// Follows `isDefault` edges from a node, which is the path US-020 takes when nothing else
    /// qualifies — i.e. the line a player is guaranteed to walk.
    private func defaultPath(from id: String) throws -> [EvolutionNode] {
        var path: [EvolutionNode] = []
        var next: String? = id

        while let current = next {
            // Also catches a cycle: a line longer than the ladder can only be looping.
            guard path.count <= ladder.count else {
                XCTFail("default path from \(id) does not terminate: \(path.map(\.id))")
                return path
            }
            let node = try XCTUnwrap(graph.node(id: current), "no node with id \(current)")
            path.append(node)
            next = node.evolutions.first(where: \.isDefault)?.to
        }
        return path
    }

    // MARK: - AC: 3 complete lines, each Digitama -> Baby I -> Baby II -> Child -> Adult -> Perfect -> Ultimate

    func testEachSeedLineIsCompleteFromDigitamaToUltimate() throws {
        for line in seedLines {
            let path = try defaultPath(from: line[0])

            XCTAssertEqual(path.map(\.id), line, "line from \(line[0]) does not follow its default edges")
            XCTAssertEqual(path.map(\.stage), ladder, "line from \(line[0]) does not cover all 7 stages in order")
        }
    }

    /// Walks the EARNED edge at each rung — the outgoing edge that is not the junk fallback — and
    /// fails if a rung offers more than one, so this cannot silently start describing a branch.
    ///
    /// A rung with no earned edge follows its fallback instead. That is not a loophole: above Adult
    /// the lines do not branch, so a Perfect's single edge to its Ultimate is marked `isDefault`
    /// and is the only way on. Only Child and Adult carry a junk fallback, and at those rungs there
    /// is always an earned edge to prefer.
    private func earnedPath(from id: String) throws -> [EvolutionNode] {
        var path: [EvolutionNode] = []
        var next: String? = id

        while let current = next {
            guard path.count <= ladder.count else {
                XCTFail("earned path from \(id) does not terminate: \(path.map(\.id))")
                return path
            }
            let node = try XCTUnwrap(graph.node(id: current), "no node with id \(current)")
            path.append(node)

            let earned = node.evolutions.filter { !$0.isDefault }
            if earned.isEmpty {
                next = node.evolutions.first(where: \.isDefault)?.to
            } else {
                XCTAssertEqual(earned.count, 1, "\(current) has \(earned.count) earned branches, not one")
                next = earned.first?.to
            }
        }
        return path
    }

    /// The AC names these three lines by their Child-and-up forms; assert them literally. They are
    /// the EARNED paths now — US-061 moved the fallbacks onto the junk branches — which is exactly
    /// the claim worth making: raise it well and you still get WarGreymon.
    func testTheThreeNamedLinesAreTheOnesShipped() throws {
        XCTAssertEqual(try earnedPath(from: "palmon").map(\.displayName),
                       ["Palmon", "Togemon", "Lilimon", "Rosemon"])

        // Gabumon to MetalGarurumon is still the whole way up, but since US-134 it is one thread
        // through a tree rather than the only one: the V2 document gives Gabumon four earned
        // Champions and Garurumon three earned Perfects, so `earnedPath` — which insists on a
        // single earned edge per rung — can no longer walk it. Asserted as forks plus the thread
        // above them, the same shape US-133 gave the Agumon line below.
        XCTAssertEqual(
            try XCTUnwrap(graph.node(id: "gabumon")).evolutions.filter { !$0.isDefault }.map(\.to).sorted(),
            ["angemon", "garurumon", "kabuterimon", "yukidarumon"])
        XCTAssertEqual(
            try XCTUnwrap(graph.node(id: "garurumon")).evolutions.filter { !$0.isDefault }.map(\.to).sorted(),
            ["metalmamemon", "weregarurumon", "whamon"])
        XCTAssertEqual(try earnedPath(from: "weregarurumon").map(\.displayName),
                       ["WereGarurumon", "MetalGarurumon"])

        // Agumon branches three ways at Child, and since US-133 Greymon forks too — the V1 tree's
        // Ultimate is MetalGreymon (Virus), which sits beside US-043's Vaccine one. Both are
        // asserted as forks rather than forced through `earnedPath`, which walks a single thread.
        XCTAssertEqual(
            try XCTUnwrap(graph.node(id: "agumon")).evolutions.filter { !$0.isDefault }.map(\.to).sorted(),
            ["devimon", "greymon", "meramon"])
        XCTAssertEqual(
            try XCTUnwrap(graph.node(id: "greymon")).evolutions.filter { !$0.isDefault }.map(\.to).sorted(),
            ["metalgreymon", "metalgreymon_virus"])
        XCTAssertEqual(try earnedPath(from: "metalgreymon").map(\.displayName),
                       ["MetalGreymon", "WarGreymon"])

        // The AC calls out Palmon's Baby forms by name.
        XCTAssertEqual(graph.node(id: "yuramon")?.stage, .babyI)
        XCTAssertEqual(graph.node(id: "tanemon")?.stage, .babyII)
    }

    // MARK: - AC: every node uses a real 48x64 animated stage sheet, never an "Idle Frame Only" sprite

    /// Slices every seed node's art the way the app does. This is stronger than "the file exists":
    /// `SpriteSheet` rejects anything that is not 48x64 (or 48x16 for an egg), so an idle-only
    /// 16x16 sprite — or a Digimon with no animated sheet at all — fails here rather than shipping
    /// as a Digimon that cannot animate.
    func testEverySeedNodeHasAnAnimatedSheetWithTheRightFrameCount() throws {
        for node in graph.nodes {
            let sheet = try XCTUnwrap(
                SpriteSheetCache.shared.sheet(stage: node.stage.rawValue, name: node.spriteFile),
                "\(node.id): \(node.stage.rawValue)/\(node.spriteFile) is not a sliceable sheet")

            if node.stage == .digitama {
                XCTAssertEqual(sheet.kind, .egg, "\(node.id) is a Digitama but its sheet is not 48x16")
                XCTAssertEqual(sheet.frames.count, 3, "\(node.id) should have idle, wobble, hatch")
            } else {
                XCTAssertEqual(sheet.kind, .stage, "\(node.id) is not backed by a 48x64 animated sheet")
                XCTAssertEqual(sheet.frames.count, 12, "\(node.id) should have all 12 frames")
                // The idle loop is what the main screen drives; prove it resolves.
                XCTAssertNotNil(sheet[SpriteFrame.walk1], "\(node.id) cannot animate its idle loop")
            }
        }
    }

    /// The 157 idle-only Digimon (Poyomon, Ankylomon, ...) have no animated sheet, so they must
    /// never be playable. No seed node may be one.
    func testNoSeedNodeIsDexOnly() {
        for node in graph.nodes {
            XCTAssertFalse(node.dexOnly, "\(node.id) is dexOnly and must not appear in an evolution line")
        }
    }

    // MARK: - AC: at least one node has 2+ outgoing edges with different requiredEnergy

    func testAtLeastOneNodeBranchesOnDominantEnergy() {
        let branching = graph.nodes.filter { node in
            Set(node.evolutions.compactMap(\.requiredEnergy)).count >= 2
        }
        XCTAssertFalse(branching.isEmpty, "no node branches on dominant energy — nothing exercises US-019")
    }

    /// The branch above, pinned: Agumon is where dominant energy first changes the outcome. Since
    /// US-061 it is earned branches plus the Numemon fallback, and the fallback shares Greymon's
    /// strength gate, sitting below it on `minEnergy` so it only wins when Greymon is shut out.
    /// US-133 added the V1 tree's third earned Champion, Devimon, on the spirit branch.
    func testAgumonBranchesOnStrengthOrStamina() throws {
        let agumon = try XCTUnwrap(graph.node(id: "agumon"))
        XCTAssertEqual(agumon.evolutions.count, 4)

        let earned = agumon.evolutions.filter { !$0.isDefault }
        // Deliberately NOT Dictionary(uniqueKeysWithValues:) keyed on requiredEnergy: two edges
        // sharing an energy would TRAP there, killing the test host so the rest of the suite
        // never reports (see EvolutionGraph.bundled). Collapsed branches must fail, not crash.
        XCTAssertEqual(Set(earned.compactMap(\.requiredEnergy)).count, earned.count,
                       "Agumon's earned edges must require DIFFERENT energies or a branch is fake")

        let toGreymon = try XCTUnwrap(earned.first { $0.to == "greymon" })
        let toMeramon = try XCTUnwrap(earned.first { $0.to == "meramon" })
        XCTAssertEqual(toGreymon.requiredEnergy, .strength)
        XCTAssertEqual(toMeramon.requiredEnergy, .stamina)

        let toNumemon = try XCTUnwrap(agumon.evolutions.first(where: \.isDefault))
        XCTAssertEqual(toNumemon.to, "numemon")
        XCTAssertEqual(toNumemon.requiredEnergy, toGreymon.requiredEnergy)
        XCTAssertLessThan(toNumemon.minEnergy, toGreymon.minEnergy,
                          "Numemon must sit below Greymon or it would win the strength branch outright")

        // Meramon and Numemon both converge back into MetalGreymon, so neither is a dead end.
        XCTAssertEqual(graph.parents(of: "metalgreymon").map(\.id).sorted(),
                       ["greymon", "meramon", "numemon"])
    }

    // MARK: - AC: every non-terminal node has exactly one isDefault edge

    func testEveryNonTerminalNodeHasExactlyOneDefaultEdge() {
        for node in graph.nodes where !node.evolutions.isEmpty {
            XCTAssertEqual(
                node.evolutions.filter(\.isDefault).count, 1,
                "\(node.id) must have exactly one isDefault edge or US-020 has no fallback")
        }
    }

    /// A Digitama hatches on TOTAL energy (US-018), so no single type may gate its edge, and its
    /// maxCareMistakes must not be able to block hatching. Every other edge names its energy.
    func testOnlyDigitamaEdgesOmitRequiredEnergy() {
        for node in graph.nodes {
            for edge in node.evolutions {
                if node.stage == .digitama {
                    XCTAssertNil(edge.requiredEnergy, "\(node.id) is an egg; its hatch must not be type-gated")
                    XCTAssertEqual(edge.minEnergy, 50, "\(node.id) must hatch at the US-018 threshold")
                    XCTAssertGreaterThan(edge.maxCareMistakes, 3, "\(node.id) hatch must not be blocked by neglect")
                } else {
                    XCTAssertNotNil(edge.requiredEnergy, "\(node.id) -> \(edge.to) has no requiredEnergy")
                }
            }
        }
    }

    // MARK: - US-044: the V3 Patamon line

    /// Every node the line may reach, checked against the set US-043 verified has animated art.
    /// A node from outside it is either a Digimon with no sheet or one invented out of thin air.
    /// KingEtemon is US-061's addition, verified the same way the rest were: it is a real 48x64
    /// sheet in `Ultimate-Super Ultimate/`, which `testEverySeedNodeHasAnAnimatedSheetWithTheRightFrameCount`
    /// re-proves by slicing it.
    /// The last four are US-148's, verified the same way KingEtemon was: each is a real 48x64 sheet
    /// under `Adult/`, which `ChildSweepAToFTests.testEveryNodeThisSweepAddedIsASliceableSheet`
    /// re-proves by slicing it. They are on this line because the Child sweep put the three
    /// X-Antibody Children under Tokomon X, which US-147 hung on dmc-v3, and Armadimon under
    /// Upamon — an in-edge decides the line, so the Champions above them had nowhere else to go.
    private let patamonLineVerifiedSet: Set<String> = [
        "Unimon", "Centalmon", "Ogremon", "Bakemon", "Shellmon", "Drimogemon", "Scumon",
        "Andromon", "Giromon", "Etemon", "HiAndromon", "Gokumon", "BanchoLeomon", "KingEtemon",
        "Greymon X", "DarkTyranomon X", "Growmon X", "Tortamon",
        // US-149's four. The X-Antibody thread US-148 opened on this line took Gabumon X and
        // Gomamon X, and Cupimon took Lucemon and Hackmon, so their Champions land here too.
        "Gururumon", "Tylomon X", "Dinohumon", "Pidmon",
        // US-150's two, verified the same way: Sangomon went under Upamon (the only In-Training
        // with a free energy that Wikimon names for it) and Sistermon Blanc was already on this
        // line, so Tobiumon and Rhinomon X are the Champions above them.
        "Tobiumon", "Rhinomon X",
    ]

    func testThePatamonLineDrawsItsAdultsAndUpFromTheVerifiedSet() {
        let adult = Stage.adult.ladderIndex!
        let above = graph.nodes.filter { $0.line == "dmc-v3" && ($0.stage.ladderIndex ?? -1) >= adult }

        XCTAssertFalse(above.isEmpty, "the Patamon line has no Adult-or-later nodes at all")
        for node in above {
            XCTAssertTrue(patamonLineVerifiedSet.contains(node.displayName),
                          "\(node.displayName) is not in the US-043 verified-available set")
        }
    }

    /// Poyomon, the V3 tree's Fresh stage, is one of the 157 idle-only Digimon. The line must not
    /// name it anywhere — not as a node, and not as an edge target.
    func testTheLineDoesNotUsePoyomon() {
        XCTAssertNil(graph.node(id: "poyomon"), "Poyomon is dexOnly and may not be a node")
        for node in graph.nodes {
            for edge in node.evolutions {
                XCTAssertNotEqual(edge.to, "poyomon", "\(node.id) points at dexOnly Poyomon")
            }
        }
    }

    /// The substitute Baby I is real, animated, and its divergence from the source tree is written
    /// down in the data file itself — the next reader will diff `evolutions.json` against the tree
    /// markdown and needs to find the reason there, not in a commit message.
    func testThePoyomonSubstitutionIsRecordedInTheDataFile() throws {
        let substitute = try XCTUnwrap(graph.node(id: "puttimon"))
        XCTAssertEqual(substitute.stage, .babyI)
        XCTAssertFalse(substitute.dexOnly)
        XCTAssertEqual(substitute.evolutions.first(where: \.isDefault)?.to, "tokomon")

        // The raw file, not the decoded graph: `comment` is not a schema field, so the decoder
        // drops it and only re-reading the JSON can prove it is actually written down.
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])
        let authored = try XCTUnwrap(nodes.first { $0["id"] as? String == "puttimon" })
        let comment = try XCTUnwrap(authored["comment"] as? String,
                                    "the Baby I substitute carries no comment explaining the divergence")
        XCTAssertTrue(comment.contains("Poyomon"), "the comment must name what it diverges from")
    }

    /// Patamon's five Champions are the V3 tree's five and every one still leads to an Ultimate.
    ///
    /// US-061 had to split them across two Children — a Child could offer at most two earned
    /// branches plus its junk fallback back then — and gave Tsukaimon, Patamon's dark counterpart,
    /// the other two. US-135 raised the out-degree ceiling to five (US-134 had already taken it
    /// there for the Ver.2 tree) and put all five back on Patamon where the document draws them.
    /// Tsukaimon KEEPS Ogremon and Bakemon rather than being emptied: it is in no source tree, so
    /// stripping its branches would leave a shipped Child that evolves into nothing.
    func testThePatamonLinesFiveChampionsAllHangOffPatamon() throws {
        let patamon = try XCTUnwrap(graph.node(id: "patamon"))
        let tsukaimon = try XCTUnwrap(graph.node(id: "tsukaimon"))

        XCTAssertEqual(patamon.evolutions.map(\.to).sorted(),
                       ["bakemon", "centalmon", "ogremon", "scumon", "unimon"])
        XCTAssertEqual(tsukaimon.evolutions.map(\.to).sorted(), ["bakemon", "ogremon", "scumon"])
        XCTAssertEqual(graph.parents(of: "tsukaimon").map(\.id), ["tokomon"],
                       "the second Child hangs off the Baby II, so both are reachable from the egg")

        for edge in patamon.evolutions + tsukaimon.evolutions {
            let path = try defaultPath(from: edge.to)
            XCTAssertEqual(path.map(\.stage), [.adult, .perfect, .ultimate],
                           "the branch through \(edge.to) does not reach Ultimate: \(path.map(\.id))")
        }
    }

    /// Each Child's earned branches need distinct dominant types, or one of them is unreachable.
    /// Scumon is deliberately excluded on all three: it shares an earned branch's gate and wins only
    /// when that branch's higher `minEnergy`, stricter `maxCareMistakes` or unmet criteria shut it
    /// out.
    ///
    /// Kunemon, the V3 tree's second Rookie, joined in US-135; four earned branches is the most a
    /// Child can carry, since there are only four energy types to tell them apart with.
    func testThePatamonChildrensEarnedBranchesUseDistinctEnergies() throws {
        for (child, shadowed) in [("patamon", "unimon"), ("tsukaimon", "bakemon"),
                                  ("kunemon", "drimogemon")] {
            let node = try XCTUnwrap(graph.node(id: child))
            let earned = node.evolutions.filter { !$0.isDefault }

            XCTAssertEqual(Set(earned.compactMap(\.requiredEnergy)).count, earned.count,
                           "\(child): two earned branches share a dominant type")

            let scumon = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            let rival = try XCTUnwrap(node.evolutions.first { $0.to == shadowed })
            XCTAssertEqual(scumon.to, "scumon")
            XCTAssertEqual(scumon.requiredEnergy, rival.requiredEnergy)
            XCTAssertLessThan(scumon.minEnergy, rival.minEnergy,
                              "\(child): Scumon must sit below \(shadowed) or it wins that branch outright")
        }
    }

    /// The junk branch is not just declared — prove the engine actually routes to it, and that a
    /// well-raised vitality Tsukaimon still gets Bakemon instead. The criteria are supplied here,
    /// because since US-061 meeting the energy gate is no longer enough on its own.
    func testANeglectedVitalityTsukaimonGetsScumonAndAWellRaisedOneGetsBakemon() throws {
        let tsukaimon = try XCTUnwrap(graph.node(id: "tsukaimon"))
        let plenty = EnergyTotals(strength: 0, vitality: 90, spirit: 0, stamina: 0)
        let raisedWell = ConditionContext(
            stageTotals: MetricTotals(values: ["health.sleep": 100_000]),
            sleepDisturbancesThisStage: 0)

        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: tsukaimon, stageEnergy: plenty, dominant: .vitality,
                                            careMistakes: 0, battleWins: 0, conditions: raisedWell),
            "bakemon")
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: tsukaimon, stageEnergy: plenty, dominant: .vitality,
                                            careMistakes: 9, battleWins: 0, conditions: raisedWell),
            "scumon", "past Bakemon's care-mistake limit, only the junk branch is left")
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: tsukaimon, stageEnergy: plenty, dominant: .vitality,
                                            careMistakes: 0, battleWins: 0, conditions: .unknown),
            "scumon", "energy alone no longer buys Bakemon — the criteria have to be met too")
    }

    // MARK: - US-045: the V4 Piyomon line

    /// Every node the line may reach, checked against the set US-045's AC names as verified
    /// available. A node from outside it is either a Digimon with no sheet or one invented.
    /// GoldNumemon, GreatKingScumon and Boltmon are US-061's junk branch, verified the same way.
    private let piyomonLineVerifiedSet: Set<String> = [
        "Monochromon", "Leomon", "Kuwagamon", "Coelamon", "Mojyamon",
        "Megadramon", "Piccolomon", "Digitamamon", "Darkdramon", "BloomLordmon", "Gankoomon",
        "GoldNumemon", "GreatKingScumon", "Boltmon",
    ]

    func testThePiyomonLineDrawsItsAdultsAndUpFromTheVerifiedSet() {
        let adult = Stage.adult.ladderIndex!
        let above = graph.nodes.filter { $0.line == "dmc-v4" && ($0.stage.ladderIndex ?? -1) >= adult }

        XCTAssertFalse(above.isEmpty, "the Piyomon line has no Adult-or-later nodes at all")
        for node in above {
            XCTAssertTrue(piyomonLineVerifiedSet.contains(node.displayName),
                          "\(node.displayName) is not in the US-045 verified-available set")
        }
    }

    /// Kokatorimon is absent from the asset pack entirely and Nanimon is one of the 157 idle-only
    /// Digimon, so the V4 tree's other two Champions must appear nowhere — not as nodes, and not
    /// as edge targets.
    func testTheLineOmitsKokatorimonAndNanimon() {
        for missing in ["kokatorimon", "nanimon"] {
            XCTAssertNil(graph.node(id: missing), "\(missing) has no animated sheet and may not be a node")
            for node in graph.nodes {
                for edge in node.evolutions {
                    XCTAssertNotEqual(edge.to, missing, "\(node.id) points at unseedable \(missing)")
                }
            }
        }
    }

    /// The V4 tree roots this line at Yuramon -> Tanemon, ids the palmon line already owns, and
    /// US-136 added its second Rookie, Palmon, which collides the same way. This line was given its
    /// own ids rather than sharing those nodes, so assert BOTH survive: the three pairs are
    /// distinct nodes on the same art, and each sits in its own line.
    func testTheYuramonCollisionIsResolvedWithLineScopedIds() throws {
        for (shared, scoped) in [("yuramon", "piyo_yuramon"), ("tanemon", "piyo_tanemon"),
                                 ("palmon", "dmcv4_palmon")] {
            let palmonNode = try XCTUnwrap(graph.node(id: shared))
            let piyomonNode = try XCTUnwrap(graph.node(id: scoped))

            XCTAssertEqual(palmonNode.line, "palmon")
            XCTAssertEqual(piyomonNode.line, "dmc-v4")
            XCTAssertEqual(piyomonNode.displayName, palmonNode.displayName, "same Digimon in two trees")
            XCTAssertEqual(piyomonNode.spriteFile, palmonNode.spriteFile, "and the same art, not a copy")
            XCTAssertEqual(piyomonNode.stage, palmonNode.stage)
        }
    }

    /// The reason for those scoped ids: `line` is single-valued and the Dex draws one tree per
    /// line, so a shared node would sit in ONE tree and `EvolutionTreeLayout` would silently drop
    /// every connector crossing into the other. Prove no edge in either line leaves its own line —
    /// which is what sharing the nodes would have broken.
    func testEveryEdgeInBothLinesStaysInsideItsOwnLine() throws {
        for line in ["palmon", "dmc-v4"] {
            for node in graph.nodes where node.line == line {
                for edge in node.evolutions {
                    let target = try XCTUnwrap(graph.node(id: edge.to))
                    XCTAssertEqual(target.line, line,
                                   "\(node.id) -> \(edge.to) leaves line '\(line)', so the Dex would not draw it")
                }
            }
        }
    }

    /// Both divergences from the source tree are written down in the data file itself, so the next
    /// reader diffing `evolutions.json` against the tree markdown finds the reason there.
    func testThePiyomonDivergencesAreRecordedInTheDataFile() throws {
        // The raw file, not the decoded graph: `comment` is not a schema field, so the decoder
        // drops it and only re-reading the JSON can prove it is actually written down.
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])

        func comment(on id: String) throws -> String {
            let authored = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no authored node \(id)")
            return try XCTUnwrap(authored["comment"] as? String, "\(id) carries no comment")
        }

        XCTAssertTrue(try comment(on: "piyo_yuramon").contains("palmon"),
                      "the scoped id must explain which line it collides with")
        let piyomon = try comment(on: "piyomon")
        XCTAssertTrue(piyomon.contains("Kokatorimon"), "the omitted Champions must be named")
        XCTAssertTrue(piyomon.contains("Nanimon"), "the omitted Champions must be named")
        XCTAssertTrue(try comment(on: "kuwagamon").contains("Digitamamon"),
                      "rehoming Digitamamon off Nanimon must be explained where it happens")
    }

    /// The line's five drawable Champions, and every one of them leads to an Ultimate rather than
    /// dead-ending partway up the ladder. US-061 split them across three Children — two earned
    /// branches was a Child's maximum once its junk fallback took the third slot — with Hyokomon
    /// and Muchomon carrying the rest. US-136 added `dmcv4_palmon`, the document's second Rookie,
    /// as a fourth; the invented two keep their branches. All four fall back to GoldNumemon.
    func testThePiyomonLinesFiveChampionsAreSplitAcrossItsChildren() throws {
        let children = ["piyomon", "dmcv4_palmon", "hyokomon", "muchomon"]
        var champions: Set<String> = []

        for id in children {
            let child = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(child.stage, .child)
            XCTAssertEqual(EvolutionEngine.defaultEdge(of: child)?.to, "goldnumemon")

            for edge in child.evolutions where !edge.isDefault { champions.insert(edge.to) }
            for edge in child.evolutions {
                let path = try defaultPath(from: edge.to)
                XCTAssertEqual(path.map(\.stage), [.adult, .perfect, .ultimate],
                               "the branch through \(edge.to) does not reach Ultimate: \(path.map(\.id))")
            }
        }

        XCTAssertEqual(champions.sorted(),
                       ["coelamon", "kuwagamon", "leomon", "mojyamon", "monochromon"])
        // `contains` rather than `==` since US-147: Hyokomon and Muchomon each gained a second
        // Baby II parent from the Baby II sweep. Piyo's Tanemon is still one of them, which is
        // what "reachable" needs.
        for id in ["dmcv4_palmon", "hyokomon", "muchomon"] {
            XCTAssertTrue(graph.parents(of: id).map(\.id).contains("piyo_tanemon"),
                          "\(id) must hang off the Baby II or it is unreachable")
        }
    }

    /// Each Child's earned branches need distinct dominant types, or one of them is unreachable.
    /// GoldNumemon is deliberately excluded: it shares an earned branch's gate and wins only when
    /// that branch is shut out.
    ///
    /// `dmcv4_palmon` is the widest Child in the file — four earned branches, one per energy type,
    /// which is the hard ceiling US-135 named. It fits only because two of the document's six
    /// Champions for this Rookie have no animated sheet.
    func testThePiyomonChildrensEarnedBranchesUseDistinctEnergies() throws {
        for (child, shadowed) in [("piyomon", "leomon"), ("dmcv4_palmon", "mojyamon"),
                                  ("hyokomon", "mojyamon"), ("muchomon", "kuwagamon")] {
            let node = try XCTUnwrap(graph.node(id: child))
            let earned = node.evolutions.filter { !$0.isDefault }

            XCTAssertEqual(Set(earned.compactMap(\.requiredEnergy)).count, earned.count,
                           "\(child): two earned branches share a dominant type")

            let junk = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            let rival = try XCTUnwrap(node.evolutions.first { $0.to == shadowed })
            XCTAssertEqual(junk.to, "goldnumemon")
            XCTAssertEqual(junk.requiredEnergy, rival.requiredEnergy)
            XCTAssertLessThan(junk.minEnergy, rival.minEnergy,
                              "\(child): GoldNumemon must sit below \(shadowed) or it wins that branch outright")
        }
    }

    /// The fallback branches are not just declared — prove the engine routes to them, at both the
    /// Child and the Adult rung, and that a well-raised Digimon still gets the earned target.
    ///
    /// Digitamamon is the line's glutton branch since US-061: reachable only by overfeeding a
    /// Kuwagamon and barely exercising it, which is why it is asked for with a context rather than
    /// with energy alone.
    func testTheNeglectPathRunsPiyomonToGoldNumemonAndGluttonyReachesDigitamamon() throws {
        let piyomon = try XCTUnwrap(graph.node(id: "piyomon"))
        let kuwagamon = try XCTUnwrap(graph.node(id: "kuwagamon"))
        let plenty = EnergyTotals(strength: 150, vitality: 0, spirit: 0, stamina: 0)
        let walkedFar = ConditionContext(
            stageTotals: MetricTotals(values: ["health.steps": 500_000, "health.exerciseMinutes": 5_000]),
            trainingSessionsThisStage: 30, overfeedsThisStage: 0)

        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: piyomon, stageEnergy: plenty, dominant: .strength,
                                            careMistakes: 0, battleWins: 0, conditions: walkedFar),
            "leomon")
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: piyomon, stageEnergy: plenty, dominant: .strength,
                                            careMistakes: 9, battleWins: 0, conditions: walkedFar),
            "goldnumemon", "past Leomon's care-mistake limit, only the junk branch is left")

        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: kuwagamon, stageEnergy: plenty, dominant: .strength,
                                            careMistakes: 0, battleWins: 0, conditions: walkedFar),
            "piccolomon")

        let overfed = ConditionContext(
            stageTotals: MetricTotals(values: ["health.exerciseMinutes": 10]),
            trainingSessionsThisStage: 0, overfeedsThisStage: 12)
        XCTAssertEqual(
            EvolutionEngine.evolutionTarget(for: kuwagamon, stageEnergy: plenty, dominant: .strength,
                                            careMistakes: 0, battleWins: 0, conditions: overfed),
            "digitamamon", "gorging a barely-exercised Kuwagamon is what earns Digitamamon")
    }

    // MARK: - US-046: the V5 Gazimon line

    /// Every node the line may reach, checked against the set US-046's AC names as verified
    /// available. A node from outside it is either a Digimon with no sheet or one invented.
    /// Vademon and Ebemon are US-061's junk branch, verified the same way.
    private let gazimonLineVerifiedSet: Set<String> = [
        "DarkTyranomon", "Cyclomon", "Devidramon", "Tuskmon", "Raremon", "Deltamon",
        "MetalTyranomon", "Ex-Tyranomon", "Nanomon", "Mugendramon", "Gaioumon", "Raidenmon",
        "Vademon", "Ebemon",
        // US-149's one: Gazimon X hangs off Pagumon, its base form's own In-Training, so its
        // Champion is on this line as well.
        "Leomon X",
    ]

    func testTheGazimonLineDrawsItsAdultsAndUpFromTheVerifiedSet() {
        let adult = Stage.adult.ladderIndex!
        let above = graph.nodes.filter { $0.line == "dmc-v5" && ($0.stage.ladderIndex ?? -1) >= adult }

        XCTAssertFalse(above.isEmpty, "the Gazimon line has no Adult-or-later nodes at all")
        for node in above {
            XCTAssertTrue(gazimonLineVerifiedSet.contains(node.displayName),
                          "\(node.displayName) is not in the US-046 verified-available set")
        }
    }

    /// Flymon is one of the 157 idle-only Digimon, so the V5 tree's sixth Champion must appear
    /// nowhere — not as a node, and not as an edge target.
    func testTheLineOmitsFlymon() {
        XCTAssertNil(graph.node(id: "flymon"), "Flymon is dexOnly and may not be a node")
        for node in graph.nodes {
            for edge in node.evolutions {
                XCTAssertNotEqual(edge.to, "flymon", "\(node.id) points at dexOnly Flymon")
            }
        }
    }

    /// The Flymon omission and the reason Gizamon hangs off Pagumon are written down in the data
    /// file itself, so the next reader diffing `evolutions.json` against the tree markdown finds
    /// them there rather than in a commit message.
    func testTheGazimonDivergencesAreRecordedInTheDataFile() throws {
        // The raw file, not the decoded graph: `comment` is not a schema field, so the decoder
        // drops it and only re-reading the JSON can prove it is actually written down.
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evolutions", withExtension: "json"))
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        let nodes = try XCTUnwrap(raw["nodes"] as? [[String: Any]])

        func comment(on id: String) throws -> String {
            let authored = try XCTUnwrap(nodes.first { $0["id"] as? String == id }, "no authored node \(id)")
            return try XCTUnwrap(authored["comment"] as? String, "\(id) carries no comment")
        }

        XCTAssertTrue(try comment(on: "gizamon").contains("Flymon"),
                      "the omitted Champion must be named where it is omitted")
        XCTAssertTrue(try comment(on: "pagumon").contains("Gizamon"),
                      "the branching Baby II must explain why it carries a second Rookie")
    }

    /// Gizamon is the one Rookie across V3/V4/V5 with no Digitama of its own (US-043). It is
    /// seeded anyway, reached through Pagumon — so assert both halves: it is in the line, and it
    /// roots nothing, because there is no egg that could hatch into it.
    func testGizamonIsReachedThroughPagumonRatherThanItsOwnEgg() throws {
        let gizamon = try XCTUnwrap(graph.node(id: "gizamon"))
        XCTAssertEqual(gizamon.stage, .child)
        XCTAssertEqual(gizamon.line, "dmc-v5")
        XCTAssertEqual(graph.parents(of: "gizamon").map(\.id), ["pagumon"])

        let eggs = graph.nodes(at: .digitama).filter { $0.line == "dmc-v5" }
        XCTAssertEqual(eggs.map(\.id), ["gazi_digitama"],
                       "this line has exactly one egg — Gizamon has no Giza_Digitama on disk")
    }

    /// The first branching Baby II in the roster: every Rookie must be reachable, and each must
    /// climb the whole ladder rather than dead-ending. US-061 added a third, Psychemon, so the
    /// line's five Champions fit two earned branches to a Child.
    func testPagumonBranchesToBothRookiesAndEachReachesUltimate() throws {
        let pagumon = try XCTUnwrap(graph.node(id: "pagumon"))

        // US-149 spent Pagumon's last free energy on Gazimon X, the X-Antibody variant of the
        // Rookie it already carried, so the branch is four wide and full.
        XCTAssertEqual(pagumon.evolutions.map(\.to).sorted(),
                       ["gazimon", "gazimon_x", "gizamon", "psychemon"])
        XCTAssertEqual(Set(pagumon.evolutions.compactMap(\.requiredEnergy)).count, 4,
                       "the Rookie edges must require DIFFERENT energies or the branch is fake")

        for edge in pagumon.evolutions {
            let path = try defaultPath(from: edge.to)
            XCTAssertEqual(path.map(\.stage), [.child, .adult, .perfect, .ultimate],
                           "the branch through \(edge.to) does not reach Ultimate: \(path.map(\.id))")
        }
    }

    /// The line's five Champions across its three Rookies, and every one leads to an Ultimate.
    /// Deltamon is Gizamon's alone — it is the node that would have been lost had this line seeded
    /// only Gazimon, as US-044 and US-045 did with their second Rookies.
    func testTheThreeRookiesCoverEveryChampionAndEveryBranchReachesUltimate() throws {
        let rookies = ["gazimon", "gizamon", "psychemon"]
        var champions: Set<String> = []

        for id in rookies {
            let rookie = try XCTUnwrap(graph.node(id: id))
            XCTAssertEqual(EvolutionEngine.defaultEdge(of: rookie)?.to, "raremon")

            for edge in rookie.evolutions where !edge.isDefault { champions.insert(edge.to) }
            for edge in rookie.evolutions {
                let path = try defaultPath(from: edge.to)
                XCTAssertEqual(path.map(\.stage), [.adult, .perfect, .ultimate],
                               "the branch through \(edge.to) does not reach Ultimate: \(path.map(\.id))")
            }
        }

        XCTAssertEqual(champions.sorted(),
                       ["cyclomon", "darktyranomon", "deltamon", "devidramon", "tuskmon"])
        XCTAssertEqual(graph.parents(of: "deltamon").map(\.id), ["gizamon"],
                       "Deltamon hangs off Gizamon alone, which is why Gizamon is seeded")
    }

    /// Each Rookie's earned branches need distinct dominant types, or one of them is unreachable.
    /// Raremon is deliberately excluded: it shares one earned branch's gate from below and wins
    /// only when that branch is shut out.
    func testEveryRookiesEarnedBranchesUseDistinctEnergies() throws {
        for (rookie, shadowed) in [("gazimon", "darktyranomon"), ("gizamon", "deltamon"),
                                   ("psychemon", "devidramon")] {
            let node = try XCTUnwrap(graph.node(id: rookie))
            let earned = node.evolutions.filter { !$0.isDefault }

            XCTAssertEqual(Set(earned.compactMap(\.requiredEnergy)).count, earned.count,
                           "\(rookie): two earned branches share a dominant type, so one can never be chosen")

            let raremon = try XCTUnwrap(node.evolutions.first(where: \.isDefault))
            let rival = try XCTUnwrap(node.evolutions.first { $0.to == shadowed })
            XCTAssertEqual(raremon.to, "raremon")
            XCTAssertEqual(raremon.requiredEnergy, rival.requiredEnergy)
            XCTAssertLessThan(raremon.minEnergy, rival.minEnergy,
                              "\(rookie): Raremon must sit below \(shadowed) or it wins the branch outright")
        }
    }

    /// The junk branch is not just declared — prove the engine routes to it from both strength
    /// Rookies, and that a well-raised strength Digimon still gets its earned Champion instead.
    func testANeglectedStrengthRookieGetsRaremonFromEitherSide() throws {
        let plenty = EnergyTotals(strength: 150, vitality: 0, spirit: 0, stamina: 0)
        let raisedWell = ConditionContext(
            stageTotals: MetricTotals(values: ["health.steps": 500_000, "health.activeEnergy": 50_000]),
            trainingSessionsThisStage: 30, overfeedsThisStage: 0)

        for (rookie, earned) in [("gazimon", "darktyranomon"), ("gizamon", "deltamon")] {
            let node = try XCTUnwrap(graph.node(id: rookie))

            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: plenty, dominant: .strength,
                                                careMistakes: 0, battleWins: 0, conditions: raisedWell),
                earned)
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: plenty, dominant: .strength,
                                                careMistakes: 9, battleWins: 0, conditions: raisedWell),
                "raremon", "\(rookie): past \(earned)'s care-mistake limit, only the junk branch is left")
            XCTAssertEqual(
                EvolutionEngine.evolutionTarget(for: node, stageEnergy: plenty, dominant: .strength,
                                                careMistakes: 0, battleWins: 0, conditions: .unknown),
                "raremon", "\(rookie): energy alone no longer buys \(earned)")
        }
    }
}
