import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-031 — turn-based battle resolution and animation.
///
/// Four layers, mirroring the split the code itself makes:
/// - `SeededGeneratorTests` — the RNG really is reproducible, which everything below leans on.
/// - `BattleEngineTests` — the pure resolution: determinism, the turn structure, who wins.
/// - `BattleMatchmakerTests` — the opponent comes from the roster and is near the player's stage.
/// - `BattleFrameTests` / `BattleViewHapticTests` — the frame assignment and the result haptic, the
///   two criteria a Simulator screenshot cannot pin on its own.
/// - `BattleApplyTests` — the real `MainScreenModel` and the real store, including the criterion that
///   matters most: LOSING NEVER KILLS AND NEVER COUNTS AS A CARE MISTAKE.
///
/// No test waits real time and none draws a random number it did not seed.

// MARK: - The seeded generator

final class SeededGeneratorTests: XCTestCase {
    /// The whole point: same seed, same sequence. Everything else here is only deterministic because
    /// this is.
    func testTheSameSeedProducesTheSameSequence() {
        var a = SeededGenerator(seed: 12345)
        var b = SeededGenerator(seed: 12345)

        let first = (0..<20).map { _ in a.next() }
        let second = (0..<20).map { _ in b.next() }

        XCTAssertEqual(first, second)
    }

    /// And different seeds do not. Without this the suite could pass on a generator that returns a
    /// constant, which would be "deterministic" and useless.
    func testDifferentSeedsProduceDifferentSequences() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)

        let first = (0..<20).map { _ in a.next() }
        let second = (0..<20).map { _ in b.next() }

        XCTAssertNotEqual(first, second)
    }

    /// A single generator does not repeat itself either — a stuck state would make every turn of a
    /// battle roll the same damage and still look deterministic.
    func testOneGeneratorDoesNotRepeatItself() {
        var generator = SeededGenerator(seed: 99)
        let draws = (0..<50).map { _ in generator.next() }

        XCTAssertEqual(Set(draws).count, draws.count, "50 draws, 50 distinct values")
    }
}

// MARK: - AC2 / AC6: resolution off a seeded RNG

final class BattleEngineTests: XCTestCase {

    private func resolve(player: Int, opponent: Int, seed: UInt64) -> BattleReport {
        var generator = SeededGenerator(seed: seed)
        return BattleEngine.resolve(playerPower: player, opponentPower: opponent, using: &generator)
    }

    /// AC6, the headline criterion: one seed, one winner, every time. Asserted over the WHOLE report
    /// and not merely the winner, so a change that reshuffles the exchanges but happens to land on
    /// the same result still fails here rather than silently changing every battle.
    func testASeededBattleIsDeterministic() {
        let first = resolve(player: 40, opponent: 33, seed: 2026)

        for _ in 0..<10 {
            XCTAssertEqual(resolve(player: 40, opponent: 33, seed: 2026), first,
                           "the same seed replays the same battle, blow for blow")
        }
    }

    /// The literal outcome for one seed, pinned. This is what would catch an accidental change to the
    /// draw order or to SplitMix64 itself — the assertions above would all still pass on a different
    /// but self-consistent engine.
    func testAPinnedSeedProducesAPinnedWinner() {
        let report = resolve(player: 40, opponent: 33, seed: 2026)

        XCTAssertEqual(report.winner, .player)
        XCTAssertTrue(report.playerWon)
        XCTAssertEqual(report.turns.count, 5)
        XCTAssertEqual(report.turns.map(\.damage), [4, 2, 3, 2, 4])
    }

    /// Different seeds really do produce different battles, so "deterministic" does not mean "fixed".
    /// Over 200 seeds an evenly matched pair must sometimes lose — otherwise the loss branch, and
    /// with it half the result screen, is unreachable in the shipped game.
    func testEvenlyMatchedBattlesGoBothWays() {
        let winners = (0..<200).map { resolve(player: 30, opponent: 30, seed: UInt64($0)).winner }

        XCTAssertTrue(winners.contains(.player), "an even match is sometimes won")
        XCTAssertTrue(winners.contains(.opponent), "and sometimes lost")
    }

    // MARK: The turn structure

    /// AC2's "turn-based": the player swings first and the sides then strictly alternate. A resolution
    /// that let one side hit twice would break the animation's attack/hurt pairing.
    func testTurnsAlternateStartingWithThePlayer() {
        for seed in UInt64(0)..<50 {
            let report = resolve(player: 35, opponent: 35, seed: seed)
            let expected = report.turns.indices.map { $0.isMultiple(of: 2) ? BattleSide.player : .opponent }

            XCTAssertEqual(report.turns.map(\.attacker), expected, "seed \(seed)")
        }
    }

    /// A battle is always at least one swing and always ends in a knockout at these constants — so the
    /// view always has a turn to animate and the result always has a reason.
    func testEveryBattleEndsOnAKnockoutByTheLastTurn() {
        for seed in UInt64(0)..<100 {
            let report = resolve(player: 20, opponent: 45, seed: seed)

            XCTAssertFalse(report.turns.isEmpty, "seed \(seed)")
            let last = try? XCTUnwrap(report.turns.last)
            XCTAssertEqual(last?.isKnockout, true, "seed \(seed): the last turn is the felling blow")
            XCTAssertEqual(last?.attacker, report.winner, "seed \(seed): whoever landed it won")
            XCTAssertEqual(report.turns.dropLast().contains(where: \.isKnockout), false,
                           "seed \(seed): nothing continues after a knockout")
        }
    }

    /// Hit points only ever fall, never below zero, and by exactly the damage rolled. This is what the
    /// view's on-screen counter is derived from, so a drift here would show up as a wrong number.
    func testDamageAccountsForTheHitPointsShown() {
        let report = resolve(player: 30, opponent: 26, seed: 7)

        for side in BattleSide.allCases {
            var expected = BattleEngine.startingHitPoints
            for (index, turn) in report.turns.enumerated() where turn.attacker == side.other {
                expected = max(0, expected - turn.damage)
                XCTAssertEqual(turn.defenderRemainingHitPoints, expected)
                XCTAssertEqual(BattleView.hitPoints(side, afterTurn: index, of: report.turns), expected,
                               "the number on screen matches the report")
            }
        }
    }

    /// Every roll stays inside `1...maximumDamage`, so a hopeless underdog still chips away (which is
    /// what guarantees termination) and nobody one-shots anybody.
    func testDamageStaysWithinItsRolledRange() {
        let report = resolve(player: 9, opponent: 60, seed: 3)
        let playerCeiling = BattleEngine.maximumDamage(attacker: 9, defender: 60)
        let opponentCeiling = BattleEngine.maximumDamage(attacker: 60, defender: 9)

        for turn in report.turns {
            XCTAssertGreaterThanOrEqual(turn.damage, BattleEngine.minimumDamage)
            XCTAssertLessThanOrEqual(turn.damage,
                                     turn.attacker == .player ? playerCeiling : opponentCeiling)
        }
    }

    // MARK: Power actually matters

    /// The reason to train at all: over many seeds, a much stronger Digimon wins much more often.
    /// Asserted as a RATE rather than at a single seed, because one battle is a dice roll and the
    /// claim being made is about the odds.
    func testStrongerDigimonWinFarMoreOften() {
        let strong = (0..<300).filter { resolve(player: 60, opponent: 20, seed: UInt64($0)).playerWon }.count
        let weak = (0..<300).filter { resolve(player: 20, opponent: 60, seed: UInt64($0)).playerWon }.count

        XCTAssertGreaterThan(strong, 240, "4:1 on power should win the large majority")
        XCTAssertLessThan(weak, 60, "and lose the large majority from the other side")
        XCTAssertGreaterThan(strong, weak * 3)
    }

    /// The damage ceiling is a SHARE of the two powers, not an absolute: an even match at 10 and an
    /// even match at 1000 roll the same range. That is what keeps battles the same length at every
    /// stage instead of Ultimates trading 40-point blows.
    func testTheDamageCeilingDependsOnTheRatioNotTheMagnitude() {
        XCTAssertEqual(BattleEngine.maximumDamage(attacker: 10, defender: 10),
                       BattleEngine.maximumDamage(attacker: 1000, defender: 1000))
        XCTAssertGreaterThan(BattleEngine.maximumDamage(attacker: 60, defender: 20),
                             BattleEngine.maximumDamage(attacker: 20, defender: 60))
    }

    /// A zero or negative power cannot divide by zero or roll an empty range. `BattlePower.base`
    /// already makes a real Digimon's power at least 1, but the engine must not depend on that.
    func testAZeroPowerCannotCrashTheRoll() {
        let report = resolve(player: 0, opponent: 0, seed: 5)

        XCTAssertFalse(report.turns.isEmpty)
        XCTAssertTrue(report.turns.allSatisfy { $0.damage >= BattleEngine.minimumDamage })
    }
}

// MARK: - AC1: the opponent

final class BattleMatchmakerTests: XCTestCase {
    /// The shipped roster, because AC1 is a claim about the ROSTER and a fixture graph could satisfy
    /// it while the real one had nobody to fight at some stage.
    private let graph = EvolutionGraph.bundled

    private func choose(playerId: String, seed: UInt64) -> BattleOpponent? {
        var generator = SeededGenerator(seed: seed)
        return BattleMatchmaker.choose(in: graph, playerId: playerId, using: &generator)
    }

    /// AC1: an opponent comes back for every playable Digimon in the roster, and it is always a node
    /// FROM the roster. Swept over the whole roster and many seeds, so a stage with a thin pool
    /// cannot hide.
    func testEveryPlayableDigimonFindsAnOpponentInTheRoster() {
        let playable = graph.nodes.filter { !$0.dexOnly }
        XCTAssertFalse(playable.isEmpty, "the fixture roster is not empty")

        for node in playable {
            for seed in UInt64(0)..<20 {
                guard let opponent = choose(playerId: node.id, seed: seed) else {
                    return XCTFail("\(node.id) found nobody to fight at seed \(seed)")
                }
                XCTAssertNotNil(graph.node(id: opponent.node.id), "the opponent is a roster node")
            }
        }
    }

    /// AC1's "near the player's stage": never more than one rung away, at any seed.
    func testTheOpponentIsAlwaysWithinOneRungOfThePlayer() {
        for node in graph.nodes where !node.dexOnly {
            let rung = BattlePower.battleRung(node.stage)
            for seed in UInt64(0)..<25 {
                guard let opponent = choose(playerId: node.id, seed: seed) else { continue }
                let gap = abs(BattlePower.battleRung(opponent.node.stage) - rung)

                XCTAssertLessThanOrEqual(gap, BattleMatchmaker.maximumRungGap,
                                         "\(node.id) (rung \(rung)) drew \(opponent.node.id) at seed \(seed)")
            }
        }
    }

    /// A Digimon never fights itself — that is not a battle, and the result screen would show the
    /// same sprite winning and losing.
    func testAPlayerNeverFightsItself() {
        for node in graph.nodes where !node.dexOnly {
            for seed in UInt64(0)..<25 {
                XCTAssertNotEqual(choose(playerId: node.id, seed: seed)?.node.id, node.id)
            }
        }
    }

    /// A `dexOnly` node has no animated sheet, so its attack and hurt frames do not exist: picking one
    /// would animate the battle as two placeholders.
    func testDexOnlyDigimonAreNeverPickedAsOpponents() {
        let dexOnly = Set(graph.nodes.filter(\.dexOnly).map(\.id))

        for node in graph.nodes where !node.dexOnly {
            for seed in UInt64(0)..<25 {
                guard let opponent = choose(playerId: node.id, seed: seed) else { continue }
                XCTAssertFalse(dexOnly.contains(opponent.node.id),
                               "\(opponent.node.id) has no animated sheet to fight with")
            }
        }
    }

    /// The pool is a POOL: across seeds a Child meets more than one opponent, so battling does not
    /// become the same fight over and over.
    func testThePoolOffersMoreThanOneOpponent() {
        let met = Set((0..<40).compactMap { choose(playerId: "agumon", seed: UInt64($0))?.node.id })

        XCTAssertGreaterThan(met.count, 1, "a Child should meet a variety of opponents, met: \(met)")
    }

    /// Same seed, same opponent — matchmaking is part of the seeded battle, not a separate roll off
    /// the system RNG that would make a "deterministic" battle irreproducible in practice.
    func testMatchmakingIsDeterministicForASeed() {
        let first = choose(playerId: "agumon", seed: 77)

        for _ in 0..<10 {
            XCTAssertEqual(choose(playerId: "agumon", seed: 77), first)
        }
    }

    /// The opponent's power is a real `BattlePower` figure from its own stage — always positive, so
    /// the engine's ratio is never a division by zero, and rising with the stage it was drawn at.
    func testTheOpponentsPowerIsPositiveAndScalesWithItsStage() {
        for seed in UInt64(0)..<40 {
            guard let opponent = choose(playerId: "agumon", seed: seed) else { continue }
            let rung = BattlePower.battleRung(opponent.node.stage)
            let floor = BattlePower.power(stage: opponent.node.stage, strengthStat: 0,
                                          lifetimeEnergy: .zero)
            let ceiling = BattlePower.power(stage: opponent.node.stage, strengthStat: rung + 2,
                                            lifetimeEnergy: .zero)

            XCTAssertGreaterThan(opponent.power, 0)
            XCTAssertGreaterThanOrEqual(opponent.power, floor)
            XCTAssertLessThanOrEqual(opponent.power, ceiling)
        }
    }

    /// An unknown id — a save whose Digimon the roster has since dropped — yields nobody rather than
    /// trapping or fighting a stranger.
    func testAnUnknownPlayerFindsNoOpponent() {
        XCTAssertNil(choose(playerId: "not-a-digimon", seed: 1))
    }
}

// MARK: - AC3 / AC4: the frames

final class BattleFrameTests: XCTestCase {
    /// AC3, asserted over every turn of a real battle: the attacker holds the attack frame (11) and
    /// the defender plays the hurt loop (9 <-> 10). A screenshot can only show one instant of this.
    func testTheAttackerAttacksAndTheDefenderIsHurtOnEveryTurn() {
        var generator = SeededGenerator(seed: 4242)
        let report = BattleEngine.resolve(playerPower: 38, opponentPower: 31, using: &generator)
        XCTAssertFalse(report.turns.isEmpty)

        for turn in report.turns {
            let attacker = BattleView.animation(for: turn.attacker, during: turn)
            let defender = BattleView.animation(for: turn.attacker.other, during: turn)

            XCTAssertEqual(attacker, .still(.attack))
            XCTAssertEqual(defender, .hurt)
        }
    }

    /// The frame indices themselves, pinned against the sheet layout: attack is 11 and the hurt loop
    /// is 9 then 10. This is what would catch a renamed case pointing at the wrong slice.
    func testTheFramesAreTheOnesThePRDNames() {
        XCTAssertEqual(SpriteFrame.attack.rawValue, 11)
        XCTAssertEqual(SpriteAnimation.hurt.stageFrames.map(\.rawValue), [9, 10])
        XCTAssertEqual(SpriteFrame.happy.rawValue, 7)
    }

    /// AC4's frames: the happy frame (7) on a win, a hurt frame on a loss.
    func testTheResultShowsHappyOnAWinAndHurtOnALoss() {
        XCTAssertEqual(BattleView.resultFrame(playerWon: true), .happy)
        XCTAssertEqual(BattleView.resultFrame(playerWon: false), .hurt1)
    }

    // MARK: - US-072: the projectile's flight

    /// The player's shot leaves the player (on the left) and reaches the opponent (on the right): a
    /// rightward flight runs from `-span/2` at the attacker to `+span/2` at the defender.
    func testAPlayerProjectileFliesLeftToRight() {
        let span = BattleArenaLayout.projectileSpan(inWidth: BattleArenaLayout.narrowestScreenWidth)
        XCTAssertEqual(BattleView.projectileOffset(rightward: true, progress: 0, span: span),
                       -span / 2, accuracy: 0.001, "starts at the player on the left")
        XCTAssertEqual(BattleView.projectileOffset(rightward: true, progress: 0.5, span: span),
                       0, accuracy: 0.001, "halfway is arena centre")
        XCTAssertEqual(BattleView.projectileOffset(rightward: true, progress: 1, span: span),
                       span / 2, accuracy: 0.001, "reaches the opponent on the right")
    }

    /// The opponent's shot is the mirror image: it leaves the opponent on the right and reaches the
    /// player on the left, so it flies out of the opponent's front rather than backward out of its back.
    func testAnOpponentProjectileFliesRightToLeft() {
        let span = BattleArenaLayout.projectileSpan(inWidth: BattleArenaLayout.narrowestScreenWidth)
        XCTAssertEqual(BattleView.projectileOffset(rightward: false, progress: 0, span: span),
                       span / 2, accuracy: 0.001, "starts at the opponent on the right")
        XCTAssertEqual(BattleView.projectileOffset(rightward: false, progress: 1, span: span),
                       -span / 2, accuracy: 0.001, "reaches the player on the left")
    }

    /// The two directions are genuine mirror images at every point of the flight — the same progress
    /// puts the two shots on opposite sides of centre, never the same place.
    func testTheTwoDirectionsAreMirrored() {
        let span = BattleArenaLayout.projectileSpan(inWidth: BattleArenaLayout.narrowestScreenWidth)
        for step in 0...10 {
            let progress = CGFloat(step) / 10
            let right = BattleView.projectileOffset(rightward: true, progress: progress, span: span)
            let left = BattleView.projectileOffset(rightward: false, progress: progress, span: span)
            XCTAssertEqual(right, -left, accuracy: 0.001)
        }
    }

    /// The projectile is drawn in whichever side is swinging's colour — read off the bout's per-side
    /// move, so the opponent's shot is not silently painted in the player's tint.
    func testTheProjectileTakesTheAttackersMove() {
        let bout = BattleBout(
            player: DigimonPresentation(displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            opponent: DigimonPresentation(displayName: "Foe", stage: .adult, spriteFile: "Greymon"),
            report: BattleReport(playerPower: 10, opponentPower: 10, turns: [], winner: .player),
            playerMove: Move(projectileSymbol: "flame.fill", tint: .orange,
                             signatureName: "Pepper Breath", signatureSymbol: "flame"),
            opponentMove: Move(projectileSymbol: "drop.fill", tint: .blue,
                               signatureName: "Splash", signatureSymbol: "drop"))

        XCTAssertEqual(bout.move(for: .player).tint, .orange)
        XCTAssertEqual(bout.move(for: .opponent).tint, .blue)
        XCTAssertEqual(bout.move(for: .player).projectileSymbol, "flame.fill")
        XCTAssertEqual(bout.move(for: .opponent).projectileSymbol, "drop.fill")
    }

    /// Every tint the catalog can name maps to a colour — an exhaustive switch (no `default:`), so a
    /// tint added to `MoveTint` without a colour is a compile error rather than a grey projectile at
    /// battle time. The distinctness check confirms the mapping is not a single constant for all.
    func testEveryMoveTintHasAColour() {
        let colours = MoveTint.allCases.map(\.color)
        XCTAssertEqual(colours.count, MoveTint.allCases.count)
        XCTAssertNotEqual(MoveTint.red.color, MoveTint.blue.color)
        XCTAssertNotEqual(MoveTint.orange.color, MoveTint.green.color)
    }

    // MARK: - US-073: the signature move on the finishing blow

    /// AC6: knockout-turn detection is pure and asserted against a seeded report. Exactly ONE turn —
    /// the last — is the finishing blow, and the signature move must fire on that turn and no other.
    func testTheKnockoutTurnIsTheLastTurnAndOnlyThat() {
        for seed in UInt64(0)..<40 {
            var generator = SeededGenerator(seed: seed)
            let report = BattleEngine.resolve(playerPower: 33, opponentPower: 29, using: &generator)
            let last = report.turns.count - 1
            for index in report.turns.indices {
                XCTAssertEqual(BattleView.isKnockoutTurn(index, of: report.turns), index == last,
                               "seed \(seed): only the last turn is the knockout")
            }
        }
    }

    /// AC4: the finish fires whether the PLAYER or the OPPONENT lands it — the detection is about the
    /// turn ending the battle, not about which side is swinging. Across many seeds both winners occur,
    /// and in every case it is the winner's turn that is the knockout.
    func testTheFinishFiresForEitherSide() {
        var sawPlayerFinish = false
        var sawOpponentFinish = false
        for seed in UInt64(0)..<60 {
            var generator = SeededGenerator(seed: seed)
            let report = BattleEngine.resolve(playerPower: 30, opponentPower: 30, using: &generator)
            let last = report.turns.count - 1
            XCTAssertTrue(BattleView.isKnockoutTurn(last, of: report.turns))
            XCTAssertEqual(report.turns[last].attacker, report.winner,
                           "seed \(seed): the felling blow is the winner's")
            if report.winner == .player { sawPlayerFinish = true } else { sawOpponentFinish = true }
        }
        XCTAssertTrue(sawPlayerFinish, "some battles are won by the player")
        XCTAssertTrue(sawOpponentFinish, "some battles are won by the opponent")
    }

    /// AC1: an out-of-range index is not a knockout — the detection never traps or false-positives on
    /// an index `run()` would never actually feed it.
    func testAnOutOfRangeTurnIsNotAKnockout() {
        var generator = SeededGenerator(seed: 7)
        let report = BattleEngine.resolve(playerPower: 20, opponentPower: 20, using: &generator)
        XCTAssertFalse(BattleView.isKnockoutTurn(-1, of: report.turns))
        XCTAssertFalse(BattleView.isKnockoutTurn(report.turns.count, of: report.turns))
        XCTAssertFalse(BattleView.isKnockoutTurn(0, of: []))
    }

    /// AC2: the signature glyph is drawn visibly larger than an ordinary projectile — asserted on the
    /// two sizes directly so the two literals cannot quietly drift to the same value.
    func testTheSignatureIsLargerThanAnOrdinaryProjectile() {
        XCTAssertGreaterThan(BattleView.signatureSize, BattleView.projectileSize,
                             "the finishing blow's glyph is bigger than an ordinary shot")
    }

    /// US-071: the two combatants face each other. The pack's art faces left, so the player on the
    /// left is mirrored to turn right and the opponent on the right keeps its natural leftward
    /// heading — the two are drawn facing opposite ways, which is the whole point of the face-off.
    func testTheCombatantsFaceEachOther() {
        XCTAssertTrue(BattleView.faces(.player), "player on the left is mirrored to face right")
        XCTAssertFalse(BattleView.faces(.opponent), "opponent on the right keeps its leftward art")
        XCTAssertNotEqual(BattleView.faces(.player), BattleView.faces(.opponent))
    }
}

/// AC4's haptic. The Simulator has no haptics and `simctl` cannot capture one, so what is checkable
/// is that the battle fires exactly one tap, that it lands at the RESULT rather than on appear, and
/// that it carries the outcome — a win and a loss must be tellable apart without looking.
@MainActor
final class BattleViewHapticTests: XCTestCase {
    /// Long enough that a tap in the wrong beat is unambiguous in elapsed time, short enough that the
    /// whole battle runs in well under a second.
    private static let beat: TimeInterval = 0.05

    private func makeBout(playerPower: Int, opponentPower: Int, seed: UInt64) -> BattleBout {
        var generator = SeededGenerator(seed: seed)
        return BattleBout(
            player: DigimonPresentation(displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            opponent: DigimonPresentation(displayName: "Foe", stage: .adult, spriteFile: "Greymon"),
            report: BattleEngine.resolve(playerPower: playerPower, opponentPower: opponentPower,
                                         using: &generator)
        )
    }

    private func playOut(_ bout: BattleBout) async -> (taps: [Bool], firstTapAt: TimeInterval?) {
        var taps: [Bool] = []
        var firstTapAt: TimeInterval?
        let start = Date()

        let view = BattleView(
            bout: bout,
            onFinish: {},
            playHaptic: { won in
                taps.append(won)
                if firstTapAt == nil { firstTapAt = Date().timeIntervalSince(start) }
            },
            introDuration: Self.beat,
            turnDuration: Self.beat
        )
        await view.run()
        return (taps, firstTapAt)
    }

    /// Exactly one tap, and only after the stare-down and every exchange have had their beats — a
    /// haptic moved to `onAppear` would land near zero and fail this.
    func testOneHapticFiresAtTheResult() async throws {
        let bout = makeBout(playerPower: 60, opponentPower: 20, seed: 11)
        let (taps, firstTapAt) = await playOut(bout)

        XCTAssertEqual(taps.count, 1, "one tap, not one per exchange and not none")
        let tap = try XCTUnwrap(firstTapAt)
        XCTAssertGreaterThanOrEqual(tap, Self.beat * Double(bout.report.turns.count + 1) * 0.8,
                                    "the tap lands at the result, after every exchange")
    }

    /// The tap carries the outcome, so a win and a loss feel different on the wrist. Both directions,
    /// or a hard-coded `.success` would pass on the win alone.
    func testTheHapticCarriesTheOutcome() async {
        let won = await playOut(makeBout(playerPower: 60, opponentPower: 20, seed: 11))
        let lost = await playOut(makeBout(playerPower: 20, opponentPower: 60, seed: 11))

        XCTAssertEqual(won.taps, [true], "a win taps as a win")
        XCTAssertEqual(lost.taps, [false], "a loss taps as a loss")
    }
}

// MARK: - AC5: what a battle does, and does not do, to the saved game

private func makeState(stage: Stage = .child, strength: Int = 0) -> GameState {
    let state = GameState(currentDigimonId: "agumon", stage: stage,
                          now: Date(timeIntervalSinceReferenceDate: 600_000))
    state.strengthStat = strength
    return state
}

private func report(playerWon: Bool) -> BattleReport {
    BattleReport(playerPower: 10, opponentPower: 10,
                 turns: [BattleTurn(attacker: playerWon ? .player : .opponent,
                                    damage: 10, defenderRemainingHitPoints: 0)],
                 winner: playerWon ? .player : .opponent)
}

final class BattleRecordTests: XCTestCase {

    func testAWinIsRecordedAsAWin() {
        let state = makeState()

        state.recordBattle(report(playerWon: true))

        XCTAssertEqual(state.battleWins, 1)
        XCTAssertEqual(state.battleLosses, 0)
    }

    func testALossIsRecordedAsALoss() {
        let state = makeState()

        state.recordBattle(report(playerWon: false))

        XCTAssertEqual(state.battleWins, 0)
        XCTAssertEqual(state.battleLosses, 1)
    }

    /// AC5, stated directly: a loss touches the record and NOTHING else. Every field a loss could
    /// plausibly have been made to punish is asserted unchanged — a Digimon must never be killed or
    /// marked as neglected for losing a fight it was allowed to pick.
    func testLosingCausesNeitherDeathNorACareMistake() {
        let state = makeState()
        state.careMistakeCount = 2
        state.hunger = 1

        state.recordBattle(report(playerWon: false))

        XCTAssertEqual(state.healthStatus, .healthy, "losing never kills and never sickens")
        XCTAssertNil(state.sickSince, "and never starts the illness that would")
        XCTAssertNil(state.diedAt)
        XCTAssertEqual(state.careMistakeCount, 2, "losing is not neglect")
        XCTAssertEqual(state.hunger, 1, "and does not starve it either")
    }

    /// A losing STREAK is still not fatal. The single-loss test above could pass on a rule that kills
    /// after five, which is exactly the sort of "fair" punishment AC5 rules out.
    func testALosingStreakStillCausesNeitherDeathNorACareMistake() {
        let state = makeState()

        for _ in 0..<25 {
            state.recordBattle(report(playerWon: false))
        }

        XCTAssertEqual(state.battleLosses, 25)
        XCTAssertEqual(state.healthStatus, .healthy)
        XCTAssertEqual(state.careMistakeCount, 0)
        XCTAssertNil(state.diedAt)
    }

    /// A battle is resolved from the power US-030 computes, so training really does change the fight.
    func testTrainingRaisesThePowerABattleIsResolvedFrom() {
        let untrained = makeState(strength: 0)
        let trained = makeState(strength: 10)

        XCTAssertGreaterThan(trained.battlePower, untrained.battlePower)
    }
}

// MARK: - Through the real model and the real store

private final class EmptySampleFetcher: HealthSampleFetching, @unchecked Sendable {
    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] { [] }
}

private final class EmptySleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class BattleApplyTests: XCTestCase {
    private var storeDirectory: URL!

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

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Mid-morning, and stated as a wall-clock time rather than an interval on purpose: the fallback
    /// sleep window is 22:00-07:00, so a bare `timeIntervalSinceReferenceDate` can silently land the
    /// whole suite inside it and block every battle for the reason a sleeping Digimon is blocked.
    private static let now: Date = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "2026-07-17 10:00")!
    }()

    /// A three-node fixture: an egg, the Child fought as, and one Adult to fight. Small on purpose —
    /// with a single eligible opponent, matchmaking cannot be the thing that varies between runs.
    private func fixtureGraph() -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(id: "egg", displayName: "Egg", stage: .digitama, spriteFile: "Agu_Digitama",
                          evolutions: [EvolutionEdge(to: "hero", minEnergy: 50, maxCareMistakes: 99)]),
            EvolutionNode(id: "hero", displayName: "Hero", stage: .child, spriteFile: "Agumon"),
            EvolutionNode(id: "foe", displayName: "Foe", stage: .adult, spriteFile: "Greymon")
        ])
    }

    /// A model over a real store, seeded at "hero" with the given strength and a FIXED battle seed.
    private func makeModel(storeName: String = "Battle",
                           strength: Int,
                           seed: UInt64) throws -> (MainScreenModel, GameStore) {
        let store = try GameStore(url: storeDirectory.appendingPathComponent("\(storeName).store"))
        let state = try store.loadOrCreate(digitamaId: "hero", now: Self.now)
        state.stage = .child
        state.strengthStat = strength
        // US-027: the empty readers would otherwise have the audit charge a mistake for every day
        // since the epoch, which would sicken the Digimon before a single battle.
        state.healthDataLastSeen = Self.now
        state.hungerUpdatedAt = Self.now
        state.stageEnteredDate = Self.now
        try store.save()

        let model = MainScreenModel(
            makeStore: { [store] in store },
            graph: fixtureGraph(),
            energySource: HealthEnergySource(
                todayReader: TodayHealthReader(fetcher: EmptySampleFetcher(), calendar: Self.calendar),
                sleepReader: LastNightSleepReader(fetcher: EmptySleepFetcher(), calendar: Self.calendar)
            ),
            calendar: Self.calendar,
            now: { Self.now },
            chooseStartingDigitama: { $0.first },
            makeBattleGenerator: { SeededGenerator(seed: seed) }
        )
        return (model, store)
    }

    /// AC1/AC2 through the shipped path: tapping Battle picks the roster opponent and publishes an
    /// already-resolved bout for the screen to replay.
    func testBattlingPublishesAResolvedBoutAgainstARosterOpponent() async throws {
        let (model, _) = try makeModel(strength: 8, seed: 1)
        await model.start()
        XCTAssertNil(model.pendingBattle, "nothing before the button is tapped")

        let bout = try XCTUnwrap(model.battle(), "the battle should have started")

        XCTAssertEqual(bout.player.displayName, "Hero")
        XCTAssertEqual(bout.opponent.displayName, "Foe", "the only eligible opponent in the roster")
        XCTAssertEqual(bout.opponent.spriteFile, "Greymon")
        XCTAssertFalse(bout.report.turns.isEmpty, "already resolved before a frame is drawn")
        XCTAssertEqual(model.pendingBattle, bout)
    }

    /// AC2/AC6 through the model, not just the engine: a fixed seed gives a fixed battle, so the
    /// injection point the app really uses is the one being pinned.
    func testTheSameSeedGivesTheSameBattleThroughTheModel() async throws {
        let (first, _) = try makeModel(storeName: "A", strength: 8, seed: 4242)
        await first.start()
        let (second, _) = try makeModel(storeName: "B", strength: 8, seed: 4242)
        await second.start()

        XCTAssertEqual(first.battle(), second.battle())
    }

    /// The result is filed once, when the user dismisses it, and the screen comes down with it.
    func testFinishingABattleRecordsItOnceAndClearsTheScreen() async throws {
        let (model, store) = try makeModel(strength: 8, seed: 1)
        await model.start()
        let bout = try XCTUnwrap(model.battle())

        model.finishBattle()

        XCTAssertNil(model.pendingBattle, "the battle screen comes down")
        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.battleWins + state.battleLosses, 1, "recorded exactly once")
        XCTAssertEqual(bout.report.playerWon, state.battleWins == 1)

        // A second dismissal — a double tap on Done — must not file the same battle again.
        model.finishBattle()
        XCTAssertEqual(state.battleWins + state.battleLosses, 1, "no double count")

        // And it survives the app being closed, which is what makes it usable as `minBattleWins`.
        try store.save()
        let reopened = try GameStore(url: storeDirectory.appendingPathComponent("Battle.store"))
        // `loadOrCreate` finds the saved game rather than creating one — the same call the app makes
        // on launch, which is the path the record has to survive.
        let saved = try reopened.loadOrCreate(digitamaId: "egg", now: Self.now)
        XCTAssertEqual(saved.battleWins + saved.battleLosses, 1)
    }

    /// AC5 through the whole shipped path: a Digimon that LOSES a battle it really fought is left
    /// alive, healthy and unmarked. The seed is chosen so the underdog genuinely loses.
    func testLosingAFoughtBattleLeavesTheDigimonAliveAndUnmarked() async throws {
        // An untrained Child against an Adult: the pinned seed below produces a loss.
        let (model, _) = try makeModel(strength: 0, seed: 3)
        await model.start()

        let bout = try XCTUnwrap(model.battle())
        XCTAssertFalse(bout.report.playerWon, "this fixture is meant to be a loss")

        model.finishBattle()

        let state = try XCTUnwrap(model.state)
        XCTAssertEqual(state.battleLosses, 1)
        XCTAssertEqual(state.healthStatus, .healthy, "losing never kills or sickens")
        XCTAssertEqual(state.careMistakeCount, 0, "and is never a care mistake")
        XCTAssertNil(state.diedAt)

        // A refresh is where sickness and death are actually settled (US-028/US-029), so the loss
        // must survive one — a punishment deferred to the next foregrounding is still a punishment.
        await model.refresh()
        XCTAssertEqual(state.healthStatus, .healthy)
        XCTAssertEqual(state.careMistakeCount, 0)
    }

    /// A sleeping Digimon is not dragged into a fight — the same block feeding and training apply,
    /// with the same reason shown and the same waking-early mistake charged.
    func testASleepingDigimonCannotBeBattled() async throws {
        let (model, _) = try makeModel(strength: 8, seed: 1)
        await model.start()
        model.isAsleep = true

        XCTAssertNil(model.battle(), "no battle while it sleeps")
        XCTAssertNil(model.pendingBattle)
        XCTAssertEqual(model.actionMessage, "Asleep — let it rest.")
        XCTAssertEqual(model.state?.careMistakeCount, 1, "prodding it awake is the usual mistake")
    }

    /// A dead Digimon cannot battle. The memorial covers the button, but the guard is what makes that
    /// a rule rather than a layout accident.
    func testADeadDigimonCannotBeBattled() async throws {
        let (model, _) = try makeModel(strength: 8, seed: 1)
        await model.start()
        model.state?.healthStatus = .dead

        XCTAssertNil(model.battle())
        XCTAssertNil(model.pendingBattle)
        XCTAssertEqual(model.state?.battleWins, 0)
        XCTAssertEqual(model.state?.battleLosses, 0)
    }
}
