import XCTest

@testable import DigiVPet

/// US-191 — training raises HP / Attack / Agility toward a per-stage cap.
///
/// The bonuses are stored per-Digimon on `GameState` (`trainedHPBonus`/`trainedAttackBonus`/
/// `trainedAgilityBonus`), each raised by `trainStat(_:cap:)` toward a `cap` that comes from the
/// stage's `StageStats.trainingCap`. The battle-facing value is `effectiveStat(_:base:)` = base +
/// bonus, which is what US-188's HP bar and US-189's dodge model fight on.
///
/// Pure and clock-free: a hand-built `GameState` and the bundled `ConsumptionConfig` are all these
/// need, so nothing waits real time or stands up a store.
final class TrainedStatsTests: XCTestCase {
    private func freshState() -> GameState {
        GameState(currentDigimonId: "hero", stage: .child, now: Date(timeIntervalSince1970: 0))
    }

    // MARK: - AC1: bonuses start at zero and are stored per-Digimon

    func testAFreshDigimonHasNoTrainedBonuses() {
        let state = freshState()
        XCTAssertEqual(state.trainedHPBonus, 0)
        XCTAssertEqual(state.trainedAttackBonus, 0)
        XCTAssertEqual(state.trainedAgilityBonus, 0)
        for stat in BattleStat.allCases {
            XCTAssertEqual(state.trainedBonus(for: stat), 0)
        }
    }

    /// Two Digimon train independently — the bonus lives on each record, so one is never wearing the
    /// other's muscle.
    func testTwoDigimonTrainIndependently() {
        let mover = freshState()
        let idler = freshState()

        mover.trainStat(.attack, cap: 4)
        mover.trainStat(.attack, cap: 4)

        XCTAssertEqual(mover.trainedAttackBonus, 2)
        XCTAssertEqual(idler.trainedAttackBonus, 0, "the one that never trained gained nothing")
    }

    // MARK: - AC3 / AC4: repeated training never passes base + cap

    /// THE AC headline: however many times a stat is trained, the bonus never crosses the cap and so
    /// the effective stat never crosses `base + cap`.
    func testRepeatedTrainingNeverPassesTheCap() {
        let config = ConsumptionConfig.bundled
        let stats = try! XCTUnwrap(config.stats(for: .child))
        let cap = stats.trainingCap
        let state = freshState()

        for _ in 0..<(cap + 20) {
            state.trainStat(.hp, cap: cap)
        }

        XCTAssertEqual(state.trainedHPBonus, cap, "the bonus is pinned at the cap, not one past it")
        XCTAssertEqual(state.effectiveStat(.hp, base: stats.baseHP), stats.baseHP + cap,
                       "effective HP is base + cap and no more")
    }

    /// A stat sitting at its cap cannot be raised further: `trainStat` reports a gain of 0 and leaves
    /// the bonus alone.
    func testTrainingAtTheCapGainsNothing() {
        let state = freshState()
        for _ in 0..<4 { state.trainStat(.agility, cap: 4) }
        XCTAssertEqual(state.trainedAgilityBonus, 4)

        let gain = state.trainStat(.agility, cap: 4)
        XCTAssertEqual(gain, 0, "at the cap there is nothing left to gain")
        XCTAssertEqual(state.trainedAgilityBonus, 4, "and the bonus is unchanged")
    }

    /// Each call below the cap returns exactly the one point it added.
    func testTrainingBelowTheCapGainsOnePerCall() {
        let state = freshState()
        XCTAssertEqual(state.trainStat(.hp, cap: 4), 1)
        XCTAssertEqual(state.trainStat(.hp, cap: 4), 1)
        XCTAssertEqual(state.trainedHPBonus, 2)
    }

    // MARK: - AC2: a higher stage has a larger cap

    /// A Perfect's training cap exceeds a Child's for the same stat, so evolving is what opens the
    /// room to grow — read straight off the shipped per-stage table.
    func testAPerfectsCapExceedsAChilds() {
        let config = ConsumptionConfig.bundled
        let child = try! XCTUnwrap(config.stats(for: .child))
        let perfect = try! XCTUnwrap(config.stats(for: .perfect))

        XCTAssertGreaterThan(perfect.trainingCap, child.trainingCap,
                             "a higher-stage Digimon can train further")

        // And that larger cap really lets a Perfect out-train a Child on the same stat.
        let childMon = GameState(currentDigimonId: "c", stage: .child,
                                 now: Date(timeIntervalSince1970: 0))
        let perfectMon = GameState(currentDigimonId: "p", stage: .perfect,
                                   now: Date(timeIntervalSince1970: 0))
        for _ in 0..<100 {
            childMon.trainStat(.attack, cap: child.trainingCap)
            perfectMon.trainStat(.attack, cap: perfect.trainingCap)
        }
        XCTAssertGreaterThan(perfectMon.trainedAttackBonus, childMon.trainedAttackBonus)
    }

    // MARK: - AC3: effective stat = base + bonus

    func testEffectiveStatIsBasePlusBonus() {
        let config = ConsumptionConfig.bundled
        let stats = try! XCTUnwrap(config.stats(for: .child))
        let state = freshState()

        state.trainStat(.hp, cap: stats.trainingCap)
        state.trainStat(.hp, cap: stats.trainingCap)
        state.trainStat(.agility, cap: stats.trainingCap)

        XCTAssertEqual(state.effectiveStat(.hp, base: stats.baseHP), stats.baseHP + 2)
        XCTAssertEqual(state.effectiveStat(.agility, base: stats.baseAgility), stats.baseAgility + 1)
        XCTAssertEqual(state.effectiveStat(.attack, base: stats.baseAttack), stats.baseAttack,
                       "an untrained stat is just its base")
    }

    /// Training only ever adds: a negative `amount` gains nothing, and once a bonus is earned a
    /// negative (floored-to-zero) cap can neither raise it nor trim it away.
    func testTrainingNeverReducesAStat() {
        let state = freshState()
        XCTAssertEqual(state.trainStat(.hp, cap: 4, by: -5), 0, "a negative amount adds nothing")
        XCTAssertEqual(state.trainedHPBonus, 0)

        state.trainStat(.hp, cap: 4)
        XCTAssertEqual(state.trainStat(.hp, cap: -1), 0, "a negative cap floors at 0, so no gain")
        XCTAssertEqual(state.trainedHPBonus, 1, "and the earned point is left intact")
    }
}
