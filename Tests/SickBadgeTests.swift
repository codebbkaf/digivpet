import CoreGraphics
import Foundation
import XCTest
@testable import DigiVPet

/// US-069: the pulsing bandage that says the Digimon is ill.
///
/// What is assertable here is WHEN the badge is owed and that it cannot collide with the Digimon.
/// That it actually pulses on a real screen is a Simulator screenshot, recorded in progress.txt —
/// and per US-068's note, the Simulator throttles redraws, so a screenshot can prove the badge
/// CHANGES but never how fast.
@MainActor
final class SickBadgeTests: XCTestCase {
    private var storeDirectory: URL!
    private var storeURL: URL { storeDirectory.appendingPathComponent("SickBadge.store") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        try super.tearDownWithError()
    }

    private func makeModel() -> MainScreenModel {
        MainScreenModel(makeStore: { [storeURL] in try GameStore(url: storeURL) },
                        chooseStartingDigitama: { $0.first })
    }

    // MARK: - When the badge is owed

    /// AC1/AC3: sick and only sick. Dead is not "very sick" — the memorial is what that state owes.
    func testTheBadgeIsOwedForSicknessAndNothingElse() async throws {
        let model = makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)

        for status in HealthStatus.allCases {
            state.healthStatus = status
            XCTAssertEqual(model.isSick, status == .sick,
                           "\(status) should \(status == .sick ? "" : "not ")show the badge")
        }
    }

    /// A cure has to take the badge away again there and then, not on the next launch.
    func testCuringTakesTheBadgeAway() async throws {
        let model = makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)

        state.healthStatus = .sick
        XCTAssertTrue(model.isSick)

        state.healthStatus = .healthy
        XCTAssertFalse(model.isSick)
    }

    /// No game at all is not an illness — the badge must not appear over the loading or failed
    /// screens, where there is nothing for it to be describing.
    func testThereIsNoBadgeWithoutAGame() {
        XCTAssertFalse(makeModel().isSick)
    }

    // MARK: - AC4: the badge cannot overlap the Digimon

    /// The band is taken out of the sprite's height rather than drawn over it, so the sprite the
    /// screen sizes is strictly shorter than the slot the badge shares with it.
    func testASickSpriteIsSizedAgainstLessThanTheWholeSlot() {
        for slot in stride(from: 40.0, through: 200.0, by: 1.0) {
            let offered = SickBadgeLayout.spriteHeight(in: CGFloat(slot), isSick: true)
            XCTAssertEqual(offered, CGFloat(slot) - SickBadgeLayout.reservedHeight,
                           "slot \(slot) did not reserve the band")
        }
    }

    /// The whole point: a sick Digimon drawn at the floor of its slot ends below the band the badge
    /// occupies. This is the assertion that would fail if someone put the badge back to being a
    /// plain overlay on the full-height sprite.
    ///
    /// Asserted from `clearanceFloor` up, and that bound is not a convenience — see
    /// `testBelowTheClearanceFloorTheSpriteIsAlreadyOverflowingAnyway` for what happens under it and
    /// why the badge is not what breaks there.
    func testTheSickSpriteNeverReachesIntoTheBadgesBand() {
        for slot in stride(from: Double(SickBadgeLayout.clearanceFloor), through: 200.0, by: 0.5) {
            let offered = SickBadgeLayout.spriteHeight(in: CGFloat(slot), isSick: true)
            let side = SpriteScale.fitting(offered) * CGFloat(SpriteSheet.frameSize)
            // Bottom-aligned, so the sprite's top edge is this far down the slot.
            let spriteTop = CGFloat(slot) - side
            XCTAssertGreaterThanOrEqual(spriteTop, SickBadgeLayout.reservedHeight,
                                        "the sprite reached the badge's band at slot \(slot)")
        }
    }

    /// Under `clearanceFloor` the guarantee above genuinely stops holding, and this pins exactly how
    /// and why: what is left after the band is shorter than the smallest Digimon US-039 will draw,
    /// so `SpriteScale.minimum` becomes binding and the sprite overflows upward into the badge.
    ///
    /// US-039 chose that floor on purpose — below 32pt the art stops reading as a Digimon, so it
    /// overflows visibly rather than shrinking into a smudge that fits. The badge inherits it. This
    /// is a test rather than a comment because it is the one place the layout's promise breaks, and
    /// the next person to add a fixed row should find out from a red test rather than from a
    /// screenshot of a bandage sitting on Agumon's head.
    func testBelowTheClearanceFloorTheSickSpriteOverflowsIntoTheBand() {
        for slot in stride(from: 20.0, to: Double(SickBadgeLayout.clearanceFloor), by: 0.5) {
            let offered = SickBadgeLayout.spriteHeight(in: CGFloat(slot), isSick: true)
            XCTAssertEqual(SpriteScale.fitting(offered), SpriteScale.minimum,
                           "slot \(slot) was not at the floor, so the band should have been clear")
            let side = SpriteScale.fitting(offered) * CGFloat(SpriteSheet.frameSize)
            XCTAssertGreaterThan(side, CGFloat(slot) - SickBadgeLayout.reservedHeight,
                                 "slot \(slot) had room after all")
        }
    }

    /// The floor is exactly "the band, plus the smallest Digimon US-039 will draw" — stated as that
    /// sum rather than as a number, so trimming the band or moving the floor moves it too.
    func testTheClearanceFloorIsTheBandPlusTheSmallestSprite() {
        XCTAssertEqual(SickBadgeLayout.clearanceFloor,
                       SickBadgeLayout.reservedHeight
                           + SpriteScale.minimum * CGFloat(SpriteSheet.frameSize))
    }

    /// The band is genuinely big enough for what is drawn in it — a reserved strip smaller than the
    /// symbol would clip the badge instead of the sprite, which is the same bug wearing a hat.
    func testTheBandFitsTheSymbolItReserves() {
        XCTAssertGreaterThan(SickBadgeLayout.reservedHeight, SickBadgeLayout.iconSize)
    }

    /// A healthy Digimon pays nothing for a badge it does not have.
    func testAHealthyDigimonGetsTheWholeSlot() {
        for slot in stride(from: 0.0, through: 200.0, by: 1.0) {
            XCTAssertEqual(SickBadgeLayout.spriteHeight(in: CGFloat(slot), isSick: false),
                           CGFloat(slot),
                           "slot \(slot) lost height while healthy")
        }
    }

    /// A slot shorter than the band cannot produce a negative height. `SpriteScale.fitting` floors
    /// the scale from there, so the sprite overflows visibly rather than vanishing.
    func testATinySlotFloorsAtZeroRatherThanGoingNegative() {
        XCTAssertEqual(SickBadgeLayout.spriteHeight(in: 0, isSick: true), 0)
        XCTAssertEqual(SickBadgeLayout.spriteHeight(in: SickBadgeLayout.reservedHeight / 2,
                                                    isSick: true), 0)
    }

    // MARK: - AC5: US-039 is not regressed

    /// The band costs the sprite at most one scale step, so a sick Digimon on the smallest watch is
    /// still drawn above `SpriteScale.minimum` rather than being pushed onto the floor where things
    /// start overlapping.
    func testTheBandCostsAtMostOneScaleStep() {
        for slot in stride(from: 40.0, through: 200.0, by: 0.5) {
            let healthy = SpriteScale.fitting(CGFloat(slot))
            let sick = SpriteScale.fitting(SickBadgeLayout.spriteHeight(in: CGFloat(slot),
                                                                       isSick: true))
            XCTAssertLessThanOrEqual(sick, healthy, "sick was drawn larger at slot \(slot)")
            XCTAssertGreaterThanOrEqual(sick, healthy - 2, "slot \(slot) lost more than one step")
        }
    }

    /// The pulse is a two-ended fade, not a blink to nothing: a badge that disappears entirely reads
    /// as a rendering glitch on a screen already showing something wrong.
    func testThePulseFadesRatherThanVanishing() {
        XCTAssertGreaterThan(SickBadgeLayout.dimmestOpacity, 0)
        XCTAssertLessThan(SickBadgeLayout.dimmestOpacity, 1)
    }

    /// The badge beats against the sick loop rather than in step with it — two things blinking on
    /// the same beat read as one thing.
    func testThePulseIsOffTheSickLoopsCadence() {
        XCTAssertNotEqual(SickBadgeLayout.pulseDuration, SpriteAnimation.sickFrameDuration)
        XCTAssertNotEqual(SickBadgeLayout.pulseDuration, SpriteAnimation.frameDuration)
    }
}
