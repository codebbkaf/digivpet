import Foundation
import XCTest

@testable import DigiVPet

/// US-130 — the Jogress catalog: the shipped file, the decoder's contract with it, and the
/// unordered-parents property the whole type exists to guarantee.
///
/// The shipped `jogress.json` was EMPTY of recipes in US-130 and is authored in US-131, so the
/// decode tests here still run over literals rather than over the file: a shipped recipe that
/// happens to exercise a key says nothing about the key the file does NOT use (`conditions`), and a
/// renamed key must fail as a test rather than as a launch trap in `JogressCatalog.bundled`.
/// The authored data is asserted separately, further down.
final class JogressCatalogTests: XCTestCase {

    // MARK: - The shipped file

    func testTheShippedFileIsBundledAndDecodes() throws {
        let catalog = try JogressCatalog.load()

        XCTAssertEqual(catalog, JogressCatalog.bundled)
    }

    /// US-130's marker test asserted this file was still EMPTY; US-131 authored it, so the marker is
    /// replaced by the count it was waiting for. A bare count is a weak assertion on its own — the
    /// four tests below say WHICH recipes, and the validator suite sweeps the whole file — but it is
    /// what fails first if a later story deletes the data while leaving the machinery.
    func testTheShippedFileHoldsTheAuthoredRecipes() throws {
        XCTAssertEqual(try JogressCatalog.load().recipes.count, 14)
    }

    // MARK: - The authored data (US-131)

    /// THE AC: the four pairs the local evolution-tree document states verbatim. Looked up through
    /// `recipe(for:and:)` in the order the DOCUMENT names them, which is not the order the file
    /// authors them all in — so this is a fact about the catalog, not about the JSON's column order.
    func testTheFourRecipesTheLocalDocumentStatesArePresent() throws {
        let catalog = try JogressCatalog.load()

        XCTAssertEqual(
            catalog.recipe(for: "blitzgreymon", and: "cresgarurumon")?.result, "omegamon_alter-s")
        XCTAssertEqual(catalog.recipe(for: "darkdramon", and: "bancholeomon")?.result, "chaosmon")
        XCTAssertEqual(catalog.recipe(for: "mugendramon", and: "darkdramon")?.result, "chaosdramon")
        XCTAssertEqual(catalog.recipe(for: "wargreymon", and: "metalgarurumon")?.result, "omegamon")
    }

    /// The ten recipes read off the two shipped Bandai charts beyond those four. Spelled out rather
    /// than counted, because "10 more exist" would still pass if one of them fused the wrong pair.
    func testTheRecipesReadOffTheShippedChartsArePresent() throws {
        let catalog = try JogressCatalog.load()

        let expected: [(String, String, String)] = [
            ("chimairamon", "mugendramon", "millenniumon"),
            ("angewomon", "ladydevimon", "mastemon"),
            ("saberleomon", "eldoradimon", "tlalocmon"),
            ("saberleomon", "metaletemon", "tlalocmon"),
            ("metalseadramon", "plesiomon", "aegisdramon"),
            ("marinangemon", "hououmon", "mitamamon"),
            ("vamdemon", "piemon", "voltobautamon"),
            ("griffomon", "pinochimon", "cernumon"),
            ("griffomon", "hydramon", "cernumon"),
            ("mugendramon", "hiandromon", "chaosdramon"),
        ]

        for (a, b, result) in expected {
            XCTAssertEqual(
                catalog.recipe(for: a, and: b)?.result, result, "\(a) + \(b) should fuse to \(result)")
        }
    }

    /// Two Digimon can fuse only ONE way, so a pair that appears twice is a bug the lookup hides —
    /// `byPair` keeps the first and the second is unreachable. The validator reports it; this pins
    /// it over the shipped file as a plain fact, since the same result reached by two DIFFERENT
    /// pairs is legitimate and shipped (Chaosdramon and Tlalocmon and Cernumon each have two).
    func testNoTwoShippedRecipesShareAPair() throws {
        let recipes = try JogressCatalog.load().recipes

        XCTAssertEqual(Set(recipes.map(\.pair)).count, recipes.count)
        XCTAssertEqual(recipes.filter { $0.result == "chaosdramon" }.count, 2)
    }

    /// A recipe naming a Digimon the player can never own is dead data, and the one the PRD calls
    /// out by name is XV-mon + Stingmon -> Paildramon: `stingmon` is one of the 157 idle-only
    /// entries. Pinned as an ABSENCE so a later iteration adding it from a wiki fails here rather
    /// than shipping a fusion no party screen can ever offer.
    func testTheKnownUnusableRecipesAreNotShipped() throws {
        let catalog = try JogressCatalog.load()

        XCTAssertNil(catalog.recipe(for: "xv-mon", and: "stingmon"))
        XCTAssertTrue(Roster.bundled.entry(id: "stingmon")?.dexOnly == true)
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
