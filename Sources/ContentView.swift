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
    @State private var showsTreeDemo = CommandLine.arguments.contains("-dexTreeDemo")
    #endif

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
            // Same reason again: since US-039 the bell is on screen without scrolling, but `simctl`
            // still cannot tap it.
            .navigationDestination(isPresented: $showsSettingsDemo) {
                NotificationSettingsView(settings: model.notificationSettings)
            }
            // US-041's tree, which has no way onto the screen until US-042 puts it on the Dex.
            .navigationDestination(isPresented: $showsTreeDemo) {
                EvolutionTreeDemoView()
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
            // No ScrollView (US-039). Everything the user acts with has to be reachable without
            // scrolling away from the Digimon, so the rows are all fixed-height and the sprite
            // takes whatever they leave — see `SpriteScale`. What used to be three stacked stat
            // blocks is one strip, which is most of the room that bought.
            VStack(spacing: 1) {
                if let state = model.state {
                    StatsStrip(hunger: state.hunger,
                               strengthStat: state.strengthStat,
                               power: state.battlePower,
                               wins: state.battleWins,
                               losses: state.battleLosses)
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
                        scale: SpriteScale.fitting(geometry.size.height),
                        isMoving: model.isWandering
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)

                // Name, stage and action message share ONE row since US-039, where the name had a
                // headline row to itself above the sprite. That row cost 16 of the 136 points a
                // 42mm screen has, which is a third of the Digimon. The slot is still always
                // present, so a message still does not shove the sprite up mid-animation; what a
                // message now costs is the name for the two seconds it is up, and while a Digimon
                // is refusing food its name is not the thing the user needs to read.
                Text(model.actionMessage ?? "\(presentation.displayName) · \(presentation.stage.displayName)")
                    .font(.system(size: 12, weight: model.actionMessage == nil ? .semibold : .regular))
                    .foregroundStyle(model.actionMessage == nil ? Color.primary : Color.orange)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if let progress = model.energyProgress {
                    EnergyBarsView(progress: progress, dominant: model.state?.dominantEnergyType)
                }

                if model.state != nil {
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
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battle power")
            .accessibilityValue("\(power), \(wins) wins, \(losses) losses")
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

            Text(value)
                .font(.system(size: 11, weight: .semibold))
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
