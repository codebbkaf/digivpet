import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

/// The full-screen memorial for a Digimon that has died: what it was called, how long it lived, and
/// what it achieved — then the button that starts the next one.
///
/// Shown as an overlay above the whole main screen for the same reason `EvolutionCeremonyView` is:
/// this is not a state the user can play around, and leaving the energy bars and the Feed button
/// visible underneath would invite tapping them. Dismissal is deliberately a BUTTON and not a timer
/// — a death should not scroll past while the watch is on a wrist that was not looking.
struct MemorialView: View {
    let memorial: Memorial
    /// Starts the next Digimon. The caller wires this to the rebirth, which is why the label says
    /// what will happen rather than "OK".
    let onDismiss: () -> Void

    /// The sombre tap the memorial opens with. Injected for the same reason
    /// `EvolutionCeremonyView.playHaptic` is: it is the one thing no screenshot can show, so a test
    /// spies on it instead.
    var playHaptic: () -> Void = MemorialView.failureHaptic

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 4) {
                    Text(memorial.displayName)
                        .font(.headline)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    Text(memorial.stage.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // The lifespan, which is the headline of a memorial — big, and in the one unit
                    // the PRD names.
                    Text(lifespanText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .padding(.top, 2)

                    // The final stats, as label/value rows so they line up at any text size.
                    VStack(spacing: 2) {
                        MemorialStat(label: "Lifetime", value: "\(memorial.lifetimeEnergy.total)")
                        MemorialStat(label: "STR", value: "\(memorial.strengthStat)")
                        MemorialStat(label: "Battles",
                                     value: "\(memorial.battleWins)W \(memorial.battleLosses)L")
                    }
                    .padding(.top, 4)

                    // Said plainly, because it is the reassurance that makes a death bearable: the
                    // Dex and the lifetime total are not lost with the Digimon.
                    Text("Your Dex and lifetime energy carry over.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    Button(action: onDismiss) {
                        Label("New Digitama", systemImage: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { playHaptic() }
    }

    /// "3 days", and "1 day" rather than "1 days" — a Digimon that dies young is exactly the case
    /// where a plural bug would show.
    var lifespanText: String {
        "Lived \(memorial.lifespanDays) day\(memorial.lifespanDays == 1 ? "" : "s")"
    }

    /// The real haptic. `.failure` rather than the ceremony's `.success` — the two moments should be
    /// tellable apart without looking at the watch. No-ops where `WKInterfaceDevice` is unavailable
    /// (never on watchOS).
    static func failureHaptic() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.failure)
        #endif
    }
}

/// One label/value row of the memorial's final stats.
private struct MemorialStat: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MemorialView(
        memorial: Memorial(
            displayName: "Agumon",
            stage: .child,
            lifespanDays: 6,
            lifetimeEnergy: EnergyTotals(strength: 120, vitality: 80, spirit: 40, stamina: 30),
            strengthStat: 7,
            battleWins: 3,
            battleLosses: 1
        ),
        onDismiss: {},
        playHaptic: {}
    )
}
