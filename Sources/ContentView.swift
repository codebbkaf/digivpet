import SwiftUI

/// The main screen: your Digimon, idling, with what it is and what stage it has reached.
///
/// US-017 adds the four energy bars beneath the sprite, which is why the sprite does not simply
/// fill the screen.
struct ContentView: View {
    @StateObject private var model: MainScreenModel
    @Environment(\.scenePhase) private var scenePhase

    /// Whether the Settings screen (US-198) is showing. Driven by the top-right gear, and — so the
    /// screen stays screenshottable, since `simctl` cannot tap the toolbar — by the DEBUG
    /// `-settingsDemo` launch flag.
    #if DEBUG
    @State private var showsSettings = CommandLine.arguments.contains("-settingsDemo")
    #else
    @State private var showsSettings = false
    #endif

    #if DEBUG
    @State private var showsDexDemo = CommandLine.arguments.contains("-dexDemo")
    @State private var showsComplicationDemo = CommandLine.arguments.contains("-complicationDemo")
    @State private var showsTreeDemo = CommandLine.arguments.contains("-dexTreeDemo")
    /// US-119's map list. Pushed from the launch command because nothing on the main screen reaches
    /// it yet — the strip that will is US-120 — and because `simctl` could not tap it if it did.
    @State private var showsMapListDemo = CommandLine.arguments.contains("-mapListDemo")
        || CommandLine.arguments.contains("-mapListPartialDemo")
    /// US-126's party screen. Same reason as the map list: `simctl` cannot tap the strip's trailing
    /// button, so the only way to photograph the screen behind it is to push it from the launch
    /// command. `MainScreenModel.seedPartyDemoIfRequested` is what fills the box it draws.
    /// US-132's Jogress entry point lives on that same screen, so `-jogressDemo` pushes it too —
    /// what AC10 asks to be photographed is the entry point IN `PartyView`, not a screen of its own.
    @State private var showsPartyDemo = CommandLine.arguments.contains("-partyDemo")
        || CommandLine.arguments.contains("-jogressDemo")
    /// US-132's pair list, one level below the entry point above. Same reason as US-121's map
    /// detail: the list is what a tap on the entry row opens, and `simctl` cannot tap a row — so
    /// the only way to photograph `JogressOfferRow`'s three-sprite layout is to open it from the
    /// launch command. `MainScreenModel.seedJogressDemoIfRequested` is what fills the box it offers
    /// from, so this flag implies `-jogressDemo`'s seed.
    @State private var showsJogressListDemo = CommandLine.arguments.contains("-jogressListDemo")
    /// US-121's map detail. Same reason as the list above, one level deeper: the detail is what a
    /// tap on a row opens, and `simctl` cannot tap a row.
    @State private var showsMapDetailDemo = CommandLine.arguments.contains("-mapDetailDemo")
        || CommandLine.arguments.contains("-mapDetailSlotsDemo")
        || CommandLine.arguments.contains("-mapDetailFoesDemo")
    /// US-076's timing bar, in isolation from whichever game Train actually opens. `-timingBarDemo`
    /// shows it sweeping; `-timingBarResultDemo` shows a decided round, since `simctl` cannot tap
    /// the marker to decide one.
    @State private var showsTimingBarDemo = CommandLine.arguments.contains("-timingBarDemo")
        || CommandLine.arguments.contains("-timingBarResultDemo")
    /// US-077's button masher, on the same footing: `-buttonMasherDemo` shows a round in play with
    /// taps on the counter, `-buttonMasherResultDemo` shows the grade those taps earned.
    @State private var showsButtonMasherDemo = CommandLine.arguments.contains("-buttonMasherDemo")
        || CommandLine.arguments.contains("-buttonMasherResultDemo")
    /// US-078's power meter, on the same footing again: `-powerMeterDemo` shows a meter mid-charge,
    /// `-powerMeterResultDemo` shows the grade a release in the band earned.
    @State private var showsPowerMeterDemo = CommandLine.arguments.contains("-powerMeterDemo")
        || CommandLine.arguments.contains("-powerMeterResultDemo")
        || CommandLine.arguments.contains("-powerMeterOverloadDemo")
    /// US-079's crown sprint, on the same footing once more: `-crownSprintDemo` turns the crown
    /// binding on a timer so the gauge is caught filling, `-crownSprintResultDemo` shows the grade a
    /// finished sprint earned. `simctl` cannot turn a crown at all, so the demo drives the binding
    /// through the game's own handler rather than the hardware.
    @State private var showsCrownSprintDemo = CommandLine.arguments.contains("-crownSprintDemo")
        || CommandLine.arguments.contains("-crownSprintResultDemo")
    /// US-080's reflex strike, on the same footing again: `-reflexStrikeDemo` pins the wait long
    /// enough that one launch can be screenshotted on both sides of it, `-reflexStrikeResultDemo`
    /// shows the grade a fast answer earned, and `-reflexStrikeFalseStartDemo` shows what tapping
    /// early costs. `simctl` cannot tap, so the last two stage the reaction and let the real rule
    /// grade it.
    @State private var showsReflexStrikeDemo = CommandLine.arguments.contains("-reflexStrikeDemo")
        || CommandLine.arguments.contains("-reflexStrikeResultDemo")
        || CommandLine.arguments.contains("-reflexStrikeFalseStartDemo")
    /// US-081's sequence recall, on the same footing again: `-sequenceRecallDemo` holds the first
    /// pad of the pattern lit so playback can be screenshotted, `-sequenceRecallInputDemo` races
    /// through playback so the round is caught listening, and the two result demos stage how much
    /// was remembered.
    @State private var showsSequenceRecallDemo = CommandLine.arguments.contains("-sequenceRecallDemo")
        || CommandLine.arguments.contains("-sequenceRecallInputDemo")
        || CommandLine.arguments.contains("-sequenceRecallResultDemo")
        || CommandLine.arguments.contains("-sequenceRecallMissDemo")
    #endif

    /// The battle replay's pacing. Constant in a release build; in DEBUG, `-battleResultDemo` paces
    /// it down to nothing so a `simctl` screenshot lands on the result screen rather than mid-
    /// exchange, and `-battleTurnDemo` stretches one exchange out long enough to catch the attack and
    /// hurt frames. `simctl` can neither tap nor time a screenshot to a 1.4s beat, so the pacing is
    /// what has to move. The shipped values are `BattleView`'s own defaults rather than literals, so
    /// the app can never be paced differently from what the tests assert.
    ///
    /// `-battleIntroDemo` is the mirror of `-battleResultDemo`: it holds the STARE-DOWN instead of
    /// racing past it, which is the only beat US-094's element badges and effectiveness caption are
    /// on screen for.
    private static var battleIntroDuration: TimeInterval {
        #if DEBUG
        if CommandLine.arguments.contains("-battleIntroDemo") { return 600 }
        if CommandLine.arguments.contains("-battleResultDemo") { return 0.01 }
        if CommandLine.arguments.contains("-battleTurnDemo") { return 0.01 }
        if CommandLine.arguments.contains("-battleSignatureDemo") { return 0.01 }
        #endif
        return BattleView.defaultIntroDuration
    }

    private static var battleTurnDuration: TimeInterval {
        #if DEBUG
        if CommandLine.arguments.contains("-battleResultDemo") { return 0.01 }
        if CommandLine.arguments.contains("-battleTurnDemo") { return 60 }
        if CommandLine.arguments.contains("-battleSignatureDemo") { return 60 }
        #endif
        return BattleView.defaultTurnDuration
    }

    /// How long a shot spends in the air. Stretched under the held-exchange demos — but nowhere near
    /// as far as the exchange itself is (60s), because a projectile crawling a screen width over a
    /// minute is indistinguishable from a still one: two `simctl` screenshots a fraction of a second
    /// apart have to land at visibly different points on the arc (US-091 AC7), and 12s is slow enough
    /// to catch and fast enough to see move.
    private static var battleFlightDuration: TimeInterval {
        #if DEBUG
        if CommandLine.arguments.contains("-battleResultDemo") { return 0.01 }
        if CommandLine.arguments.contains("-battleTurnDemo") { return 12 }
        if CommandLine.arguments.contains("-battleSignatureDemo") { return 12 }
        #endif
        return BattleView.defaultFlightDuration
    }

    /// The exchange the battle overlay holds on for a screenshot. nil in a release build and for the
    /// other demos, which play in order; `-battleSignatureDemo` (US-073) points it at the KNOCKOUT
    /// turn — never turn 0 — so `simctl` can catch the signature move and its banner rather than an
    /// ordinary exchange.
    private static func battleDemoFocusTurn(_ bout: BattleBout) -> Int? {
        #if DEBUG
        if CommandLine.arguments.contains("-battleSignatureDemo") {
            return bout.report.turns.count - 1
        }
        #endif
        return nil
    }

    #if DEBUG
    /// The timing bar staged for a screenshot. `-timingBarResultDemo` starts it already stopped dead
    /// centre — a `Perfect` — and holds the result long enough for `simctl` to catch it; plain
    /// `-timingBarDemo` slows the sweep to a crawl so the marker is caught somewhere along the bar
    /// rather than as a blur. `simctl` can neither tap nor time a screenshot to a 1.8s sweep, so, as
    /// with the battle demos, the pacing is what has to move.
    private static var timingBarDemoGame: TimingBarGame {
        var game = TimingBarGame(onFinish: { _ in })
        if CommandLine.arguments.contains("-timingBarResultDemo") {
            game.demoStopPosition = 0.5
            game.resultDuration = 600
        } else {
            game.sweepDuration = 30
        }
        return game
    }

    /// The button masher staged for a screenshot. `simctl` cannot mash, so both demos start the
    /// round already holding a count and let the REAL window run over it — the grade is still the
    /// one `grade(taps:window:)` gives that count.
    ///
    /// `-buttonMasherDemo` stretches the window so the round stays in play, counter and draining
    /// timer visible; `-buttonMasherResultDemo` leaves the shipped 5s window and stages the 30 taps
    /// that clear the perfect threshold, then holds the result long enough to catch it.
    private static var buttonMasherDemoGame: ButtonMasherGame {
        var game = ButtonMasherGame(onFinish: { _ in })
        if CommandLine.arguments.contains("-buttonMasherResultDemo") {
            game.demoTapCount = ButtonMasherGame.requiredTaps(for: .perfect, window: game.window)
            game.resultDuration = 600
        } else {
            game.demoTapCount = 12
            game.window = 20
        }
        return game
    }

    /// The power meter staged for a screenshot. `simctl` cannot hold the screen down, so both demos
    /// start the round with the charge back-dated onto the real clock — the grade is still the one
    /// `grade(fill:lowerBound:upperBound:)` gives that fill.
    ///
    /// `-powerMeterDemo` slows the fill to a crawl so the meter is caught climbing rather than
    /// already burst, and starts it below the band so a later screenshot catches it inside one;
    /// `-powerMeterResultDemo` leaves the shipped rate and stages exactly the band's bottom edge,
    /// so the screenshot is the threshold being met rather than a number typed in;
    /// `-powerMeterOverloadDemo` stages one step past the band's TOP edge, which is the game's own
    /// rule — the cost of greed — and the one ending the other two flags cannot show.
    private static var powerMeterDemoGame: PowerMeterGame {
        var game = PowerMeterGame(onFinish: { _ in })
        let band = PowerMeterGame.bandEdges(lowerBound: game.bandLowerBound,
                                            upperBound: game.bandUpperBound)
        if CommandLine.arguments.contains("-powerMeterResultDemo") {
            game.demoFill = band.lower
            game.demoReleasesImmediately = true
            game.resultDuration = 600
        } else if CommandLine.arguments.contains("-powerMeterOverloadDemo") {
            game.demoFill = band.upper.nextUp
            game.demoReleasesImmediately = true
            game.resultDuration = 600
        } else {
            game.demoFill = 0.4
            game.fillRate = 0.02
        }
        return game
    }

    /// The crown sprint staged for a screenshot. `simctl` has no crown at all, so `-crownSprintDemo`
    /// spins the binding itself, slowly, over a window long enough to outlast two screenshots — the
    /// rotation still accumulates through `spun(from:to:)` and the gauge still fills off the same
    /// pure `progress(rotation:target:)`.
    ///
    /// `-crownSprintResultDemo` stages exactly the shipped target, which is the `perfect` threshold
    /// itself rather than a number that happens to clear it, and holds the result long enough to
    /// catch it.
    private static var crownSprintDemoGame: CrownSprintGame {
        var game = CrownSprintGame(onFinish: { _ in })
        if CommandLine.arguments.contains("-crownSprintResultDemo") {
            game.demoRotation = game.rotationTarget
            game.demoGradesImmediately = true
            game.resultDuration = 600
        } else {
            game.demoSpinStep = 0.5
            game.window = 600
        }
        return game
    }

    /// The reflex strike staged for a screenshot. `simctl` cannot tap, so the two decided rounds
    /// stage a reaction time and let the real `grade(latency:)` say what it was worth.
    ///
    /// `-reflexStrikeDemo` pins the wait to a stretched-out eight seconds and holds the reaction
    /// window open, so ONE launch can be screenshotted before and after the signal — the round is
    /// the real one, sleeping on a real drawn delay and revealing itself, with nothing staged.
    /// `-reflexStrikeResultDemo` stages exactly `perfectLatency`, which is the threshold itself
    /// rather than a number that happens to clear it.
    /// `-reflexStrikeFalseStartDemo` stages a tap two tenths BEFORE the signal, which is a negative
    /// latency and so the false start rule (AC2) rendering its own verdict.
    private static var reflexStrikeDemoGame: ReflexStrikeGame {
        var game = ReflexStrikeGame(onFinish: { _ in })
        if CommandLine.arguments.contains("-reflexStrikeResultDemo") {
            game.demoLatency = ReflexStrikeGame.perfectLatency
            game.resultDuration = 600
        } else if CommandLine.arguments.contains("-reflexStrikeFalseStartDemo") {
            game.demoLatency = -0.2
            game.resultDuration = 600
        } else {
            // A pinned wait rather than a wide one: a screenshot has to know which side of the
            // signal it is on. It is still drawn through `delay(using:range:)` and still slept.
            game.delayRange = 8...8
            game.reactionTimeout = 600
        }
        return game
    }

    /// The sequence recall staged for a screenshot. `simctl` cannot tap, so the two decided rounds
    /// stage how much of the pattern was remembered and let the real rules say what it was worth.
    ///
    /// `-sequenceRecallDemo` stretches one step of playback out past any screenshot, so the recital
    /// is caught with a pad lit — the pattern is the real one, drawn and played back with nothing
    /// staged.
    /// `-sequenceRecallInputDemo` races through playback instead and holds the round listening, which
    /// is the other half of AC1: shown, then waiting to be reproduced.
    /// `-sequenceRecallResultDemo` stages the WHOLE pattern remembered, which is AC2's premise rather
    /// than a count that happens to clear a threshold.
    /// `-sequenceRecallMissDemo` stages one step remembered of four, so the round ends the way a real
    /// one does — on a wrong entry, through `correctCount(of:against:)`.
    private static var sequenceRecallDemoGame: SequenceRecallGame {
        var game = SequenceRecallGame(onFinish: { _ in })
        if CommandLine.arguments.contains("-sequenceRecallResultDemo") {
            game.demoCorrectCount = game.sequenceLength
            game.resultDuration = 600
        } else if CommandLine.arguments.contains("-sequenceRecallMissDemo") {
            game.demoCorrectCount = 1
            game.resultDuration = 600
        } else if CommandLine.arguments.contains("-sequenceRecallInputDemo") {
            game.stepDuration = 0.05
            game.stepGap = 0.05
            game.inputTimeout = 600
        } else {
            game.stepDuration = 600
        }
        return game
    }
    #endif

    /// The model is always passed in rather than defaulted: building one is a `@MainActor` call,
    /// and a default argument would be evaluated in this `init`'s non-isolated context. Same
    /// reason as `HealthAuthorizationGate`.
    init(model: @autoclosure @escaping () -> MainScreenModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        // The stack exists to hold the Dex (US-022), which is pushed rather than presented so it
        // keeps a back button and can push a detail of its own.
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView()
                case .playing:
                    digimon
                case .failed(let detail):
                    SavedGameUnavailableView(detail: detail)
                }
            }
            // The room light and the Dex both moved out of the toolbar and into the action grid in
            // US-197 (`ActionControls`); US-198 fills the trailing slot with a settings gear that
            // opens the Settings screen (notification toggles for now). The gear is the only thing
            // in the toolbar.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            // The Settings screen, pushed onto this stack so it keeps a back button. Reached by the
            // gear above, and by the DEBUG `-settingsDemo` flag that seeds `showsSettings` true.
            .navigationDestination(isPresented: $showsSettings) {
                SettingsView(settings: model.notificationSettings)
            }
            #if DEBUG
            // Debug-only: `simctl` cannot tap the toolbar button, so the Dex is unscreenshottable
            // without a way to push it from the launch command. Compiled out of release builds.
            .navigationDestination(isPresented: $showsDexDemo) {
                // As above (US-193): the demo Dex reads the live game's store, not a second one.
                DexView(model: DexModel(makeStore: model.sharedStore))
            }
            // Same reason, and one more: `simctl` cannot add a complication to a watch face either,
            // so this pushes the extension's own views inside the app where a screenshot can reach
            // them. Pushed rather than shown instead of the game, so `start()` has already run and
            // published the snapshot this draws.
            .navigationDestination(isPresented: $showsComplicationDemo) {
                ComplicationDemoView()
            }
            // US-041's tree in isolation, on a fixture line. Since US-042 the Dex opens the real
            // thing (`-dexDemo -dexLineDemo`); this stays as the layout's own screenshot path,
            // independent of whatever the shipped roster happens to hold.
            .navigationDestination(isPresented: $showsTreeDemo) {
                EvolutionTreeDemoView()
            }
            // US-119's map list, on the same footing and for the same reason: it is pushed onto
            // THIS stack — the one the Dex uses — so what the screenshot photographs is the real
            // destination, back button and all, and not a preview of it. US-120's strip is what
            // will push it with a tap.
            .navigationDestination(isPresented: $showsMapListDemo) {
                MapListView(rows: model.mapRows,
                            detail: { model.mapDetail(for: $0) }) { model.selectMap($0) }
            }
            // US-126's party screen, pushed for the same reason and onto the same stack: what the
            // screenshot photographs is the real destination the strip's button leads to, seeded
            // box and all, rather than a preview of it.
            .navigationDestination(isPresented: $showsPartyDemo) {
                PartyView(rows: model.partyRows, board: model.jogressBoard,
                          activate: { model.activate($0) },
                          fuse: { model.performJogress($0) })
            }
            // US-132's pair list, pushed straight past the entry row for the same reason the map
            // detail is pushed past its list. Fusing from here still goes through the real
            // `performJogress`, so the ceremony it raises is a real one.
            .navigationDestination(isPresented: $showsJogressListDemo) {
                JogressView(offers: model.jogressBoard.offers) { model.performJogress($0) }
            }
            // US-121's detail, pushed straight rather than through the list: `simctl` has no tap
            // command, so the only way to photograph the screen a tap opens is to open it from the
            // launch command. It takes the first UNLOCKED row, which on any save is the starting
            // map — see `MainScreenModel.mapDetailDemoContext` for why that map shows all three
            // slot states at once.
            .navigationDestination(isPresented: $showsMapDetailDemo) {
                if let row = model.mapRows.first(where: { !$0.isLocked }),
                   let detail = model.mapDetail(for: row) {
                    MapDetailView(detail: detail) { model.selectMap(row.id) }
                }
            }
            #endif
        }
        // The evolution ceremony sits above everything, so it covers the bars and stage text too.
        // It appears whenever a refresh moved the Digimon — including the refresh `start()` runs on
        // app open, which is how an evolution that came due while the app was closed is celebrated.
        .overlay {
            if let evolution = model.pendingEvolution {
                EvolutionCeremonyView(event: evolution) {
                    model.acknowledgeEvolution()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.pendingEvolution)
        // A dropped egg is announced over the game (US-128). Below the ceremony overlay, since a
        // hatch or evolution is the bigger moment and should cover a drop banner if they ever
        // coincide; a tap acknowledges it, which is what stops it showing twice.
        .overlay {
            if let drop = model.pendingDigitamaDrop {
                DigitamaDropBanner(announcement: drop) {
                    model.acknowledgeDigitamaDrop()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.pendingDigitamaDrop)
        // The battle sits above the ceremony for the same reason the ceremony sits above the bars:
        // it is a moment, not a place, and the Feed and Train buttons underneath must not be
        // tappable through it. `finishBattle` is what files the win or loss and takes it down.
        .overlay {
            if let bout = model.pendingBattle {
                BattleView(bout: bout,
                           onFinish: { model.finishBattle() },
                           introDuration: Self.battleIntroDuration,
                           turnDuration: Self.battleTurnDuration,
                           flightDuration: Self.battleFlightDuration,
                           demoFocusTurn: Self.battleDemoFocusTurn(bout))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.pendingBattle)
        // The wild-encounter dialog (US-201) sits with the battle: it is a moment the player has to
        // answer, so the Feed and Train buttons under it must not be tappable through it. Accepting
        // clears it and raises `pendingBattle` (the fight replays over the same spot); fleeing clears
        // it and turns the Digimon away. Mutually exclusive with the battle overlay above — only one
        // is ever non-nil — so their order relative to each other never shows.
        .overlay {
            if let encounter = model.pendingWildEncounter {
                WildEncounterView(encounter: encounter,
                                  onBattle: { model.acceptWildEncounter() },
                                  onFlee: { model.fleeWildEncounter() })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.pendingWildEncounter)
        // The boss dialog (US-203) sits with the wild encounter and the battle: it is a moment the
        // player must answer, so the Feed and Train buttons under it must not be tappable through it.
        // Its only action is BATTLE — a boss is a gate, not an ambush — which clears it and raises
        // `pendingBattle` (the fight replays over the same spot). Mutually exclusive with the wild and
        // battle overlays above; the model never raises two at once, so their order never shows.
        .overlay {
            if let boss = model.pendingBossEncounter {
                BossEncounterView(encounter: boss,
                                  onBattle: { model.acceptBossEncounter() })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.pendingBossEncounter)
        // The training round sits with the battle, above the ceremony, and for the same reasons: it
        // is a moment rather than a place, and the Feed and Train buttons underneath must not be
        // tappable through it — a second Train tap during a round would charge for a second one.
        // Which game appears is US-082's assignment; `finishTraining` is what pays the grade out and
        // takes it down. `TrainingMinigame` guarantees exactly one call, so the round cannot be paid
        // twice or hang forever unpaid.
        .overlay {
            if let round = model.pendingTraining {
                round.kind.view { result in model.finishTraining(result) }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.pendingTraining)
        // The pre-battle round (US-093) sits exactly where the training round does, because it is the
        // same thing on screen: the Digimon's assigned minigame, full screen, over everything else.
        // What differs is only what the grade buys — `finishBattleRound` spends it on the fight rather
        // than on `strengthStat`, and the arena comes up in its place.
        .overlay {
            if let round = model.pendingBattleRound {
                round.game.view { result in model.finishBattleRound(result) }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.pendingBattleRound)
        // Applied AFTER the ceremony's overlay, so it layers above it: a Digimon that died has
        // nothing left to celebrate. This is also what stops the Feed and Train buttons underneath
        // from being tapped while the memorial is up.
        .overlay {
            if let memorial = model.memorial {
                MemorialView(memorial: memorial) {
                    model.dismissMemorial()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.memorial)
        #if DEBUG
        // Debug-only: each game in ISOLATION, staged for a screenshot of its own rules. The Train
        // button opens the assigned one for real since US-083 (the overlay above), but only one game
        // at a time and only the one the Digimon was assigned — these six flags are how the other
        // five stay screenshottable. Same overlay treatment, so what they show is what a real round
        // shows. Compiled out of release builds.
        .overlay {
            if showsTimingBarDemo {
                Self.timingBarDemoGame
            } else if showsButtonMasherDemo {
                Self.buttonMasherDemoGame
            } else if showsPowerMeterDemo {
                Self.powerMeterDemoGame
            } else if showsCrownSprintDemo {
                Self.crownSprintDemoGame
            } else if showsReflexStrikeDemo {
                Self.reflexStrikeDemoGame
            } else if showsSequenceRecallDemo {
                Self.sequenceRecallDemoGame
            }
        }
        #endif
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            // A round left mid-play is graded a miss, and the energy it cost stays spent (US-083
            // AC4). `.background` rather than `.inactive` on purpose: watchOS passes through
            // `.inactive` for a notification banner or a wrist tilt, and abandoning a round the user
            // is still holding their arm up for would be a bug rather than a rule.
            if phase == .background {
                model.abandonTraining()
                // The pre-battle round is abandoned on the same beat but is NOT cancelled with it: the
                // energy is already gone, so the fight goes ahead at the miss multiplier (US-093
                // AC4) and is waiting on the arena when the app comes back.
                model.abandonBattleRound()
            }
            // The whole refresh: health data is only read when the app is in front, since
            // watchOS gives a backgrounded app no reason to expect it will run at all.
            // `start()` covers the first appearance; this covers every return to it.
            guard phase == .active else { return }
            Task { await model.refresh() }
        }
    }

    @ViewBuilder
    private var digimon: some View {
        if let presentation = model.presentation {
            // No ScrollView (US-039). Everything the user acts with has to be reachable without
            // scrolling away from the Digimon, so the rows are all fixed-height and the sprite
            // takes whatever they leave — see `SpriteScale`. What used to be three stacked stat
            // blocks is one strip, which is most of the room that bought.
            //
            // Zero spacing since US-120, not one point. The map strip added a sixth row to this
            // stack, and `SpriteScale.fitting` FLOORS `slotHeight / 16`: the slot sat at exactly
            // 49.0pt on 41mm and exactly 64.0pt on 46mm, so a row of any height at all cost the
            // Digimon a whole scale step (48 -> 32pt, 64 -> 48pt — measured, not predicted). The
            // strip's ~13.5pt had to come back out of the chrome around it, and this stack's five
            // inter-row gaps are 5.0pt of it. They are the cheapest 5 points on the screen: every
            // row here is already a self-contained band of text or controls, so what the gaps were
            // buying was air between things that do not touch anyway.
            VStack(spacing: 0) {
                if let state = model.state {
                    StatsStrip(hunger: state.hunger,
                               strengthStat: state.strengthStat,
                               power: state.battlePower(lifetimeEnergy: model.lifetimeEnergy),
                               wins: state.battleWins,
                               losses: state.battleLosses,
                               ageYears: model.ageYears)
                }

                // The pose comes from the model, so a feed shows the eat loop and a refusal the
                // refuse frame — both revert to idle on their own. `isWandering` is what stops
                // the Digimon walking while it sleeps, eats, is sick or dead, or is behind an
                // overlay; it resumes from where it stood when that clears.
                //
                // The sprite is the one flexible row: it claims the leftover height and draws
                // itself at the largest whole-pixel scale that fits it, so a 42mm screen shows a
                // smaller Digimon rather than a clipped action row.
                GeometryReader { geometry in
                    WanderingSpriteView(
                        stage: presentation.spriteStage,
                        name: presentation.spriteFile,
                        animation: model.animation,
                        scale: SpriteScale.fitting(
                            SickBadgeLayout.spriteHeight(in: geometry.size.height,
                                                         isSick: model.isSick)
                        ),
                        isMoving: model.isWandering,
                        // The nudge under the pose (US-095): the chew of a meal, the shake of a
                        // refusal. Nil while resting, and nil for a blocked action. It rides on top
                        // of wherever the walk left the sprite, which is safe because a pose that
                        // carries a motion is never `.idle` and so `isWandering` is already false.
                        motion: model.actionMotion
                    )
                    // Bottom-aligned while ill, centred otherwise. The sprite is sized against a
                    // slot one badge-band shorter than this frame, so pushing it to the floor is
                    // what turns that missing band into clear space at the TOP rather than half of
                    // it at each end — see `SickBadgeLayout`. Nothing changes when healthy.
                    .frame(maxWidth: .infinity,
                           maxHeight: .infinity,
                           alignment: model.isSick ? .bottom : .center)
                    // In the band the sprite was just sized out of, so it sits above the Digimon
                    // rather than on it, and well clear of the action row at the bottom of the
                    // screen. Centred, because the sprite walks the full width and there is no
                    // corner it cannot reach — height is the only clearance that holds.
                    .overlay(alignment: .top) {
                        if model.isSick {
                            SickBadgeView()
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                // Where the light button goes (US-099). Reported rather than drawn here: the button
                // has to be painted ABOVE the scrim that covers the whole screen, so it lives in the
                // layer below and this is the only way it can still land in this row's corner. It
                // costs the sprite nothing — a preference is measurement, not layout.
                .anchorPreference(key: SpriteSlotBoundsKey.self, value: .bounds) { $0 }

                // Name, stage and action message share ONE row since US-039, where the name had a
                // headline row to itself above the sprite. That row cost 16 of the 136 points a
                // 42mm screen has, which is a third of the Digimon. The slot is still always
                // present, so a message still does not shove the sprite up mid-animation; what a
                // message now costs is the name for the two seconds it is up, and while a Digimon
                // is refusing food its name is not the thing the user needs to read.
                // Size 9 since US-120, down from 12. Three points of this row's height is 3.6pt of
                // the map strip's cost paid back, and this is the row that can best afford it: 9pt
                // is already this screen's small-text size — the stats strip's labels and the action
                // row's caption are both 9 — so the name line joins a size the screen already
                // speaks rather than inventing a smaller one. The Digimon's name is also the one
                // thing here a glance does not need: the sprite says which Digimon it is, and a
                // 48pt sprite says it far better than a 12pt caption did.
                Text(model.actionMessage ?? "\(presentation.displayName) · \(presentation.stage.displayName)")
                    .font(.system(size: MainScreenTypography.nameFontSize,
                                  weight: model.actionMessage == nil ? .semibold : .regular))
                    .foregroundStyle(model.actionMessage == nil ? Color.primary : Color.orange)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                // Where the Digimon is adventuring, and the way to the box (US-120). Directly above
                // the energy bars rather than in the toolbar — watchOS gives a screen two slots and
                // US-114 spent the second on the room light — and rather than in the action row,
                // which is the five things you DO to the Digimon.
                //
                // Drawn whether or not a map has been chosen: with nothing selected it names the
                // first map as an invitation, and nothing on this screen is gated on having taken
                // it (AC6).
                if let strip = model.mapStrip {
                    MapStripView(strip: strip, destination: {
                        MapListView(rows: model.mapRows,
                                    detail: { model.mapDetail(for: $0) }) { model.selectMap($0) }
                    }, party: {
                        // The box of Digimon (US-126), off the strip's trailing button — the other
                        // way out of this screen, and the one that changes which Digimon is on it.
                        PartyView(rows: model.partyRows, board: model.jogressBoard,
                                  activate: { model.activate($0) },
                                  fuse: { model.performJogress($0) })
                    })
                }

                // The two readings that still matter after US-196 retired the STEP/KCAL/EXER energy
                // bars: how far the active Digimon has walked the current map, and how much it has
                // slept — each a DashBar (US-171), stacked as exactly two lines above the action
                // area. Steps, calories and exercise left the screen because they are already spent
                // into train points and battle time; map progress and sleep are what a glance at the
                // raising screen still needs. Gated on `state` like the currency row below, so no lone
                // bar draws before a Digimon is out; the map numbers come from the same `MapStrip`
                // the strip above reads, so a step credited to the map moves both together.
                if let strip = model.mapStrip, model.state != nil {
                    MainReadingBars(mapRecorded: strip.recordedSteps, mapTotal: strip.totalSteps,
                                    mapName: strip.mapName,
                                    sleepHours: model.sleepHours, sleepTotal: model.sleepHoursCap)
                }

                if model.state != nil {
                    // The meat larder, alone on its row (US-199). It was one of four currency bars
                    // (US-174, US-176, US-177, US-178); US-199 moved the OTHER three — train red,
                    // battle purple, clean blue — onto segmented rings around the very buttons that
                    // spend them, so each charge now reads where it is used. Meat has no single button
                    // that spends it (it feeds through Feed but is a pool, not a per-tap charge), so it
                    // stays as the row's `DashBar` — the app's one value language (US-171), no number,
                    // orange for the fork-and-knife it feeds.
                    DashBar(filled: model.meat, total: model.meatCap, tint: .orange, dashHeight: 5)

                    // The eight actions in a two-row grid (US-197): Feed, Train, Clean, Battle on
                    // top; Map, Party, Light, Dex below. Light and Dex moved in off the toolbar and
                    // Map and Party in off the strip, so every way out of the room is one consistent
                    // circle here rather than scattered around the screen's edges.
                    //
                    // The 2pt top padding this used to carry went to the sprite in US-120. The
                    // circles are 30pt discs with their own visual margin, so the gap above them
                    // was decoration; the Digimon needed it more.
                    ActionControls(canAffordBattle: model.canAffordBattle,
                                   poopCount: model.poopCount,
                                   lightState: model.lightState,
                                   trainCharges: model.trainCharges,
                                   trainChargeCap: model.trainChargeCap,
                                   battleCharges: model.battleCharges,
                                   battleChargeCap: model.battleChargeCap,
                                   cleanCharges: model.cleanCharges,
                                   cleanChargeCap: model.cleanChargeCap,
                                   feed: { model.feed() },
                                   train: { model.train() },
                                   clean: { model.clean() },
                                   battle: { model.battle() },
                                   cycleLight: { _ = model.cycleLight() },
                                   mapDestination: {
                                       MapListView(rows: model.mapRows,
                                                   detail: { model.mapDetail(for: $0) }) { model.selectMap($0) }
                                   },
                                   partyDestination: {
                                       PartyView(rows: model.partyRows, board: model.jogressBoard,
                                                 activate: { model.activate($0) },
                                                 fuse: { model.performJogress($0) })
                                   },
                                   dexDestination: {
                                       // Reuses the game's one store (US-193), never a second one.
                                       DexView(model: DexModel(makeStore: model.sharedStore))
                                   })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The adventure map (US-115), behind the Digimon and inside its slot alone. Off the same
            // anchor the scrim uses, so the map and the darkness that falls on it are the same rect
            // by construction rather than by two sets of arithmetic agreeing.
            //
            // A BACKGROUND rather than an overlay, which is the whole difference between scenery and
            // a stain: this layer is painted before the VStack, so the sprite, the stats strip and
            // the action row are all drawn on top of it, and `LightLayer` — an overlay — is painted
            // after all of them. That stacking is what makes the map dim with the room instead of
            // floating above the scrim.
            //
            // Costs the sprite nothing: a background is sized by the view it is behind and never
            // proposes a size back to it, so the map cannot grow the layout in either axis however
            // large the asset is.
            .backgroundPreferenceValue(SpriteSlotBoundsKey.self) { spriteSlot in
                GeometryReader { proxy in
                    // Nothing at all with no map selected, and nothing before the first layout pass
                    // has measured the slot — the same nil rule the scrim follows.
                    if MapBackgroundLayout.shouldDraw(assetName: model.selectedMapAsset),
                       let mapAsset = model.selectedMapAsset,
                       let slot = spriteSlot.map({ proxy[$0] }) {
                        MapBackgroundView(assetName: mapAsset)
                            .frame(width: slot.width, height: slot.height)
                            // The fill's overflow stops here. Without this the map spills up over
                            // the stats strip and down over the energy bars.
                            .clipped()
                            // `.offset` rather than padding, for the reason the scrim uses one:
                            // padding is laid out, an offset only moves the drawing.
                            .offset(x: slot.minX, y: slot.minY)
                    }
                }
                .allowsHitTesting(false)
            }
            // The room light's scrim (US-099), over the sprite's slot and nothing beyond it since
            // US-112. Applied HERE and not to the `NavigationStack`, so the ceremony, the battle,
            // the training round and the memorial — which are applied out there — are painted on
            // top of it and are never dimmed, and so a pushed Dex is not dimmed either. The button
            // that changes it is in the toolbar since US-114 and is not part of this layer.
            .overlayPreferenceValue(SpriteSlotBoundsKey.self) { spriteSlot in
                ZStack(alignment: .topLeading) {
                    LightLayer(state: model.lightState, spriteSlot: spriteSlot)

                    // The mess, on the ground at the near edge of the sprite's slot: beside the
                    // Digimon rather than under it, because the sprite is drawn with `.offset` and
                    // walks the full width, so anything sharing its centre would be walked over.
                    // The bottom-trailing corner is the one place a pile of four is always beside
                    // whatever the Digimon is doing. Nothing is drawn at zero, so a clean screen
                    // costs no layout at all — and the pile does not blink out of existence when
                    // the count reaches zero, it shrinks and fades away over 0.35s. See
                    // `PoopGround`.
                    //
                    // Drawn in THIS layer rather than as an overlay inside the sprite's row, which
                    // is where it lived until US-112: the scrim is painted over that row now, and
                    // a pile the user cannot see is a pile they will not clean. Placed off the same
                    // anchor as the lamp, so the two corners of the room stay lit together. Not
                    // hit-testable, or the frame it is placed in — the whole slot, so the pile can
                    // sit in its corner of it — would swallow the lamp's own taps.
                    GeometryReader { proxy in
                        let slot = spriteSlot.map { proxy[$0] } ?? .zero

                        PoopGround(count: model.poopCount)
                            .padding(.trailing, 6)
                            .frame(width: slot.width, height: slot.height,
                                   alignment: .bottomTrailing)
                            .offset(x: slot.minX, y: slot.minY)
                    }
                    .allowsHitTesting(false)
                }
            }
            // Pin the action row to the screen bottom and hand the reclaimed band to the play area
            // (US-172). watchOS reserves a bottom safe-area inset — 26pt on 41mm, 36pt on 46mm — for
            // the display's corner curvature, and until now the action row sat ABOVE it, leaving that
            // whole band empty under the buttons. `.ignoresSafeArea(.container, edges: .bottom)` lets
            // this stack draw into it, and because the sprite's `GeometryReader` is the one row that
            // claims `maxHeight: .infinity`, every reclaimed point lands on the play area — and, off
            // `SpriteSlotBoundsKey`, on the map behind it. The bottom padding is what stops the
            // row landing flush on the display edge; applied INSIDE the ignore, so the stack fills the
            // full height less that inset and the row ends exactly `actionRowBottomInset` (12 since
            // US-194) from the physical bottom — the extra 8pt over US-172's 4 shortens the room.
            // Applied here, after the map and scrim preference layers, so those keep tracking the
            // sprite slot's bounds unchanged — only the height the slot is offered grows.
            .padding(.bottom, MainScreenLayout.actionRowBottomInset)
            .ignoresSafeArea(.container, edges: .bottom)
        } else {
            // The graph has no node for the saved id — a roster edit that dropped a Digimon out
            // from under a live save. Nothing to draw, so say so rather than showing an empty box.
            SavedGameUnavailableView(detail: model.state.map { "Unknown Digimon '\($0.currentDigimonId)'." })
        }
    }
}

/// How large to draw the sprite in whatever height the fixed rows leave it (US-039).
///
/// A whole number of screen points per sprite pixel, always: a fractional scale resamples 16x16 art
/// onto a grid it does not line up with, and `.interpolation(.none)` then makes that visible as
/// uneven pixel widths rather than hiding it as blur.
///
/// Free-standing rather than a static on the view that uses it, because the view is generic over
/// nothing useful here and a test should not have to build a view graph to check the arithmetic.
/// The two text sizes on the main screen that the sprite's scale depends on (US-120).
///
/// Named rather than left as literals in a `body` for `MapStripLayout.fontSize`'s reason: these are
/// not taste, they are load-bearing. `SpriteScale.fitting` FLOORS `slotHeight / 16`. Before US-194
/// the slot sat right on a scale boundary — 49.5pt on 41mm, 64.0pt on 46mm, 0.5pt and 0.0pt of slack
/// — so a point of font silently cost the Digimon a whole scale step. US-194's shorter room (the
/// action row's inset grew 4 -> 12, all of it out of this one flexible slot) re-measured to 41.5pt
/// on 41mm and 56.0pt on 46mm, dropping the sprite one deliberate step and, as a side effect, moving
/// both slots to mid-band with real slack. The ceiling stays as a conservative guard even so.
///
/// `MainScreenLayoutTests` holds these here so a change that would shrink the sprite fails a test.
enum MainScreenTypography {
    /// The Digimon's name and stage, and the action message that replaces it.
    static let nameFontSize: CGFloat = 9

    /// The stats strip's values (STR, PWR). Matched to the 9pt labels beside them; the strip's
    /// height is its tallest element, and these were it.
    static let statValueFontSize: CGFloat = 9

    /// The largest either may be before a font point starts costing the sprite a scale step.
    ///
    /// Not a style rule — a measured ceiling. It bought the razor-thin 0.5pt of 41mm slack the map
    /// strip left; US-194's shorter room since moved both slots mid-band, so the ceiling is looser
    /// than it must be now, but it stays pinned so a future row that eats the new slack fails a test.
    static let maximumSafeFontSize: CGFloat = 9
}

/// The fixed insets the main screen's outer frame carries (US-172).
///
/// Named rather than a literal in `body` for `MainScreenTypography`'s reason: this one is load-
/// bearing too. `MainScreenLayoutTests` pins it so an edit that pads the action row further off the
/// bottom — quietly taking height back from the play area US-172 just handed it — fails a test.
enum MainScreenLayout {
    /// The gap between the action row and the physical bottom of the display. US-172 pins the row to
    /// the screen bottom and hands the safe-area band it used to sit above to the sprite slot.
    ///
    /// US-194 grows this from 4 to 12. Because the inset is padded INSIDE `.ignoresSafeArea(.bottom)`
    /// and the sprite `GeometryReader` is the one row claiming `maxHeight: .infinity`, every point
    /// added here comes straight back out of the play area — so this single constant is BOTH "the
    /// action row sits 12 from the bottom" and "the room is a little shorter": the sprite slot loses
    /// exactly the 8pt this gained (before: slot 49.5pt/64.0pt on 41mm/46mm with a 4pt inset; after:
    /// 8pt shorter, re-measured on the Simulator — see `MainScreenLayoutTests` and progress.txt).
    static let actionRowBottomInset: CGFloat = 12
}

enum SpriteScale {
    /// The scale the screen showed before there was anything to compete with it for room.
    static let maximum: CGFloat = 5

    /// The floor, and it is a real floor: the sprite is drawn with `.offset` inside its slot and so
    /// OVERFLOWS rather than clips when it does not fit, which on a 42mm screen meant Agumon's head
    /// landing on top of the energy bars. Two is where it stops shrinking because 32pt is still a
    /// recognisable Digimon — the complication draws one no larger. The rows above and below were
    /// trimmed until 42mm lands above this rather than on it; if a later row pushes it back down
    /// here, the sprite gets small before anything starts overlapping.
    static let minimum: CGFloat = 2

    static func fitting(_ height: CGFloat) -> CGFloat {
        let whole = (height / CGFloat(SpriteSheet.frameSize)).rounded(.down)
        return min(max(whole, minimum), maximum)
    }
}

/// Every stat in one strip: hunger pips, STR, PWR and the W/L record (US-039).
///
/// One row where there were three stacked blocks, because those blocks plus the bars and the action
/// row did not fit a 42mm screen and the ScrollView that hid the overflow was scrolling the user
/// away from the Digimon to reach a button.
///
/// Hunger stays pips while the rest stay numbers: hunger is a small integer with a hard ceiling, so
/// four pips say "one more and it is starving" at a glance where "2" does not, and `strengthStat`
/// and `battlePower` have no ceiling to read a bar against. Power sits next to the record because it
/// is the number the battle is actually resolved from (US-030) — a user who trains should be able to
/// watch it move, rather than wait for the next fight to find out training did anything.
///
/// The Feed/Train/Battle buttons that used to sit under each block moved into `ActionControls` in
/// US-038; the three separate accessibility elements survive here unchanged, so VoiceOver still
/// reads three stats and not one run-on line.
struct StatsStrip: View {
    let hunger: Int
    let strengthStat: Int
    let power: Int
    let wins: Int
    let losses: Int
    /// One year per real day since the Digitama hatched (US-200), shown as `1Y` right after the W/L
    /// record. Defaulted to 0 so a preview or a future call site that has no age to hand simply draws
    /// `0Y` rather than needing to plumb the clock through.
    var ageYears: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<HungerClock.maximumHunger, id: \.self) { pip in
                    Circle()
                        .fill(pip < hunger ? Color.orange : Color.secondary.opacity(0.3))
                        .frame(width: 5, height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hunger")
            .accessibilityValue("\(hunger) of \(HungerClock.maximumHunger)")

            stat("STR", value: "\(strengthStat)", tint: .red)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Strength")
                .accessibilityValue("\(strengthStat)")

            HStack(spacing: 3) {
                stat("PWR", value: "\(power)", tint: .purple)

                Text("\(wins)W \(losses)L")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                // The age, immediately after the W/L record (US-200): one year per real day since
                // the Digitama hatched. Same size and secondary tint as the record beside it — it is
                // another small at-a-glance fact on this line, not a value to be read against a bar.
                Text("\(ageYears)Y")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battle power")
            .accessibilityValue("\(power), \(wins) wins, \(losses) losses, \(ageYears) years old")
        }
        // The strip is one line on both watch sizes; on the narrower one it shrinks rather than
        // wrapping, since a second line would come straight back out of the sprite's height.
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func stat(_ label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            // Size 9 since US-120, down from 11, which matches the label beside it. The strip's
            // height is its tallest element and the values were it, so those two points came
            // straight off the row and went to the sprite (US-120 AC4). The values keep their
            // semibold weight and their tint, which is what separated them from the labels — the
            // size difference was never doing that work on its own.
            Text(value)
                .font(.system(size: MainScreenTypography.statValueFontSize, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

/// Shown when there is a saved game to open but it cannot be reached or drawn.
struct SavedGameUnavailableView: View {
    let detail: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("No Digimon")
                    .font(.headline)

                Text("Your saved game could not be opened.")
                    .font(.footnote)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ContentView(model: MainScreenModel())
}
