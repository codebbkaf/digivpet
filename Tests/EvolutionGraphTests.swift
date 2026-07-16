import Foundation
import XCTest

@testable import DigiVPet

final class EvolutionGraphTests: XCTestCase {
    /// A decode fixture, NOT roster data — US-008 authors the real lines. Every `spriteFile`
    /// here is nonetheless a file that really exists, so the fixture never teaches a path that
    /// would not resolve.
    ///
    /// Shape under test: `agumon` branches on dominant energy, `metalgreymon` converges from two
    /// parents, `metalgreymon_virus` carries a variant, and `poyomon` is dexOnly.
    ///
    /// Poyomon is verified idle-only (its art exists solely in `Idle Frame Only/`), but the
    /// stage written here is fixture scaffolding, not a verified claim: the true stage of the
    /// 157 idle-only Digimon is not derivable from disk, since that folder is flat. US-010 has
    /// to source it.
    private let fixture = """
    {
      "nodes": [
        {
          "id": "agumon",
          "displayName": "Agumon",
          "stage": "Child",
          "spriteFile": "Agumon",
          "evolutions": [
            {
              "to": "greymon",
              "requiredEnergy": "strength",
              "minEnergy": 60,
              "maxCareMistakes": 2,
              "minBattleWins": 3,
              "isDefault": true
            },
            {
              "to": "meramon",
              "requiredEnergy": "spirit",
              "minEnergy": 45,
              "maxCareMistakes": 1
            }
          ]
        },
        {
          "id": "greymon",
          "displayName": "Greymon",
          "stage": "Adult",
          "spriteFile": "Greymon",
          "evolutions": [
            {
              "to": "metalgreymon",
              "requiredEnergy": "strength",
              "minEnergy": 80,
              "maxCareMistakes": 2,
              "isDefault": true
            }
          ]
        },
        {
          "id": "meramon",
          "displayName": "Meramon",
          "stage": "Adult",
          "spriteFile": "Meramon",
          "evolutions": [
            {
              "to": "metalgreymon",
              "requiredEnergy": "spirit",
              "minEnergy": 90,
              "maxCareMistakes": 0,
              "isDefault": true
            }
          ]
        },
        {
          "id": "metalgreymon",
          "displayName": "MetalGreymon",
          "stage": "Perfect",
          "spriteFile": "MetalGreymon"
        },
        {
          "id": "metalgreymon_virus",
          "displayName": "MetalGreymon",
          "stage": "Perfect",
          "spriteFile": "MetalGreymon_Virus",
          "variant": "Virus"
        },
        {
          "id": "poyomon",
          "displayName": "Poyomon",
          "stage": "Baby I",
          "spriteFile": "Poyomon",
          "dexOnly": true
        }
      ]
    }
    """

    private func decodeFixture() throws -> EvolutionGraph {
        let data = try XCTUnwrap(fixture.data(using: .utf8))
        return try JSONDecoder().decode(EvolutionGraph.self, from: data)
    }

    // MARK: - Branching

    /// The core of the schema: one node, several edges, each gated on a different dominant
    /// energy. Both must survive the decode with every field intact — a branch that loses an
    /// edge silently narrows a Digimon's fate.
    func testBranchingNodeParsesBothEdges() throws {
        let graph = try decodeFixture()
        let agumon = try XCTUnwrap(graph.node(id: "agumon"))

        XCTAssertEqual(agumon.evolutions.count, 2)

        let strengthEdge = try XCTUnwrap(agumon.evolutions.first { $0.to == "greymon" })
        XCTAssertEqual(strengthEdge.requiredEnergy, .strength)
        XCTAssertEqual(strengthEdge.minEnergy, 60)
        XCTAssertEqual(strengthEdge.maxCareMistakes, 2)
        XCTAssertEqual(strengthEdge.minBattleWins, 3)
        XCTAssertTrue(strengthEdge.isDefault)

        let spiritEdge = try XCTUnwrap(agumon.evolutions.first { $0.to == "meramon" })
        XCTAssertEqual(spiritEdge.requiredEnergy, .spirit)
        XCTAssertEqual(spiritEdge.minEnergy, 45)
        XCTAssertEqual(spiritEdge.maxCareMistakes, 1)

        // The two edges lead somewhere different, which is the point of branching at all.
        XCTAssertNotEqual(strengthEdge.to, spiritEdge.to)
        XCTAssertNotEqual(strengthEdge.requiredEnergy, spiritEdge.requiredEnergy)
    }

    // MARK: - Converging

    /// Several parents may name the same child. Edges live on the parent, so this is what proves
    /// converging lines need no special support in the schema.
    func testConvergingNodeIsReachableFromEveryParent() throws {
        let graph = try decodeFixture()

        let parents = graph.parents(of: "metalgreymon").map(\.id).sorted()
        XCTAssertEqual(parents, ["greymon", "meramon"])

        XCTAssertEqual(graph.parents(of: "agumon"), [])
    }

    // MARK: - Optional fields

    /// An omitted `minBattleWins` means ungated and an omitted `isDefault` means false — the
    /// common case for an edge, so it must not have to be spelled out.
    func testOmittedOptionalEdgeFieldsTakeTheirDefaults() throws {
        let graph = try decodeFixture()
        let agumon = try XCTUnwrap(graph.node(id: "agumon"))
        let spiritEdge = try XCTUnwrap(agumon.evolutions.first { $0.to == "meramon" })

        XCTAssertNil(spiritEdge.minBattleWins)
        XCTAssertFalse(spiritEdge.isDefault)
    }

    func testOmittedOptionalNodeFieldsTakeTheirDefaults() throws {
        let graph = try decodeFixture()
        let metalGreymon = try XCTUnwrap(graph.node(id: "metalgreymon"))

        XCTAssertNil(metalGreymon.variant)
        XCTAssertFalse(metalGreymon.dexOnly)
        // Terminal: `evolutions` is left out entirely rather than written as [].
        XCTAssertEqual(metalGreymon.evolutions, [])
    }

    func testVariantAndDexOnlyDecodeWhenPresent() throws {
        let graph = try decodeFixture()

        let variant = try XCTUnwrap(graph.node(id: "metalgreymon_virus"))
        XCTAssertEqual(variant.variant, "Virus")
        // A variant is its own node but keeps the base display name; only the art differs.
        XCTAssertEqual(variant.displayName, "MetalGreymon")
        XCTAssertEqual(variant.spriteFile, "MetalGreymon_Virus")
        XCTAssertFalse(variant.dexOnly)

        let dexOnly = try XCTUnwrap(graph.node(id: "poyomon"))
        XCTAssertTrue(dexOnly.dexOnly)
        XCTAssertEqual(dexOnly.spriteFile, "Poyomon")
    }

    // MARK: - Lookup

    func testUnknownIdLooksUpToNil() throws {
        let graph = try decodeFixture()
        XCTAssertNil(graph.node(id: "notadigimon"))
        XCTAssertNil(graph.node(id: ""))
    }

    func testNodesAtStage() throws {
        let graph = try decodeFixture()
        XCTAssertEqual(graph.nodes(at: .adult).map(\.id).sorted(), ["greymon", "meramon"])
        XCTAssertEqual(graph.nodes(at: .digitama), [])
    }

    // MARK: - Failing loudly

    /// A typo'd stage must fail the decode rather than default to something. US-002 found the
    /// same class of bug in `Bundle.url(forResource:)`, where a blank name quietly loaded the
    /// wrong Digimon; wrong-but-plausible data is the thing to avoid.
    func testUnknownStageFailsToDecode() throws {
        let json = """
        { "nodes": [{ "id": "x", "displayName": "X", "stage": "Rookie", "spriteFile": "Agumon" }] }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(EvolutionGraph.self, from: data))
    }

    func testUnknownEnergyTypeFailsToDecode() throws {
        let json = """
        {
          "nodes": [{
            "id": "x", "displayName": "X", "stage": "Child", "spriteFile": "Agumon",
            "evolutions": [{ "to": "y", "requiredEnergy": "wisdom", "minEnergy": 1, "maxCareMistakes": 1 }]
          }]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(EvolutionGraph.self, from: data))
    }

    func testMissingRequiredFieldFailsToDecode() throws {
        // No spriteFile — there is no sensible default, so this must throw.
        let json = """
        { "nodes": [{ "id": "x", "displayName": "X", "stage": "Child" }] }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(EvolutionGraph.self, from: data))
    }

    // MARK: - Codable round trip

    /// Hand-written `init(from:)` is the kind of thing that drifts from the encoded shape, so
    /// re-decoding what was encoded is what keeps them honest.
    func testGraphRoundTripsThroughEncodeAndDecode() throws {
        let original = try decodeFixture()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvolutionGraph.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.node(id: "agumon"), original.node(id: "agumon"))
    }

    // MARK: - The real file

    /// The AC: the shipped `evolutions.json` decodes from the app bundle. Tests run inside the
    /// app via TEST_HOST, so `Bundle.main` here IS the app bundle the watch launches — if this
    /// passes, launch decoding works, and no fixture-only test could tell you that.
    func testBundledEvolutionsJsonDecodes() throws {
        let graph = try EvolutionGraph.load()

        XCTAssertFalse(graph.nodes.isEmpty)
        XCTAssertEqual(graph.nodes.count, EvolutionGraph.bundled.nodes.count)

        // The seed line as far as US-007 takes it; US-008 extends it through Ultimate.
        let egg = try XCTUnwrap(graph.node(id: "agu_digitama"))
        XCTAssertEqual(egg.stage, .digitama)

        let hatch = try XCTUnwrap(egg.evolutions.first)
        XCTAssertEqual(hatch.to, "botamon")
        XCTAssertTrue(hatch.isDefault)
        // A Digitama hatches on TOTAL energy (US-018), so no single type gates it.
        XCTAssertNil(hatch.requiredEnergy)

        XCTAssertEqual(graph.node(id: "botamon")?.stage, .babyI)
        XCTAssertEqual(graph.node(id: "koromon")?.stage, .babyII)
        XCTAssertEqual(graph.node(id: "agumon")?.stage, .child)
    }

    /// Every `spriteFile` in the seed must name art that really loads. This is a spot check on
    /// the seed, not the graph validator — US-009 owns validation of the whole file.
    func testBundledNodesNameSpriteFilesThatLoad() throws {
        for node in try EvolutionGraph.load().nodes {
            XCTAssertNotNil(
                SpriteLoader.loadSheet(stage: node.stage.rawValue, name: node.spriteFile),
                "\(node.id) names a sprite that does not load: \(node.stage.rawValue)/\(node.spriteFile)")
        }
    }

    func testLoadFromABundleWithNoGraphThrows() {
        XCTAssertThrowsError(try EvolutionGraph.load(from: Bundle(for: Self.self))) { error in
            XCTAssertEqual(error as? EvolutionGraph.LoadError, .fileNotBundled)
        }
    }
}
