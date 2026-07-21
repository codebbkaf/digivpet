import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

/// One battle, ready to be shown: who is fighting, and the already-resolved blow-by-blow.
///
/// Resolution happens BEFORE the view appears (`BattleEngine.resolve`), so the screen is a replay of
/// a decided outcome rather than a place where dice are rolled. That split is what lets a test assert
/// the winner without a view, and the view animate without knowing the rules.
struct BattleBout: Equatable {
    let player: DigimonPresentation
    let opponent: DigimonPresentation
    let report: BattleReport
}

/// The full-screen battle: two Digimon trading blows, then the result.
///
/// Shown as an overlay above the main screen for the same reason `EvolutionCeremonyView` and
/// `MemorialView` are — it is a moment, not a place, and the Feed and Train buttons underneath must
/// not be tappable through it.
///
/// Each exchange holds `turnDuration`, during which the ATTACKER holds the attack frame (11) and the
/// DEFENDER plays the hurt loop (9 <-> 10) — the PRD's frame assignment, and the reason the resolved
/// report carries `attacker` per turn rather than only a winner. The result then holds until the user
/// dismisses it: a button rather than a timer, as on the memorial, because a result that scrolls past
/// unread is a battle that never happened as far as the user is concerned.
struct BattleView: View {
    let bout: BattleBout
    let onFinish: () -> Void

    /// The tap at the result — `.success` on a win, `.failure` on a loss. Injected for the same
    /// reason `EvolutionCeremonyView.playHaptic` is: it is the one acceptance criterion no
    /// screenshot can show, so a test spies on it instead.
    var playHaptic: (Bool) -> Void = BattleView.resultHaptic

    /// Where the replay has got to: the intro, the index of the exchange being shown, or the result.
    private enum Beat: Equatable {
        case intro
        case turn(Int)
        case result
    }
    @State private var beat: Beat = .intro

    /// How long the stare-down and each exchange hold. Injected for the same reason the ceremony's
    /// beats are — a test drives the whole battle in milliseconds instead of waiting it out.
    var introDuration: TimeInterval = 1.0
    var turnDuration: TimeInterval = 0.7

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if beat == .result {
                result
            } else {
                arena
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await run() }
    }

    /// The two combatants facing off: the player on the left facing right, the opponent on the right
    /// facing left, so the arena reads as a fight rather than as two Digimon both looking the same way.
    private var arena: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                DigimonSpriteView(stage: bout.player.spriteStage, name: bout.player.spriteFile,
                                  animation: animation(for: .player), scale: 3,
                                  flipped: Self.faces(.player))
                DigimonSpriteView(stage: bout.opponent.spriteStage, name: bout.opponent.spriteFile,
                                  animation: animation(for: .opponent), scale: 3,
                                  flipped: Self.faces(.opponent))
            }

            Text(bout.opponent.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            // The hit points left on each side, so the exchanges read as progress rather than as two
            // sprites twitching at each other.
            Text("\(hitPoints(.player)) — \(hitPoints(.opponent))")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
    }

    /// The outcome: the winner's happy frame (7) on a win, the player's hurt frame on a loss.
    private var result: some View {
        VStack(spacing: 6) {
            DigimonSpriteView(
                stage: bout.player.spriteStage,
                name: bout.player.spriteFile,
                animation: .still(Self.resultFrame(playerWon: bout.report.playerWon)),
                scale: 4
            )

            Text(bout.report.playerWon ? "Victory!" : "Defeat")
                .font(.headline)
                .foregroundStyle(bout.report.playerWon ? Color.orange : Color.secondary)

            // Said plainly, because it is the reassurance that makes losing tryable: a loss costs
            // nothing but the record. See `GameState.recordBattle`.
            Text(bout.report.playerWon
                 ? "\(bout.opponent.displayName) is beaten."
                 : "\(bout.opponent.displayName) was too strong.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(2)

            Button(action: onFinish) {
                Label("Done", systemImage: "checkmark")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .padding(.top, 2)
        }
    }

    /// What `side` is doing during the exchange on screen.
    private func animation(for side: BattleSide) -> SpriteAnimation {
        guard case .turn(let index) = beat, index < bout.report.turns.count else { return .idle }
        return Self.animation(for: side, during: bout.report.turns[index])
    }

    /// `side`'s hit points as of the exchange on screen.
    private func hitPoints(_ side: BattleSide) -> Int {
        guard case .turn(let index) = beat else { return BattleEngine.startingHitPoints }
        return Self.hitPoints(side, afterTurn: index, of: bout.report.turns)
    }

    /// Which way `side` should be drawn, as a pure function so the face-off can be asserted without a
    /// view: the two combatants look AT each other, the player on the left facing right, the opponent
    /// on the right facing left.
    ///
    /// The pack's art faces LEFT (see `DigimonSpriteView.flipped` and `SpriteWanderer`), so the
    /// player is the side that gets mirrored to turn toward the opponent, and the opponent keeps its
    /// natural leftward heading. `.interpolation(.none)` sits ahead of that mirror on the `Image`, so
    /// the pixels stay crisp whichever way a sprite faces.
    static func faces(_ side: BattleSide) -> Bool {
        side == .player
    }

    /// The PRD's frame assignment, as a pure function: the attacker holds the attack frame (11) and
    /// the defender plays the hurt loop (9 <-> 10).
    ///
    /// Static and separate from the view for the same reason `BattleEngine` is separate from both —
    /// this mapping IS the acceptance criterion, and a screenshot can only ever show one instant of
    /// it. A test asserts every turn of a real battle against this instead.
    static func animation(for side: BattleSide, during turn: BattleTurn) -> SpriteAnimation {
        turn.attacker == side ? .still(.attack) : .hurt
    }

    /// `side`'s hit points once the exchange at `index` has been played out.
    ///
    /// Derived from the report rather than tracked in `@State`, so the number on screen can never
    /// drift out of step with the frames animating beside it.
    static func hitPoints(_ side: BattleSide, afterTurn index: Int, of turns: [BattleTurn]) -> Int {
        let taken = turns.prefix(index + 1)
            .filter { $0.attacker == side.other }
            .reduce(0) { $0 + $1.damage }
        return max(0, BattleEngine.startingHitPoints - taken)
    }

    /// The frame the result screen holds: the happy frame (7) on a win, a hurt frame on a loss.
    ///
    /// Held still on a loss rather than looping, because the battle is over and nothing is hitting it
    /// any more. Static for the same reason `animation(for:during:)` is — it is the criterion itself.
    static func resultFrame(playerWon: Bool) -> SpriteFrame {
        playerWon ? .happy : .hurt1
    }

    /// The stare-down, every exchange in order, then the result and its haptic. Not private so a test
    /// can drive it directly at a fast pacing with a haptic spy.
    func run() async {
        try? await Task.sleep(for: .seconds(introDuration))

        for index in bout.report.turns.indices {
            withAnimation(.easeInOut(duration: 0.15)) { beat = .turn(index) }
            try? await Task.sleep(for: .seconds(turnDuration))
        }

        playHaptic(bout.report.playerWon)
        withAnimation(.easeOut(duration: 0.3)) { beat = .result }
    }

    /// The real haptic. `.success` on a win and `.failure` on a loss, so the result is felt without
    /// looking — the same two taps the ceremony and the memorial use, for the same reason. No-ops
    /// where `WKInterfaceDevice` is unavailable (never on watchOS).
    static func resultHaptic(playerWon: Bool) {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(playerWon ? .success : .failure)
        #endif
    }
}

#Preview {
    BattleView(
        bout: BattleBout(
            player: DigimonPresentation(displayName: "Agumon", stage: .child, spriteFile: "Agumon"),
            opponent: DigimonPresentation(displayName: "Greymon", stage: .adult, spriteFile: "Greymon"),
            report: {
                var generator = SeededGenerator(seed: 42)
                return BattleEngine.resolve(playerPower: 40, opponentPower: 33, using: &generator)
            }()
        ),
        onFinish: {},
        playHaptic: { _ in }
    )
}
