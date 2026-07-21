import Foundation
import XCTest

@testable import DigiVPet

/// US-130 — the Jogress catalog: the shipped file, the decoder's contract with it, and the
/// unordered-parents property the whole type exists to guarantee.
///
/// The shipped `jogress.json` is EMPTY of recipes in this story — US-131 authors them — so the
/// decode tests here deliberately do not lean on its contents. They pin the two things an empty
/// file cannot pin on its own: that the file is bundled and decodes at all, and that the field
/// names the decoder expects are the ones US-131 will be writing. Without the second, the first
/// authored recipe would trap at launch rather than fail a test.
final class JogressCatalogTests: XCTestCase {

    // MARK: - The shipped file

    func testTheShippedFileIsBundledAndDecodes() throws {
        let catalog = try JogressCatalog.load()

        XCTAssertEqual(catalog, JogressCatalog.bundled)
    }

    /// Not an assertion that the file SHOULD be empty forever — it is a marker that US-131 has not
    /// landed yet, and the story that authors the recipes replaces it with a real count. Kept so
    /// that "zero findings over the shipped file" is never read as proof of authored data.
    func testTheShippedFileHoldsNoRecipesUntilUS131() throws {
        XCTAssertEqual(try JogressCatalog.load().recipes.count, 0)
    }

    // MARK: - The decoder's contract with the file

    /// The field names US-131 will author against, exercised through the REAL decoding path over a
    /// literal in the shipped shape. An empty `recipes` array cannot catch a renamed key; this can.
    func testARecipeDecodesFromTheShippedShape() throws {
        let json = Data(
            """
            {
              "recipes": [
                {
                  "parentA": "wargreymon",
                  "parentB": "metalgarurumon",
                  "result": "omegamon",
                  "conditions": [
                    {
                      "metric": "care.battleCount",
                      "window": "lifetime",
                      "comparison": "atLeast",
                      "value": 20,
                      "hint": "Win 20 battles"
                    }
                  ]
                }
              ]
            }
            """.utf8)

        let catalog = try JSONDecoder().decode(JogressCatalog.self, from: json)

        XCTAssertEqual(catalog.recipes.count, 1)
        let recipe = try XCTUnwrap(catalog.recipes.first)
        XCTAssertEqual(recipe.parentA, "wargreymon")
        XCTAssertEqual(recipe.parentB, "metalgarurumon")
        XCTAssertEqual(recipe.result, "omegamon")
        XCTAssertEqual(recipe.conditions.count, 1)
        XCTAssertEqual(recipe.conditions.first?.metric, ConditionMetric.careBattleCount.rawValue)
        XCTAssertEqual(recipe.conditions.first?.hint, "Win 20 battles")
    }

    /// `conditions` is the one optional field: a fusion gated only on owning both parents is the
    /// ordinary Color-device case, and the key is omitted rather than written as `[]`.
    func testConditionsDefaultToEmptyWhenTheKeyIsAbsent() throws {
        let json = Data(
            """
            {"recipes": [{"parentA": "a", "parentB": "b", "result": "c"}]}
            """.utf8)

        let catalog = try JSONDecoder().decode(JogressCatalog.self, from: json)

        XCTAssertEqual(catalog.recipes.first?.conditions, [])
    }

    /// The three ids are strict `decode`, so a recipe with no result fails the load loudly instead
    /// of shipping as a fusion into "" — which `Bundle.url(forResource:)` would then resolve to an
    /// arbitrary sprite (see `GraphValidationError.emptySpriteFile`).
    func testARecipeMissingAnIdFailsToDecode() {
        let json = Data(
            """
            {"recipes": [{"parentA": "a", "parentB": "b"}]}
            """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(JogressCatalog.self, from: json))
    }

    // MARK: - Parents are unordered

    func testThePairIsTheSameValueWhicheverOrderItIsBuiltIn() {
        XCTAssertEqual(JogressPair("b", "a"), JogressPair("a", "b"))
        XCTAssertEqual(JogressPair("b", "a").hashValue, JogressPair("a", "b").hashValue)
        XCTAssertEqual(JogressPair("b", "a").ids, ["a", "b"])
    }

    func testThePairKnowsWhichIdsItNames() {
        let pair = JogressPair("wargreymon", "metalgarurumon")

        XCTAssertTrue(pair.contains("wargreymon"))
        XCTAssertTrue(pair.contains("metalgarurumon"))
        XCTAssertFalse(pair.contains("omegamon"))
    }

    /// THE AC: A+B and B+A resolve to the SAME recipe. Asserted from a catalog authored one way and
    /// looked up both ways — the direction the player's party screen will ask in is whichever two
    /// rows they happened to tap.
    func testARecipeResolvesFromEitherOrderOfItsParents() {
        let catalog = JogressCatalog(recipes: [
            JogressRecipe(parentA: "wargreymon", parentB: "metalgarurumon", result: "omegamon")
        ])

        let forwards = catalog.recipe(for: "wargreymon", and: "metalgarurumon")
        let backwards = catalog.recipe(for: "metalgarurumon", and: "wargreymon")

        XCTAssertEqual(forwards?.result, "omegamon")
        XCTAssertEqual(forwards, backwards)
    }

    /// And the same holds when the FILE authors the pair the other way round — the lookup is
    /// canonical, not merely symmetric about whatever order was written first.
    func testTheAuthoredOrderDoesNotChangeTheLookup() {
        let asWritten = JogressCatalog(recipes: [
            JogressRecipe(parentA: "wargreymon", parentB: "metalgarurumon", result: "omegamon")
        ])
        let reversed = JogressCatalog(recipes: [
            JogressRecipe(parentA: "metalgarurumon", parentB: "wargreymon", result: "omegamon")
        ])

        for a in ["wargreymon", "metalgarurumon"] {
            let b = a == "wargreymon" ? "metalgarurumon" : "wargreymon"
            XCTAssertEqual(asWritten.recipe(for: a, and: b)?.result, "omegamon")
            XCTAssertEqual(reversed.recipe(for: a, and: b)?.result, "omegamon")
        }
    }

    func testAPairThatFusesNothingResolvesToNil() {
        let catalog = JogressCatalog(recipes: [
            JogressRecipe(parentA: "wargreymon", parentB: "metalgarurumon", result: "omegamon")
        ])

        XCTAssertNil(catalog.recipe(for: "wargreymon", and: "agumon"))
        XCTAssertNil(catalog.recipe(for: "wargreymon", and: "wargreymon"))
    }

    // MARK: - Looking a Digimon up

    /// What US-132 walks the box with: every fusion this Digimon is half of, whichever side of the
    /// file it was authored on.
    func testRecipesInvolvingFindsBothSidesOfTheFile() {
        let catalog = JogressCatalog(recipes: [
            JogressRecipe(parentA: "darkdramon", parentB: "bancholeomon", result: "chaosmon"),
            JogressRecipe(parentA: "mugendramon", parentB: "darkdramon", result: "chaosdramon"),
            JogressRecipe(parentA: "wargreymon", parentB: "metalgarurumon", result: "omegamon"),
        ])

        let involving = catalog.recipes(involving: "darkdramon").map(\.result)

        XCTAssertEqual(involving, ["chaosmon", "chaosdramon"])
        XCTAssertEqual(catalog.recipes(involving: "omegamon"), [])
    }

    /// A duplicate pair keeps the FIRST recipe in the index — documented here rather than left to
    /// be discovered, because it is exactly why the validator reports duplicates: the second one is
    /// unreachable and nothing at runtime says so.
    func testADuplicatePairKeepsTheFirstRecipeInTheIndex() {
        let catalog = JogressCatalog(recipes: [
            JogressRecipe(parentA: "a", parentB: "b", result: "first"),
            JogressRecipe(parentA: "b", parentB: "a", result: "second"),
        ])

        XCTAssertEqual(catalog.recipe(for: "a", and: "b")?.result, "first")
        XCTAssertEqual(catalog.recipes.count, 2)
    }
}
