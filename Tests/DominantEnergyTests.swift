import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// Hand-written instants, ordered by construction. Nothing here waits real time, so "more recently
/// earned" is decided by the injected clock and not by how long a test took to run.
///
/// All three are hours apart within ONE local day of a fixed-zone calendar, which matters for the
/// crediting tests: instants a day apart would roll the ledger over and credit the same readings
/// twice, and a machine-zone calendar would decide midnight differently depending on where the
/// suite ran.
private enum When {
    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private static func at(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = losAngeles
        formatter.timeZone = losAngeles.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("bad fixture date \(iso)")
        }
        return date
    }

    static let early = at("2026-07-17 08:00")
    static let later = at("2026-07-17 12:00")
    static let latest = at("2026-07-17 18:00")
    static let dayStart = losAngeles.startOfDay(for: early)
}

private func newGame() -> GameState {
    GameState(currentDigimonId: "agu_digitama", now: When.early)
}

/// `GameState` as it stood before `energyLastEarned` existed — every other field identical.
///
/// Nested so it can carry the same unqualified type name, which is what SwiftData names the
/// entity: a store written through this class is the store the app wrote one version ago. Every
/// other test writes its store under the CURRENT model, so without this the old shape is never
/// exercised and a migration failure would first be seen by a user with a saved game.
private enum PreRecencySchema {
    @Model
    final class GameState {
        var currentDigimonId: String
        var stage: Stage
        var stageEnergy: EnergyTotals
        var lifetimeEnergy: EnergyTotals
        var birthDate: Date
        var stageEnteredDate: Date
        var careMistakeCount: Int
        var hunger: Int
        var strengthStat: Int
        var healthStatus: HealthStatus
        var battleWins: Int
        var battleLosses: Int

        init(currentDigimonId: String, stage: Stage, stageEnergy: EnergyTotals, now: Date) {
            self.currentDigimonId = currentDigimonId
            self.stage = stage
            self.stageEnergy = stageEnergy
            self.lifetimeEnergy = .zero
            self.birthDate = now
            self.stageEnteredDate = now
            self.careMistakeCount = 0
            self.hunger = 0
            self.strengthStat = 0
            self.healthStatus = .healthy
            self.battleWins = 0
            self.battleLosses = 0
        }
    }
}

@MainActor
final class DominantEnergyTests: XCTestCase {
    // MARK: - A clear winner

    /// THE AC: the type with the highest `stageEnergy` total.
    func testAClearWinnerIsTheTypeWithTheMostStageEnergy() {
        let state = newGame()
        state.stageEnergy = EnergyTotals(strength: 10, vitality: 40, spirit: 20, stamina: 30)

        XCTAssertEqual(state.dominantEnergyType, .vitality)
    }

    /// The winner is found wherever it sits in `allCases`, not just when it happens to be first.
    /// A reduce that never replaced its leader would pass the test above only because `.vitality`
    /// is second; this one puts the winner last, and pins the other two types besides.
    func testTheWinnerIsFoundWhereverItSitsInTheOrder() {
        let state = newGame()

        state.stageEnergy = EnergyTotals(strength: 40, vitality: 10, spirit: 20, stamina: 30)
        XCTAssertEqual(state.dominantEnergyType, .strength)

        state.stageEnergy = EnergyTotals(strength: 10, vitality: 20, spirit: 40, stamina: 30)
        XCTAssertEqual(state.dominantEnergyType, .spirit)

        state.stageEnergy = EnergyTotals(strength: 10, vitality: 20, spirit: 30, stamina: 40)
        XCTAssertEqual(state.dominantEnergyType, .stamina)
    }

    /// One point is a winner. The nil case is "nothing earned at all", not "barely anything".
    func testASinglePointIsEnoughToBeDominant() {
        let state = newGame()
        state.stageEnergy = EnergyTotals(strength: 0, vitality: 0, spirit: 1, stamina: 0)

        XCTAssertEqual(state.dominantEnergyType, .spirit)
    }

    /// The branch follows THIS stage, so a big lifetime total from a previous stage cannot drag
    /// the answer back. Vitality leads a life of walking; strength leads the stage that counts.
    func testTheDominantTypeIgnoresLifetimeEnergy() {
        let state = newGame()
        state.stageEnergy = EnergyTotals(strength: 5, vitality: 1, spirit: 0, stamina: 0)
        // On the PLAYER since US-123, which is a stronger form of the same claim: the branch is
        // decided by a Digimon that cannot reach the lifetime total at all.
        let profile = PlayerProfile(
            lifetimeEnergy: EnergyTotals(strength: 5, vitality: 900, spirit: 0, stamina: 0))

        XCTAssertEqual(state.dominantEnergyType, .strength)
        XCTAssertEqual(profile.lifetimeEnergy.vitality, 900, "and the total is really there")
    }

    // MARK: - Ties

    /// THE AC: a two-way tie goes to the most recently incremented type.
    ///
    /// Asserted in BOTH directions on the same pair. `.strength` precedes `.vitality` in
    /// `allCases`, so an implementation that ignored recency and kept the first type it saw would
    /// still pass the second half — only the first half catches it, and only the second half
    /// catches an implementation that blindly prefers the last type instead.
    func testATwoWayTieIsBrokenByTheMostRecentlyEarnedType() {
        let state = newGame()
        state.stageEnergy = EnergyTotals(strength: 25, vitality: 25, spirit: 0, stamina: 0)

        state.energyLastEarned = EnergyRecency(strength: When.early, vitality: When.later)
        XCTAssertEqual(state.dominantEnergyType, .vitality, "vitality was earned more recently")

        state.energyLastEarned = EnergyRecency(strength: When.later, vitality: When.early)
        XCTAssertEqual(state.dominantEnergyType, .strength, "strength was earned more recently")
    }

    /// The same rule holds for a pair that is not the first two in `allCases`, and while a third
    /// type sits below the tie: the tie-break must run between the leaders, not against the field.
    func testATieIsBrokenByRecencyEvenWhenTheTiedTypesAreLastInOrder() {
        let state = newGame()
        state.stageEnergy = EnergyTotals(strength: 3, vitality: 0, spirit: 25, stamina: 25)

        state.energyLastEarned = EnergyRecency(strength: When.latest, spirit: When.early, stamina: When.later)
        XCTAssertEqual(state.dominantEnergyType, .stamina, "stamina was earned more recently than spirit")

        state.energyLastEarned = EnergyRecency(strength: When.latest, spirit: When.later, stamina: When.early)
        XCTAssertEqual(state.dominantEnergyType, .spirit, "spirit was earned more recently than stamina")
    }

    /// A type carrying a stale timestamp from an earlier stage does not win on it: recency only
    /// ever breaks a tie, and a type it is tied with is one it has not out-earned.
    func testRecencyNeverOutranksAHigherTotal() {
        let state = newGame()
        state.stageEnergy = EnergyTotals(strength: 26, vitality: 25, spirit: 0, stamina: 0)
        state.energyLastEarned = EnergyRecency(strength: When.early, vitality: When.latest)

        XCTAssertEqual(state.dominantEnergyType, .strength, "26 beats 25 however recent 25 is")
    }

    /// Energy earned before this property existed has no timestamp. A type that has one is the
    /// better answer, and the untimestamped type must not win by virtue of nil.
    func testATiedTypeWithNoTimestampLosesToOneThatHasOne() {
        let state = newGame()
        state.stageEnergy = EnergyTotals(strength: 25, vitality: 25, spirit: 0, stamina: 0)

        state.energyLastEarned = EnergyRecency(strength: nil, vitality: When.early)
        XCTAssertEqual(state.dominantEnergyType, .vitality)

        state.energyLastEarned = EnergyRecency(strength: When.early, vitality: nil)
        XCTAssertEqual(state.dominantEnergyType, .strength)
    }

    /// Nothing separates two types earned in the same instant — one read credits every type with
    /// the same `now` — so the answer must at least be stable rather than varying between calls.
    func testATieWithNothingToSeparateItIsStable() {
        let state = newGame()
        state.stageEnergy = EnergyTotals(strength: 25, vitality: 25, spirit: 0, stamina: 0)
        state.energyLastEarned = EnergyRecency(strength: When.early, vitality: When.early)

        let answers = (0..<5).map { _ in state.dominantEnergyType }
        XCTAssertEqual(Set(answers.map(\.?.rawValue)).count, 1, "the same tie must not answer two ways")
        XCTAssertNotNil(state.dominantEnergyType)
    }

    // MARK: - Nothing earned

    /// THE AC: nil when all four totals are zero.
    func testAllZeroTotalsHaveNoDominantType() {
        XCTAssertNil(newGame().dominantEnergyType, "a fresh egg has no leaning")
    }

    /// Not even a leftover timestamp conjures a dominant type out of an empty stage — which is
    /// what a freshly evolved Digimon looks like the instant its stage energy is reset.
    func testAllZeroTotalsHaveNoDominantTypeEvenWithTimestamps() {
        let state = newGame()
        state.stageEnergy = .zero
        state.energyLastEarned = EnergyRecency(strength: When.early, vitality: When.latest)

        XCTAssertNil(state.dominantEnergyType)
    }

    // MARK: - Credited energy

    /// The timestamps are not decoration: crediting real readings must stamp the types it credits,
    /// or every tie in the shipped app falls back to `allCases` order forever.
    func testCreditingEnergyStampsTheTypesItCredits() {
        let state = newGame()
        let ledger = EnergyLedger(day: When.dayStart)

        EnergyCreditor.credit(
            [.strength: .value(500), .vitality: .noData],
            to: state, profile: PlayerProfile(), ledger: ledger, now: When.later, calendar: When.losAngeles
        )

        XCTAssertEqual(state.energyLastEarned.strength, When.later, "strength was credited, so it was earned now")
        XCTAssertNil(state.energyLastEarned.vitality, "vitality earned nothing and must not be stamped")
        XCTAssertNil(state.energyLastEarned.spirit)
        XCTAssertNil(state.energyLastEarned.stamina)
    }

    /// A read that credits nothing new — the same day's totals, already paid for — is not an
    /// earning, and must not reorder a tie behind the user's back.
    func testAReadThatCreditsNothingDoesNotRestampAType() {
        let state = newGame()
        let ledger = EnergyLedger(day: When.dayStart)

        // The same 500 steps, read twice in one day: the second read is the same steps already
        // paid for, not 500 more.
        EnergyCreditor.credit(
            [.strength: .value(500)], to: state, profile: PlayerProfile(), ledger: ledger, now: When.early, calendar: When.losAngeles
        )
        EnergyCreditor.credit(
            [.strength: .value(500)], to: state, profile: PlayerProfile(), ledger: ledger, now: When.later, calendar: When.losAngeles
        )

        XCTAssertEqual(state.stageEnergy.strength, 5, "the same steps must not be paid for twice")
        XCTAssertEqual(state.energyLastEarned.strength, When.early, "the second read bought nothing")
    }

    /// End to end: two reads, the second one earning vitality, leaves vitality dominant on a tie
    /// that `allCases` order would have given to strength.
    func testCreditedEnergyDecidesATieByWhichReadEarnedItLast() {
        let state = newGame()
        let ledger = EnergyLedger(day: When.dayStart)

        // 100 steps buys 1 Strength; then 20 kcal buys 1 Vitality on a later read, off the same
        // day's unchanged step count.
        EnergyCreditor.credit(
            [.strength: .value(100)], to: state, profile: PlayerProfile(), ledger: ledger, now: When.early, calendar: When.losAngeles
        )
        EnergyCreditor.credit(
            [.strength: .value(100), .vitality: .value(20)],
            to: state, profile: PlayerProfile(), ledger: ledger, now: When.later, calendar: When.losAngeles
        )

        XCTAssertEqual(state.stageEnergy, EnergyTotals(strength: 1, vitality: 1, spirit: 0, stamina: 0))
        XCTAssertEqual(state.dominantEnergyType, .vitality)
    }

    // MARK: - Persistence

    /// A tie survives a relaunch only if the timestamps do. Dropped to disk and read back through
    /// a new container, so what is asserted came off the file rather than out of a live context.
    func testRecencySurvivesAReopen() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DominantEnergyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("GameState.store")

        do {
            let store = try GameStore(url: storeURL)
            let state = try store.loadOrCreate(digitamaId: "agu_digitama", now: When.early)
            state.stageEnergy = EnergyTotals(strength: 25, vitality: 25, spirit: 0, stamina: 0)
            state.energyLastEarned = EnergyRecency(strength: When.early, vitality: When.later)
            try store.save()
        }

        let reopened = try GameStore(url: storeURL)
        let loaded = try reopened.loadOrCreate(digitamaId: "agu_digitama", now: When.latest)

        XCTAssertEqual(loaded.energyLastEarned, EnergyRecency(strength: When.early, vitality: When.later))
        XCTAssertEqual(loaded.dominantEnergyType, .vitality, "the tie must break the same way after a relaunch")
    }

    /// A saved game written before `energyLastEarned` existed must still open — this property was
    /// added to a shipped model, and a store that cannot migrate THROWS, which for the app is a
    /// crash at launch on exactly the watches that already have a Digimon.
    ///
    /// Its own control: `loadOrCreate` is asked for "gabu_digitama" but must hand back the
    /// pre-existing "agu_digitama", which can only happen if the old file was genuinely read back
    /// rather than quietly replaced with a new store.
    func testASaveGameWrittenBeforeRecencyExistedStillOpens() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DominantEnergyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("GameState.store")

        do {
            let oldSchema = Schema([PreRecencySchema.GameState.self])
            let oldContainer = try ModelContainer(
                for: oldSchema,
                configurations: ModelConfiguration(schema: oldSchema, url: storeURL)
            )
            oldContainer.mainContext.insert(
                PreRecencySchema.GameState(
                    currentDigimonId: "agu_digitama",
                    stage: .child,
                    stageEnergy: EnergyTotals(strength: 25, vitality: 25, spirit: 0, stamina: 0),
                    now: When.early
                )
            )
            try oldContainer.mainContext.save()
        }

        let upgraded = try GameStore(url: storeURL)
        let loaded = try upgraded.loadOrCreate(digitamaId: "gabu_digitama", now: When.latest)

        XCTAssertEqual(loaded.currentDigimonId, "agu_digitama",
                       "the saved game survived — it was not replaced by a new one")
        XCTAssertEqual(loaded.stageEnergy, EnergyTotals(strength: 25, vitality: 25, spirit: 0, stamina: 0))
        XCTAssertEqual(loaded.energyLastEarned, .never, "energy earned before the property has no timestamp")

        // Saving a migrated game is where a merely-defaulted property dies: it opens fine, then
        // the first save of an untouched `energyLastEarned` fails validation as a required value
        // that never actually reached the store. This is the app's own path — open, play, save.
        loaded.hunger += 1
        XCTAssertNoThrow(try upgraded.save(), "a migrated saved game must still be savable")

        // The tie above has nothing to break it, but the answer must still be an answer rather
        // than a crash or a nil, and the next thing earned must take the lead.
        XCTAssertNotNil(loaded.dominantEnergyType)
        let ledger = try upgraded.loadOrCreateLedger(now: When.latest, calendar: When.losAngeles)
        EnergyCreditor.credit(
            [.vitality: .value(20)], to: loaded, profile: PlayerProfile(), ledger: ledger, now: When.latest, calendar: When.losAngeles
        )
        try upgraded.save()
        XCTAssertEqual(loaded.dominantEnergyType, .vitality, "a migrated store still credits and still leads")
    }
}
