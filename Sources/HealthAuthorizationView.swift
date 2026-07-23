import SwiftUI

/// Gates the app on health authorization.
///
/// The order is the point: `HealthOnboardingView` explains what is read and where it goes, and
/// only its Continue button raises the system prompt. Nothing here prompts on launch.
///
/// The content is handed the `HealthCollectionStatus` this gate derived, because US-215's Settings
/// row has to say what the gate decided rather than ask a second time. A plain value, not the
/// model: the gate observes the model, so a phase change re-renders and passes a fresh status down
/// on its own, and nothing below here needs to know HealthKit exists.
struct HealthAuthorizationGate<Content: View>: View {
    @StateObject private var model: HealthAuthorizationModel
    private let content: (HealthCollectionStatus) -> Content

    /// The model is always passed in rather than defaulted: constructing one reaches
    /// `HKHealthStore()`, and a default argument is evaluated off the main actor.
    init(model: @autoclosure @escaping () -> HealthAuthorizationModel,
         @ViewBuilder content: @escaping (HealthCollectionStatus) -> Content) {
        _model = StateObject(wrappedValue: model())
        self.content = content
    }

    #if DEBUG
    /// Whether the gate shows the app regardless of the phase.
    ///
    /// US-215's screenshot problem: two of the three statuses Settings can show are states the gate
    /// NEVER lets the app run in, so `-healthDenied` and `-healthUnavailable` alone photograph the
    /// onboarding and unavailable screens and never the Settings row. `-settingsDemo` — the flag
    /// that already pushes Settings, per US-213's "one flag per story" — waves the gate through as
    /// well, so `-settingsDemo -healthDenied` reaches the row it is meant to photograph.
    ///
    /// It moves nothing else: the status shown is still the one the real state machine computed
    /// from the injected authorizer, so what the screenshot proves about the row stays true.
    static func showsContentRegardless(
        _ arguments: [String] = CommandLine.arguments
    ) -> Bool {
        arguments.contains("-settingsDemo")
    }
    #endif

    var body: some View {
        Group {
            #if DEBUG
            if Self.showsContentRegardless() {
                content(model.collectionStatus)
            } else {
                phaseBody
            }
            #else
            phaseBody
            #endif
        }
        .task {
            await model.start()
            #if DEBUG
            // Screenshot hook: nothing can script a tap on the watchOS Simulator, so this
            // stands in for the Continue button when verifying that the REAL system prompt
            // appears. It calls exactly the method the button calls, against whichever
            // authorizer was injected — with no stub argument, that is real HealthKit.
            if ProcessInfo.processInfo.arguments.contains("-healthAutoConfirm"),
               model.phase == .explaining {
                await model.confirmAndRequest()
            }
            #endif
        }
    }

    @ViewBuilder
    private var phaseBody: some View {
        switch model.phase {
        case .checking, .requesting:
            ProgressView()
        case .explaining:
            HealthOnboardingView(readSet: model.readSet) { await model.confirmAndRequest() }
        case .ready:
            content(model.collectionStatus)
        case .denied:
            HealthAccessBlockedView(detail: model.failureDetail) { await model.start() }
        case .unavailable:
            HealthUnavailableView()
        }
    }
}

/// Shown BEFORE the system prompt, so the user knows what is being asked and why.
struct HealthOnboardingView: View {
    /// The ask this screen is explaining. Passed in rather than defaulted to the bundled graph's,
    /// so the screen can only ever describe the set that is actually about to be requested.
    let readSet: HealthReadSet
    let onContinue: () async -> Void

    var body: some View {
        ScrollView {
            // Kept tight enough that the whole thing — including Continue — fits a 41mm screen
            // without scrolling (verified at 41mm/42mm/46mm): a wall of text that hides the
            // button under a scroll is how a user ends up denying access they would have
            // granted. The ScrollView is the fallback for large accessibility text sizes.
            // Wording is load-bearing on line count; re-check 41mm before lengthening it.
            VStack(alignment: .leading, spacing: 6) {
                Text("Feed Your Digimon")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(readSet.energyMetrics, id: \.self) { metric in
                        Text("\(metric.displayName) → \(metric.energyType.displayName)")
                            .font(.caption)
                    }
                }

                // One summary line, not a list — see `additionalTypesDescription` for why a
                // couple of dozen metric names would break this screen. Absent entirely when the
                // graph names no extra metrics, so the screen never promises a read it will not do.
                if let extras = readSet.additionalTypesDescription {
                    Text(extras)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // The one promise, said in one place: `SettingsView` repeats this string after the
                // prompt has been answered, and the two must not drift (US-215).
                Text(HealthCopy.neverLeavesTheWatch)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button("Continue") {
                    Task { await onContinue() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The explanatory state for a request that failed.
///
/// watchOS has no `openSettingsURLString` — there is no API to deep-link a watch app into
/// Settings, so the guidance is spelled out instead of linked. Try Again re-runs the check
/// rather than dead-ending, since the user can fix this in Settings and come back.
struct HealthAccessBlockedView: View {
    let detail: String?
    let onRetry: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("No Health Access")
                    .font(.headline)

                Text("Your Digimon can't earn energy without it.")
                    .font(.footnote)

                // Deliberately does not name the types one by one any more: the ask now includes
                // whatever metrics the evolution graph's conditions name, and a hardcoded list here
                // would go stale exactly the way `HealthReadSet` exists to stop.
                Text("On your watch, open Settings → Privacy & Security → Health → DigiVPet and turn on everything listed there.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Button("Try Again") {
                    Task { await onRetry() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// HealthKit is missing entirely. Nothing to prompt for and nothing to fix, so this one has no
/// action — it just says so rather than leaving a spinner up forever.
struct HealthUnavailableView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Health Unavailable")
                    .font(.headline)
                Text("This device has no Health data, so DigiVPet can't feed your Digimon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Onboarding") {
    HealthOnboardingView(readSet: .bundled) {}
}

#Preview("Onboarding with evolution metrics") {
    HealthOnboardingView(
        readSet: HealthReadSet(conditionMetrics: [.healthFlightsClimbed, .healthMindfulMinutes])
    ) {}
}

#Preview("Blocked") {
    HealthAccessBlockedView(detail: "Authorization is not available.") {}
}
