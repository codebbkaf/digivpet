import Foundation
import XCTest

@testable import DigiVPet

/// US-121 — the map detail: what lives in a map, and what its eggs are waiting for.
///
/// What arithmetic can reach: which Digitama may be named, which is ready to find, what a "?" slot
/// is allowed to say, how the pool is grouped, and that a locked map has no detail at all. The rest
/// of the story — that a mix of "?" and revealed slots reads on a 46mm watch — is a Simulator
/// screenshot, recorded in progress.txt. Same split as `MapListTests`.
private enum Fixture {
    /// Roster ids used below. Real ones, so `roster` can be the shipped file where a test wants the
    /// real thing and a fixture where it wants a fixed answer.
    static let agu = "agu_digitama"
    static let pata = "pata_digitama"
    static let pal = "pal_digitama"

    /// A small roster with one of each thing the detail resolves: two Digitama, and opponents on
    /// three different stages so the grouping has something to group.
    static let roster = Roster(entries: [
        RosterEntry(id: agu, displayName: "Agu Digitama", stage: .digitama, spriteFile: "Agu"),
        RosterEntry(id: pata, displayName: "Pata Digitama", stage: .digitama, spriteFile: "Pata"),
        RosterEntry(id: pal, displayName: "Pal Digitama", stage: .digitama, spriteFile: "Pal"),
        RosterEntry(id: "koromon", displayName: "Koromon", stage: .babyII, spriteFile: "Koromon"),
        RosterEntry(id: "tanemon", displayName: "Tanemon", stage: .babyII, spriteFile: "Tanemon"),
        RosterEntry(id: "agumon", displayName: "Agumon", stage: .child, spriteFile: "Agumon"),
        RosterEntry(id: "botamon", displayName: "Botamon", stage: .babyI, spriteFile: "Botamon"),
    ])

    /// Walk 2,000 steps in a day. `.day`, so it is answered by `bestDayThisStage` — see
    /// `ConditionContext`.
    static let steps = EvolutionCondition(
        metric: .healthSteps, window: .day, comparison: .atLeast, value: 2_000,
        hint: "Walk with it most days")

    /// Train once this stage.
    static let training = EvolutionCondition(
        metric: .careTrainingSessions, window: .stage, comparison: .atLeast, value: 1,
        hint: "It wants to be put through its paces")

    /// Two maps in a chain, deliberately NOT the shipped catalog — see `MapListTests.Fixture`.
    /// The first holds three slots so one can be revealed, one ready and one neither; the second is
    /// locked until the first is finished, which is what AC6 is asked of.
    static let catalog = MapCatalog(maps: [
        AdventureMap(id: "first", displayName: "First", assetName: "01_grassland",
                     tier: 1, totalSteps: 1_000,
                     // Out of stage order on purpose: the grouping must impose the ladder, not
                     // inherit it from however the pool happens to be typed.
                     opponentPool: ["agumon", "koromon", "botamon", "tanemon"],
                     digitamaSlots: [DigitamaSlot(digitamaId: agu, conditions: [training]),
                                     DigitamaSlot(digitamaId: pata, conditions: [steps]),
                                     DigitamaSlot(digitamaId: pal, conditions: [steps, training])]),
        AdventureMap(id: "second", displayName: "Second", assetName: "02_river",
                     tier: 2, totalSteps: 25_000, unlockedBy: "first",
                     opponentPool: ["agumon"],
                     digitamaSlots: [DigitamaSlot(digitamaId: pata, conditions: [steps])]),
    ])

    static let noon = Date(timeIntervalSince1970: 1_770_000_000)

    /// A context that has walked `steps` steps on its best day this stage, and trained `sessions`
    /// times.
    static func context(steps: Double = 0, sessions: Int = 0) -> ConditionContext {
        ConditionContext(
            bestDayThisStage: MetricTotals(values: [ConditionMetric.healthSteps.rawValue: steps]),
            trainingSessionsThisStage: sessions)
    }

    static func row(_ id: String, _ progress: MapProgress?) -> MapListRow {
        MapListRow.rows(in: catalog, progress: progress).first { $0.id == id }!
    }

    /// The detail of the first map, which is unlocked on any save.
    static func detail(
        discovered: Set<String> = [],
        context: ConditionContext = .unknown,
        progress: MapProgress? = MapProgress()
    ) -> MapDetail {
        MapDetail.make(for: row("first", progress), in: catalog, roster: roster,
                       discovered: discovered, context: context)!
    }

    static func slot(_ id: String, in detail: MapDetail) -> MapDetail.DigitamaSlotDetail {
        detail.digitama.first { $0.digitamaId == id }!
    }
}

// MARK: - AC1: what the screen lists

final class MapDetailContentsTests: XCTestCase {
    /// AC1: the opponent pool, grouped by stage — and in LADDER order, whatever order the pool was
    /// authored in. `Stage.allCases` is the ladder, with the side branch last.
    func testTheOpponentPoolIsGroupedByStageInLadderOrder() {
        let detail = Fixture.detail()

        XCTAssertEqual(detail.opponentGroups.map(\.stage), [.babyI, .babyII, .child])
        XCTAssertEqual(detail.opponentGroups.map { $0.opponents.map(\.id) },
                       [["botamon"], ["koromon", "tanemon"], ["agumon"]])
    }

    /// Within a group the authored order stands: that is the order US-116 wrote and the order
    /// US-122 will band, and re-sorting it here would make two screens disagree about the pool.
    func testWithinAStageTheAuthoredOrderStands() {
        let detail = Fixture.detail()

        XCTAssertEqual(Fixture.catalog.maps[0].opponentPool.filter { ["koromon", "tanemon"].contains($0) },
                       ["koromon", "tanemon"])
        XCTAssertEqual(detail.opponentGroups.first { $0.stage == .babyII }?.opponents.map(\.id),
                       ["koromon", "tanemon"])
    }

    /// Every opponent in the pool reaches the screen exactly once, carrying the name and the art
    /// the roster gives it — the sprite an `IdleSpriteView` resolves.
    func testEveryOpponentIsDrawnOnceWithItsRosterNameAndArt() {
        let detail = Fixture.detail()

        XCTAssertEqual(detail.opponents.count, 4)
        XCTAssertEqual(Set(detail.opponents.map(\.id)),
                       Set(Fixture.catalog.maps[0].opponentPool))
        let agumon = detail.opponents.first { $0.id == "agumon" }
        XCTAssertEqual(agumon?.displayName, "Agumon")
        XCTAssertEqual(agumon?.spriteFile, "Agumon")
        XCTAssertEqual(agumon?.stage, .child)
    }

    /// An id the roster does not know is dropped rather than drawn as a nameless blank. The US-117
    /// validator already rejects one, so this is about a fixture and a future data edit, not about
    /// shipped data.
    func testAnUnknownOpponentIsDroppedRatherThanDrawnBlank() {
        let catalog = MapCatalog(maps: [
            AdventureMap(id: "only", displayName: "Only", assetName: "01_grassland",
                         tier: 1, totalSteps: 100, opponentPool: ["agumon", "nosuchmon"]),
        ])
        let detail = MapDetail.make(for: MapListRow.rows(in: catalog, progress: MapProgress())[0],
                                    in: catalog, roster: Fixture.roster,
                                    discovered: [], context: .unknown)

        XCTAssertEqual(detail?.opponents.map(\.id), ["agumon"])
    }

    /// Two mentions of one id collapse to one row. `ForEach` keys on `id`, so a duplicate is not a
    /// second row — it is one row and a lost one.
    func testADuplicatedOpponentIsDrawnOnce() {
        let catalog = MapCatalog(maps: [
            AdventureMap(id: "only", displayName: "Only", assetName: "01_grassland",
                         tier: 1, totalSteps: 100, opponentPool: ["agumon", "agumon"]),
        ])
        let detail = MapDetail.make(for: MapListRow.rows(in: catalog, progress: MapProgress())[0],
                                    in: catalog, roster: Fixture.roster,
                                    discovered: [], context: .unknown)

        XCTAssertEqual(detail?.opponents.map(\.id), ["agumon"])
    }

    /// AC1: every Digitama slot is listed, in the order the catalog authors them.
    func testEverySlotIsListedInAuthoredOrder() {
        let detail = Fixture.detail()

        XCTAssertEqual(detail.digitama.map(\.digitamaId), [Fixture.agu, Fixture.pata, Fixture.pal])
    }

    /// The header says where the player is up to, in the same spelling the list uses — the two
    /// screens name one figure and must not disagree about how it reads.
    func testProgressIsSpelledExactlyAsTheListSpellsIt() {
        let progress = MapProgress(recorded: ["first": 450.9])
        let detail = Fixture.detail(progress: progress)

        XCTAssertEqual(detail.progressText, "450 / 1000")
        XCTAssertEqual(detail.progressText, Fixture.row("first", progress).progressText)
    }
}

// MARK: - AC2/AC3/AC4: what a slot is allowed to say

final class MapDetailRevealTests: XCTestCase {
    /// AC2: a Digitama the player has never owned is withheld entirely — no name, no art. The view
    /// draws `MapDetailMarks.unknownName` in its place, which is a "?" and not a silhouette.
    func testANeverOwnedDigitamaIsWithheld() {
        let slot = Fixture.slot(Fixture.pata, in: Fixture.detail(discovered: []))

        XCTAssertNil(slot.revealed)
        XCTAssertFalse(slot.isRevealed)
        XCTAssertEqual(MapDetailMarks.unknownName, "?")
    }

    /// AC4: one the player owns or has owned draws its real sprite and name.
    func testAnOwnedDigitamaDrawsItsRealSpriteAndName() {
        let slot = Fixture.slot(Fixture.agu, in: Fixture.detail(discovered: [Fixture.agu]))

        XCTAssertEqual(slot.revealed?.displayName, "Agu Digitama")
        XCTAssertEqual(slot.revealed?.spriteFile, "Agu")
        XCTAssertEqual(slot.revealed?.stage, .digitama)
    }

    /// AC4: "with no hint rows" — a revealed slot carries no criteria at all, so there is nothing
    /// for the view to draw even if it tried.
    func testARevealedSlotCarriesNoHintRows() {
        let detail = Fixture.detail(discovered: [Fixture.agu])

        XCTAssertTrue(Fixture.slot(Fixture.agu, in: detail).conditions.isEmpty)
        // And the withheld slot beside it still has its own, so the emptiness is the reveal and not
        // a slot that lost its conditions on the way in.
        XCTAssertEqual(Fixture.slot(Fixture.pata, in: detail).conditions, [Fixture.steps])
    }

    /// Discovering one Digitama reveals that one and nothing else on the screen.
    func testRevealingOneSlotLeavesTheOthersWithheld() {
        let detail = Fixture.detail(discovered: [Fixture.agu])

        XCTAssertTrue(Fixture.slot(Fixture.agu, in: detail).isRevealed)
        XCTAssertFalse(Fixture.slot(Fixture.pata, in: detail).isRevealed)
        XCTAssertFalse(Fixture.slot(Fixture.pal, in: detail).isRevealed)
    }

    /// A slot whose id the roster does not know stays a "?" however discovered it is: there is no
    /// name and no art to draw. Its conditions are still listed, so a data fault shows up as an egg
    /// nobody can name rather than as a slot that quietly vanished.
    func testASlotWithNoRosterEntryStaysAQuestionMarkButKeepsItsHints() {
        let catalog = MapCatalog(maps: [
            AdventureMap(id: "only", displayName: "Only", assetName: "01_grassland",
                         tier: 1, totalSteps: 100,
                         digitamaSlots: [DigitamaSlot(digitamaId: "nosuchmon",
                                                      conditions: [Fixture.steps])]),
        ])
        let detail = MapDetail.make(for: MapListRow.rows(in: catalog, progress: MapProgress())[0],
                                    in: catalog, roster: Fixture.roster,
                                    discovered: ["nosuchmon"], context: .unknown)

        XCTAssertEqual(detail?.digitama.count, 1)
        XCTAssertNil(detail?.digitama.first?.revealed)
        XCTAssertEqual(detail?.digitama.first?.conditions, [Fixture.steps])
    }

    /// AC3: a "?" slot's lines are `ConditionReveal.line(for:in:)` — literally, not merely
    /// similarly. The view draws them through `ConditionHintRow`, which is the Dex's own row type,
    /// so the wording is identical because it is the same code.
    func testAHintLineIsExactlyWhatConditionRevealSays() {
        let context = Fixture.context(steps: 1_200)
        let slot = Fixture.slot(Fixture.pata, in: Fixture.detail(context: context))

        XCTAssertEqual(slot.conditions.map { ConditionReveal.line(for: $0, in: context) },
                       [ConditionReveal.line(for: Fixture.steps, in: context)])
    }

    /// AC3: the reveal is PROGRESSIVE — a far-off criterion reads vague and a nearly-met one reads
    /// specific, off the same context the detail carries. All three levels, one slot.
    func testTheSameSlotReadsDifferentlyAsThePlayerGetsCloser() {
        let far = Fixture.detail(context: Fixture.context(steps: 100))
        let close = Fixture.detail(context: Fixture.context(steps: 1_500))
        let met = Fixture.detail(context: Fixture.context(steps: 2_000))

        func line(_ detail: MapDetail) -> String {
            let slot = Fixture.slot(Fixture.pata, in: detail)
            return ConditionReveal.line(for: slot.conditions[0], in: detail.context)
        }

        XCTAssertEqual(ConditionReveal.level(of: Fixture.steps, in: far.context), .far)
        XCTAssertEqual(ConditionReveal.level(of: Fixture.steps, in: close.context), .close)
        XCTAssertEqual(ConditionReveal.level(of: Fixture.steps, in: met.context), .met)
        // Vague at 5%, warmed at 75%: the qualifier is the whole difference, and it is the Dex's.
        XCTAssertEqual(line(far), Fixture.steps.hint)
        XCTAssertTrue(line(close).hasSuffix(RevealLevel.close.qualifier!))
        XCTAssertEqual(line(met), Fixture.steps.hint)
    }

    /// The context on the detail is the one the caller handed in — the screen has ONE input, so a
    /// hint on it cannot be read against a different player's counters than the ready mark beside
    /// it.
    func testTheDetailCarriesTheContextItWasBuiltWith() {
        let context = Fixture.context(steps: 900, sessions: 2)

        XCTAssertEqual(Fixture.detail(context: context).context, context)
    }
}

// MARK: - AC5: ready

final class MapDetailReadyTests: XCTestCase {
    /// AC5: every condition met and the egg not in hand — the next drop check can hand it over.
    func testASlotWithEveryConditionMetIsReady() {
        let detail = Fixture.detail(context: Fixture.context(steps: 2_000))

        XCTAssertTrue(Fixture.slot(Fixture.pata, in: detail).isReady)
    }

    /// One met out of two is not ready. ALL of them, like an edge's.
    func testASlotWithOnlySomeConditionsMetIsNotReady() {
        let detail = Fixture.detail(context: Fixture.context(steps: 2_000, sessions: 0))

        XCTAssertEqual(Fixture.slot(Fixture.pal, in: detail).conditions.count, 2)
        XCTAssertFalse(Fixture.slot(Fixture.pal, in: detail).isReady)
        // Both met, and it turns ready — so the false above is the second condition and not the
        // slot being ready-proof.
        let both = Fixture.detail(context: Fixture.context(steps: 2_000, sessions: 1))
        XCTAssertTrue(Fixture.slot(Fixture.pal, in: both).isReady)
    }

    /// Nothing earned, nothing ready.
    func testWithNothingEarnedNoSlotIsReady() {
        let detail = Fixture.detail(context: .unknown)

        XCTAssertTrue(detail.digitama.allSatisfy { !$0.isReady })
    }

    /// AC5 says "has not dropped yet". An egg already owned is one that HAS dropped, so it is not
    /// ready however met its conditions are — the mark is a promise about something still to come.
    func testAnAlreadyOwnedSlotIsNeverReady() {
        let detail = Fixture.detail(discovered: [Fixture.agu],
                                    context: Fixture.context(steps: 2_000, sessions: 1))

        XCTAssertTrue(Fixture.slot(Fixture.agu, in: detail).isRevealed)
        XCTAssertFalse(Fixture.slot(Fixture.agu, in: detail).isReady)
        // The unowned slot beside it, on the same context, IS ready — so the false above is the
        // ownership and not the context.
        XCTAssertTrue(Fixture.slot(Fixture.pata, in: detail).isReady)
    }

    /// The ready mark is a named symbol, and it is not one of the list's two marks: a map row can
    /// carry finished and selected, and this screen sits one tap from that row.
    func testTheReadyMarkIsItsOwnSymbol() {
        XCTAssertFalse(MapDetailMarks.readySymbol.isEmpty)
        XCTAssertFalse(MapDetailMarks.readyLabel.isEmpty)
        XCTAssertNotEqual(MapDetailMarks.readySymbol, MapListMarks.finishedSymbol)
        XCTAssertNotEqual(MapDetailMarks.readySymbol, MapListMarks.selectedSymbol)
        XCTAssertNotEqual(MapDetailMarks.readySymbol, MapListMarks.lockedSymbol)
    }
}

// MARK: - AC6: a locked map has no detail

final class MapDetailLockTests: XCTestCase {
    /// AC6: nil, not a stripped detail. There is nothing for the view to push.
    func testALockedMapHasNoDetail() {
        let locked = Fixture.row("second", MapProgress())

        XCTAssertTrue(locked.isLocked)
        XCTAssertNil(MapDetail.make(for: locked, in: Fixture.catalog, roster: Fixture.roster,
                                    discovered: [], context: .unknown))
    }

    /// And it appears the moment the lock opens, on the same save — so the nil above is the lock
    /// and not the fixture's second map being undetailable.
    func testTheDetailAppearsTheMomentTheLockOpens() {
        let progress = MapProgress(finishedAt: ["first": Fixture.noon])
        let opened = Fixture.row("second", progress)

        XCTAssertFalse(opened.isLocked)
        XCTAssertNotNil(MapDetail.make(for: opened, in: Fixture.catalog, roster: Fixture.roster,
                                       discovered: [], context: .unknown))
    }

    /// A row naming a map the catalog does not hold has no detail either — a screen with a title
    /// and nothing under it is worse than no screen.
    func testARowNamingNoMapHasNoDetail() {
        let stranger = MapListRow(id: "nowhere", displayName: "Nowhere", assetName: "01_grassland",
                                  recordedSteps: 0, totalSteps: 100, isSelected: false,
                                  isFinished: false, isLocked: false, unlockLine: nil,
                                  contents: nil)

        XCTAssertNil(MapDetail.make(for: stranger, in: Fixture.catalog, roster: Fixture.roster,
                                    discovered: [], context: .unknown))
    }

    /// The travel button says which of its two things it is, and the "here" case is a statement
    /// rather than a vanished control.
    func testTheDetailKnowsWhetherThePlayerIsAlreadyHere() {
        XCTAssertTrue(Fixture.detail(progress: MapProgress(selectedMapId: "first")).isSelected)
        XCTAssertFalse(Fixture.detail(progress: MapProgress()).isSelected)
        XCTAssertNotEqual(MapDetailMarks.travelLabel, MapDetailMarks.hereLabel)
    }
}

// MARK: - The shipped data

final class MapDetailShippedDataTests: XCTestCase {
    /// Every unlocked map in the shipped catalog builds a detail, and every one of the 170 opponent
    /// ids and 57 Digitama ids in it resolves against the real roster — the same claim the US-117
    /// validator makes, made again through the screen that has to draw them.
    func testEveryShippedMapDrawsItsWholePoolAndEverySlot() {
        // Every map finished, so none of them is locked and all sixteen are reachable.
        let progress = MapProgress(finishedAt: Dictionary(
            uniqueKeysWithValues: MapCatalog.bundled.maps.map { ($0.id, Fixture.noon) }))

        for row in MapListRow.rows(in: .bundled, progress: progress) {
            let map = MapCatalog.bundled.map(id: row.id)!
            let detail = MapDetail.make(for: row, discovered: [], context: .unknown)
            XCTAssertNotNil(detail, "\(row.id) has no detail")
            XCTAssertEqual(detail?.opponents.count, map.opponentPool.count,
                           "\(row.id) lost an opponent on the way to the screen")
            XCTAssertEqual(detail?.digitama.count, map.digitamaSlots.count,
                           "\(row.id) lost a Digitama slot")
            XCTAssertTrue(detail?.digitama.allSatisfy { !$0.conditions.isEmpty } ?? false,
                          "\(row.id) has a slot with no criteria to show")
        }
    }

    /// Every shipped slot names a Digitama that really is at `Stage.digitama`, so a revealed one
    /// draws art out of the Digitama folder and not out of nowhere.
    func testEveryShippedSlotResolvesToADigitama() {
        let progress = MapProgress(finishedAt: Dictionary(
            uniqueKeysWithValues: MapCatalog.bundled.maps.map { ($0.id, Fixture.noon) }))
        let ids = MapCatalog.bundled.maps.flatMap { $0.digitamaSlots.map(\.digitamaId) }
        let rows = MapListRow.rows(in: .bundled, progress: progress)

        for row in rows {
            let detail = MapDetail.make(for: row, discovered: Set(ids), context: .unknown)!
            for slot in detail.digitama {
                XCTAssertEqual(slot.revealed?.stage, .digitama,
                               "\(slot.digitamaId) in \(row.id) is not a Digitama")
            }
        }
    }

    /// On a fresh save the starting map's slots are all still "?" — the shipped detail opens
    /// withheld, which is what makes the reveal worth anything.
    func testTheStartingMapOpensEntirelyWithheld() throws {
        let row = MapListRow.rows(in: .bundled, progress: MapProgress()).first { !$0.isLocked }
        let detail = try XCTUnwrap(MapDetail.make(for: try XCTUnwrap(row),
                                                  discovered: [], context: .unknown))

        XCTAssertFalse(detail.digitama.isEmpty)
        XCTAssertTrue(detail.digitama.allSatisfy { !$0.isRevealed })
    }
}

// MARK: - The model seam the view pushes this screen from

@MainActor
final class MapDetailModelTests: XCTestCase {
    /// `MainScreenModel.mapDetail(for:)` is what `MapListView` is handed, and it is built off the
    /// injected catalog rather than the shipped one — the same seam `mapRows` uses.
    func testTheModelBuildsTheDetailForTheCatalogItWasGiven() {
        let model = MainScreenModel(roster: Fixture.roster, maps: Fixture.catalog)
        let row = model.mapRows.first { $0.id == "first" }!

        let detail = model.mapDetail(for: row)

        XCTAssertEqual(detail?.id, "first")
        XCTAssertEqual(detail?.digitama.map(\.digitamaId), [Fixture.agu, Fixture.pata, Fixture.pal])
        XCTAssertEqual(detail?.opponents.count, 4)
    }

    /// AC6 at the seam: a locked row hands back nothing, so there is nothing for the list to push.
    func testTheModelRefusesALockedMap() {
        let model = MainScreenModel(roster: Fixture.roster, maps: Fixture.catalog)
        let locked = model.mapRows.first { $0.id == "second" }!

        XCTAssertTrue(locked.isLocked)
        XCTAssertNil(model.mapDetail(for: locked))
    }

    /// Before `start()` nothing has been discovered, so every slot is withheld — a screen opened
    /// while the store is still coming up shows "?" rather than a name it has not earned.
    func testWithNoSaveEverySlotIsWithheld() {
        let model = MainScreenModel(roster: Fixture.roster, maps: Fixture.catalog)
        let row = model.mapRows.first { $0.id == "first" }!

        XCTAssertTrue(model.discoveredDigimonIds.isEmpty)
        XCTAssertTrue(model.mapDetail(for: row)?.digitama.allSatisfy { !$0.isRevealed } ?? false)
    }
}
