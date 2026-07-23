import XCTest
@testable import DigiVPet

/// US-087. Pins the authored typings in `elements.json` and every tier of the lookup that reads
/// them. `ElementTests` owns the vocabulary and the counter chart; this file owns the data.
final class ElementCatalogTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled
    private var catalog: ElementCatalog { ElementCatalog.bundled }

    // MARK: - Resolution tiers (pure)

    func testDirectIdEntryWins() {
        let type = catalog.type(for: "agumon", in: graph)
        XCTAssertEqual(type, DigimonType(element: .fire, attribute: .vaccine))
        XCTAssertEqual(type, catalog.types["agumon"])
    }

    /// Every graph node is authored (below), so the line tier is a safety net for a node added
    /// LATER rather than a live path — exercised here with an id the graph does not yet contain.
    ///
    /// DERIVED rather than named: this said `greymon_x` until US-148 typed Greymon (X-Antibody),
    /// and every sweep of Phase E turns another roster-only id into a node.
    func testFallsBackByLineWhenIdIsUnauthored() throws {
        let unauthored = try XCTUnwrap(
            roster.entries.first { catalog.types[$0.id] == nil && graph.node(id: $0.id) == nil }?.id,
            "every roster Digimon is now an authored graph node — the line tier is unreachable")

        XCTAssertEqual(catalog.type(forId: unauthored, line: "dmc-v1"), catalog.lineDefaults["dmc-v1"])
    }

    /// The tier that has no counterpart in `MoveCatalog`: a roster-only Digimon in no line is typed
    /// off its NAME, because a name often says what something is even when nobody has authored it.
    ///
    /// The example is picked out of the roster at RUN TIME rather than named. This test said a
    /// Seadramon until US-165 wired the last of them into the graph; `ankylomon` replaces it — one
    /// of the 157 idle-only Digimon that can never become a node, so no later sweep can claim it,
    /// and `ankylo` keyword-types to earth.
    func testFallsBackToAKeywordRuleForARosterOnlyDigimon() throws {
        let rosterOnly = try XCTUnwrap(
            roster.entries.first { $0.id.contains("ankylo") && graph.node(id: $0.id) == nil },
            "ankylomon is now a graph node — pick another keyword rule to exercise")

        XCTAssertNil(catalog.types[rosterOnly.id])
        XCTAssertEqual(catalog.type(for: rosterOnly.id, in: graph).element, .earth)
        XCTAssertEqual(catalog.type(for: "seraphimon", in: graph).element, .light)
        XCTAssertEqual(catalog.type(for: "gotsumon", in: graph).element, .earth)
    }

    func testAnUntypeableIdReachesTheInertFloor() {
        XCTAssertEqual(catalog.type(forId: "zzznotadigimon", line: nil), .unauthored)
        XCTAssertEqual(DigimonType.unauthored, DigimonType(element: .neutral, attribute: .free))
        // The floor must hand out no advantage on either axis — see docs/elements.md.
        XCTAssertTrue(DigimonType.unauthored.element.beats.isEmpty)
        XCTAssertTrue(DigimonType.unauthored.attribute.beats.isEmpty)
    }

    func testPureCoreResolvesAllFourTiers() {
        let fixture = ElementCatalog(
            types: ["a": DigimonType(element: .fire, attribute: .vaccine)],
            lineDefaults: ["l": DigimonType(element: .water, attribute: .data)],
            keywordRules: [
                ElementKeywordRule(keyword: "trice", element: .earth, attribute: .free),
                ElementKeywordRule(keyword: "ice", element: .ice, attribute: .free)
            ]
        )
        // Tier 1: id present, and it wins even when a keyword would also match.
        XCTAssertEqual(fixture.type(forId: "a", line: "l").element, .fire)
        // Tier 2: id absent, line present, and it wins over a matching keyword.
        XCTAssertEqual(fixture.type(forId: "icemon", line: "l").element, .water)
        // Tier 3: id + line absent -> the first matching rule, in file order.
        XCTAssertEqual(fixture.type(forId: "icemon", line: nil).element, .ice)
        XCTAssertEqual(fixture.type(forId: "triceramon", line: nil).element, .earth,
                       "an earlier rule must win: triceramon also contains \"ice\"")
        XCTAssertEqual(fixture.type(forId: "TRICERAMON", line: nil).element, .earth,
                       "matching is case-insensitive")
        // Floor: nothing resolves.
        XCTAssertEqual(fixture.type(forId: "zzz", line: "unknown"), .unauthored)
        XCTAssertEqual(fixture.type(forId: "zzz", line: nil), .unauthored)
    }

    // MARK: - Authored coverage of the curated graph

    /// AC2. Counted off the graph rather than a literal, so adding a node to `evolutions.json`
    /// without typing it fails HERE instead of shipping a playable Digimon with no matchup.
    func testEveryGraphNodeHasAnExplicitTypesEntry() {
        XCTAssertEqual(graph.nodes.count, 931)
        for node in graph.nodes {
            XCTAssertNotNil(catalog.types[node.id],
                            "\(node.id) (\(node.displayName)) has no explicit elements.json entry")
        }
    }

    /// The other direction: no authored entry names a Digimon the graph does not have, which would
    /// be a typo'd id quietly doing nothing.
    func testEveryAuthoredTypeNamesARealNode() {
        let ids = Set(graph.nodes.map(\.id))
        for id in catalog.types.keys {
            XCTAssertTrue(ids.contains(id), "elements.json types \(id), which is not a graph node")
        }
    }

    func testEveryGraphLineHasALineDefault() {
        for line in Set(graph.nodes.map(\.line)) {
            XCTAssertNotNil(catalog.lineDefaults[line], "no lineDefault for line \(line)")
        }
    }

    // MARK: - What the authored data says

    /// AC3, spot-checked on the canon the story names. These are looked up, not invented — see the
    /// file's `_comment` for which ids were judgement calls instead.
    func testAttributesFollowCanonWhereCanonExists() {
        XCTAssertEqual(catalog.types["agumon"]?.attribute, .vaccine)
        XCTAssertEqual(catalog.types["greymon"]?.attribute, .vaccine)
        XCTAssertEqual(catalog.types["metalgreymon"]?.attribute, .vaccine)
        XCTAssertEqual(catalog.types["andromon"]?.attribute, .vaccine)
        XCTAssertEqual(catalog.types["gabumon"]?.attribute, .data)
        XCTAssertEqual(catalog.types["palmon"]?.attribute, .data)
        XCTAssertEqual(catalog.types["patamon"]?.attribute, .data)
        XCTAssertEqual(catalog.types["numemon"]?.attribute, .virus)
        XCTAssertEqual(catalog.types["gazimon"]?.attribute, .virus)
        XCTAssertEqual(catalog.types["mugendramon"]?.attribute, .virus)
    }

    /// AC4. An element may change down a line — the story's own example. A line whose every member
    /// shared one element would be a templated file rather than an authored one.
    func testElementsVaryWithinALine() {
        XCTAssertEqual(catalog.types["agumon"]?.element, .fire)
        XCTAssertEqual(catalog.types["greymon"]?.element, .fire)
        XCTAssertEqual(catalog.types["metalgreymon"]?.element, .machine)
        for line in Set(graph.nodes.map(\.line)) {
            let elements = Set(graph.nodes.filter { $0.line == line }
                .compactMap { catalog.types[$0.id]?.element })
            XCTAssertGreaterThan(elements.count, 1, "line \(line) is a single element throughout")
        }
    }

    /// An explicit entry overrides a keyword rule that would type the same id differently. Pinned
    /// because Darkdramon is the case where the name lies: it is a Vaccine machine dragon, and
    /// without its own entry the `dark` rule would make it a dark virus.
    func testAnExplicitEntryOverridesAContradictingKeywordRule() {
        XCTAssertEqual(catalog.types["darkdramon"], DigimonType(element: .machine, attribute: .vaccine))
        let byKeyword = catalog.keywordRules.first { "darkdramon".contains($0.keyword) }
        XCTAssertEqual(byKeyword?.element, .dark, "test assumes a dark rule would otherwise match")
        XCTAssertEqual(catalog.type(for: "darkdramon", in: graph).element, .machine)
    }

    // MARK: - The keyword table

    /// AC6, rule by rule. Asserted through the whole lookup rather than against the table, so a rule
    /// that exists but is shadowed by an earlier one still fails.
    func testKeywordRulesCoverTheFamiliesTheStoryNames() {
        let expected: [(String, DigimonElement)] = [
            ("agu", .fire), ("mera", .fire), ("flame", .fire),
            ("gomamon", .water), ("seadra", .water), ("aqua", .water),
            ("palmon", .plant), ("woodmon", .plant), ("floramon", .plant),
            ("thunder", .electric), ("raidra", .electric), ("kabuterimon", .electric),
            ("yuki", .ice), ("ice", .ice), ("frigi", .ice),
            ("piyo", .wind), ("birdra", .wind), ("aquila", .wind),
            ("gotsu", .earth), ("golem", .earth), ("ankylo", .earth),
            ("metal", .machine), ("andro", .machine), ("guardro", .machine), ("machine", .machine),
            ("angel", .light), ("holy", .light), ("seraphi", .light),
            ("devi", .dark), ("dark", .dark), ("black", .dark), ("skull", .dark), ("vamde", .dark)
        ]
        for (keyword, element) in expected {
            XCTAssertTrue(catalog.keywordRules.contains { $0.keyword == keyword },
                          "no keyword rule for \(keyword)")
            // A synthetic id carrying only that keyword: no explicit entry and no line, so the rule
            // is the only thing that can type it — a rule shadowed by an earlier one fails here.
            let id = "zz\(keyword)zz"
            XCTAssertNil(catalog.types[id])
            XCTAssertEqual(catalog.type(forId: id, line: nil).element, element,
                           "\(id) should resolve to \(element.rawValue) via the \(keyword) rule")
        }
    }

    func testKeywordsAreDistinctAndNonEmpty() {
        var seen = Set<String>()
        for rule in catalog.keywordRules {
            XCTAssertFalse(rule.keyword.isEmpty)
            XCTAssertEqual(rule.keyword, rule.keyword.lowercased(),
                           "keywords are authored lowercase so the file reads as it matches")
            XCTAssertTrue(seen.insert(rule.keyword).inserted, "duplicate keyword \(rule.keyword)")
        }
    }

    // MARK: - Guarantees over the whole roster

    /// AC7. Every one of the 1,022 roster ids resolves without throwing or trapping. How many land
    /// on `neutral` is REPORTED in the story's notes, not asserted — an honest number beats a
    /// padded keyword table.
    func testEveryRosterDigimonResolvesToSomething() {
        XCTAssertEqual(roster.entries.count, 1022)
        var neutral = 0
        for entry in roster.entries {
            let type = catalog.type(for: entry.id, in: graph)
            if type.element == .neutral { neutral += 1 }
            XCTAssertTrue(DigimonElement.allCases.contains(type.element))
            XCTAssertTrue(DigimonAttribute.allCases.contains(type.attribute))
        }
        // 776 of 1,022 at the time of writing. Bounded rather than pinned: authoring more typings
        // is an improvement and must not fail this, but a table that types almost nothing should.
        XCTAssertLessThan(neutral, roster.entries.count * 9 / 10)
    }

    // MARK: - Decoding

    func testBundledCatalogDecodes() {
        XCTAssertFalse(catalog.types.isEmpty)
        XCTAssertFalse(catalog.lineDefaults.isEmpty)
        XCTAssertFalse(catalog.keywordRules.isEmpty)
    }

    func testAnUnknownElementFailsToDecode() {
        // Both enums are closed sets, so a misspelled type is a decode failure caught at load
        // rather than a Digimon silently fighting as a neutral.
        let json = Data("""
        { "types": { "x": { "element": "chartreuse", "attribute": "vaccine" } },
          "lineDefaults": {}, "keywordRules": [] }
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ElementCatalog.self, from: json))
    }

    func testAnUnknownAttributeFailsToDecode() {
        let json = Data("""
        { "types": { "x": { "element": "fire", "attribute": "antivirus" } },
          "lineDefaults": {}, "keywordRules": [] }
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ElementCatalog.self, from: json))
    }

    func testAMissingSectionFailsToDecode() {
        let json = Data(#"{ "types": {}, "lineDefaults": {} }"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ElementCatalog.self, from: json))
    }

    func testLoadingFromABundleWithoutTheFileThrows() {
        XCTAssertThrowsError(try ElementCatalog.load(from: Bundle(for: ElementCatalogTests.self))) {
            XCTAssertEqual($0 as? ElementCatalog.LoadError, .fileNotBundled)
        }
    }
}
