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

    func testFallsBackByLineWhenIdIsUnauthored() {
        // greymon is in the agumon line and has NO id entry in moves.json.
        XCTAssertNil(catalog.moves["greymon"], "test assumes greymon is unauthored")
        XCTAssertEqual(graph.node(id: "greymon")?.line, "agumon")
        let move = catalog.move(for: "greymon", in: graph, roster: roster)
        XCTAssertEqual(move, catalog.lineDefaults["agumon"])
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
