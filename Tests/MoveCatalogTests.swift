import UIKit
import XCTest
@testable import DigiVPet

final class MoveCatalogTests: XCTestCase {
    private let graph = EvolutionGraph.bundled
    private let roster = Roster.bundled
    private var catalog: MoveCatalog { MoveCatalog.bundled }

    // MARK: - Resolution tiers (pure)

    func testDirectIdEntryWins() {
        let move = catalog.move(for: "agumon", in: graph, roster: roster)
        XCTAssertEqual(move, catalog.moves["agumon"])
        XCTAssertEqual(move.signatureName, "Pepper Breath")
    }

    /// US-074 authored every graph node, so the line tier is now a safety net for a node added
    /// LATER rather than a live path — exercised here with an id the graph does not yet contain.
    ///
    /// That id is DERIVED rather than named. It said `greymon_x` until US-148 wired Greymon
    /// (X-Antibody) onto dmc-v3; Phase E is pulling the whole roster into the graph one sweep at a
    /// time, so any hard-coded "not a node yet" example is on a timer.
    func testFallsBackByLineWhenIdIsUnauthored() throws {
        let unauthored = try XCTUnwrap(
            roster.entries.first { catalog.moves[$0.id] == nil && graph.node(id: $0.id) == nil }?.id,
            "every roster Digimon is now an authored graph node — the line tier is unreachable")

        let move = catalog.move(forId: unauthored, line: "dmc-v1", stage: .adult)
        XCTAssertEqual(move, catalog.lineDefaults["dmc-v1"])
        XCTAssertNotEqual(move, catalog.stageDefaults[Stage.adult.rawValue],
                          "line tier must win over the stage floor")
    }

    func testFallsBackByStageForARosterOnlyDigimon() {
        // poyomon exists only in the roster (no graph node, so no line) and is a Baby I.
        XCTAssertNil(graph.node(id: "poyomon"), "test assumes poyomon has no graph node")
        XCTAssertEqual(roster.entry(id: "poyomon")?.stage, .babyI)
        let move = catalog.move(for: "poyomon", in: graph, roster: roster)
        XCTAssertEqual(move, catalog.stageDefaults[Stage.babyI.rawValue])
    }

    func testPureCoreResolvesAllThreeTiersAndAFloor() {
        let fixture = MoveCatalog(
            moves: ["a": Move(projectileSymbol: "flame.fill", tint: .red,
                              signatureName: "A", signatureSymbol: "flame.fill")],
            lineDefaults: ["l": Move(projectileSymbol: "leaf.fill", tint: .green,
                                     signatureName: "L", signatureSymbol: "leaf.fill")],
            stageDefaults: [Stage.child.rawValue: Move(projectileSymbol: "bolt.fill", tint: .yellow,
                                                       signatureName: "S", signatureSymbol: "bolt.fill")]
        )
        // Tier 1: id present.
        XCTAssertEqual(fixture.move(forId: "a", line: "l", stage: .child).signatureName, "A")
        // Tier 2: id absent, line present.
        XCTAssertEqual(fixture.move(forId: "z", line: "l", stage: .child).signatureName, "L")
        // Tier 3: id + line absent, stage present.
        XCTAssertEqual(fixture.move(forId: "z", line: "unknown", stage: .child).signatureName, "S")
        XCTAssertEqual(fixture.move(forId: "z", line: nil, stage: .child).signatureName, "S")
        // Floor: nothing resolves -> placeholder, never an empty move.
        XCTAssertEqual(fixture.move(forId: "z", line: "unknown", stage: .adult), .placeholder)
        XCTAssertEqual(fixture.move(forId: "z", line: nil, stage: nil), .placeholder)
    }

    // MARK: - Guarantees over the whole roster

    func testEveryRosterDigimonResolvesToARealMove() {
        XCTAssertEqual(roster.entries.count, 1022)
        for entry in roster.entries {
            let move = catalog.move(for: entry.id, in: graph, roster: roster)
            XCTAssertNotEqual(move, .placeholder,
                              "\(entry.id) fell through to the placeholder floor")
            XCTAssertFalse(move.projectileSymbol.isEmpty)
        }
    }

    func testStageDefaultsCoverEveryStage() {
        for stage in Stage.allCases {
            XCTAssertNotNil(catalog.stageDefaults[stage.rawValue],
                            "no stageDefault for \(stage.rawValue)")
        }
    }

    func testEveryGraphLineHasALineDefault() {
        let lines = Set(graph.nodes.map { $0.line })
        for line in lines {
            XCTAssertNotNil(catalog.lineDefaults[line], "no lineDefault for line \(line)")
        }
    }

    // MARK: - Authored coverage of the curated graph (US-074)

    /// AC1. Every curated node is authored EXPLICITLY, so no playable Digimon reaches battle on a
    /// line or stage fallback. Counted off the graph rather than a literal so adding a node to
    /// `evolutions.json` without a move fails here instead of shipping a generic attack.
    func testEveryGraphNodeHasAnExplicitMoveEntry() {
        XCTAssertFalse(graph.nodes.isEmpty)
        for node in graph.nodes {
            XCTAssertNotNil(catalog.moves[node.id],
                            "\(node.id) (\(node.displayName)) has no explicit moves.json entry")
        }
    }

    /// The other direction: no authored entry names a Digimon the graph does not have, which would
    /// be a typo'd id quietly doing nothing.
    func testEveryAuthoredMoveNamesARealNode() {
        let ids = Set(graph.nodes.map(\.id))
        for id in catalog.moves.keys {
            XCTAssertTrue(ids.contains(id), "moves.json authors \(id), which is not a graph node")
        }
    }

    /// AC3. Two members of the same family must never throw the same thing, so an evolution reads
    /// as a change. Uniqueness is on the pair — reusing `flame.fill` in a fire line is fine as long
    /// as the colour differs.
    func testNoTwoDigimonInALineShareASymbolAndTint() {
        var seen: [String: [String: String]] = [:]  // line -> "symbol|tint" -> id
        for node in graph.nodes {
            guard let move = catalog.moves[node.id] else { continue }
            let key = "\(move.projectileSymbol)|\(move.tint.rawValue)"
            if let other = seen[node.line]?[key] {
                XCTFail("\(node.id) and \(other) both throw \(key) in line \(node.line)")
            }
            seen[node.line, default: [:]][key] = node.id
        }
    }

    /// AC2, spot-checked on the cases the story names: the two starter rivals throw the same glyph
    /// in different colours, the plant line throws leaves, the electric one bolts.
    func testAttacksSuitTheDigimon() {
        XCTAssertEqual(catalog.moves["agumon"]?.projectileSymbol, "flame.fill")
        XCTAssertEqual(catalog.moves["agumon"]?.tint, .orange)
        XCTAssertEqual(catalog.moves["gabumon"]?.projectileSymbol, "flame.fill")
        XCTAssertEqual(catalog.moves["gabumon"]?.tint, .blue)
        XCTAssertEqual(catalog.moves["palmon"]?.projectileSymbol, "leaf.fill")
        XCTAssertEqual(catalog.moves["togemon"]?.projectileSymbol, "leaf.fill")
        XCTAssertEqual(catalog.moves["gazimon"]?.projectileSymbol, "bolt.fill")
        XCTAssertEqual(catalog.moves["metaltyranomon"]?.projectileSymbol, "bolt.fill")
    }

    /// AC5. Authored, not generated: no signature name is derived from the Digimon's own name or
    /// stage, and the 88 names are all distinct. A templated file would fail both halves.
    func testSignatureNamesAreAuthoredRatherThanTemplated() {
        var names: [String: String] = [:]
        for node in graph.nodes {
            guard let move = catalog.moves[node.id] else { continue }
            let name = move.signatureName
            XCTAssertFalse(name.isEmpty, "\(node.id) has an empty signature name")
            XCTAssertFalse(name.lowercased().contains(node.displayName.lowercased()),
                           "\(node.id)'s signature \"\(name)\" is built from its display name")
            XCTAssertFalse(name.lowercased().contains(node.stage.rawValue.lowercased()),
                           "\(node.id)'s signature \"\(name)\" is built from its stage")
            if let other = names[name] {
                XCTFail("\(node.id) and \(other) share the signature name \"\(name)\"")
            }
            names[name] = node.id
        }
    }

    // MARK: - Symbols render

    func testEverySymbolInTheCatalogRenders() {
        let allMoves = Array(catalog.moves.values)
            + Array(catalog.lineDefaults.values)
            + Array(catalog.stageDefaults.values)
        var symbols = Set<String>()
        for move in allMoves {
            symbols.insert(move.projectileSymbol)
            symbols.insert(move.signatureSymbol)
        }
        XCTAssertGreaterThanOrEqual(symbols.count, 8, "expected at least eight distinct symbols")
        for symbol in symbols {
            XCTAssertNotNil(UIImage(systemName: symbol),
                            "\(symbol) does not render as an SF Symbol")
        }
    }

    func testAnUnknownSymbolFailsToRender() {
        // Proves the render check above is meaningful: a bogus name yields nil, so a real
        // catalog symbol passing it is genuine coverage rather than a check that never fails.
        XCTAssertNil(UIImage(systemName: "definitely.not.a.real.sf.symbol.zzz"))
    }

    // MARK: - Decoding

    func testBundledCatalogDecodes() {
        XCTAssertFalse(catalog.moves.isEmpty)
        XCTAssertFalse(catalog.lineDefaults.isEmpty)
        XCTAssertFalse(catalog.stageDefaults.isEmpty)
    }

    func testAnUnknownTintFailsToDecode() {
        // MoveTint is a closed set, so a colour the renderer cannot map is a decode failure caught
        // at load rather than a blank draw at battle time.
        let json = Data("""
        { "moves": { "x": { "projectileSymbol": "flame.fill", "tint": "chartreuse",
          "signatureName": "X", "signatureSymbol": "flame.fill" } },
          "lineDefaults": {}, "stageDefaults": {} }
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MoveCatalog.self, from: json))
    }
}
