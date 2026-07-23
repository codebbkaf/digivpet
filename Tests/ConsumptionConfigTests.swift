import Foundation
import XCTest

@testable import DigiVPet

/// US-170 — the shipped metric-to-game conversion config and its validator.
///
/// The point of the file being data is that the economy can be retuned without a build, so these
/// tests pin the things a retune must NOT break: it still decodes, the named constants are present
/// and sane, and the validator has ZERO to say about the shipped file while still firing on a bad
/// one.
final class ConsumptionConfigTests: XCTestCase {

    // MARK: - The shipped file

    /// THE AC: `ConsumptionConfig.bundled` decodes.
    func testBundledConfigDecodes() throws {
        let config = try ConsumptionConfig.load()
        XCTAssertEqual(config, ConsumptionConfig.bundled)
    }

    /// THE AC: the named constants are present with the PRD's values.
    func testNamedConstantsMatchThePRD() throws {
        let config = try ConsumptionConfig.load()
        XCTAssertEqual(config.kcalPerTrain, 50)
        XCTAssertEqual(config.maxTrainCharges, 10)
        XCTAssertEqual(config.stepsPerBattleCharge, 300)
        XCTAssertEqual(config.maxBattleCharges, 10)
        XCTAssertEqual(config.maxCleanCharges, 2)
        XCTAssertGreaterThan(config.handwashPerCleanCharge, 0)
        XCTAssertLessThanOrEqual(config.meatPerBattleWin.min, config.meatPerBattleWin.max)
        XCTAssertGreaterThanOrEqual(config.meatCap, 0)
    }

    /// THE AC: every rate is > 0 and every cap >= 0, checked over the SAME lists the validator uses
    /// so the two never drift.
    func testEveryRateIsPositiveAndEveryCapIsNonNegative() throws {
        let config = try ConsumptionConfig.load()
        for rate in config.rates {
            XCTAssertGreaterThan(rate.value, 0, "\(rate.name) must be > 0")
        }
        for cap in config.caps {
            XCTAssertGreaterThanOrEqual(cap.value, 0, "\(cap.name) must be >= 0")
        }
    }

    /// The hit-rate coefficients are a well-formed clamp band, and the element multipliers order
    /// advantage above neutral above disadvantage — the shape US-186/US-189 lean on.
    func testHitRateAndElementCoefficientsAreWellFormed() throws {
        let config = try ConsumptionConfig.load()

        XCTAssertGreaterThan(config.hitRate.ceiling, config.hitRate.floor)
        XCTAssertGreaterThanOrEqual(config.hitRate.base, config.hitRate.floor)
        XCTAssertLessThanOrEqual(config.hitRate.base, config.hitRate.ceiling)

        XCTAssertGreaterThan(config.elementDamage.advantage, config.elementDamage.neutral)
        XCTAssertGreaterThan(config.elementDamage.neutral, config.elementDamage.disadvantage)
        XCTAssertGreaterThanOrEqual(config.elementDamage.minimum, 1)
    }

    /// The per-stage stat table covers every playable stage (all but Digitama, which never fights),
    /// with a strictly climbing base and a non-decreasing training cap up the ladder — higher
    /// stages are tougher and have more room to grow.
    func testStageStatsCoverEveryPlayableStageAndClimb() throws {
        let config = try ConsumptionConfig.load()

        for stage in Stage.allCases where stage != .digitama {
            XCTAssertNotNil(config.stats(for: stage), "no stats for \(stage.rawValue)")
        }
        XCTAssertNil(config.stats(for: .digitama))

        let ladder: [Stage] = [.babyI, .babyII, .child, .adult, .perfect, .ultimate]
        let stats = ladder.compactMap { config.stats(for: $0) }
        XCTAssertEqual(stats.count, ladder.count)
        for (lower, higher) in zip(stats, stats.dropFirst()) {
            XCTAssertGreaterThan(higher.baseHP, lower.baseHP)
            XCTAssertGreaterThan(higher.baseAttack, lower.baseAttack)
            XCTAssertGreaterThanOrEqual(higher.trainingCap, lower.trainingCap)
        }
    }

    // MARK: - The validator

    /// THE AC: the validator reports ZERO findings over the shipped config.
    func testValidatorReportsNothingOverTheShippedConfig() throws {
        let findings = try ConsumptionConfig.load().validate()
        XCTAssertEqual(findings, [], "\(findings.map(\.description))")
    }

    /// A sound hand-built config the rejection tests mutate one field at a time, so the reported
    /// error can only be the break. A control run asserts it is itself clean.
    private func soundConfig() -> ConsumptionConfig {
        ConsumptionConfig(
            kcalPerTrain: 50,
            maxTrainCharges: 10,
            stepsPerBattleCharge: 300,
            maxBattleCharges: 10,
            handwashPerCleanCharge: 1,
            maxCleanCharges: 2,
            meatPerBattleWin: MeatRange(min: 1, max: 3),
            meatCap: 20,
            hitRate: HitRateCoefficients(base: 0.85, agilityWeight: 0.03, floor: 0.30, ceiling: 0.98),
            elementDamage: ElementDamageMultipliers(
                advantage: 1.5, neutral: 1.0, disadvantage: 0.5, minimum: 1),
            stageStats: ["Child": StageStats(baseHP: 5, baseAttack: 3, baseAgility: 3, trainingCap: 4)]
        )
    }

    func testSoundHandBuiltConfigValidatesClean() {
        XCTAssertEqual(soundConfig().validate(), [])
    }

    /// THE AC: a non-positive rate is rejected.
    func testValidatorRejectsANonPositiveRate() {
        var config = soundConfig()
        config = ConsumptionConfig(
            kcalPerTrain: 0,
            maxTrainCharges: config.maxTrainCharges,
            stepsPerBattleCharge: config.stepsPerBattleCharge,
            maxBattleCharges: config.maxBattleCharges,
            handwashPerCleanCharge: config.handwashPerCleanCharge,
            maxCleanCharges: config.maxCleanCharges,
            meatPerBattleWin: config.meatPerBattleWin,
            meatCap: config.meatCap,
            hitRate: config.hitRate,
            elementDamage: config.elementDamage,
            stageStats: config.stageStats)

        XCTAssertEqual(config.validate(), [.nonPositiveRate(field: "kcalPerTrain", value: 0)])
    }

    /// THE AC: a max below zero is rejected.
    func testValidatorRejectsAMaxBelowZero() {
        let sound = soundConfig()
        let config = ConsumptionConfig(
            kcalPerTrain: sound.kcalPerTrain,
            maxTrainCharges: sound.maxTrainCharges,
            stepsPerBattleCharge: sound.stepsPerBattleCharge,
            maxBattleCharges: -1,
            handwashPerCleanCharge: sound.handwashPerCleanCharge,
            maxCleanCharges: sound.maxCleanCharges,
            meatPerBattleWin: sound.meatPerBattleWin,
            meatCap: sound.meatCap,
            hitRate: sound.hitRate,
            elementDamage: sound.elementDamage,
            stageStats: sound.stageStats)

        XCTAssertEqual(config.validate(), [.negativeMax(field: "maxBattleCharges", value: -1)])
    }

    /// THE AC: an empty stat table is rejected.
    func testValidatorRejectsAnEmptyStatTable() {
        let sound = soundConfig()
        let config = ConsumptionConfig(
            kcalPerTrain: sound.kcalPerTrain,
            maxTrainCharges: sound.maxTrainCharges,
            stepsPerBattleCharge: sound.stepsPerBattleCharge,
            maxBattleCharges: sound.maxBattleCharges,
            handwashPerCleanCharge: sound.handwashPerCleanCharge,
            maxCleanCharges: sound.maxCleanCharges,
            meatPerBattleWin: sound.meatPerBattleWin,
            meatCap: sound.meatCap,
            hitRate: sound.hitRate,
            elementDamage: sound.elementDamage,
            stageStats: [:])

        XCTAssertEqual(config.validate(), [.emptyStatTable])
    }
}
