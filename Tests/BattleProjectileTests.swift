import XCTest
import SwiftUI
@testable import DigiVPet

/// US-104: the shot hits the other Digimon and is GONE — no parked glyph on the defender, and above
/// all no reverse travel back to the attacker.
///
/// The bug was invisible to every existing test because it lived in a SwiftUI transaction:
/// `projectileProgress = 0` shared an update with an animated `beat` change, so the reset was swept
/// into the animation and the glyph slid backward over 0.15s. Two things make it checkable without a
/// view. `isProjectileVisible(atElapsed:flightDuration:)` is the drawing rule as arithmetic on the
/// clock; `ProjectileChange` is what `run()` actually writes, in order, with the one bit the bug
/// turned on — whether the write is animated.
@MainActor
final class BattleProjectileTests: XCTestCase {

    // MARK: - The visibility rule, as arithmetic

    /// AC1/AC9: the projectile is drawn while it is in the air and at no other time. Both ends are
    /// half-open — at `flightDuration` exactly it has already landed.
    func testTheProjectileIsVisibleOnlyWhileItIsInTheAir() {
        let flight = BattleView.defaultFlightDuration

        for elapsed in [0.001, flight / 2, flight * 0.99] {
            XCTAssertTrue(BattleView.isProjectileVisible(atElapsed: elapsed, flightDuration: flight),
                          "a shot \(elapsed)s into its \(flight)s flight is airborne")
        }
        for elapsed in [flight, flight * 1.2, flight + 100] {
            XCTAssertFalse(BattleView.isProjectileVisible(atElapsed: elapsed, flightDuration: flight),
                           "at \(elapsed)s the shot has landed and is gone")
        }
        for elapsed in [0.0, -0.001, -flight] {
            XCTAssertFalse(BattleView.isProjectileVisible(atElapsed: elapsed, flightDuration: flight),
                           "at \(elapsed)s the turn has not started")
        }
    }

    /// The turn's tail — the ~0.3s between impact and the next exchange — has no projectile anywhere
    /// in it. This is the half of the bug where the glyph parked on the defender, stated as the whole
    /// interval rather than as one sampled instant.
    func testNothingIsDrawnDuringTheTailAfterImpact() {
        let flight = BattleView.defaultFlightDuration
        let turn = BattleView.defaultTurnDuration
        XCTAssertGreaterThan(turn - flight, 0.2, "there is a tail worth flinching in")

        for step in 0...20 {
            let elapsed = flight + (turn - flight) * Double(step) / 20
            XCTAssertFalse(BattleView.isProjectileVisible(atElapsed: elapsed, flightDuration: flight),
                           "\(elapsed)s in — inside the tail — nothing is drawn")
        }
    }

    /// AC7: the invariant the tail depends on. Asserted here as well as in `BattlePacingTests`
    /// because it is now load-bearing for a second reason — a flight as long as its turn would leave
    /// the previous shot airborne when the next one is snapped back to the attacker.
    func testTheShotStillLandsInsideTheTurnThatThrewIt() {
        XCTAssertLessThan(BattleView.defaultFlightDuration, BattleView.defaultTurnDuration)
    }

    // MARK: - What run() actually writes

    private func makeBout(playerPower: Int, opponentPower: Int, seed: UInt64) -> BattleBout {
        var generator = SeededGenerator(seed: seed)
        return BattleBout(
            player: DigimonPresentation(displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            opponent: DigimonPresentation(displayName: "Foe", stage: .adult, spriteFile: "Greymon"),
            report: BattleEngine.resolve(playerPower: playerPower, opponentPower: opponentPower,
                                         using: &generator))
    }

    /// A whole battle played out at a pacing measured in milliseconds, with every change the
    /// projectile is put through recorded in order.
    private func playOut(_ bout: BattleBout) async -> [BattleView.ProjectileChange] {
        var changes: [BattleView.ProjectileChange] = []
        let view = BattleView(bout: bout, onFinish: {}, playHaptic: { _ in },
                              introDuration: 0.01, turnDuration: 0.03, flightDuration: 0.02,
                              onProjectileChange: { changes.append($0) })
        await view.run()
        return changes
    }

    /// AC10, and the story's whole point: sample the projectile through a real multi-turn battle and
    /// there is no moment where it is on screen at a progress lower than the one before. Progress
    /// does go down — once per exchange, when the next shot is snapped back to the attacker — and
    /// every one of those drops must be a snap (`animated == false`) made while the previous shot had
    /// already vanished (`visible == false`). Under the bug BOTH halves fail: the reset was animated,
    /// and it happened while the spent glyph was still being drawn on the defender.
    func testTheProjectileIsNeverVisibleAtADecreasedProgress() async throws {
        let bout = makeBout(playerPower: 30, opponentPower: 30, seed: 5)
        XCTAssertGreaterThan(bout.report.turns.count, 1, "a multi-turn report, or there is nothing to check")

        let changes = await playOut(bout)

        for (previous, current) in zip(changes, changes.dropFirst()) where current.progress < previous.progress {
            XCTAssertFalse(current.animated,
                           "the reset to \(current.progress) on turn \(current.turn) is a snap, not a slide")
            XCTAssertFalse(previous.visible,
                           "nothing is on screen to slide backward when turn \(current.turn) resets")
        }
        XCTAssertTrue(changes.contains { $0.progress == 0 }, "the projectile really was reset at least once")
    }

    /// AC3/AC4: every exchange begins with the shot at the attacker and not yet landed, and ends with
    /// it gone. The per-turn shape, asserted turn by turn rather than in aggregate — turn 2 starting
    /// already landed is exactly what would leave US-105's defender flinching before anything hit it.
    func testEveryTurnStartsUnlandedAtTheAttackerAndEndsGone() async {
        let bout = makeBout(playerPower: 30, opponentPower: 30, seed: 5)

        let changes = await playOut(bout)

        for index in bout.report.turns.indices {
            let ofTurn = changes.filter { $0.turn == index }
            XCTAssertEqual(ofTurn.count, 3, "turn \(index): reset, launch, impact")
            XCTAssertEqual(ofTurn.first?.progress, 0, "turn \(index) starts at the attacker")
            XCTAssertEqual(ofTurn.first?.visible, true, "turn \(index) starts with the shot in the air")
            XCTAssertEqual(ofTurn.last?.visible, false, "turn \(index) ends with the shot gone")
            XCTAssertEqual(ofTurn.last?.progress, 1, "and it is gone AT the defender, not short of it")
        }
        XCTAssertEqual(changes.map(\.turn), bout.report.turns.indices.flatMap { [$0, $0, $0] },
                       "every exchange, in order, and no stray change between them")
    }

    /// AC5: consecutive turns by the SAME attacker — the case the backward slide was most visible in,
    /// because both shots fly the same way and the reset is a clean reversal — each still start their
    /// shot at the attacker.
    ///
    /// The report is hand-built rather than seeded, and deliberately so: `BattleEngine.resolve`
    /// alternates strictly today, so no seed produces this shape. The view must not depend on that —
    /// it replays whatever report it is handed, and a retuned engine that ever let one side swing
    /// twice would otherwise resurrect the slide with no test to catch it.
    func testConsecutiveTurnsByTheSameAttackerEachStartAtTheAttacker() async throws {
        let bout = Self.bout(replaying: [
            BattleTurn(attacker: .player, damage: 3, defenderRemainingHitPoints: 7),
            BattleTurn(attacker: .player, damage: 3, defenderRemainingHitPoints: 4),
            BattleTurn(attacker: .opponent, damage: 2, defenderRemainingHitPoints: 8),
            BattleTurn(attacker: .player, damage: 4, defenderRemainingHitPoints: 0),
        ], winner: .player)
        let repeats = bout.report.turns.indices.dropFirst().filter {
            bout.report.turns[$0].attacker == bout.report.turns[$0 - 1].attacker
        }

        let changes = await playOut(bout)

        XCTAssertFalse(repeats.isEmpty, "the report really does repeat an attacker")
        for index in repeats {
            let first = try XCTUnwrap(changes.first { $0.turn == index })
            XCTAssertEqual(first.progress, 0,
                           "turn \(index) repeats turn \(index - 1)'s attacker and still starts at it")
            XCTAssertFalse(first.animated, "and gets there by snapping, not by sliding back across the gap")
        }
    }

    /// AC6: alternating attackers still fly the correct way. Every turn of a real battle, checked
    /// against `faces(_:)` — a rightward shot starts left of centre and ends right of it, a leftward
    /// one the mirror — so a reset that fixed the direction by flipping it would fail here.
    func testEveryTurnFliesFromItsOwnAttackerTowardTheDefender() throws {
        let bout = try XCTUnwrap(Self.boutWithBothSidesAttacking(), "a battle both sides swing in")
        let span = BattleArenaLayout.projectileSpan(inWidth: BattleArenaLayout.narrowestScreenWidth)

        for turn in bout.report.turns {
            let rightward = BattleView.faces(turn.attacker)
            let start = BattleView.projectileOffset(rightward: rightward, progress: 0, span: span)
            let end = BattleView.projectileOffset(rightward: rightward, progress: 1, span: span)

            if turn.attacker == .player {
                XCTAssertLessThan(start, end, "a player shot travels rightward, toward the opponent")
                XCTAssertEqual(start, -span / 2, accuracy: 0.001)
            } else {
                XCTAssertGreaterThan(start, end, "an opponent shot travels leftward, toward the player")
                XCTAssertEqual(start, span / 2, accuracy: 0.001)
            }
        }
    }

    /// A seeded battle in which both sides swing — searched rather than hand-built, so the report the
    /// direction assertions run against is one the engine really produces.
    private static func boutWithBothSidesAttacking() -> BattleBout? {
        bout { turns in
            turns.contains { $0.attacker == .player } && turns.contains { $0.attacker == .opponent }
        }
    }

    private static func bout(where matches: ([BattleTurn]) -> Bool) -> BattleBout? {
        for seed in UInt64(0)..<60 {
            var generator = SeededGenerator(seed: seed)
            let report = BattleEngine.resolve(playerPower: 30, opponentPower: 30, using: &generator)
            guard matches(report.turns) else { continue }
            return BattleBout(
                player: DigimonPresentation(displayName: "Hero", stage: .child, spriteFile: "Agumon"),
                opponent: DigimonPresentation(displayName: "Foe", stage: .adult, spriteFile: "Greymon"),
                report: report)
        }
        return nil
    }

    /// A bout replaying an exact list of exchanges, for the shapes the engine does not produce.
    private static func bout(replaying turns: [BattleTurn], winner: BattleSide) -> BattleBout {
        BattleBout(
            player: DigimonPresentation(displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            opponent: DigimonPresentation(displayName: "Foe", stage: .adult, spriteFile: "Greymon"),
            report: BattleReport(playerPower: 30, opponentPower: 30, turns: turns, winner: winner))
    }
}
