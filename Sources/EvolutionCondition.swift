import Foundation

/// The single gating vocabulary an evolution criterion may be authored against.
///
/// Two families, deliberately in ONE enum rather than two: an edge's `conditions` list mixes them
/// freely, and splitting the vocabulary would mean two parallel arrays on the edge and two of
/// every validator rule.
///
/// - `health.*` — HealthKit-backed. Every case here is an identifier US-055 probed and marked
///   **usable** on watchOS 26.4 (see `docs/health-metrics.md`); nothing else may be added without
///   probing it first. "Usable" means the type exists and is readable — it does NOT mean it ever
///   carries data. Seven of these are typically iPhone- or feature-sourced (`toothbrushingEvent`,
///   `handwashingEvent`, `dietaryWater`, `timeInDaylight`, `environmentalAudioExposure`,
///   `lowCardioFitnessEvent`, `appleWalkingSteadinessEvent`); an edge gated on one of those must
///   be a bonus branch, never the only way out of a node, or an empty metric on real hardware
///   makes that Digimon unreachable.
/// - `care.*` — game counters the engine keeps itself. These exist because nothing in the edge
///   schema could express them before: `minEnergy`, `maxCareMistakes` and `minBattleWins` are the
///   whole of the old vocabulary.
///
/// `care.careMistakes` is deliberately ABSENT. The edge's existing `maxCareMistakes` field already
/// gates on that counter, and two ways to say one thing invites a later iteration to delete one of
/// them — and to delete the wrong one, because the edges in the file use the field.
enum ConditionMetric: String, CaseIterable {
    // MARK: health.* — quantity types

    case healthSteps = "health.steps"
    case healthDistanceWalkingRunning = "health.distanceWalkingRunning"
    case healthFlightsClimbed = "health.flightsClimbed"
    case healthExerciseMinutes = "health.exerciseMinutes"
    case healthStandTime = "health.standTime"
    case healthActiveEnergy = "health.activeEnergy"
    case healthBasalEnergy = "health.basalEnergy"
    case healthVO2Max = "health.vo2Max"
    case healthRestingHeartRate = "health.restingHeartRate"
    case healthHeartRateVariability = "health.heartRateVariability"
    case healthRespiratoryRate = "health.respiratoryRate"
    case healthOxygenSaturation = "health.oxygenSaturation"
    case healthDistanceSwimming = "health.distanceSwimming"
    case healthDistanceCycling = "health.distanceCycling"
    case healthWater = "health.water"
    case healthDaylight = "health.daylight"
    case healthPhysicalEffort = "health.physicalEffort"
    case healthAudioExposure = "health.audioExposure"

    // MARK: health.* — category types

    case healthHandwashing = "health.handwashing"
    case healthMindfulMinutes = "health.mindfulMinutes"
    case healthStandHours = "health.standHours"
    case healthToothbrushing = "health.toothbrushing"
    case healthSleep = "health.sleep"
    case healthHighHeartRateEvents = "health.highHeartRateEvents"
    case healthLowCardioFitnessEvents = "health.lowCardioFitnessEvents"
    case healthWalkingSteadinessEvents = "health.walkingSteadinessEvents"

    // MARK: health.* — workouts

    /// Workout count. A single `HKWorkoutType.workoutType()` read grant covers every activity
    /// type — there is no per-activity authorization — so bucketing by activity needs no new
    /// metric here, only a filter at read time.
    case healthWorkouts = "health.workouts"

    // MARK: care.* — game counters

    case careTrainingSessions = "care.trainingSessions"
    case careOverfeeds = "care.overfeeds"
    case careSleepDisturbances = "care.sleepDisturbances"
    case careBattleCount = "care.battleCount"

    /// Wins as a 0.0–1.0 FRACTION of battles fought, not a count. This is what `minBattleWins`
    /// cannot express: DMC's "15+ battles at 80%+ wins" is `care.battleCount atLeast 15` plus
    /// `care.battleWinRatio atLeast 0.8`, where a win COUNT alone would let 15 wins in 200 battles
    /// through. `minBattleWins` stays and keeps working; an edge may use either or both.
    case careBattleWinRatio = "care.battleWinRatio"

    /// True for the HealthKit-backed family. Used by the validator's range rules and by US-061
    /// when it decides which criteria need an authorization grant.
    var isHealthMetric: Bool { rawValue.hasPrefix("health.") }

    /// True for the seven HealthKit metrics that are typically iPhone- or feature-sourced and so are
    /// usually EMPTY on a watch-only user's device — the set the type comment above names:
    /// handwashing, toothbrushing, dietary water, time in daylight, environmental audio exposure,
    /// low-cardio-fitness events and walking-steadiness events.
    ///
    /// The doc comment above already STATES the rule these metrics live under — a condition on one of
    /// them "must be a bonus branch, never the only way out of a node, or an empty metric on real
    /// hardware makes that Digimon unreachable". This property is what lets a validator ENFORCE it.
    /// It matters more for a Digitama slot than for an evolution edge: a slot is the ONLY route to
    /// its egg, so a slot gated solely on one of these is an egg no watch-only player can ever earn.
    /// See `MapValidationError.soleSparseCondition` and US-128.
    var isSparseOnHardware: Bool {
        switch self {
        case .healthHandwashing, .healthToothbrushing, .healthWater, .healthDaylight,
             .healthAudioExposure, .healthLowCardioFitnessEvents, .healthWalkingSteadinessEvents:
            return true
        default:
            return false
        }
    }
}

/// The span of history a condition's value is measured over.
enum ConditionWindow: String, Codable, Equatable {
    /// Since the Digimon entered its current stage. The default reading of an evolution criterion:
    /// what you did to EARN this evolution, not what you did two forms ago.
    case stage
    /// Today only, from local midnight. For "walk 10,000 steps in a single day" criteria, which a
    /// stage-long total would trivially satisfy.
    case day
    /// The whole life of this Digimon, across every stage.
    case lifetime
}

/// Which side of `value` satisfies the condition.
enum ConditionComparison: String, Codable, Equatable {
    case atLeast
    case atMost
}

/// One criterion on an evolution edge. ALL of an edge's conditions must hold for it to qualify.
///
/// A **band** is two conditions on one edge — `atLeast X` plus `atMost Y` on the same metric. That
/// reproduces the Digital Monster Color pattern where training 8–31 earns the good branch while
/// 0–7 *and* 32+ both fall through to the junk one: overtraining is punished exactly as much as
/// undertraining. There is no `between` comparison because two conditions already say it, and a
/// third spelling of the same idea is a third thing to validate.
struct EvolutionCondition: Codable, Equatable {
    /// The metric, as authored. Kept as a STRING rather than a `ConditionMetric` on purpose: an
    /// unrecognised metric has to be a validation error, and a typed property would make it a
    /// DECODE error instead — which `EvolutionGraph.bundled` turns into a launch trap that kills
    /// the whole test suite naming neither the file nor the metric. `metric` is the one field here
    /// whose vocabulary will keep growing, so it is the one that gets this treatment; `window` and
    /// `comparison` are closed sets and decode strictly.
    let metric: String

    /// The parsed metric, or nil if `metric` names nothing in the vocabulary. Nil is what
    /// `EvolutionGraphValidator` reports as `unknownConditionMetric`.
    var knownMetric: ConditionMetric? { ConditionMetric(rawValue: metric) }

    let window: ConditionWindow
    let comparison: ConditionComparison

    /// The threshold, in the metric's own unit — steps, minutes, kilocalories, a count, or a
    /// 0.0–1.0 fraction for `care.battleWinRatio`. Never negative.
    let value: Double

    /// One line shown to the user, in their terms: "Walk 10,000 steps a day". Never blank — a
    /// condition with no hint is a criterion the player cannot discover, which reads to them as
    /// the evolution being random.
    let hint: String

    init(
        metric: String,
        window: ConditionWindow,
        comparison: ConditionComparison,
        value: Double,
        hint: String
    ) {
        self.metric = metric
        self.window = window
        self.comparison = comparison
        self.value = value
        self.hint = hint
    }

    /// Convenience for the common case of a metric that is known at the call site.
    init(
        metric: ConditionMetric,
        window: ConditionWindow,
        comparison: ConditionComparison,
        value: Double,
        hint: String
    ) {
        self.init(
            metric: metric.rawValue, window: window, comparison: comparison,
            value: value, hint: hint)
    }
}
