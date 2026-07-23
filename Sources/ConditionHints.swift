import Foundation

/// The flavour text a condition shows the player when it will not show them the number.
///
/// A hint is a NUDGE, never a checklist. The player should finish reading one knowing which
/// direction to push and not knowing where the line is — that gap is the whole of the discovery
/// loop, and a leaked threshold closes it permanently for that branch. So the vocabulary here is
/// deliberately written in the Digimon's voice ("It turns toward the sun.") rather than the
/// player's imperative voice ("Get more daylight"): a sentence about what the creature WANTS has
/// nowhere natural to put a number, where an instruction is always one edit away from growing one.
/// `ConditionHintTests.testNoHintContainsADigit` pins that as an invariant across both the
/// defaults below and every hint authored in `evolutions.json`.
extension ConditionMetric {
    /// What this metric says when an edge does not say anything more specific.
    ///
    /// Exhaustive on purpose — no `default:` clause. Adding a case to `ConditionMetric` must be a
    /// compile error here, because the alternative is a new metric silently inheriting some other
    /// metric's flavour text and quietly telling the player the wrong thing.
    var defaultHint: String {
        switch self {
        // MARK: health.* — quantity types

        case .healthSteps:
            return "Restless. It wants to see the horizon."
        case .healthDistanceWalkingRunning:
            return "It measures the world in ground covered."
        case .healthFlightsClimbed:
            return "It looks up, always, at anything tall."
        case .healthExerciseMinutes:
            return "It is happiest out of breath."
        case .healthStandTime:
            return "It fidgets whenever you settle."
        case .healthActiveEnergy:
            return "It feeds on effort spent."
        case .healthBasalEnergy:
            return "Something in it burns even at rest."
        case .healthVO2Max:
            return "It admires a deep and steady lung."
        case .healthRestingHeartRate:
            return "It listens for a slow, calm pulse."
        case .healthHeartRateVariability:
            return "It thrives where the heart is unhurried and free."
        case .healthRespiratoryRate:
            return "It breathes in time with you."
        case .healthOxygenSaturation:
            return "It wants clean air in your blood."
        case .healthDistanceSwimming:
            return "It dreams of open water."
        case .healthDistanceCycling:
            return "It leans into the turns with you."
        case .healthWater:
            return "It thirsts on your behalf."
        case .healthDaylight:
            return "It turns toward the sun."
        case .healthPhysicalEffort:
            return "It respects hard, honest work."
        case .healthAudioExposure:
            return "Loud places make it cower."

        // MARK: health.* — category types

        case .healthHandwashing:
            return "It flinches from grime."
        case .healthMindfulMinutes:
            return "It listens for stillness."
        case .healthStandHours:
            return "It cannot bear sitting still."
        case .healthToothbrushing:
            return "It bares its teeth and expects yours to shine."
        case .healthSleep:
            return "It rests only as well as you do."
        case .healthHighHeartRateEvents:
            return "A racing heart unsettles it."
        case .healthLowCardioFitnessEvents:
            return "It worries when your wind runs short."
        case .healthWalkingSteadinessEvents:
            return "It watches your footing."
        case .healthWorkouts:
            return "It counts the times you chose to train."

        // MARK: care.* — game counters

        case .careTrainingSessions:
            return "It sharpens itself against you."
        case .careOverfeeds:
            return "It eats whatever you offer, well past wisdom."
        case .careSleepDisturbances:
            return "It remembers every night you woke it."
        case .careBattleCount:
            return "It goes looking for a fight."
        case .careBattleWinRatio:
            return "Losing shames it."
        case .careLightOff:
            return "It comes alive when the lights go out."
        }
    }
}

/// Resolves the one line of flavour text a condition shows.
///
/// A free function on a caseless enum rather than a computed property on `EvolutionCondition`, so
/// the fallback for an unknown metric lives somewhere a test can name and reach directly. Pure: it
/// touches no clock, no store and no view, and `ConditionHintTests` exercises every branch without
/// building anything SwiftUI.
enum ConditionHint {
    /// Shown when a condition names a metric the vocabulary does not have.
    ///
    /// Unreachable through shipped data — `EvolutionGraphValidator` rejects both an unknown metric
    /// and a blank hint, and `EvolutionGraphTests` runs the validator over `evolutions.json`. It
    /// exists so that a graph edited at runtime, or a future data source that skips validation,
    /// degrades to a vague true statement instead of an empty row the player reads as a bug.
    static let fallback = "It wants something it cannot name yet."

    /// The line for this condition: its authored hint if it has one, else its metric's default.
    ///
    /// An authored hint WINS because it can say what the metric alone cannot — the same
    /// `care.trainingSessions` metric gates both "It sharpens itself against you" and the junk
    /// branch's "Stop once it has had enough for this stage", and only the edge knows which. A
    /// hint that is blank or nothing but whitespace counts as unauthored: the validator treats
    /// those as identical, and so must this, or an edge could pass validation-by-a-space and show
    /// the player an empty line.
    static func resolve(for condition: EvolutionCondition) -> String {
        let authored = condition.hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authored.isEmpty { return authored }
        return condition.knownMetric?.defaultHint ?? fallback
    }
}
