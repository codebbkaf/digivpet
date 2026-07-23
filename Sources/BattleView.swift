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

    /// How much meat this win dropped into the global larder (US-175), already clamped to the cap.
    /// Zero for a loss and for any bout built without one — a preview or a test that only cares
    /// about the frames — so the result screen's meat line is present exactly when a win banked meat.
    var meatGained: Int = 0

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
/// Each exchange holds `turnDuration`, during which the ATTACKER swings — the attack frame (11)
/// looped against walk1, so the blow is a moving drawing rather than one frame held for the whole
/// exchange — and the DEFENDER stands in its idle loop until the shot LANDS, and plays the hurt loop
/// (9 <-> 10) only from that instant on (US-105). That is the PRD's frame assignment plus the one
/// thing it left out: the flinch is caused by the impact, so it cannot begin before it. Both are the
/// reason the resolved report carries `attacker` per turn rather than only a winner, and the reason
/// `hasLanded` is view state rather than a local. The result then holds until the user
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
    /// The flight is a hair short of the turn on purpose: the remaining ~0.3s is the tail where the
    /// shot has LANDED and is off screen entirely (US-104), leaving the defender flinching alone with
    /// nothing else moving. That beat is what makes an exchange read as a blow landing rather than as
    /// a glyph flickering past; a projectile still drawn during it would read as parked on the
    /// defender instead of as having hit it.
    static let defaultIntroDuration: TimeInterval = 1.2
    static let defaultTurnDuration: TimeInterval = 1.4
    static let defaultFlightDuration: TimeInterval = 1.1

    /// How long the shot is actually in the air. `flightDuration`, but never longer than the turn
    /// that threw it: the shipped constants already satisfy that (`defaultFlightDuration <
    /// defaultTurnDuration`, asserted in `BattlePacingTests`), and the clamp is for an INJECTED
    /// pacing, where a flight outlasting its turn would leave the previous shot still airborne when
    /// the next exchange snaps it back to the attacker — precisely the reverse slide this story
    /// removes. Clamped rather than trapped because a test's pacing is allowed to be silly.
    private var flight: TimeInterval { min(flightDuration, max(0, turnDuration)) }

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
                .overlay(alignment: .top) { matchupBanner }

                Text(bout.opponent.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                // The hit points left on each side as a dash bar (US-188): its total is the combatant's
                // MAX HP and its solid count the HP left, so a landed blow visibly knocks dashes off and
                // the exchanges read as progress rather than as two sprites twitching at each other. No
                // number anywhere — the bar IS the readout, the same language every value bar speaks.
                HStack(spacing: 8) {
                    hpBar(for: .player)
                    hpBar(for: .opponent)
                }
                .padding(.horizontal, BattleArenaLayout.bezelInset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// The attacker's projectile mid-flight (US-072): drawn only while an exchange's shot is in the
    /// AIR, tinted and shaped by the attacker's `MoveCatalog` move, sliding from the attacker toward
    /// the defender as `projectileProgress` runs 0 → 1 over `flightDuration`. Its direction is read
    /// off `faces(attacker)` so the opponent's shots fly leftward out of its front rather than
    /// backward out of its back.
    ///
    /// `!hasLanded` is US-104's other half: the moment the shot reaches the defender it is gone, so
    /// the turn's tail shows a flinch with an empty gap rather than a glyph parked on the defender.
    ///
    /// On the FINISHING blow — the one turn where `isKnockout` is true — it becomes the winner's
    /// `signatureSymbol`, drawn visibly larger (US-073), so the killing blow reads as special rather
    /// than as one more identical shot.
    ///
    /// `.interpolation(.none)` is not needed here — an SF Symbol is a vector, not the pixel art the
    /// sprites are, so scaling it stays crisp on its own.
    @ViewBuilder private func projectile(inWidth arenaWidth: CGFloat) -> some View {
        if case .turn(let index) = beat, index < bout.report.turns.count, !hasLanded {
            let move = bout.move(for: bout.report.turns[index].attacker)
            let knockout = Self.isKnockoutTurn(index, of: bout.report.turns)
            Image(systemName: knockout ? move.signatureSymbol : move.projectileSymbol)
                .font(.system(size: knockout ? Self.signatureSize : Self.projectileSize, weight: .bold))
                .foregroundStyle(move.tint.color)
                .offset(x: Self.projectileOffset(
                    rightward: Self.faces(bout.report.turns[index].attacker),
                    progress: projectileProgress,
                    span: BattleArenaLayout.projectileSpan(inWidth: arenaWidth)))
                // Each exchange's shot is its OWN view. Without this every turn reuses one Image, so
                // the animated `beat` change interpolates it from the last turn's tint and offset to
                // this one's — a glyph sliding across the arena between exchanges, which is US-104's
                // reverse travel wearing a different hat. Photographed at the turn boundary before
                // this line existed; see the story's notes.
                .id(index)
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

    /// The stare-down's matchup banner (US-094): each combatant's ELEMENT badge over its own head,
    /// and what the arithmetic makes of the pairing.
    ///
    /// The INTRO beat only. Once the exchanges start, the top of the arena belongs to the signature
    /// banner and the screen belongs to the fight — the matchup is context for the stare-down, and
    /// leaving it up would put two banners in the same place on the knockout turn.
    ///
    /// The attribute badges are deliberately not here: two badges a side is four capsules across a
    /// 42mm screen, and the element is the axis worth a quarter of the fight. The attribute still
    /// gets its say on the result screen, where there is a line to spell it out on.
    @ViewBuilder private var matchupBanner: some View {
        if beat == .intro, let matchup = bout.matchup {
            VStack(spacing: 1) {
                HStack(spacing: 0) {
                    TypeBadge.element(matchup.playerType.element)
                    Spacer(minLength: 4)
                    TypeBadge.element(matchup.opponentType.element)
                }

                if let caption = BattleBreakdown.effectivenessCaption(matchup.elementEffectiveness) {
                    Text(caption)
                        .font(.system(size: BattleBreakdownLayout.textSize, weight: .semibold))
                        // The result screen's two colours, so "Super effective" at the stare-down and
                        // "Victory!" at the end are plainly the same good news.
                        .foregroundStyle(matchup.elementEffectiveness == .advantage
                                         ? Color.orange : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(BattleBreakdownLayout.minimumScale)
                }
            }
            .padding(.horizontal, BattleArenaLayout.bezelInset)
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

    /// Whether this exchange's shot has reached the defender yet: false for the first `flight`
    /// seconds of every turn, true for the tail after it, and false again the instant the next turn
    /// begins. The impact instant as view state, which is what takes the projectile off screen here
    /// and what US-105 hangs the defender's hurt loop on.
    @State private var hasLanded = false

    /// Whether the projectile is drawn `elapsed` seconds into an exchange: in the air once the turn
    /// has begun, and gone from the moment it lands. Pure and view-free — the same rule `run()` plays
    /// out with a sleep and `hasLanded` — so "no parked glyph, no reverse travel" is assertable
    /// against the clock rather than against a screenshot, the way `isKnockoutTurn` and
    /// `projectileOffset` already are.
    ///
    /// Half-open at BOTH ends on purpose. At `elapsed >= flightDuration` the shot has landed and is
    /// already gone — that is the half of US-104 where the glyph sat on the defender for the turn's
    /// last ~0.3s. At `elapsed <= 0` the turn has not started, so there is nothing yet to draw and
    /// certainly nothing left over from the turn before.
    static func isProjectileVisible(atElapsed elapsed: TimeInterval,
                                    flightDuration: TimeInterval) -> Bool {
        elapsed > 0 && elapsed < flightDuration
    }

    /// One change `run()` makes to the projectile, in the order it is made.
    ///
    /// Reported to `onProjectileChange` for the same reason the result haptic is injected: SwiftUI
    /// animates `projectileProgress` inside a view no test can mount, so the only place the
    /// reset-then-fly ORDER can be observed is where the writes are issued. `animated` is the crux of
    /// US-104 — a reset reported as animated is the bug itself, because SwiftUI would then sweep the
    /// glyph BACKWARD from the defender to the attacker instead of snapping it there.
    struct ProjectileChange: Equatable {
        /// The exchange this shot belongs to.
        let turn: Int
        /// Where the projectile is being sent, 0 at the attacker and 1 at the defender.
        let progress: CGFloat
        /// Whether the projectile is drawn at all once this change has landed.
        let visible: Bool
        /// Whether SwiftUI sweeps the value there over time rather than snapping to it.
        let animated: Bool
    }

    /// A spy on the projectile's flight. No-op in the app; see `ProjectileChange`.
    var onProjectileChange: (ProjectileChange) -> Void = { _ in }

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
        VStack(spacing: BattleBreakdownLayout.resultSpacing) {
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

            // The meat this win dropped into the larder (US-175), shown only when a win actually
            // banked some — a loss and a win at a full larder both bank nothing, and a "+0" would
            // read as a reward that never came. Orange fork-and-knife to match the meat DashBar and
            // the Feed button it will buy a meal at.
            if bout.meatGained > 0 {
                Label("+\(bout.meatGained)", systemImage: "fork.knife")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            breakdown

            Button(action: onFinish) {
                Label("Done", systemImage: "checkmark")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .padding(.top, 2)
        }
    }

    /// Why the fight went the way it did (US-094): what the round and the two typings were worth to
    /// the player, and the power that bought.
    ///
    /// Every number is read off `bout.matchup` — the arithmetic `BattleEngine` was actually handed —
    /// so the breakdown and the outcome cannot disagree. Absent entirely for a bout built without a
    /// matchup, which is every preview and every test that only cares about the frames.
    @ViewBuilder private var breakdown: some View {
        if let matchup = bout.matchup {
            if let contributions = BattleBreakdown.text(for: matchup) {
                Text(contributions)
                    .font(.system(size: BattleBreakdownLayout.textSize))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(BattleBreakdownLayout.minimumScale)
                    .lineLimit(BattleBreakdownLayout.lineLimit)
            }

            Text(BattleBreakdown.powerText(for: matchup))
                .font(.system(size: BattleBreakdownLayout.powerSize, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(BattleBreakdownLayout.minimumScale)
        }
    }

    /// What `side` is doing during the exchange on screen. `hasLanded` is the impact instant US-104
    /// put on screen, read here so the defender's flinch starts when the shot arrives rather than
    /// when the exchange begins.
    private func animation(for side: BattleSide) -> SpriteAnimation {
        guard case .turn(let index) = beat, index < bout.report.turns.count else { return .idle }
        return Self.animation(for: side, during: bout.report.turns[index], landed: hasLanded)
    }

    /// `side`'s MAX hit points — the length of its HP dash bar (US-188), read off the resolved report
    /// so a 5-HP Child and a 12-HP Ultimate draw bars of their own length.
    private func maxHitPoints(_ side: BattleSide) -> Int {
        bout.report.maxHitPoints(side)
    }

    /// `side`'s HP dash bar (US-171): `maxHitPoints` dashes total, the current `hitPoints` solid and
    /// the rest outline, in the health red the detail page's HP bar and the heart glyph share. Each
    /// takes half the row so the player's bar sits under the player and the opponent's under the
    /// opponent, and `.red` keeps HP one colour across the app.
    private func hpBar(for side: BattleSide) -> some View {
        DashBar(filled: hitPoints(side), total: maxHitPoints(side),
                tint: .red, dashHeight: 5)
            .frame(maxWidth: .infinity)
    }

    /// `side`'s CURRENT hit points as of the exchange on screen — the solid count of its HP dash bar.
    /// Full before the first exchange (the intro's stare-down); the result screen replaces the arena,
    /// so the felled side's empty bar is never asked for here.
    private func hitPoints(_ side: BattleSide) -> Int {
        guard case .turn(let index) = beat else { return maxHitPoints(side) }
        return Self.hitPoints(side, afterTurn: index, of: bout.report.turns,
                              maxHitPoints: maxHitPoints(side))
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

    /// The PRD's frame assignment, as a pure function: the attacker SWINGS — the attack frame (11)
    /// looped against walk1 (US-102) for the whole exchange, before and after impact alike — and the
    /// defender stands in its idle loop until the shot lands, then plays the hurt loop (9 <-> 10).
    ///
    /// `landed` is the whole of US-105. With the flinch keyed off the turn instead of the impact the
    /// defender began recoiling 1.1s before anything reached it, which reads as two sprites twitching
    /// at each other rather than as a blow landing. Taken as a parameter rather than read from
    /// `hasLanded` so this stays pure.
    ///
    /// Static and separate from the view for the same reason `BattleEngine` is separate from both —
    /// this mapping IS the acceptance criterion, and a screenshot can only ever show one instant of
    /// it. A test asserts every turn of a real battle against this instead.
    static func animation(for side: BattleSide, during turn: BattleTurn,
                          landed: Bool) -> SpriteAnimation {
        guard turn.attacker != side else { return .pose(.attack) }
        return landed ? .hurt : .idle
    }

    /// `side`'s hit points once the exchange at `index` has been played out — `maxHitPoints` less the
    /// damage every incoming blow up to and including this one landed for (US-188). `maxHitPoints`
    /// defaults to the flat pool so a test predating per-Digimon HP still reads the old numbers.
    ///
    /// Derived from the report rather than tracked in `@State`, so the solid dash count on screen can
    /// never drift out of step with the frames animating beside it.
    static func hitPoints(_ side: BattleSide, afterTurn index: Int, of turns: [BattleTurn],
                          maxHitPoints: Int = BattleEngine.startingHitPoints) -> Int {
        let taken = turns.prefix(index + 1)
            .filter { $0.attacker == side.other }
            .reduce(0) { $0 + $1.damage }
        return max(0, maxHitPoints - taken)
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
    ///
    /// `@MainActor` is load-bearing, not hygiene. An exchange begins with three writes — snap the
    /// projectile back, change the beat, launch the shot — and they only coalesce into ONE SwiftUI
    /// update if they happen in a single main-thread turn. Off the main actor they can land in
    /// separate updates, and the animated middle one then interpolates the projectile from where the
    /// spent shot was to where the new one starts: a glyph sliding across the arena between
    /// exchanges. That was photographed at the turn boundary on the Simulator, which is why this and
    /// `.id(index)` on the projectile both exist.
    @MainActor
    func run() async {
        try? await Task.sleep(for: .seconds(introDuration))

        let indices = demoFocusTurn.map { [$0] } ?? Array(bout.report.turns.indices)
        for index in indices where bout.report.turns.indices.contains(index) {
            // Snap the projectile back to the attacker with animations EXPLICITLY disabled, and clear
            // the impact. Left bare, this write shares an update with the animated `beat` change below
            // and SwiftUI sweeps it: the glyph slides backward from the defender to the attacker over
            // 0.15s before flying out again (US-104). The transaction is what makes the snap a
            // property of the write rather than of the order of these three lines.
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) {
                projectileProgress = 0
                hasLanded = false
            }
            onProjectileChange(ProjectileChange(turn: index, progress: 0, visible: true, animated: false))

            // Then fly it across the gap. `flight` is SHORTER than the turn, so the shot lands with a
            // beat of the defender's flinch still to run before the next exchange begins. Both are
            // injected, so a test still runs a whole battle in milliseconds.
            withAnimation(.easeInOut(duration: 0.15)) { beat = .turn(index) }
            withAnimation(Self.flightAnimation(duration: flight)) { projectileProgress = 1 }
            onProjectileChange(ProjectileChange(turn: index, progress: 1, visible: true, animated: true))

            // Impact: the shot is gone the moment it arrives, and the tail belongs to the defender.
            try? await Task.sleep(for: .seconds(flight))
            hasLanded = true
            onProjectileChange(ProjectileChange(turn: index, progress: 1, visible: false, animated: false))
            try? await Task.sleep(for: .seconds(turnDuration - flight))
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
