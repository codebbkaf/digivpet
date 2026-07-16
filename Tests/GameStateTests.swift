import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

@MainActor
final class GameStateTests: XCTestCase {
    /// A private directory per test, so no test can pass by reading another's leftovers.
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("GameState.store") }

    private let t0 = Date(timeIntervalSinceReferenceDate: 700_000)
    private let t1 = Date(timeIntervalSinceReferenceDate: 900_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GameStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Removes the -wal and -shm sidecars along with the store itself.
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    // MARK: - Persistence

    /// Writes every field, drops the container, then reads through a brand new one pointed at
    /// the same file — so what is asserted came off disk, not out of the first context's cache.
    func testSaveThenLoadRoundTripsEveryField() throws {
        // Distinct values throughout: nothing is left at its default, and no two fields share a
        // value, so a crossed-wire mapping cannot round-trip by coincidence.
        do {
            let store = try GameStore(url: storeURL)
            let state = GameState(currentDigimonId: "greymon", stage: .adult, now: t0)
            state.stageEnergy = EnergyTotals(strength: 11, vitality: 22, spirit: 33, stamina: 44)
            state.lifetimeEnergy = EnergyTotals(strength: 55, vitality: 66, spirit: 77, stamina: 88)
            state.stageEnteredDate = t1
            state.careMistakeCount = 2
            state.hunger = 3
            state.strengthStat = 17
            state.healthStatus = .sick
            state.battleWins = 5
            state.battleLosses = 6
            store.container.mainContext.insert(state)
            try store.save()
        }

        let reopened = try GameStore(url: storeURL)
        let saved = try reopened.container.mainContext.fetch(FetchDescriptor<GameState>())
        XCTAssertEqual(saved.count, 1)
        let loaded = try XCTUnwrap(saved.first)

        XCTAssertEqual(loaded.currentDigimonId, "greymon")
        XCTAssertEqual(loaded.stage, .adult)
        XCTAssertEqual(loaded.stageEnergy, EnergyTotals(strength: 11, vitality: 22, spirit: 33, stamina: 44))
        XCTAssertEqual(loaded.lifetimeEnergy, EnergyTotals(strength: 55, vitality: 66, spirit: 77, stamina: 88))
        XCTAssertEqual(loaded.birthDate, t0)
        XCTAssertEqual(loaded.stageEnteredDate, t1)
        XCTAssertEqual(loaded.careMistakeCount, 2)
        XCTAssertEqual(loaded.hunger, 3)
        XCTAssertEqual(loaded.strengthStat, 17)
        XCTAssertEqual(loaded.healthStatus, .sick)
        XCTAssertEqual(loaded.battleWins, 5)
        XCTAssertEqual(loaded.battleLosses, 6)
    }

    /// The store file is a real file on disk, not an in-memory store that would evaporate on
    /// relaunch while still passing a same-process round-trip.
    func testStateIsWrittenToADurableFile() throws {
        let store = try GameStore(url: storeURL)
        try store.resetGame(digitamaId: "agu_digitama", now: t0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        let size = try FileManager.default.attributesOfItem(atPath: storeURL.path)[.size] as? Int
        XCTAssertGreaterThan(size ?? 0, 0)
    }

    func testLoadOrCreateReturnsTheSavedGameRatherThanStartingOver() throws {
        let store = try GameStore(url: storeURL)
        let first = try store.loadOrCreate(digitamaId: "agu_digitama", now: t0)
        first.hunger = 3
        try store.save()

        let second = try store.loadOrCreate(digitamaId: "gabu_digitama", now: t1)

        // Came back as the egg already being raised, not the one just passed in.
        XCTAssertEqual(second.currentDigimonId, "agu_digitama")
        XCTAssertEqual(second.hunger, 3)
        XCTAssertEqual(second.birthDate, t0)
    }

    // MARK: - Reset

    func testResetGameClearsStateBackToANewDigitama() throws {
        let store = try GameStore(url: storeURL)
        let played = try store.loadOrCreate(digitamaId: "agu_digitama", now: t0)
        played.currentDigimonId = "greymon"
        played.stage = .adult
        played.stageEnergy = EnergyTotals(strength: 90, vitality: 90, spirit: 90, stamina: 90)
        played.lifetimeEnergy = EnergyTotals(strength: 500, vitality: 500, spirit: 500, stamina: 500)
        played.careMistakeCount = 3
        played.hunger = 4
        played.strengthStat = 40
        played.healthStatus = .sick
        played.battleWins = 9
        played.battleLosses = 8
        try store.save()

        let fresh = try store.resetGame(digitamaId: "gabu_digitama", now: t1)

        XCTAssertEqual(fresh.currentDigimonId, "gabu_digitama")
        XCTAssertEqual(fresh.stage, .digitama)
        XCTAssertEqual(fresh.stageEnergy, .zero)
        // A total wipe by design — this is the debug reset, not rebirth after death, which has
        // to keep lifetime energy.
        XCTAssertEqual(fresh.lifetimeEnergy, .zero)
        XCTAssertEqual(fresh.birthDate, t1)
        XCTAssertEqual(fresh.stageEnteredDate, t1)
        XCTAssertEqual(fresh.careMistakeCount, 0)
        XCTAssertEqual(fresh.hunger, 0)
        XCTAssertEqual(fresh.strengthStat, 0)
        XCTAssertEqual(fresh.healthStatus, .healthy)
        XCTAssertEqual(fresh.battleWins, 0)
        XCTAssertEqual(fresh.battleLosses, 0)
    }

    /// The old game is deleted, not merely shadowed — two records would make `loadOrCreate`
    /// return whichever the fetch happened to order first.
    func testResetGameLeavesExactlyOneSavedGame() throws {
        let store = try GameStore(url: storeURL)
        try store.resetGame(digitamaId: "agu_digitama", now: t0)
        try store.resetGame(digitamaId: "gabu_digitama", now: t1)

        let saved = try store.container.mainContext.fetch(FetchDescriptor<GameState>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.currentDigimonId, "gabu_digitama")
    }

    func testResetGameSurvivesReopening() throws {
        do {
            let store = try GameStore(url: storeURL)
            try store.resetGame(digitamaId: "gabu_digitama", now: t1)
        }

        let reopened = try GameStore(url: storeURL)
        let loaded = try reopened.loadOrCreate(digitamaId: "unused_egg", now: t0)
        XCTAssertEqual(loaded.currentDigimonId, "gabu_digitama")
        XCTAssertEqual(loaded.birthDate, t1)
    }

    // MARK: - The app's real store

    /// Every other test here passes a temp URL, so none of them touch the store the shipping app
    /// actually opens: `GameStore()` with SwiftData's default location. If that location cannot be
    /// opened on watchOS, this whole file still passes and the app breaks on first launch instead.
    func testDefaultStoreLocationOpensAndPersists() throws {
        do {
            let store = try GameStore()
            // Starts from a known record rather than whatever a previous run left in the app
            // container, so this does not depend on test order or a clean simulator.
            try store.resetGame(digitamaId: "agu_digitama", now: t0)
        }

        do {
            let reopened = try GameStore()
            let loaded = try reopened.loadOrCreate(digitamaId: "unused_egg", now: t1)
            XCTAssertEqual(loaded.currentDigimonId, "agu_digitama")
            XCTAssertEqual(loaded.birthDate, t0)
        }
    }

    // MARK: - Energy totals

    func testEnergyTotalsAddressEachTypeIndependently() {
        var totals = EnergyTotals()
        for (index, type) in EnergyType.allCases.enumerated() {
            totals[type] = (index + 1) * 10
        }

        // Pins the subscript to the named properties, so a crossed wire cannot hide behind a
        // get and set that are wrong in the same direction.
        XCTAssertEqual(totals.strength, 10)
        XCTAssertEqual(totals.vitality, 20)
        XCTAssertEqual(totals.spirit, 30)
        XCTAssertEqual(totals.stamina, 40)
        XCTAssertEqual(EnergyType.allCases.map { totals[$0] }, [10, 20, 30, 40])
        XCTAssertEqual(totals.total, 100)
    }

    func testEnergyTotalsStartAtZero() {
        XCTAssertEqual(EnergyTotals.zero.total, 0)
        XCTAssertEqual(EnergyType.allCases.map { EnergyTotals.zero[$0] }, [0, 0, 0, 0])
    }

    // MARK: - Stage

    /// A stage's raw value is the folder its art lives in, so a typo here is a missing sprite
    /// at runtime rather than a compile error.
    func testEveryStageNamesARealSpriteFolder() throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL)
            .appendingPathComponent(SpriteLoader.spriteRoot)

        for stage in Stage.allCases {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appendingPathComponent(stage.rawValue).path,
                isDirectory: &isDirectory
            )
            XCTAssertTrue(exists && isDirectory.boolValue, "no sprite folder for stage \(stage)")
        }
    }

    func testLadderIndexOrdersTheStagesAndSkipsArmorHybrid() {
        XCTAssertEqual(Stage.digitama.ladderIndex, 0)
        XCTAssertEqual(Stage.child.ladderIndex, 3)
        XCTAssertEqual(Stage.ultimate.ladderIndex, 6)
        XCTAssertNil(Stage.armorHybrid.ladderIndex)
        XCTAssertEqual(Stage.allCases.compactMap(\.ladderIndex), Array(0...6))
    }
}
