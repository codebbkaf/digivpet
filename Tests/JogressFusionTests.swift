import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// A fixed-timezone calendar and hand-written instants, as in every other suite here.
private enum Fixture {
    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = losAngeles
        formatter.timeZone = losAngeles.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("bad fixture date \(iso)")
        }
        return date
    }

    static let morning = date("2026-07-17 08:00")
    static let born = date("2026-07-10 08:00")
    static let bornLater = date("2026-07-12 08:00")
    static let bornLast = date("2026-07-14 08:00")

    /// A roster of its own, so the pure tests say what they mean without depending on what the
    /// shipped roster currently calls anything. Two fusable Ultimates, their result, a third
    /// Ultimate that fuses with nothing, and the two eggs the pair hatched from.
    static let roster = Roster(entries: [
        RosterEntry(id: "red_egg", displayName: "Red Digitama", stage: .digitama,
                    spriteFile: "Agu_Digitama"),
        RosterEntry(id: "blue_egg", displayName: "Blue Digitama", stage: .digitama,
                    spriteFile: "Gabu_Digitama"),
        RosterEntry(id: "red", displayName: "Red", stage: .ultimate, spriteFile: "WarGreymon"),
        RosterEntry(id: "blue", displayName: "Blue", stage: .ultimate, spriteFile: "MetalGarurumon"),
        RosterEntry(id: "green", displayName: "Green", stage: .ultimate, spriteFile: "Omegamon"),
        RosterEntry(id: "fused", displayName: "Fused", stage: .ultimate, spriteFile: "Omegamon"),
        RosterEntry(id: "other", displayName: "Other", stage: .ultimate, spriteFile: "Chaosmon"),
    ])

    /// `red + blue -> fused`, authored blue-first ON PURPOSE: a Jogress is unordered, and a board
    /// that only found the recipe when the box happened to list the parents the same way round as
    /// the file would be a bug nobody saw until a player froze one of them.
    static let catalog = JogressCatalog(recipes: [
        JogressRecipe(parentA: "blue", parentB: "red", result: "fused"),
    ])

    /// The same one recipe, gated on ten training sessions this stage.
    static let gatedCatalog = JogressCatalog(recipes: [
        JogressRecipe(parentA: "red", parentB: "blue", result: "fused",
                      conditions: [EvolutionCondition(metric: "care.trainingSessions",
                                                      window: .stage, comparison: .atLeast,
                                                      value: 10,
                                                      hint: "Train them both hard")]),
    ])

    static func state(_ id: String, stage: Stage = .ultimate, isActive: Bool = false,
                      origin: String? = nil, dead: Bool = false,
                      born: Date = born) -> GameState {
        let state = GameState(currentDigimonId: id, stage: stage, isActive: isActive,
                              originDigitamaId: origin, now: born)
        if dead {
            state.healthStatus = .dead
            state.diedAt = born
        }
        return state
    }

    /// Everything a context can answer, from the saved record itself — the same construction the
    /// model uses.
    static func context(_ state: GameState) -> ConditionContext {
        ConditionContext(state: state, now: morning, calendar: losAngeles)
    }

    static func board(_ states: [GameState],
                      catalog: JogressCatalog = Fixture.catalog,
                      roster: Roster = Fixture.roster) -> JogressBoard {
        JogressBoard.make(for: states, catalog: catalog, roster: roster, context: context)
    }
}

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    var samples: [QuantityMetric: [HealthSample]] = [:]

    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        samples[metric] ?? []
    }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

// MARK: - What the entry point offers (pure)

/// US-132 AC1/AC2, at the level they are decided: which pairs the board offers, and what it says
/// when it offers none.
@MainActor
final class JogressBoardTests: XCTestCase {
    /// THE AC (AC1): a pair the player owns, both alive, matching a recipe, is offered — with the
    /// two parents' positions, names and origins, and the result the roster draws.
    func testAPairThatMatchesARecipeIsOffered() throws {
        let board = Fixture.board([Fixture.state("red", isActive: true, origin: "red_egg"),
                                   Fixture.state("blue", origin: "blue_egg", born: Fixture.bornLater)])

        XCTAssertNil(board.reason)
        XCTAssertTrue(board.isAvailable)
        XCTAssertEqual(board.offers.count, 1)
        let offer = try XCTUnwrap(board.offers.first)
        XCTAssertEqual(offer.first.rowId, 0)
        XCTAssertEqual(offer.second.rowId, 1)
        XCTAssertEqual(offer.first.displayName, "Red")
        XCTAssertEqual(offer.second.displayName, "Blue")
        XCTAssertEqual(offer.first.originDigitamaId, "red_egg")
        XCTAssertEqual(offer.second.originDigitamaId, "blue_egg")
        XCTAssertEqual(offer.resultId, "fused")
        XCTAssertEqual(offer.resultDisplayName, "Fused")
        XCTAssertEqual(offer.resultSpriteFile, "Omegamon")
        XCTAssertEqual(offer.title, "Red + Blue")
    }

    /// The recipe is authored `blue + red` and the box lists `red` first, so this passes only
    /// because the lookup is unordered (US-130's `JogressPair`).
    func testTheRecipeIsFoundWhicheverWayRoundTheBoxListsThePair() {
        let forward = Fixture.board([Fixture.state("red"), Fixture.state("blue")])
        let backward = Fixture.board([Fixture.state("blue"), Fixture.state("red")])

        XCTAssertEqual(forward.offers.count, 1)
        XCTAssertEqual(backward.offers.count, 1)
        XCTAssertEqual(backward.offers.first?.first.displayName, "Blue")
    }

    /// AC1: a DEAD Digimon is never a parent. It stays in the box as the record of what the player
    /// raised, and fusing it would be raising it again.
    func testADeadDigimonIsNeverOfferedAsAParent() {
        let board = Fixture.board([Fixture.state("red", isActive: true),
                                   Fixture.state("blue", dead: true, born: Fixture.bornLater)])

        XCTAssertTrue(board.offers.isEmpty)
        XCTAssertEqual(board.reason, JogressWording.needsTwo)
    }

    /// AC2, the first of the three reasons: one Digimon in the box — the ordinary state of a new
    /// game — says so rather than showing nothing.
    func testABoxWithNothingToPairSaysSo() {
        let board = Fixture.board([Fixture.state("red", isActive: true)])

        XCTAssertFalse(board.isAvailable)
        XCTAssertEqual(board.reason, JogressWording.needsTwo)
    }

    /// AC2's second reason: two Digimon that simply do not fuse.
    func testTwoDigimonThatDoNotFuseSayWhy() {
        let board = Fixture.board([Fixture.state("red", isActive: true),
                                   Fixture.state("other", born: Fixture.bornLater)])

        XCTAssertTrue(board.offers.isEmpty)
        XCTAssertEqual(board.reason, JogressWording.noRecipe)
    }

    /// AC2's third reason, and AC1's condition clause: a pair that IS a recipe but whose conditions
    /// are unmet is NOT offered, and the reason names the pair and carries the hint — through
    /// `ConditionReveal.line`, so the player reads the same wording the Dex and the map detail use.
    func testAPairWhoseConditionsAreUnmetIsNotOfferedAndTheReasonNamesIt() throws {
        let red = Fixture.state("red", isActive: true)
        let blue = Fixture.state("blue", born: Fixture.bornLater)
        let board = Fixture.board([red, blue], catalog: Fixture.gatedCatalog)

        XCTAssertTrue(board.offers.isEmpty)
        let reason = try XCTUnwrap(board.reason)
        XCTAssertTrue(reason.contains("Red + Blue"), reason)
        XCTAssertTrue(reason.contains("Train them both hard"), reason)
    }

    /// The same gated recipe, with the criterion met on BOTH parents: now it is offered. The pair
    /// with the pair's own counters is the whole difference between this test and the one above.
    func testAGatedPairIsOfferedOnceBothParentsHaveMetIt() {
        let red = Fixture.state("red", isActive: true)
        let blue = Fixture.state("blue", born: Fixture.bornLater)
        for state in [red, blue] {
            for _ in 0..<10 { state.recordTrainingSession() }
        }
        let board = Fixture.board([red, blue], catalog: Fixture.gatedCatalog)

        XCTAssertEqual(board.offers.count, 1)
        XCTAssertNil(board.reason)
    }

    /// A condition met by ONE parent is met by half the fusion. The strict reading, stated as a test
    /// because it is a decision rather than an accident of the loop.
    func testAConditionMetByOnlyOneParentDoesNotOpenTheFusion() {
        let red = Fixture.state("red", isActive: true)
        let blue = Fixture.state("blue", born: Fixture.bornLater)
        for _ in 0..<10 { red.recordTrainingSession() }
        let board = Fixture.board([red, blue], catalog: Fixture.gatedCatalog)

        XCTAssertTrue(board.offers.isEmpty)
        XCTAssertNotNil(board.reason)
    }

    /// A recipe whose RESULT the roster cannot draw is skipped rather than offered: an offer that
    /// led to an unnameable Digimon is a fusion the player cannot be shown the outcome of.
    func testARecipeWhoseResultTheRosterDoesNotKnowIsNotOffered() {
        let catalog = JogressCatalog(recipes: [
            JogressRecipe(parentA: "red", parentB: "blue", result: "ghost"),
        ])
        let board = Fixture.board([Fixture.state("red"), Fixture.state("blue")], catalog: catalog)

        XCTAssertTrue(board.offers.isEmpty)
        XCTAssertEqual(board.reason, JogressWording.noRecipe)
    }

    /// Several fusable pairs in one box are all offered, each with its own id — three shipped results
    /// are reachable by two different pairs, so an id keyed on the result alone would collapse two
    /// rows into one.
    func testEveryFusablePairInTheBoxIsOfferedWithItsOwnIdentity() {
        let catalog = JogressCatalog(recipes: [
            JogressRecipe(parentA: "red", parentB: "blue", result: "fused"),
            JogressRecipe(parentA: "red", parentB: "green", result: "fused"),
        ])
        let board = Fixture.board([Fixture.state("red", isActive: true),
                                   Fixture.state("blue", born: Fixture.bornLater),
                                   Fixture.state("green", born: Fixture.bornLast)],
                                  catalog: catalog)

        XCTAssertEqual(board.offers.count, 2)
        XCTAssertEqual(board.offers.map(\.title), ["Red + Blue", "Red + Green"])
        XCTAssertEqual(Set(board.offers.map(\.id)).count, 2)
    }

    /// AC2 as a property of the TYPE: an available board never carries a reason and an unavailable
    /// one always carries one, whatever it was constructed with. The entry point cannot end up with
    /// nothing to offer and nothing to say.
    func testOffersAndTheReasonAreExclusiveByConstruction() {
        let offer = Fixture.board([Fixture.state("red"), Fixture.state("blue")]).offers
        XCTAssertNil(JogressBoard(offers: offer, reason: "ignored").reason)
        XCTAssertEqual(JogressBoard(offers: [], reason: nil).reason, JogressWording.noRecipe)
        XCTAssertFalse(JogressBoard(offers: [], reason: nil).isAvailable)
    }

    /// The entry point's own wording: a count the player can read, singular and plural.
    func testTheEntryPointCountsWhatIsReady() {
        XCTAssertEqual(JogressWording.ready(1), "1 pair ready")
        XCTAssertEqual(JogressWording.ready(3), "3 pairs ready")
        XCTAssertFalse(JogressWording.needsTwo.isEmpty)
        XCTAssertFalse(JogressWording.noRecipe.isEmpty)
    }

    /// Over the SHIPPED recipes and the SHIPPED roster, not fixtures: a box holding WarGreymon and
    /// MetalGarurumon is offered Omegamon. Without this the whole suite would pass over a catalog
    /// nobody plays.
    func testTheShippedRecipesFuseARealPair() {
        let board = JogressBoard.make(
            for: [Fixture.state("wargreymon", isActive: true, origin: "agu_digitama"),
                  Fixture.state("metalgarurumon", origin: "gabu_digitama", born: Fixture.bornLater)],
            catalog: .bundled, roster: .bundled, context: Fixture.context)

        XCTAssertEqual(board.offers.count, 1)
        XCTAssertEqual(board.offers.first?.resultId, "omegamon")
        XCTAssertEqual(board.offers.first?.title, "WarGreymon + MetalGarurumon")
        XCTAssertNil(board.reason)
    }

    /// The shipped recipes over a box that cannot fuse — the state every real save is in today.
    func testTheShippedRecipesOfferNothingToAnOrdinaryBox() {
        let board = JogressBoard.make(
            for: [Fixture.state("agumon", stage: .child, isActive: true),
                  Fixture.state("gabu_digitama", stage: .digitama, born: Fixture.bornLater)],
            catalog: .bundled, roster: .bundled, context: Fixture.context)

        XCTAssertEqual(board.reason, JogressWording.noRecipe)
    }
}

// MARK: - Performing one, through the real store

/// US-132 AC3/AC4/AC5/AC6, through a real `GameStore`: what a fusion actually does to the box.
@MainActor
final class JogressStoreTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("Jogress.store") }
    private var store: GameStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JogressTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private let recipe = JogressRecipe(parentA: "red", parentB: "blue", result: "fused")

    /// A box holding the two parents. `extra` adds a third Digimon that is the one OUT, which is the
    /// case where neither parent is active.
    ///
    /// The store is held on the test for its whole life rather than in a `let`: a `GameStore` that
    /// goes out of scope resets its context and every record fetched from it then traps.
    @discardableResult
    private func seedPair(parentsActive: Bool = true) throws -> (GameStore, GameState, GameState) {
        let store = try GameStore(url: storeURL)
        let context = store.container.mainContext
        let red = GameState(currentDigimonId: "red", stage: .ultimate, isActive: parentsActive,
                            originDigitamaId: "red_egg", now: Fixture.born)
        let blue = GameState(currentDigimonId: "blue", stage: .ultimate, isActive: false,
                             originDigitamaId: "blue_egg", now: Fixture.bornLater)
        context.insert(red)
        context.insert(blue)
        if !parentsActive {
            context.insert(GameState(currentDigimonId: "other", stage: .ultimate, isActive: true,
                                     now: Fixture.bornLast))
        }
        try store.save()
        self.store = store
        return (store, red, blue)
    }

    private func fuse(_ store: GameStore, _ a: GameState, _ b: GameState,
                      seed: UInt64 = 7,
                      flush: (() throws -> Void)? = nil) throws -> JogressOutcome {
        var generator = SeededGenerator(seed: seed)
        return try store.performJogress(recipe, parents: (a, b), roster: Fixture.roster,
                                        now: Fixture.morning, using: &generator, flush: flush)
    }

    /// THE AC (AC3 + AC4 + AC5): both parents leave the box, the result comes out ACTIVE, one of the
    /// two eggs comes back frozen, and both new ids are in the Dex.
    func testAnEligiblePairFusesIntoAnActiveResultAndReturnsOneEgg() throws {
        let (store, red, blue) = try seedPair()

        let outcome = try fuse(store, red, blue)

        let box = try store.allStates()
        XCTAssertEqual(box.map(\.currentDigimonId).sorted(), ["fused", outcome.returnedDigitamaId].sorted())
        XCTAssertEqual(outcome.consumedIds, ["red", "blue"])
        XCTAssertEqual(try store.activeState()?.currentDigimonId, "fused")
        XCTAssertEqual(box.filter(\.isActive).count, 1)
        // The result is a real Digimon at the roster's stage for it, not an egg.
        XCTAssertEqual(outcome.result.stage, .ultimate)
        // AC4: the returned egg is unhatched, in the box, and frozen — exactly as a dropped one is,
        // so it does not age while it waits (US-128).
        let egg = try XCTUnwrap(box.first { $0.stage == .digitama })
        XCTAssertFalse(egg.isActive)
        XCTAssertEqual(egg.frozenSince, Fixture.morning)
        // AC5.
        XCTAssertTrue(try store.dexIds().contains("fused"))
        XCTAssertTrue(try store.dexIds().contains(outcome.returnedDigitamaId))
        XCTAssertTrue(try store.loadOrCreateProfile(roster: Fixture.roster)
            .ownedDigitamaIds.contains(outcome.returnedDigitamaId))
    }

    /// AC4's first clause: BOTH parents' origins stop being held, and exactly one comes back — so
    /// the other is free for a map to drop again (US-127/US-128).
    func testBothOriginsAreReleasedAndExactlyOneComesBack() throws {
        let (store, red, blue) = try seedPair()
        XCTAssertEqual(try store.heldDigitamaIds(), ["red_egg", "blue_egg"])

        let outcome = try fuse(store, red, blue)

        XCTAssertTrue(["red_egg", "blue_egg"].contains(outcome.returnedDigitamaId))
        XCTAssertEqual(try store.heldDigitamaIds(), [outcome.returnedDigitamaId])
    }

    /// AC4's generator clause: the same seed returns the same egg, every time — and two seeds
    /// between them return BOTH, so the choice is a real one rather than a constant that happens to
    /// look seeded.
    func testTheReturnedEggIsDeterministicUnderASeedAndCanBeEither() throws {
        var returned: Set<String> = []
        for seed in UInt64(0)...20 {
            let directory = storeDirectory.appendingPathComponent("seed\(seed)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try GameStore(url: directory.appendingPathComponent("s.store"))
            let context = store.container.mainContext
            let red = GameState(currentDigimonId: "red", stage: .ultimate,
                                originDigitamaId: "red_egg", now: Fixture.born)
            let blue = GameState(currentDigimonId: "blue", stage: .ultimate, isActive: false,
                                 originDigitamaId: "blue_egg", now: Fixture.bornLater)
            context.insert(red)
            context.insert(blue)
            try store.save()

            var first = SeededGenerator(seed: seed)
            var second = SeededGenerator(seed: seed)
            // The same seed asked twice, off the same two origins, is the same answer — the
            // determinism a test can rest an assertion on.
            let a = ["red_egg", "blue_egg"].randomElement(using: &first)
            let b = ["red_egg", "blue_egg"].randomElement(using: &second)
            XCTAssertEqual(a, b)

            let outcome = try fuse(store, red, blue, seed: seed)
            XCTAssertEqual(outcome.returnedDigitamaId, a)
            returned.insert(outcome.returnedDigitamaId)
        }
        XCTAssertEqual(returned, ["red_egg", "blue_egg"])
    }

    /// The result inherits the RETURNED egg's origin, which is what makes AC4's "both stop being
    /// held" true of the box and not merely of the delete: were it the other parent's, both ids
    /// would still be held and nothing would have been released.
    func testTheResultCarriesTheReturnedEggsOrigin() throws {
        let (store, red, blue) = try seedPair()

        let outcome = try fuse(store, red, blue)

        XCTAssertEqual(outcome.result.originDigitamaId, outcome.returnedDigitamaId)
    }

    /// AC3, the case the shipped screen actually produces: neither parent is the Digimon that was
    /// out. The result still comes out, and the Digimon that WAS out is frozen rather than left as a
    /// second active record — US-124's invariant, which one careless insert would break.
    func testFusingTwoFrozenDigimonStillLeavesExactlyOneOut() throws {
        let (store, red, blue) = try seedPair(parentsActive: false)
        XCTAssertEqual(try store.activeState()?.currentDigimonId, "other")

        try fuse(store, red, blue)

        let box = try store.allStates()
        XCTAssertEqual(box.filter(\.isActive).map(\.currentDigimonId), ["fused"])
        let other = try XCTUnwrap(box.first { $0.currentDigimonId == "other" })
        XCTAssertFalse(other.isActive)
        XCTAssertEqual(other.frozenSince, Fixture.morning)
    }

    /// It is on DISK, not merely in memory: the same box comes back out of a reopened store.
    func testTheFusionSurvivesAReopen() throws {
        let (store, red, blue) = try seedPair()
        let outcome = try fuse(store, red, blue)

        let reopened = try GameStore(url: storeURL)
        let box = try reopened.allStates()
        XCTAssertEqual(box.map(\.currentDigimonId).sorted(),
                       ["fused", outcome.returnedDigitamaId].sorted())
        XCTAssertEqual(try reopened.activeState()?.currentDigimonId, "fused")
    }

    /// AC6's easy half, and the one a player can actually reach: an ineligible pair is refused
    /// BEFORE anything is mutated, so there is nothing to roll back. Four ways to be ineligible.
    func testAnIneligiblePairIsRefusedWithTheBoxUntouched() throws {
        let (store, red, blue) = try seedPair()
        let before = try store.allStates().map(\.currentDigimonId).sorted()

        // The recipe does not name these two.
        let wrong = JogressRecipe(parentA: "red", parentB: "green", result: "fused")
        var generator = SeededGenerator(seed: 1)
        XCTAssertThrowsError(try store.performJogress(wrong, parents: (red, blue),
                                                      roster: Fixture.roster, now: Fixture.morning,
                                                      using: &generator)) { error in
            XCTAssertEqual(error as? GameStoreError, .jogressPairNotFusable)
        }

        // The same record twice.
        XCTAssertThrowsError(try fuse(store, red, red)) { error in
            XCTAssertEqual(error as? GameStoreError, .jogressPairNotFusable)
        }

        // A dead parent — AC1 at the store, so a stale offer cannot fuse a corpse either.
        blue.healthStatus = .dead
        blue.diedAt = Fixture.morning
        XCTAssertThrowsError(try fuse(store, red, blue)) { error in
            XCTAssertEqual(error as? GameStoreError, .jogressPairNotFusable)
        }
        blue.healthStatus = .healthy
        blue.diedAt = nil

        // A result the roster cannot draw.
        let ghost = JogressRecipe(parentA: "red", parentB: "blue", result: "ghost")
        XCTAssertThrowsError(try store.performJogress(ghost, parents: (red, blue),
                                                      roster: Fixture.roster, now: Fixture.morning,
                                                      using: &generator)) { error in
            XCTAssertEqual(error as? GameStoreError, .jogressResultUnknown)
        }

        XCTAssertEqual(try store.allStates().map(\.currentDigimonId).sorted(), before)
        XCTAssertEqual(try store.allStates().filter(\.isActive).count, 1)
        XCTAssertFalse(try store.dexIds().contains("fused"))
    }

    /// A record belonging to a DIFFERENT store is refused, which is what a party screen caching an
    /// offer across stores would hand over — US-124's rule, applied to a pair.
    func testARecordFromAnotherStoreIsRefused() throws {
        let (store, red, _) = try seedPair()
        let otherStore = try GameStore(url: storeDirectory.appendingPathComponent("Other.store"))
        let stranger = GameState(currentDigimonId: "blue", stage: .ultimate, isActive: false,
                                 originDigitamaId: "blue_egg", now: Fixture.bornLater)
        otherStore.container.mainContext.insert(stranger)
        try otherStore.save()

        XCTAssertThrowsError(try fuse(store, red, stranger)) { error in
            XCTAssertEqual(error as? GameStoreError, .stateNotInStore)
        }
        XCTAssertEqual(try store.allStates().count, 2)
    }

    /// THE AC (AC6): a failure at the WRITE leaves the box exactly as it was — both parents alive
    /// and intact, no result, no egg, nothing in the Dex.
    ///
    /// The failing flush is injected because there is no other way to make SwiftData throw on
    /// demand; everything before it is the real transaction, so what is rolled back here is the real
    /// set of inserts and deletes.
    func testAFailureAtTheWriteRollsTheWholeFusionBack() throws {
        let (store, red, blue) = try seedPair()
        struct Boom: Error {}

        XCTAssertThrowsError(try fuse(store, red, blue, flush: { throw Boom() })) { error in
            XCTAssertTrue(error is Boom)
        }

        let box = try store.allStates()
        XCTAssertEqual(box.map(\.currentDigimonId).sorted(), ["blue", "red"])
        XCTAssertEqual(box.filter(\.isActive).count, 1)
        XCTAssertFalse(box.contains { $0.isDead })
        XCTAssertEqual(try store.heldDigitamaIds(), ["red_egg", "blue_egg"])
        XCTAssertFalse(try store.dexIds().contains("fused"))

        // And off disk, which is where "exactly as it was" has to be true.
        let reopened = try GameStore(url: storeURL)
        XCTAssertEqual(try reopened.allStates().map(\.currentDigimonId).sorted(), ["blue", "red"])
        XCTAssertEqual(try reopened.allStates().filter(\.isActive).count, 1)
    }

    /// The rolled-back box still fuses afterwards. A rollback that left the context confused would
    /// pass the test above and fail the player the next time they tapped.
    func testAFusionStillWorksAfterARolledBackOne() throws {
        let (store, red, blue) = try seedPair()
        struct Boom: Error {}
        XCTAssertThrowsError(try fuse(store, red, blue, flush: { throw Boom() }))

        let parents = try store.allStates()
        let outcome = try fuse(store,
                               try XCTUnwrap(parents.first { $0.currentDigimonId == "red" }),
                               try XCTUnwrap(parents.first { $0.currentDigimonId == "blue" }))

        XCTAssertEqual(outcome.result.currentDigimonId, "fused")
        XCTAssertEqual(try store.activeState()?.currentDigimonId, "fused")
    }
}

// MARK: - Performing one, through the model and the screen

/// US-132 AC3/AC7/AC8/AC9 through `MainScreenModel`: the tap, the ceremony and the failsafe.
///
/// The model is handed the SAME `GameStore` the test seeded with (US-125's learning): a second
/// container on the same file would give the test its own copy of every record, so a fusion that did
/// nothing at all would leave the test looking exactly like success.
@MainActor
final class JogressModelTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("JogressModel.store") }
    private var store: GameStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JogressModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// The two shipped parents of `wargreymon + metalgarurumon -> omegamon`, plus the egg the game
    /// started at. The SHIPPED catalog and roster, so what the model fuses is what a player would.
    @discardableResult
    private func seedBox(at url: URL? = nil) throws -> GameStore {
        let store = try GameStore(url: url ?? storeURL)
        let out = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.born)
        out.currentDigimonId = "wargreymon"
        out.stage = .ultimate
        store.container.mainContext.insert(
            GameState(currentDigimonId: "metalgarurumon", stage: .ultimate, isActive: false,
                      originDigitamaId: "gabu_digitama", now: Fixture.bornLater))
        try store.save()
        self.store = store
        return store
    }

    private func makeModel(at url: URL? = nil, jogressSeed: UInt64 = 3) -> MainScreenModel {
        let store = store
        return MainScreenModel(
            makeStore: { try store ?? GameStore(url: url ?? self.storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(),
                                               calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                 calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { Fixture.morning },
            chooseStartingDigitama: { $0.first },
            makeJogressGenerator: { SeededGenerator(seed: jogressSeed) }
        )
    }

    /// THE AC (AC3 + AC7), end to end through the model: the pair the party screen offers fuses, the
    /// result is the Digimon on screen, and the EXISTING evolution ceremony is what announces it.
    func testFusingThroughTheModelPutsTheResultOutAndPlaysTheCeremony() async throws {
        let store = try seedBox()
        let model = makeModel()
        await model.start()

        let offer = try XCTUnwrap(model.jogressBoard.offers.first)
        XCTAssertTrue(model.performJogress(offer))

        XCTAssertEqual(model.state?.currentDigimonId, "omegamon")
        XCTAssertEqual(try store.activeState()?.currentDigimonId, "omegamon")
        // AC7: the ceremony `ContentView` already plays, raised from the parent the player picked
        // first to the fusion.
        XCTAssertEqual(model.pendingEvolution?.from.displayName, "WarGreymon")
        XCTAssertEqual(model.pendingEvolution?.to.displayName, "Omegamon")
        // AC5 at the screen: the Dex set the map detail and the Dex read is kept in step, rather
        // than waiting for the next launch.
        XCTAssertTrue(model.discoveredDigimonIds.contains("omegamon"))
        XCTAssertTrue(model.discoveredDigimonIds.contains(model.heldDigitamaIds.first ?? ""))
    }

    /// The fused Digimon is DRAWABLE. `omegamon` is one of the 780 orphans no line reaches, so a
    /// graph-only lookup answers nil and the main screen would draw `SavedGameUnavailableView` over
    /// the Digimon the player had just earned — the US-122 trap, one story later.
    func testTheFusedDigimonCanBeDrawn() async throws {
        try seedBox()
        let model = makeModel()
        await model.start()
        model.performJogress(try XCTUnwrap(model.jogressBoard.offers.first))

        let presentation = try XCTUnwrap(model.presentation)
        XCTAssertEqual(presentation.displayName, "Omegamon")
        XCTAssertEqual(presentation.spriteStage, Stage.ultimate.rawValue)
        XCTAssertFalse(presentation.spriteFile.isEmpty)
    }

    /// AC9's determinism, through the model rather than the store: a given injected seed always
    /// returns the same egg, and the seeds between them return BOTH — so the model really is
    /// spending the generator it was handed rather than always keeping the first parent's.
    func testTheReturnedEggFollowsTheInjectedSeed() async throws {
        var bySeed: [UInt64: String] = [:]
        for pass in 0..<2 {
            for seed in UInt64(0)...9 {
                let directory = storeDirectory
                    .appendingPathComponent("pass\(pass)-seed\(seed)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory,
                                                        withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("Seeded.store")
                let store = try seedBox(at: url)
                let model = makeModel(at: url, jogressSeed: seed)
                await model.start()
                model.performJogress(try XCTUnwrap(model.jogressBoard.offers.first))

                let egg = try XCTUnwrap(try store.allStates().first { $0.stage == .digitama })
                if let already = bySeed[seed] {
                    XCTAssertEqual(egg.currentDigimonId, already, "seed \(seed) is not deterministic")
                } else {
                    bySeed[seed] = egg.currentDigimonId
                }
            }
        }
        XCTAssertEqual(Set(bySeed.values), ["agu_digitama", "gabu_digitama"])
    }

    /// A STALE offer is refused. The box is reordered between the offer being made and it being
    /// acted on — which is exactly what taking a Digimon out does (US-125's thaw) — and this
    /// CONSUMES what it indexes, so acting on a stale position would fuse two Digimon the player
    /// never chose.
    func testAnOfferTheBoxNoLongerMakesIsRefused() async throws {
        let store = try seedBox()
        let model = makeModel()
        await model.start()
        let offer = try XCTUnwrap(model.jogressBoard.offers.first)

        // The pair is broken up: one of the parents dies.
        let metal = try XCTUnwrap(try store.allStates().first { $0.currentDigimonId == "metalgarurumon" })
        metal.healthStatus = .dead
        metal.diedAt = Fixture.morning
        try store.save()

        XCTAssertFalse(model.performJogress(offer))
        XCTAssertEqual(try store.allStates().map(\.currentDigimonId).sorted(),
                       ["metalgarurumon", "wargreymon"])
        XCTAssertNil(model.pendingEvolution)
    }

    /// AC1 at the screen: with nothing fusable the entry point is not available and says why, and
    /// the model refuses an offer built out of that box.
    func testAnOrdinaryBoxIsOfferedNothingAndIsToldWhy() async throws {
        let store = try GameStore(url: storeURL)
        try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.born)
        self.store = store
        let model = makeModel()
        await model.start()

        XCTAssertFalse(model.jogressBoard.isAvailable)
        XCTAssertEqual(model.jogressBoard.reason, JogressWording.needsTwo)
    }

    /// AC8: the failsafe check runs after the fusion. It is a no-op BY CONSTRUCTION — the result is
    /// alive and in the box, so the player cannot be stranded — and what this pins is that it does
    /// not misfire: no spurious `agu_digitama` is granted on top of what the fusion returned.
    func testTheFailsafeRunsAfterAFusionAndGrantsNothing() async throws {
        let store = try seedBox()
        let model = makeModel()
        await model.start()
        model.performJogress(try XCTUnwrap(model.jogressBoard.offers.first))

        let box = try store.allStates()
        XCTAssertFalse(StrandedFailsafe.isStranded(in: box))
        // Two records and no more: the fusion and the one egg it returned. A failsafe that had
        // fired would have put a third, `agu_digitama`, alongside them.
        XCTAssertEqual(box.count, 2)
        XCTAssertLessThanOrEqual(
            box.filter { $0.currentDigimonId == StrandedFailsafe.digitamaId }.count, 1)
    }

    /// The party screen redraws off the same records, so after a fusion the box is the two new rows
    /// and the entry point has nothing left to offer — the pair it named is gone.
    func testThePartyScreenShowsTheFusionAndOffersNothingFurther() async throws {
        try seedBox()
        let model = makeModel()
        await model.start()
        model.performJogress(try XCTUnwrap(model.jogressBoard.offers.first))

        XCTAssertEqual(model.partyRows.count, 2)
        XCTAssertEqual(model.partyRows.filter { $0.status == .active }.map(\.displayName),
                       ["Omegamon"])
        XCTAssertFalse(model.jogressBoard.isAvailable)
        XCTAssertNotNil(model.jogressBoard.reason)
    }
}
