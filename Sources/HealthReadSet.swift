import Foundation
import HealthKit

extension ConditionMetric {
    /// The HealthKit type a read grant for this metric needs, or nil where no grant applies.
    ///
    /// Nil for every `care.*` counter: those are the game's own numbers, kept in `GameState`, and
    /// asking HealthKit for permission to read them would be asking for a type that does not exist.
    ///
    /// `health.sleep` is spelled out here rather than deferred to `ReadableHealthMetric`, which
    /// returns nil for it — sleep is read by `SleepAnalysis` under a longest-block rule instead of a
    /// flat total, but it is still `.sleepAnalysis` that has to be GRANTED. Leaning on the reader's
    /// nil would silently drop sleep from the ask, which is the one failure mode this whole type
    /// exists to prevent. (Today it is granted anyway via `HealthMetric.sleep`; that is a
    /// coincidence of the energy model, not something a condition should depend on.)
    var readObjectType: HKObjectType? {
        if self == .healthSleep { return HKCategoryType(.sleepAnalysis) }
        return ReadableHealthMetric(self)?.sampleType
    }
}

extension EvolutionGraph {
    /// Every `health.*` metric named by a condition anywhere in the graph.
    ///
    /// Unknown metric strings are skipped rather than trapping: an unrecognised metric is
    /// `EvolutionGraphValidator`'s `unknownConditionMetric` to report, and turning it into a crash
    /// here would kill the app at launch over a typo the validator already names precisely.
    var conditionHealthMetrics: Set<ConditionMetric> {
        Set(
            nodes
                .lazy
                .flatMap(\.evolutions)
                .flatMap(\.conditions)
                .compactMap(\.knownMetric)
                .filter(\.isHealthMetric)
        )
    }
}

/// Every HealthKit type the app asks to read, in one place.
///
/// The condition half is **derived from the evolution graph, never hardcoded**, and that is the
/// whole point: a list maintained by hand goes stale the first time someone authors a condition on
/// a metric and forgets to add it here. The symptom would be silent — HealthKit answers an
/// unauthorized read with no samples, indistinguishable from a user who simply did not do the
/// thing — so the edge would just never fire, and nothing would say why. Deriving it means
/// authoring the condition IS granting the metric.
///
/// The two halves stay separate rather than collapsing into one bag of `HKObjectType` because they
/// answer different questions and the onboarding copy needs both: `energyMetrics` are what FEED the
/// Digimon (one per `EnergyType`, always all four), `conditionMetrics` only STEER which one it
/// becomes. A user can reasonably grant the first and refuse the second.
struct HealthReadSet: Equatable {
    /// The four energy metrics. Always every case — an energy type with no grant is an energy bar
    /// that can never fill, so this half is not derived from anything and not negotiable.
    let energyMetrics: [HealthMetric]

    /// The `health.*` metrics some evolution condition is authored against, in a stable order so
    /// the onboarding copy does not reshuffle between launches.
    let conditionMetrics: [ConditionMetric]

    init(energyMetrics: [HealthMetric] = HealthMetric.allCases,
         conditionMetrics: [ConditionMetric] = []) {
        self.energyMetrics = energyMetrics
        self.conditionMetrics = conditionMetrics.sorted { $0.rawValue < $1.rawValue }
    }

    /// The read set an evolution graph implies.
    ///
    /// `care.*` conditions contribute nothing, correctly: they need no grant, and including them
    /// would mean either a nil object type to filter out later or a fake one to explain forever.
    static func deriving(from graph: EvolutionGraph) -> HealthReadSet {
        HealthReadSet(conditionMetrics: Array(graph.conditionHealthMetrics))
    }

    /// The shipped graph's read set. Matches how `EvolutionGraph.bundled` is reached everywhere
    /// else: the real app derives from the real file, tests pass their own graph in.
    static var bundled: HealthReadSet { .deriving(from: .bundled) }

    /// What actually goes to `HKHealthStore`, deduplicated.
    ///
    /// A union, and the deduplication is load-bearing rather than tidiness: `health.steps`,
    /// `health.activeEnergy`, `health.exerciseMinutes` and `health.sleep` name the SAME four
    /// HealthKit types the energy model already reads, so an authored condition on any of them
    /// must not show up as a second entry. HealthKit takes a `Set` in the end anyway; building one
    /// here is what lets `count` be a number worth asserting on.
    var objectTypes: Set<HKObjectType> {
        Set(energyMetrics.map(\.objectType)).union(conditionMetrics.compactMap(\.readObjectType))
    }

    /// The types asked for BEYOND the four the energy model already needed.
    ///
    /// This is what a returning user is newly prompted about — HealthKit only raises a prompt for
    /// types the user has not answered for, so an empty set here means a returning user sees no
    /// prompt at all. Also what decides whether the onboarding screen has anything extra to explain.
    var additionalObjectTypes: Set<HKObjectType> {
        objectTypes.subtracting(energyMetrics.map(\.objectType))
    }

    /// One line for the onboarding screen explaining the extra types, or nil when there are none.
    ///
    /// A COUNT rather than a list, deliberately. `HealthOnboardingView` fits a 41mm screen only
    /// because it is four short lines, and the graph may name a couple of dozen metrics — spelling
    /// them all out would push Continue under a scroll, which the view's own note explains is how a
    /// user ends up denying access they would have granted. Nil rather than empty text so a graph
    /// with no conditions renders no stray line and promises nothing it does not read.
    var additionalTypesDescription: String? {
        let count = additionalObjectTypes.count
        guard count > 0 else { return nil }
        let noun = count == 1 ? "reading" : "readings"
        return "Plus \(count) more \(noun), used only to decide what your Digimon evolves into."
    }
}
