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

    /// Each side's attack identity from the `MoveCatalog` (US-070), resolved once when the bout is
    /// built — where the ids are still to hand — so the view never has to reach for the graph or a
    /// bundle to know what colour a projectile flies. Defaulted to `Move.placeholder` so a test or a
    /// preview that only cares about the frames need not name a move.
    var playerMove: Move = .placeholder
    var opponentMove: Move = .placeholder

    /// What scaled the two powers this fight was resolved from (US-093): the typing matchup and the
    /// pre-battle training grade, factors and all. Carried rather than recomputed because it is the
    /// arithmetic the battle was ACTUALLY fought with — see `BattleModifiers`, whose factors are kept
    /// for exactly this. Nil for a bout built without a matchup, which is every test and preview that
    /// only cares about the frames.
    var matchup: BattleMatchup?

    /// The attacking side's move, so the projectile is tinted and shaped by whoever is swinging.
    func move(for side: BattleSide) -> Move {
        side == .player ? playerMove : opponentMove
    }
}

/// Where the two combatants stand and how far a shot has to travel to reach the other one.
///
/// Kept out of the view because "is there room to watch something cross the gap" is arithmetic
/// against a screen width, and a screenshot can only ever answer it for the one watch it was taken
/// on. Everything here is derived from the width the arena was actually given, so the same numbers
/// hold on a 42mm and a 46mm without a second set of literals to keep in step.
enum BattleArenaLayout {
    /// The scale the combatants are drawn at, and what one sprite therefore measures on a side.
    static let spriteScale: CGFloat = 3
    static var spriteSide: CGFloat { CGFloat(SpriteSheet.frameSize) * spriteScale }

    /// How far each sprite stops short of the bezel. Small on purpose — the point of the story is to
    /// push them apart — but not zero, so a sprite does not appear to be leaning on the rounded edge.
    static let bezelInset: CGFloat = 4

    /// The two screen widths this has to hold on: 41/42mm and 46mm, in points. Named so the test can
    /// assert the arithmetic on both rather than on whichever watch the screenshot came from.
    static let narrowestScreenWidth: CGFloat = 176
    static let widestScreenWidth: CGFloat = 208

    /// The clear space between the two sprites' INNER edges — the room a projectile has to cross,
    /// and the thing US-090 is really about. Floored at zero for a screen too narrow to hold both.
    static func gap(inWidth width: CGFloat) -> CGFloat {
        max(0, width - 2 * bezelInset - 2 * spriteSide)
    }

    /// How far the projectile travels: centre of the attacker to centre of the defender, which is
    /// the gap plus one sprite. Derived rather than a literal, so the flight still starts at the
    /// attacker and ends at the defender on a screen the literal was never measured against.
    static func projectileSpan(inWidth width: CGFloat) -> CGFloat {
        max(0, width - 2 * bezelInset - spriteSide)
    }
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

    /// How long the stare-down and each exchange hold, and how long a shot spends in the air. Injected
    /// for the same reason the ceremony's beats are — a test drives the whole battle in milliseconds
    /// instead of waiting it out.
    var introDuration: TimeInterval = BattleView.defaultIntroDuration
    var turnDuration: TimeInterval = BattleView.defaultTurnDuration
    var flightDuration: TimeInterval = BattleView.defaultFlightDuration

    /// The shipped pacing (US-091). Named constants rather than literals on the properties above so a
    /// test can assert the one invariant that makes an exchange readable — the shot LANDS inside the
    /// turn that threw it, `defaultFlightDuration < defaultTurnDuration` — instead of trusting three
    /// numbers scattered across two files not to drift apart. `ContentView` reads these too, so the
    /// app and the defaults cannot disagree.
    ///
    /// The flight is a hair short of the turn on purpose: the remaining ~0.3s is the beat where the
    /// projectile has hit and the defender's hurt loop is the only thing moving, which is what makes
    /// an exchange read as a hit rather than as a flicker.
    static let defaultIntroDuration: TimeInterval = 1.2
    static let defaultTurnDuration: TimeInterval = 1.4
    static let defaultFlightDuration: TimeInterval = 1.1

    /// Debug-only: the single exchange to skip straight to after the intro, instead of playing every
    /// turn in order. nil in the app — every battle plays out normally. Set by `ContentView`'s
    /// `-battleSignatureDemo` to the KNOCKOUT turn, which is never turn 0, so a `simctl` screenshot can
    /// land on the finishing blow (US-073 AC7). It still animates the REAL turn of the REAL report — HP
    /// and frames are all derived from the report prefix — so this stages where the screenshot lands,
    /// not what it shows.
    var demoFocusTurn: Int? = nil

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

    /// The two combatants facing off at OPPOSITE ends of the screen: the player against the leading
    /// edge facing right, the opponent against the trailing edge facing left, so the arena reads as a
    /// fight rather than as two Digimon both looking the same way — and so there is room to watch a
    /// shot cross the gap instead of it appearing and landing in the same instant.
    ///
    /// A `GeometryReader` rather than a fixed span: the arena is measured, and both the standing
    /// positions and the projectile's flight come off that one measurement, so they cannot disagree
    /// about where the two sprites are on a screen size nobody photographed.
    private var arena: some View {
        GeometryReader { geometry in
            VStack(spacing: 6) {
                ZStack {
                    HStack(spacing: 0) {
                        DigimonSpriteView(stage: bout.player.spriteStage, name: bout.player.spriteFile,
                                          animation: animation(for: .player),
                                          scale: BattleArenaLayout.spriteScale,
                                          flipped: Self.faces(.player))
                        Spacer(minLength: 0)
                        DigimonSpriteView(stage: bout.opponent.spriteStage, name: bout.opponent.spriteFile,
                                          animation: animation(for: .opponent),
                                          scale: BattleArenaLayout.spriteScale,
                                          flipped: Self.faces(.opponent))
                    }
                    .padding(.horizontal, BattleArenaLayout.bezelInset)

                    projectile(inWidth: geometry.size.width)
                }
                .overlay(alignment: .top) { signatureBanner }

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
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// The attacker's projectile mid-flight (US-072): drawn only during an exchange, tinted and
    /// shaped by the attacker's `MoveCatalog` move, sliding from the attacker toward the defender as
    /// `projectileProgress` runs 0 → 1 over `turnDuration`. Its direction is read off `faces(attacker)`
    /// so the opponent's shots fly leftward out of its front rather than backward out of its back.
    ///
    /// On the FINISHING blow — the one turn where `isKnockout` is true — it becomes the winner's
    /// `signatureSymbol`, drawn visibly larger (US-073), so the killing blow reads as special rather
    /// than as one more identical shot.
    ///
    /// `.interpolation(.none)` is not needed here — an SF Symbol is a vector, not the pixel art the
    /// sprites are, so scaling it stays crisp on its own.
    @ViewBuilder private func projectile(inWidth arenaWidth: CGFloat) -> some View {
        if case .turn(let index) = beat, index < bout.report.turns.count {
            let move = bout.move(for: bout.report.turns[index].attacker)
            let knockout = Self.isKnockoutTurn(index, of: bout.report.turns)
            Image(systemName: knockout ? move.signatureSymbol : move.projectileSymbol)
                .font(.system(size: knockout ? Self.signatureSize : Self.projectileSize, weight: .bold))
                .foregroundStyle(move.tint.color)
                .offset(x: Self.projectileOffset(
                    rightward: Self.faces(bout.report.turns[index].attacker),
                    progress: projectileProgress,
                    span: BattleArenaLayout.projectileSpan(inWidth: arenaWidth)))
        }
    }

    /// The winner's named finisher, shown as a banner across the top of the arena on the knockout turn
    /// ONLY (US-073) — the instant a win is decided gets its move said out loud. Tinted to match the
    /// signature glyph flying beneath it, and drawn on the same pure `isKnockoutTurn` test the
    /// projectile switches on, so banner and signature symbol can never disagree about which turn ends it.
    @ViewBuilder private var signatureBanner: some View {
        if case .turn(let index) = beat, Self.isKnockoutTurn(index, of: bout.report.turns) {
            let move = bout.move(for: bout.report.turns[index].attacker)
            Text(move.signatureName)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(move.tint.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.65), in: Capsule())
                .offset(y: -6)
        }
    }

    /// The ordinary projectile's glyph size, and the larger size the signature move is drawn at on the
    /// finishing blow. Static and separate so a test can assert the signature IS visibly larger (US-073
    /// AC2) rather than trusting the two literals not to drift together.
    static let projectileSize: CGFloat = 15
    static let signatureSize: CGFloat = 30

    /// Whether the exchange at `index` is the finishing blow — the one turn the signature move replaces
    /// the ordinary projectile on. Pure, so US-073's "renders on the knockout turn, and only then" can
    /// be asserted against a seeded `BattleReport` without a view. Bounds-checked so an out-of-range
    /// index (never produced by `run()`, but cheap to rule out) is simply "not a knockout".
    static func isKnockoutTurn(_ index: Int, of turns: [BattleTurn]) -> Bool {
        turns.indices.contains(index) && turns[index].isKnockout
    }

    /// How far along its flight the current projectile is, 0 at the attacker and 1 at the defender.
    /// Reset to 0 and re-animated on every exchange in `run()`.
    @State private var projectileProgress: CGFloat = 0

    /// The projectile's horizontal offset from the arena centre, as a pure function so the flight can
    /// be asserted without a view. A rightward (player) shot runs from `-span/2` to `+span/2`; a
    /// leftward (opponent) shot mirrors it, from `+span/2` back to `-span/2`.
    static func projectileOffset(rightward: Bool, progress: CGFloat, span: CGFloat) -> CGFloat {
        rightward ? span * (progress - 0.5) : span * (0.5 - progress)
    }

    /// The curve a shot flies on: eased, so it leaves the attacker with a wind-up and arrives with a
    /// settle rather than sliding across at a constant crawl (US-091). Static and separate from the
    /// `withAnimation` call for the same reason `faces(_:)` is — `Animation` is `Equatable`, so a test
    /// can assert this IS `.easeInOut` and is NOT `.linear`, which no screenshot can show.
    static func flightAnimation(duration: TimeInterval) -> Animation {
        .easeInOut(duration: duration)
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

        let indices = demoFocusTurn.map { [$0] } ?? Array(bout.report.turns.indices)
        for index in indices where bout.report.turns.indices.contains(index) {
            // Snap the projectile back to the attacker (no animation), then fly it across the gap over
            // `flightDuration` — which is SHORTER than the turn, so the shot lands with a beat of the
            // defender's hurt loop still to run before the next exchange begins. Both are injected, so
            // a test still runs a whole battle in milliseconds.
            projectileProgress = 0
            withAnimation(.easeInOut(duration: 0.15)) { beat = .turn(index) }
            withAnimation(Self.flightAnimation(duration: flightDuration)) { projectileProgress = 1 }
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

extension MoveTint {
    /// The SwiftUI colour a move is drawn in. Deferred here from US-070 (`MoveCatalog` is pure
    /// Foundation and draws nothing) to the renderer that first needs it. The enum's names mirror
    /// SwiftUI's system colours, so the mapping is exhaustive with no `default:` — adding a tint to
    /// `MoveTint` is a compile error here until it is given a colour, rather than silently drawing grey.
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        case .white: return .white
        }
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
