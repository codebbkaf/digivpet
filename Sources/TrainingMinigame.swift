import SwiftUI

/// How well one training round went — the single shape every minigame reports (US-075).
///
/// Four grades rather than a score, because the games have nothing in common numerically: a timing
/// bar measures pixels off centre, a masher measures taps per second, a sequence game measures
/// remembered steps. Grading each one to the SAME four names is what lets `TrainAction` pay them all
/// out with one rule, and what lets a seventh game be a new file rather than a new payout branch.
///
/// A `miss` is a real ending, not an error: the round happened, the energy was spent, and the only
/// thing it failed to buy was the stat. See `TrainAction.begin`.
enum TrainingResult: String, CaseIterable, Equatable {
    case miss, good, great, perfect

    /// `strengthStat` bought by a round at this grade — 0 / 1 / 2 / 3.
    ///
    /// `good` is 1, deliberately: it is what an ungraded session paid before minigames existed, so
    /// the scale extends the old value upward rather than repricing it. A `miss` is 0 and NOT
    /// negative — the round already cost energy, and taking a stat away as well would make training
    /// something a cautious player avoids.
    var strengthGain: Int {
        switch self {
        case .miss: return 0
        case .good: return 1
        case .great: return 2
        case .perfect: return 3
        }
    }

    /// What the round is called on screen when it ends.
    var displayName: String {
        switch self {
        case .miss: return "Miss"
        case .good: return "Good"
        case .great: return "Great"
        case .perfect: return "Perfect"
        }
    }

    /// What colour a finished round is announced in. Lives here rather than on a game so all six
    /// end the same way — a `Perfect` must not be a different yellow depending on which minigame
    /// paid it.
    ///
    /// A miss is grey rather than red: it cost energy already, and shouting at the user for it is
    /// what makes training something to avoid.
    var tint: Color {
        switch self {
        case .miss: return .secondary
        case .good: return .green
        case .great: return .mint
        case .perfect: return .yellow
        }
    }
}

/// The one shape every training minigame conforms to (US-075).
///
/// A minigame is a full-screen view that ends EXACTLY ONCE, by handing back a `TrainingResult`. It
/// knows nothing about energy, `strengthStat`, saving, or eligibility — `TrainAction` charged the
/// round before the view appeared and pays it out after, so a game is only ever a way of producing a
/// grade. That is the whole point of the protocol: adding a seventh game is adding a file that can
/// produce one of four values.
///
/// Timing knobs (sweep speed, round length, prompt intervals) are stored properties with defaults on
/// the conforming type, set at the call site in the manner of `BattleView.turnDuration`, so a test
/// drives a whole round in milliseconds and never waits real time.
protocol TrainingMinigame: View {
    /// The game's name, shown while it is being played. Static so the assignment in US-082 can name
    /// a game without building one.
    static var title: String { get }

    /// The only initialiser every game is guaranteed to have.
    ///
    /// - Parameter onFinish: called once, with the grade the round earned. A game that abandons
    ///   itself (ran out of time, nothing tapped) reports `.miss` rather than never calling back —
    ///   a round that never ends is a round the user already paid for and cannot leave.
    init(onFinish: @escaping (TrainingResult) -> Void)
}

extension TrainingMinigame {
    /// How much of a fixed round window is left `elapsed` seconds in: 1 at the start, 0 when time is
    /// up. Clamped at both ends, and empty for a non-positive window rather than dividing by zero.
    ///
    /// Shared rather than per-game (US-079) because it means exactly one thing wherever it appears —
    /// a draining timer bar over a window that was fixed when the round began. Contrast
    /// `PowerMeterGame.chargeTint`, which only LOOKS shareable: that one is a live warning about a
    /// hold, not a fact about the clock.
    static func remainingFraction(at elapsed: TimeInterval, window: TimeInterval) -> CGFloat {
        guard window > 0 else { return 0 }
        return CGFloat(min(max(1 - elapsed / window, 0), 1))
    }
}
