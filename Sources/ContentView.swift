import SwiftUI

/// The main screen: your Digimon, idling, with what it is and what stage it has reached.
///
/// US-017 adds the four energy bars beneath the sprite, which is why the sprite does not simply
/// fill the screen.
struct ContentView: View {
    @StateObject private var model: MainScreenModel
    @Environment(\.scenePhase) private var scenePhase

    #if DEBUG
    @State private var showsDexDemo = CommandLine.arguments.contains("-dexDemo")
    @State private var showsComplicationDemo = CommandLine.arguments.contains("-complicationDemo")
    @State private var showsSettingsDemo = CommandLine.arguments.contains("-settingsDemo")
    #endif

    /// Scroll anchor for the action row, so the Simulator demos can bring it into view. One anchor
    /// where there were four, because US-038 put all four actions in a single row — there is no
    /// longer a Feed block to scroll to independently of a Battle block. US-039 removes the scroll
    /// view outright, and with it this and the flags below.
    private static let actionControlsId = "actionControls"

    /// The battle replay's pacing. Constant in a release build; in DEBUG, `-battleResultDemo` paces
    /// it down to nothing so a `simctl` screenshot lands on the result screen rather than mid-
    /// exchange, and `-battleTurnDemo` stretches one exchange out long enough to catch the attack and
    /// hurt frames. `simctl` can neither tap nor time a screenshot to a 0.7s beat, so the pacing is
    /// what has to move.
    private static var battleIntroDuration: TimeInterval {
        #if DEBUG
        if CommandLine.arguments.contains("-battleResultDemo") { return 0.01 }
        if CommandLine.arguments.contains("-battleTurnDemo") { return 0.01 }
        #endif
        return 1.0
    }

    private static var battleTurnDuration: TimeInterval {
        #if DEBUG
        if CommandLine.arguments.contains("-battleResultDemo") { return 0.01 }
        if CommandLine.arguments.contains("-battleTurnDemo") { return 60 }
        #endif
        return 0.7
    }

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DexView(model: DexModel())
                    } label: {
                        Label("Dex", systemImage: "book")
                    }
                }
            }
            #if DEBUG
            // Debug-only: `simctl` cannot tap the toolbar button, so the Dex is unscreenshottable
            // without a way to push it from the launch command. Compiled out of release builds.
            .navigationDestination(isPresented: $showsDexDemo) {
                DexView(model: DexModel())
            }
            // Same reason, and one more: `simctl` cannot add a complication to a watch face either,
            // so this pushes the extension's own views inside the app where a screenshot can reach
            // them. Pushed rather than shown instead of the game, so `start()` has already run and
            // published the snapshot this draws.
            .navigationDestination(isPresented: $showsComplicationDemo) {
                ComplicationDemoView()
            }
            // Same reason again: the Settings link sits at the bottom of a scroll view `simctl`
            // cannot scroll, and cannot be tapped even once it is on screen.
            .navigationDestination(isPresented: $showsSettingsDemo) {
                NotificationSettingsView(settings: model.notificationSettings)
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
        // The battle sits above the ceremony for the same reason the ceremony sits above the bars:
        // it is a moment, not a place, and the Feed and Train buttons underneath must not be
        // tappable through it. `finishBattle` is what files the win or loss and takes it down.
        .overlay {
            if let bout = model.pendingBattle {
                BattleView(bout: bout,
                           onFinish: { model.finishBattle() },
                           introDuration: Self.battleIntroDuration,
                           turnDuration: Self.battleTurnDuration)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.pendingBattle)
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
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
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
            // Scrolling, because the four bars plus the feed controls are taller than a 41mm screen.
            // The sprite and name still sit at the top, where they are without scrolling.
            ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 2) {
                    Text(presentation.displayName)
                        .font(.headline)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    // The pose comes from the model, so a feed shows the eat loop and a refusal the
                    // refuse frame — both revert to idle on their own. `isWandering` is what stops
                    // the Digimon walking while it sleeps, eats, is sick or dead, or is behind an
                    // overlay; it resumes from where it stood when that clears.
                    WanderingSpriteView(
                        stage: presentation.spriteStage,
                        name: presentation.spriteFile,
                        animation: model.animation,
                        scale: 5,
                        isMoving: model.isWandering
                    )

                    // The caption slot is always present, so showing a message does not shove the
                    // sprite up the screen mid-animation.
                    Text(model.actionMessage ?? presentation.stage.displayName)
                        .font(.caption2)
                        .foregroundStyle(model.actionMessage == nil ? Color.secondary : Color.orange)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    if let progress = model.energyProgress {
                        EnergyBarsView(progress: progress, dominant: model.state?.dominantEnergyType)
                            .padding(.top, 2)
                    }

                    if let state = model.state {
                        HungerReadout(hunger: state.hunger)
                            .padding(.top, 4)

                        StrengthReadout(strengthStat: state.strengthStat)
                            .padding(.top, 2)

                        BattleReadout(power: state.battlePower,
                                      wins: state.battleWins,
                                      losses: state.battleLosses)
                            .padding(.top, 2)

                        // All four actions in one row (US-038), Notifications among them: a
                        // preference is something you visit once, but it is still a destination
                        // like the others, and a fourth circle costs less room than the labelled
                        // link below the fold that it replaces.
                        ActionControls(battlesLeft: model.battlesRemainingToday,
                                       feed: { model.feed() },
                                       train: { model.train() },
                                       battle: { model.battle() }) {
                            NotificationSettingsView(settings: model.notificationSettings)
                        }
                        .padding(.top, 6)
                        .id(Self.actionControlsId)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            #if DEBUG
            // Debug-only: `simctl` can drive neither the Digital Crown nor a tap, so the action
            // row sits below the fold and is unscreenshottable without a way to scroll to it from
            // the launch command. All four flags now land on the same row — they are kept as
            // aliases only so existing screenshot commands still work until US-039 deletes them
            // along with the scroll view. Compiled out of release builds.
            .onAppear {
                let scrollFlags = ["-feedScrollDemo", "-trainScrollDemo",
                                   "-battleScrollDemo", "-settingsScrollDemo"]
                if scrollFlags.contains(where: CommandLine.arguments.contains) {
                    scroller.scrollTo(Self.actionControlsId, anchor: .bottom)
                }
            }
            #endif
            }
        } else {
            // The graph has no node for the saved id — a roster edit that dropped a Digimon out
            // from under a live save. Nothing to draw, so say so rather than showing an empty box.
            SavedGameUnavailableView(detail: model.state.map { "Unknown Digimon '\($0.currentDigimonId)'." })
        }
    }
}

/// The hunger meter.
///
/// The meter is filled pips rather than a number because hunger is a small integer with a hard
/// ceiling — four pips say "one more and it is starving" at a glance, where "2" does not.
///
/// The Feed button that used to sit under it moved into `ActionControls` in US-038.
struct HungerReadout: View {
    let hunger: Int

    var body: some View {
        HStack(spacing: 3) {
            Text("Hunger")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            ForEach(0..<HungerClock.maximumHunger, id: \.self) { pip in
                Circle()
                    .fill(pip < hunger ? Color.orange : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hunger")
        .accessibilityValue("\(hunger) of \(HungerClock.maximumHunger)")
    }
}

/// The strength stat.
///
/// A number rather than pips, unlike hunger: `strengthStat` has no ceiling to read a bar against,
/// and the thing worth seeing is that a session moved it.
struct StrengthReadout: View {
    let strengthStat: Int

    var body: some View {
        HStack(spacing: 3) {
            Text("STR")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Text("\(strengthStat)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.red)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strength")
        .accessibilityValue("\(strengthStat)")
    }
}

/// The battle power and the win/loss record.
///
/// Power is shown next to the record because it is the number the battle is actually resolved from
/// (US-030), and a user who trains should be able to watch it move — a W/L record alone would leave
/// training feeling like it did nothing until the next fight.
///
/// The Battle button, its disabled rule and its daily-limit caption moved into `ActionControls` in
/// US-038, since the caption belongs under the row the button now lives in.
struct BattleReadout: View {
    let power: Int
    let wins: Int
    let losses: Int

    var body: some View {
        HStack(spacing: 3) {
            Text("PWR")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Text("\(power)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.purple)

            Text("\(wins)W \(losses)L")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battle power")
        .accessibilityValue("\(power), \(wins) wins, \(losses) losses")
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
