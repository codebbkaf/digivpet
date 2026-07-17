import SwiftUI

/// Gates the app on health authorization.
///
/// The order is the point: `HealthOnboardingView` explains what is read and where it goes, and
/// only its Continue button raises the system prompt. Nothing here prompts on launch.
struct HealthAuthorizationGate<Content: View>: View {
    @StateObject private var model: HealthAuthorizationModel
    private let content: () -> Content

    /// The model is always passed in rather than defaulted: constructing one reaches
    /// `HKHealthStore()`, and a default argument is evaluated off the main actor.
    init(model: @autoclosure @escaping () -> HealthAuthorizationModel,
         @ViewBuilder content: @escaping () -> Content) {
        _model = StateObject(wrappedValue: model())
        self.content = content
    }

    var body: some View {
        Group {
            switch model.phase {
            case .checking, .requesting:
                ProgressView()
            case .explaining:
                HealthOnboardingView { await model.confirmAndRequest() }
            case .ready:
                content()
            case .denied:
                HealthAccessBlockedView(detail: model.failureDetail) { await model.start() }
            case .unavailable:
                HealthUnavailableView()
            }
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
}

/// Shown BEFORE the system prompt, so the user knows what is being asked and why.
struct HealthOnboardingView: View {
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
                    ForEach(HealthMetric.allCases, id: \.self) { metric in
                        Text("\(metric.displayName) → \(metric.energyType.displayName)")
                            .font(.caption)
                    }
                }

                Text("Never leaves this watch.")
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

                Text("On your watch, open Settings → Privacy & Security → Health → DigiVPet and turn on Steps, Active Energy, Sleep and Exercise Minutes.")
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
    HealthOnboardingView {}
}

#Preview("Blocked") {
    HealthAccessBlockedView(detail: "Authorization is not available.") {}
}
