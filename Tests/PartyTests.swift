import Foundation
import SwiftData
import XCTest

@testable import DigiVPet

/// A fixed-timezone calendar and hand-written instants, as in every other suite here: a test that
/// passed only in the machine's own zone would be no test at all.
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

    /// Mid-July, deliberately away from either DST transition — a freeze straddling one shifts a
    /// timeline by three days minus an hour, for reasons that have nothing to do with the box
    /// (US-125's learning).
    static let morning = date("2026-07-17 08:00")
    static let born = date("2026-07-10 08:00")
    static let bornLater = date("2026-07-12 08:00")
    static let bornLast = date("2026-07-14 08:00")

    /// A three-node graph of its own, so the pure row tests say what they mean without depending on
    /// whatever the shipped roster currently calls anything.
    static let graph = EvolutionGraph(nodes: [
        EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama"),
        EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon"),
        EvolutionNode(id: "champ", displayName: "Champ", stage: .ultimate, spriteFile: "Greymon"),
    ])

    static func state(_ id: String, stage: Stage = .child, isActive: Bool = false,
                      dead: Bool = false, born: Date = born) -> GameState {
        let state = GameState(currentDigimonId: id, stage: stage, isActive: isActive, now: born)
        if dead {
            state.healthStatus = .dead
            state.diedAt = born
        }
        return state
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

// MARK: - What the party screen says (pure)

/// US-126 AC1/AC2/AC4/AC5/AC6, at the level they are decided: the rows themselves. Everything this
/// screen DOES — which rows can be tapped, what a dead Digimon is allowed to offer, which one is
/// marked — is arithmetic over the saved records, so it is asserted here rather than photographed.
@MainActor
final class PartyRowTests: XCTestCase {
    /// AC1 + AC2: every record in the box gets a row, in the order the store handed them over, and
    /// each row carries the sprite, name and stage the graph gives its id.
    func testEveryDigimonInTheBoxIsListedWithItsNameStageAndSprite() {
        let rows = PartyRow.rows(for: [Fixture.state("hero", isActive: true),
                                       Fixture.state("egg", stage: .digitama, born: Fixture.bornLater)],
                                 in: Fixture.graph)

        XCTAssertEqual(rows.map(\.id), [0, 1])
        XCTAssertEqual(rows.map(\.displayName), ["Hero", "Egg"])
        XCTAssertEqual(rows.map(\.stageName), ["Child", "Digitama"])
        XCTAssertEqual(rows.map(\.spriteStage), ["Child", "Digitama"])
        XCTAssertEqual(rows.map(\.spriteFile), ["Agumon", "Agu_Digitama"])
    }

    /// AC1's other half: an UNHATCHED Digitama is listed exactly like any other Digimon, because it
    /// is one — an egg the player holds is a saved `GameState` at `.digitama`, which is what makes
    /// AC6's tap the same act as every other tap on this screen.
    func testAnUnhatchedDigitamaIsListedLikeAnyOtherDigimonAndCanBeTakenOut() {
        let rows = PartyRow.rows(for: [Fixture.state("egg", stage: .digitama)], in: Fixture.graph)

        XCTAssertEqual(rows.first?.stageName, "Digitama")
        XCTAssertEqual(rows.first?.status, .frozen)
        XCTAssertTrue(rows.first?.isSelectable ?? false)
    }

    /// An empty box is an empty list rather than a crash or a placeholder row. Unreachable in the
    /// app — `loadOrCreate` always leaves one Digimon — which is exactly why it is worth pinning.
    func testAnEmptyBoxListsNothing() {
        XCTAssertTrue(PartyRow.rows(for: [], in: Fixture.graph).isEmpty)
    }

    /// A record the graph has never heard of still gets a row, named by its own saved id and staged
    /// by its own saved stage. A Digimon the player owns must never become unreachable because the
    /// roster dropped an id — it would still be in the box, still held, and invisible.
    func testARecordTheGraphDoesNotKnowStillDrawsARow() {
        let rows = PartyRow.rows(for: [Fixture.state("forgotten", stage: .perfect)], in: Fixture.graph)

        XCTAssertEqual(rows.first?.displayName, "forgotten")
        XCTAssertEqual(rows.first?.stageName, "Perfect")
        XCTAssertEqual(rows.first?.spriteStage, "Perfect")
        XCTAssertEqual(rows.first?.spriteFile, "forgotten")
    }

    /// AC2: the three statuses come off the saved facts — `isActive` and `healthStatus` — and not
    /// off anything the screen decides for itself.
    func testEachRowSaysWhetherItIsOutFrozenOrGone() {
        let rows = PartyRow.rows(for: [Fixture.state("hero", isActive: true),
                                       Fixture.state("egg", stage: .digitama),
                                       Fixture.state("champ", stage: .ultimate, dead: true)],
                                 in: Fixture.graph)

        XCTAssertEqual(rows.map(\.status), [.active, .frozen, .dead])
    }

    /// Death is read BEFORE the active flag, which is the rule and not an accident of the order of
    /// two `if`s: a Digimon can be dead and still out — that is what the memorial screen is — and of
    /// the two facts, "gone" is the one that must not be drawn as the pet the player is raising.
    func testADeadDigimonThatIsStillOutReadsAsGoneRatherThanAsActive() {
        let rows = PartyRow.rows(for: [Fixture.state("champ", stage: .ultimate,
                                                     isActive: true, dead: true)],
                                 in: Fixture.graph)

        XCTAssertEqual(rows.first?.status, .dead)
        XCTAssertFalse(rows.first?.isSelectable ?? true)
    }

    /// AC4 + AC5, as the rows state them: only a FROZEN Digimon can be taken out. The active row is
    /// a no-op because it is already out, and a dead one is refused outright.
    func testOnlyAFrozenDigimonCanBeTakenOut() {
        let rows = PartyRow.rows(for: [Fixture.state("hero", isActive: true),
                                       Fixture.state("egg", stage: .digitama),
                                       Fixture.state("champ", stage: .ultimate, dead: true)],
                                 in: Fixture.graph)

        XCTAssertEqual(rows.map(\.isSelectable), [false, true, false])
    }

    /// The three statuses are spelled out AND marked distinctly. Neither channel alone is enough:
    /// three rows carrying the same glyph would be a legend the screen does not have, and three
    /// carrying the same word would be no answer at all.
    func testEveryStatusIsSpelledOutAndMarkedDistinctly() {
        for status in PartyStatus.allCases {
            XCTAssertFalse(status.label.isEmpty, "\(status) is spelled out")
            XCTAssertFalse(status.symbol.isEmpty, "\(status) is marked")
        }
        XCTAssertEqual(Set(PartyStatus.allCases.map(\.label)).count, PartyStatus.allCases.count)
        XCTAssertEqual(Set(PartyStatus.allCases.map(\.symbol)).count, PartyStatus.allCases.count)
    }

    /// VoiceOver gets the whole row as one sentence — name, stage and status — rather than three
    /// labels to swipe between.
    func testTheRowReadsAsOneSentence() {
        let rows = PartyRow.rows(for: [Fixture.state("hero", isActive: true)], in: Fixture.graph)
        let label = rows.first?.accessibilityLabel ?? ""

        XCTAssertTrue(label.contains("Hero"), label)
        XCTAssertTrue(label.contains("Child"), label)
        XCTAssertTrue(label.contains(PartyStatus.active.label), label)
    }

    /// The sprite is big enough to recognise a Digimon by — this screen exists to be chosen from —
    /// and a dead row is faded rather than hidden or drawn as though it were alive.
    func testTheRowIsDrawnAtASizeAndFadeThatMeanSomething() {
        XCTAssertGreaterThanOrEqual(PartyRowLayout.spriteScale, 2)
        XCTAssertLessThan(PartyRowLayout.deadOpacity, 1)
        XCTAssertGreaterThan(PartyRowLayout.deadOpacity, 0)
    }
}

// MARK: - Taking a Digimon out, through the model and the save

/// US-126 AC3/AC4/AC5/AC6, through the real store: what a tap actually does to the box.
///
/// The model is handed the SAME `GameStore` the test seeded with (US-125's learning): a second
/// container on the same file would give the test its own copy of every record, so a switch that
/// did nothing at all would leave the test looking exactly like success.
@MainActor
final class PartyActivationTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("Party.store") }
    private var store: GameStore!
    private var steps: EmptySampleFetcher!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PartyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        steps = EmptySampleFetcher()
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    /// A box holding the Digimon that is out, a frozen egg, and a dead one — in birth order, which
    /// is the order the party screen lists them in.
    ///
    /// The store is held on the test for the whole test rather than in a `let` here: a `GameStore`
    /// that goes out of scope resets its context, and every record fetched from it then traps.
    @discardableResult
    private func seedBox() throws -> GameStore {
        let store = try GameStore(url: storeURL)
        let out = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.born)
        out.currentDigimonId = "greymon"
        out.stage = .adult
        let context = store.container.mainContext
        context.insert(GameState(currentDigimonId: "gabu_digitama", isActive: false,
                                 now: Fixture.bornLater))
        let gone = GameState(currentDigimonId: "agumon", stage: .child, isActive: false,
                             now: Fixture.bornLast)
        gone.healthStatus = .dead
        gone.diedAt = Fixture.bornLast
        context.insert(gone)
        try store.save()
        self.store = store
        return store
    }

    private func makeModel() -> MainScreenModel {
        let store = store
        return MainScreenModel(
            makeStore: { try store ?? GameStore(url: self.storeURL) },
            graph: .bundled,
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(),
                                                 calendar: Fixture.losAngeles)
            ),
            calendar: Fixture.losAngeles,
            now: { Fixture.morning },
            chooseStartingDigitama: { $0.first }
        )
    }

    private func walk(_ count: Double) {
        steps.samples[.steps] = [
            HealthSample(start: Fixture.date("2026-07-17 06:00"),
                         end: Fixture.date("2026-07-17 06:30"),
                         value: count)
        ]
    }

    /// AC1 + AC2, through the model: the whole box is listed, oldest first, with the one that is out
    /// marked, the egg listed as an egg, and the dead one shown rather than hidden.
    func testThePartyListsTheWholeBoxWithEachDigimonsStatus() async throws {
        try seedBox()
        let model = makeModel()
        await model.start()

        let rows = model.partyRows
        XCTAssertEqual(rows.map(\.displayName), ["Greymon", "Gabu Digitama", "Agumon"])
        XCTAssertEqual(rows.map(\.stageName), ["Adult", "Digitama", "Child"])
        XCTAssertEqual(rows.map(\.status), [.active, .frozen, .dead])
    }

    /// THE AC (AC3): tapping a frozen Digimon puts it out and freezes the one that was out — in the
    /// one saved transaction `GameStore.activate` runs, so the box can never hold zero or two.
    ///
    /// Asserted through a REOPENED store as well as in memory, so what is checked came off disk.
    func testTakingAFrozenDigimonOutFreezesTheOneThatWasOut() async throws {
        let store = try seedBox()
        let model = makeModel()
        await model.start()
        XCTAssertEqual(model.state?.currentDigimonId, "greymon")

        let egg = try XCTUnwrap(model.partyRows.first { $0.displayName == "Gabu Digitama" })
        XCTAssertTrue(model.activate(egg))

        XCTAssertEqual(model.state?.currentDigimonId, "gabu_digitama")
        XCTAssertEqual(try store.activeState()?.currentDigimonId, "gabu_digitama")
        XCTAssertEqual(try store.allStates().filter(\.isActive).count, 1)
        // US-125's other half, moved by the same transaction: the Digimon put away is measuring a
        // spell in the box from this instant, and the one taken out is measuring nothing.
        let box = try store.allStates()
        XCTAssertEqual(box.first { $0.currentDigimonId == "greymon" }?.frozenSince, Fixture.morning)
        XCTAssertNil(box.first { $0.currentDigimonId == "gabu_digitama" }?.frozenSince)

        let reopened = try GameStore(url: storeURL)
        XCTAssertEqual(try reopened.activeState()?.currentDigimonId, "gabu_digitama")
        XCTAssertEqual(try reopened.allStates().filter(\.isActive).count, 1)
    }

    /// The party screen redraws off the same records, so the row that is now marked is the one that
    /// was just taken out — the screen cannot end up marking a Digimon that is no longer out.
    ///
    /// It also pins what the switch does to the ORDER, which is US-125 showing through rather than a
    /// defect: the box is sorted by birth date and a thaw shifts the whole timeline forward by the
    /// span spent frozen, so the egg — frozen since it was laid — comes out with today's birth date
    /// and lands last. Exactly one row is marked either way, which is what the screen is about.
    func testTheListMarksTheNewlyActiveDigimonAfterTheSwitch() async throws {
        try seedBox()
        let model = makeModel()
        await model.start()

        model.activate(try XCTUnwrap(model.partyRows.first { $0.status == .frozen }))

        let rows = model.partyRows
        XCTAssertEqual(rows.filter { $0.status == .active }.map(\.displayName), ["Gabu Digitama"])
        XCTAssertEqual(rows.map(\.displayName), ["Greymon", "Agumon", "Gabu Digitama"])
        XCTAssertEqual(rows.map(\.status), [.frozen, .dead, .active])
    }

    /// AC4: tapping the Digimon that is already out changes nothing at all. Refused at the model
    /// rather than only dimmed in the view, so it is a fact rather than a shape.
    func testTappingTheDigimonThatIsAlreadyOutIsANoOp() async throws {
        let store = try seedBox()
        let model = makeModel()
        await model.start()

        let active = try XCTUnwrap(model.partyRows.first { $0.status == .active })
        XCTAssertFalse(model.activate(active))

        XCTAssertEqual(model.state?.currentDigimonId, "greymon")
        XCTAssertEqual(try store.activeState()?.currentDigimonId, "greymon")
        XCTAssertEqual(try store.allStates().filter(\.isActive).count, 1)
        // And it did not start a freeze spell on the Digimon it left standing.
        XCTAssertNil(try store.activeState()?.frozenSince)
    }

    /// AC5: a dead Digimon is listed and cannot be taken out. The refusal has to be here and not
    /// only in the view, because activating a corpse would leave the player with nothing to raise
    /// and no way back to the Digimon they had.
    func testADeadDigimonCannotBeTakenOut() async throws {
        let store = try seedBox()
        let model = makeModel()
        await model.start()

        let gone = try XCTUnwrap(model.partyRows.first { $0.status == .dead })
        XCTAssertFalse(model.activate(gone))

        XCTAssertEqual(model.state?.currentDigimonId, "greymon")
        XCTAssertEqual(try store.activeState()?.currentDigimonId, "greymon")
        XCTAssertEqual(try store.allStates().filter(\.isActive).count, 1)
    }

    /// AC6, through the REAL hatch rather than by inspection: activating an unhatched Digitama is
    /// what starts it hatching. The egg is taken out with nothing walked, then 5,000 steps are
    /// walked and the ordinary refresh runs — and it is the EGG that receives them and hatches,
    /// because it is now the Digimon that is out.
    func testTakingAnUnhatchedDigitamaOutIsWhatStartsItHatching() async throws {
        let store = try seedBox()
        let model = makeModel()
        await model.start()

        model.activate(try XCTUnwrap(model.partyRows.first { $0.stageName == "Digitama" }))
        walk(5_000) // 5,000 steps at 1 Strength / 100 = 50, which is the hatch threshold
        await model.refresh()

        XCTAssertEqual(model.state?.currentDigimonId, "punimon")
        XCTAssertEqual(model.state?.stage, .babyI)
        // The Digimon that was put away is untouched by the energy its successor was fed — the
        // freeze guards of US-125 are what promise that, and this is the first caller to lean on it.
        let greymon = try XCTUnwrap(try store.allStates().first { $0.currentDigimonId == "greymon" })
        XCTAssertFalse(greymon.isActive)
        XCTAssertEqual(greymon.stageEnergy.total, 0)
    }

    /// A row that no longer describes the record at its position is refused rather than activating
    /// whatever has moved into that slot.
    ///
    /// This is a REAL hazard and not a contrived one: taking a Digimon out reorders the box (see
    /// above), so a list held across one switch has rows pointing at their old positions. Both
    /// shapes are asserted — a position past the end, and a position that exists but now holds a
    /// different Digimon.
    func testARowThatNoLongerDescribesItsPositionIsRefused() async throws {
        let store = try seedBox()
        let model = makeModel()
        await model.start()

        let offTheEnd = PartyRow(id: 99, displayName: "Ghost", stageName: "Child",
                                 spriteStage: "Child", spriteFile: "Agumon", status: .frozen)
        XCTAssertFalse(model.activate(offTheEnd))

        // Position 1 really is a frozen Gabu Digitama in this box — this row claims it is a frozen
        // Agumon, which is the shape a list held across a reorder has.
        let wrongOccupant = PartyRow(id: 1, displayName: "Agumon", stageName: "Child",
                                     spriteStage: "Child", spriteFile: "Agumon", status: .frozen)
        XCTAssertFalse(model.activate(wrongOccupant))

        XCTAssertEqual(try store.activeState()?.currentDigimonId, "greymon")
        XCTAssertEqual(try store.allStates().filter(\.isActive).count, 1)
    }
}
