import XCTest
@testable import DigiVPet

/// US-105: the flinch is CAUSED by the impact, and the swing is a moving drawing.
///
/// Before this, `animation(for:during:)` handed the attacker `.still(.attack)` — one frame held for
/// the whole 1.4s exchange — and the defender `.hurt` from the turn's START, so it began recoiling
/// 1.1s before the shot reached it. Both are now functions of `landed`, the impact instant US-104
/// made into view state, which keeps the whole mapping assertable without mounting a view.
@MainActor
final class BattleFlinchTests: XCTestCase {

    // MARK: - The mapping, both sides of the impact

    /// AC2/AC8: the attacker swings for the WHOLE turn. `.pose(.attack)` is US-102's attack <-> walk1
    /// loop, so the same answer before and after impact is a moving drawing either way — not the one
    /// held frame that answer used to be.
    func testTheAttackerSwingsBeforeAndAfterImpact() {
        for attacker in [BattleSide.player, .opponent] {
            let turn = BattleTurn(attacker: attacker, damage: 3, defenderRemainingHitPoints: 7)

            XCTAssertEqual(BattleView.animation(for: attacker, during: turn, landed: false),
                           .pose(.attack), "\(attacker) is mid-swing before its shot lands")
            XCTAssertEqual(BattleView.animation(for: attacker, during: turn, landed: true),
                           .pose(.attack), "\(attacker) is still swinging after it lands")
        }
    }

    /// AC3/AC9: the defender stands in its idle loop until it is hit, and flinches only then. Asserted
    /// for BOTH sides, because the mapping is written against `turn.attacker` and a comparison
    /// flipped the wrong way would still pass on one of them.
    func testTheDefenderIsIdleUntilTheShotLandsAndHurtAfter() {
        for attacker in [BattleSide.player, .opponent] {
            let turn = BattleTurn(attacker: attacker, damage: 3, defenderRemainingHitPoints: 7)
            let defender = attacker.other

            XCTAssertEqual(BattleView.animation(for: defender, during: turn, landed: false),
                           .idle, "\(defender) has not been hit yet and is not flinching")
            XCTAssertEqual(BattleView.animation(for: defender, during: turn, landed: true),
                           .hurt, "\(defender) flinches from the moment the shot arrives")
        }
    }

    /// AC10: every turn of a REAL multi-turn battle, checked against `turn.attacker` on both sides of
    /// the impact. This is what catches the mapping agreeing with itself while disagreeing with the
    /// report the view is replaying.
    func testEveryTurnOfARealBattleAssignsTheRolesFromItsAttacker() {
        var generator = SeededGenerator(seed: 4242)
        let report = BattleEngine.resolve(playerPower: 38, opponentPower: 31, using: &generator)
        XCTAssertGreaterThan(report.turns.count, 1, "a multi-turn report, or there is nothing to check")

        for turn in report.turns {
            for landed in [false, true] {
                XCTAssertEqual(BattleView.animation(for: turn.attacker, during: turn, landed: landed),
                               .pose(.attack), "turn's attacker \(turn.attacker), landed: \(landed)")
                XCTAssertEqual(BattleView.animation(for: turn.attacker.other, during: turn, landed: landed),
                               landed ? .hurt : .idle,
                               "turn's defender \(turn.attacker.other), landed: \(landed)")
            }
        }
    }

    // MARK: - AC4: the flinch really is two frames

    /// AC4: the post-impact flinch is two ALTERNATING drawings, not one held. Stated as the frames
    /// the loop is made of and as the index actually advancing over the tail — a two-frame list drawn
    /// by a view that never ticks would look identical to a still.
    func testTheHurtLoopAlternatesTwoFramesDuringTheTail() {
        let frames = SpriteAnimation.hurt.stageFrames
        XCTAssertEqual(frames, [.hurt1, .hurt2], "the flinch is two different drawings")

        let start = Date(timeIntervalSinceReferenceDate: 0)
        let first = SpriteAnimation.frameIndex(at: start, count: frames.count,
                                               duration: SpriteAnimation.hurt.frameDuration)
        let next = SpriteAnimation.frameIndex(at: start.addingTimeInterval(SpriteAnimation.hurt.frameDuration),
                                              count: frames.count,
                                              duration: SpriteAnimation.hurt.frameDuration)
        XCTAssertNotEqual(frames[first], frames[next], "one beat later a DIFFERENT frame is showing")
    }

    /// The attacker's swing is two frames for the same reason, and the second of them is walk1 — the
    /// pairing US-102 established, which is why this needed no new art.
    func testTheAttackSwingIsTwoFrames() {
        XCTAssertEqual(SpriteAnimation.pose(.attack).stageFrames, [.attack, .walk1])
    }

    // MARK: - AC5: turn 2 does not start already flinching

    /// AC5, composed from the two halves that own it: `run()` reports every exchange as beginning
    /// with its shot still in the AIR (US-104's reset of `hasLanded`), and the mapping turns that
    /// into `.idle`. So the defender of turn 1, 2 and 3 alike is standing when its turn opens and
    /// flinching when it closes — the bug this story is named after would make turns after the first
    /// open mid-recoil.
    func testNoTurnOpensWithTheDefenderAlreadyFlinching() async {
        var generator = SeededGenerator(seed: 5)
        let bout = BattleBout(
            player: DigimonPresentation(displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            opponent: DigimonPresentation(displayName: "Foe", stage: .adult, spriteFile: "Greymon"),
            report: BattleEngine.resolve(playerPower: 30, opponentPower: 30, using: &generator))
        XCTAssertGreaterThan(bout.report.turns.count, 1, "more than one exchange, or AC5 says nothing")

        var changes: [BattleView.ProjectileChange] = []
        let view = BattleView(bout: bout, onFinish: {}, playHaptic: { _ in },
                              introDuration: 0.01, turnDuration: 0.03, flightDuration: 0.02,
                              onProjectileChange: { changes.append($0) })
        await view.run()

        for index in bout.report.turns.indices {
            let turn = bout.report.turns[index]
            let defender = turn.attacker.other
            let ofTurn = changes.filter { $0.turn == index }
            // `visible` is the projectile being drawn, which is exactly `!hasLanded` within a turn.
            let poses = ofTurn.map {
                BattleView.animation(for: defender, during: turn, landed: !$0.visible)
            }

            XCTAssertEqual(poses.first, .idle, "turn \(index) opens with its defender standing")
            XCTAssertEqual(poses.last, .hurt, "turn \(index) closes with its defender flinching")
        }
    }

    // MARK: - AC6: the result screen is still held

    /// AC6: the fight is over on the result screen and nothing is hitting the Digimon any more, so
    /// both outcomes stay ONE frame held. `.still`, deliberately, not `.pose` — a `.pose(.happy)`
    /// there would have the winner walking on the spot behind "Victory!".
    func testTheResultScreenStaysHeld() {
        for playerWon in [true, false] {
            let held = SpriteAnimation.still(BattleView.resultFrame(playerWon: playerWon))
            XCTAssertEqual(held.stageFrames.count, 1, "the result holds a single frame")
        }
        XCTAssertEqual(BattleView.resultFrame(playerWon: true), .happy)
        XCTAssertEqual(BattleView.resultFrame(playerWon: false), .hurt1)
    }
}
