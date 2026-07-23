import Foundation

/// What a condition's metric is worth right now, or the fact that nothing can say.
///
/// `.unknown` is NOT zero, and keeping the two apart is the whole point of this type. A denied or
/// unreadable HealthKit metric reads as zero everywhere downstream (`HealthReading.energyValue`
/// deliberately flattens `noData` and `unavailable` to 0 so one denial cannot cost three energy
/// types), and a zero SATISFIES an `atMost` gate. Passing that zero into a comparison would hand a
/// player the "did almost none of this" branch precisely because the app could not read whether
/// they did it — the opposite of earning it. So an unknown value fails its condition whichever way
/// the comparison points.
enum ConditionValue: Equatable {
    case known(Double)
    case unknown
}

/// Everything `EvolutionEngine` needs to answer an `EvolutionCondition`, gathered at the call site.
///
/// A value type built from `GameState` rather than a reference to it, so the engine stays a pure
/// function of its inputs and a test can state a scenario in one literal.
///
/// **Every field is optional and defaults to nil, and nil means `.unknown`, not zero.** That makes
/// `.unknown` — a context that can answer nothing — the default a caller gets by omission. A caller
/// that forgets to supply the numbers therefore fails every condition rather than passing the ones
/// that happen to be phrased as `atMost`, which is the direction an omission has to fail in.
struct ConditionContext: Equatable {
    /// US-058's per-stage totals — `window: .stage` for an accumulating `health.*` metric.
    var stageTotals: MetricTotals?
    /// US-058's whole-life totals — `window: .lifetime`.
    var lifetimeTotals: MetricTotals?
    /// US-058's best single local day THIS STAGE — `window: .day`. See `stageBestDayMetrics` for
    /// why a `.day` condition asks about the best day and not today's.
    var bestDayThisStage: MetricTotals?

    /// US-084's stage-scoped care counters.
    var trainingSessionsThisStage: Int?
    var overfeedsThisStage: Int?
    var sleepDisturbancesThisStage: Int?

    /// Battles fought in the local day containing "now" — `GameState.battlesFought(now:)`.
    var battlesToday: Int?
    /// Battles fought over the whole life: wins plus losses.
    var battlesLifetime: Int?
    /// `GameState.battleWinRatio`, a 0.0–1.0 fraction. Lifetime, like the record it derives from.
    var battleWinRatioLifetime: Double?

    /// Directly-read health metrics, for the ones a running total cannot answer.
    ///
    /// A resting heart rate or a VO2 max is a standing measurement, not something that adds up —
    /// `ConditionMetric.accumulatesOverTime` is false for exactly those, and US-057's
    /// `HealthMetricReader` averages them over a window instead. Such a metric is answerable ONLY
    /// from here; absent, it is `.unknown` and its condition fails.
    ///
    /// An entry here also OVERRIDES the ledger when it is `.unavailable`, for accumulating metrics
    /// too: the ledger cannot tell "they walked no steps" from "we were never allowed to look", and
    /// a caller that knows the read failed is the only thing that can.
    var readings: [ConditionMetric: HealthReading]

    /// A context that can answer nothing. Every condition evaluated against it fails.
    static let unknown = ConditionContext()

    init(
        stageTotals: MetricTotals? = nil,
        lifetimeTotals: MetricTotals? = nil,
        bestDayThisStage: MetricTotals? = nil,
        trainingSessionsThisStage: Int? = nil,
        overfeedsThisStage: Int? = nil,
        sleepDisturbancesThisStage: Int? = nil,
        battlesToday: Int? = nil,
        battlesLifetime: Int? = nil,
        battleWinRatioLifetime: Double? = nil,
        readings: [ConditionMetric: HealthReading] = [:]
    ) {
        self.stageTotals = stageTotals
        self.lifetimeTotals = lifetimeTotals
        self.bestDayThisStage = bestDayThisStage
        self.trainingSessionsThisStage = trainingSessionsThisStage
        self.overfeedsThisStage = overfeedsThisStage
        self.sleepDisturbancesThisStage = sleepDisturbancesThisStage
        self.battlesToday = battlesToday
        self.battlesLifetime = battlesLifetime
        self.battleWinRatioLifetime = battleWinRatioLifetime
        self.readings = readings
    }

    /// The value of `metric` over `window`, or `.unknown` where this context cannot say.
    func value(for metric: ConditionMetric, window: ConditionWindow) -> ConditionValue {
        metric.isHealthMetric
            ? healthValue(for: metric, window: window)
            : careValue(for: metric, window: window)
    }

    private func healthValue(for metric: ConditionMetric, window: ConditionWindow) -> ConditionValue {
        // A read the caller knows failed beats any total, which cannot distinguish a real zero from
        // a metric we were never allowed to read.
        if let reading = readings[metric], reading == .unavailable { return .unknown }

        guard metric.accumulatesOverTime else {
            // A standing measurement: only a direct read answers it, and only a real number does.
            // `noData` is not zero — nobody measured, so nothing is known.
            guard case .value(let measured)? = readings[metric] else { return .unknown }
            return .known(measured)
        }

        let totals: MetricTotals?
        switch window {
        case .stage: totals = stageTotals
        case .lifetime: totals = lifetimeTotals
        case .day: totals = bestDayThisStage
        }
        // `known(_:)`, not the subscript: an absent metric was never credited and is `.unknown`, not
        // a real zero. Reading it as zero would satisfy an `atMost` gate for free (US-180). A metric
        // credited to exactly 0 is present in the totals and stays `.known(0)`.
        guard let totals, let value = totals.known(metric) else { return .unknown }
        return .known(value)
    }

    /// The `care.*` counters, each answerable over the window it is actually kept in and `.unknown`
    /// over the others.
    ///
    /// Deliberately not "close enough": the three stage counters are stage-scoped and there is no
    /// lifetime copy of them, `care.battleCount` is kept per local day (the US-032 battle cap) with
    /// a lifetime total derivable from the win/loss record but no stage-scoped one, and
    /// `care.battleWinRatio` is lifetime only — US-084 note 4 is explicit that a per-stage ratio
    /// needs new stage-scoped win/loss fields and that this one must not be repurposed. Answering a
    /// window a counter does not track by handing back the nearest number it does track would make
    /// an edge silently gate on something other than what it says.
    private func careValue(for metric: ConditionMetric, window: ConditionWindow) -> ConditionValue {
        func known(_ count: Int?) -> ConditionValue {
            count.map { .known(Double($0)) } ?? .unknown
        }
        switch metric {
        case .careTrainingSessions:
            return window == .stage ? known(trainingSessionsThisStage) : .unknown
        case .careOverfeeds:
            return window == .stage ? known(overfeedsThisStage) : .unknown
        case .careSleepDisturbances:
            return window == .stage ? known(sleepDisturbancesThisStage) : .unknown
        case .careBattleCount:
            switch window {
            case .day: return known(battlesToday)
            case .lifetime: return known(battlesLifetime)
            case .stage: return .unknown
            }
        case .careBattleWinRatio:
            guard window == .lifetime, let ratio = battleWinRatioLifetime else { return .unknown }
            return .known(ratio)
        default:
            // Unreachable while `isHealthMetric` routes the health family away, and a failure
            // rather than a crash if a later story adds a `care.*` case and forgets this switch.
            return .unknown
        }
    }
}

extension ConditionContext {
    /// A context with EVERY field populated, so that `value(for:window:)` returns `.known` for a
    /// (metric, window) pair whenever any game state at all could answer it.
    ///
    /// This is the probe `ConditionMetric.answerableWindows` runs: a pair still `.unknown` against a
    /// context this full is one the evaluator can *never* answer — the metric is simply not kept over
    /// that window (e.g. `care.battleCount` per stage) — not merely one this player's data is missing.
    /// Deriving the rule from the evaluator itself is deliberate: a hand-authored table of answerable
    /// windows would drift the day `careValue`/`healthValue` gains a case, and this cannot.
    static func fullyPopulated(for metric: ConditionMetric) -> ConditionContext {
        let totals = MetricTotals(values: [metric.rawValue: 1])
        return ConditionContext(
            stageTotals: totals,
            lifetimeTotals: totals,
            bestDayThisStage: totals,
            trainingSessionsThisStage: 1,
            overfeedsThisStage: 1,
            sleepDisturbancesThisStage: 1,
            battlesToday: 1,
            battlesLifetime: 1,
            battleWinRatioLifetime: 0.5,
            readings: [metric: .value(1)])
    }

    /// The context describing `state` right now.
    ///
    /// - Parameter readings: direct reads for the metrics no running total can answer — see
    ///   `readings`. Empty by default: a caller with no live reads still answers every accumulating
    ///   and `care.*` condition off the saved state, and fails the standing-measurement ones rather
    ///   than guessing at them.
    init(
        state: GameState,
        now: Date,
        calendar: Calendar = .current,
        readings: [ConditionMetric: HealthReading] = [:]
    ) {
        self.init(
            stageTotals: state.stageMetricTotals,
            lifetimeTotals: state.lifetimeMetricTotals,
            bestDayThisStage: state.stageBestDayMetrics,
            trainingSessionsThisStage: state.stageTrainingSessions,
            overfeedsThisStage: state.stageOverfeeds,
            sleepDisturbancesThisStage: state.stageSleepDisturbances,
            battlesToday: state.battlesFought(now: now, calendar: calendar),
            battlesLifetime: state.battleWins + state.battleLosses,
            battleWinRatioLifetime: state.battleWinRatio,
            readings: readings)
    }
}

extension ConditionMetric {
    /// The windows over which the evaluator can EVER return a `.known` value for this metric.
    ///
    /// The health family is kept over all three windows (a running total per stage/lifetime, a best
    /// day, or a direct read for a standing measurement), so every health metric answers all three.
    /// The `care.*` counters are each kept over ONLY the window they live in — training/overfeeds/
    /// sleep-disturbances per stage, `care.battleCount` per day and per lifetime, `care.battleWinRatio`
    /// lifetime only — and are `.unknown` over the rest.
    ///
    /// Computed by probing `ConditionContext.fullyPopulated(for:)`, so it can never disagree with the
    /// evaluator it is meant to describe.
    var answerableWindows: Set<ConditionWindow> {
        let probe = ConditionContext.fullyPopulated(for: self)
        return Set(ConditionWindow.allCases.filter { probe.value(for: self, window: $0) != .unknown })
    }

    /// Whether the evaluator can ever answer this metric over `window`.
    ///
    /// False for a (metric, window) pair that is `.unknown` no matter how much data is present — an
    /// edge or Digitama slot authored on such a pair can never qualify, and both `EvolutionGraph`
    /// and `MapCatalog` validation reject it (US-184).
    func canBeAnswered(over window: ConditionWindow) -> Bool {
        answerableWindows.contains(window)
    }
}

/// Answers a single `EvolutionCondition` against a `ConditionContext`.
enum ConditionEvaluator {
    /// Whether `condition` holds. False for anything unanswerable — an unknown value, or a metric
    /// name that is not in the vocabulary at all.
    ///
    /// An unrecognised metric is `EvolutionGraphValidator`'s `unknownConditionMetric` and should
    /// never reach a shipped build; if one does, failing the condition keeps the edge shut rather
    /// than opening a branch on a criterion nothing can check. The `isDefault` fallback still
    /// guarantees the Digimon is not stuck.
    static func isSatisfied(_ condition: EvolutionCondition, in context: ConditionContext) -> Bool {
        guard let metric = condition.knownMetric else { return false }
        guard case .known(let value) = context.value(for: metric, window: condition.window) else {
            return false
        }
        switch condition.comparison {
        case .atLeast: return value >= condition.value
        case .atMost: return value <= condition.value
        }
    }
}
