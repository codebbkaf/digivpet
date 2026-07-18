import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

/// The full-screen moment of ceremony when a Digimon evolves (or an egg hatches): the old form,
/// a white flash, then the new form with its name — and a `.success` haptic at the reveal.
///
/// Driven by a three-phase sequence rather than a single animation so the flash genuinely sits
/// between the two sprites: the old one is on screen alone, the screen whites out, and the new one
/// is revealed under its name. `onFinish` runs after the reveal has held long enough to read, and
/// the caller uses it to clear the pending event so the ceremony plays exactly once.
struct EvolutionCeremonyView: View {
    let event: MainScreenModel.EvolutionEvent
    let onFinish: () -> Void

    /// The `.success` tap at the reveal. Injected so a preview (and any host without a real device)
    /// can run the ceremony without a haptic; the app uses the real `WKInterfaceDevice`.
    var playHaptic: () -> Void = EvolutionCeremonyView.successHaptic

    /// The three beats of the ceremony.
    private enum Beat { case before, flash, after }
    @State private var beat: Beat = .before

    /// How long each beat holds. One place so the pacing is legible and tunable, and injected for
    /// the same reason `playHaptic` is: a test can drive the whole sequence in milliseconds instead
    /// of waiting out the real 4.2s of ceremony.
    var beforeDuration: TimeInterval = 1.0
    var flashDuration: TimeInterval = 0.6
    var afterDuration: TimeInterval = 2.6

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // The old form, fading out as the flash takes over.
            DigimonSpriteView(stage: event.from.spriteStage, name: event.from.spriteFile,
                              animation: .idle, scale: 4)
                .opacity(beat == .before ? 1 : 0)

            // The new form under its announced name, fading in at the reveal.
            VStack(spacing: 6) {
                DigimonSpriteView(stage: event.to.spriteStage, name: event.to.spriteFile,
                                  animation: .idle, scale: 4)
                Text(event.to.displayName)
                    .font(.headline)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .opacity(beat == .after ? 1 : 0)

            // The flash between them: a full white wash at its peak.
            Color.white
                .ignoresSafeArea()
                .opacity(beat == .flash ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await run() }
    }

    /// The three beats, in order. Not private so a test can drive it directly with a fast pacing
    /// and a haptic spy — the haptic is the one acceptance criterion the Simulator cannot show.
    func run() async {
        // The old form, alone.
        try? await Task.sleep(for: .seconds(beforeDuration))
        withAnimation(.easeIn(duration: 0.25)) { beat = .flash }

        // Peak of the flash, then the reveal — the haptic fires exactly with it.
        try? await Task.sleep(for: .seconds(flashDuration))
        playHaptic()
        withAnimation(.easeOut(duration: 0.4)) { beat = .after }

        // Hold the reveal long enough to read the name, then hand back.
        try? await Task.sleep(for: .seconds(afterDuration))
        onFinish()
    }

    /// The real haptic. No-ops where `WKInterfaceDevice` is unavailable (never on watchOS).
    static func successHaptic() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
}

#Preview {
    EvolutionCeremonyView(
        event: .init(
            from: DigimonPresentation(displayName: "Agumon", stage: .child, spriteFile: "Agumon"),
            to: DigimonPresentation(displayName: "Greymon", stage: .adult, spriteFile: "Greymon")
        ),
        onFinish: {},
        playHaptic: {}
    )
}
