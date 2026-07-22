import SwiftUI

/// Which of the six training minigames a Digimon trains with (US-082).
///
/// The games are six different `View` types with nothing in common but `TrainingMinigame`, so they
/// cannot be stored in a dictionary or compared. This enum is their NAME — a plain value the
/// assignment table, a saved game or a test can hold — and `view(onFinish:)` is the one place a name
/// turns back into a game.
///
/// `CaseIterable` is load-bearing: the assignment is only interesting if all six are reachable, and
/// `MinigameAssignmentTests` asserts exactly that against `allCases` rather than against a list it
/// keeps in step by hand.
enum MinigameKind: String, CaseIterable, Codable, Equatable {
    case timingBar, buttonMasher, powerMeter, crownSprint, reflexStrike, sequenceRecall

    /// The game's name, taken from the game type itself rather than restated here — a title shown on
    /// the assignment screen and a different one shown inside the round would be a bug nothing else
    /// could catch.
    var title: String {
        switch self {
        case .timingBar: return TimingBarGame.title
        case .buttonMasher: return ButtonMasherGame.title
        case .powerMeter: return PowerMeterGame.title
        case .crownSprint: return CrownSprintGame.title
        case .reflexStrike: return ReflexStrikeGame.title
        case .sequenceRecall: return SequenceRecallGame.title
        }
    }

    /// Builds the game this names, with every difficulty knob left at its default.
    ///
    /// A `@ViewBuilder` rather than `some View` because the six branches are six unrelated types.
    /// US-083 is what presents the result; nothing calls this yet.
    @ViewBuilder
    func view(onFinish: @escaping (TrainingResult) -> Void) -> some View {
        switch self {
        case .timingBar: TimingBarGame(onFinish: onFinish)
        case .buttonMasher: ButtonMasherGame(onFinish: onFinish)
        case .powerMeter: PowerMeterGame(onFinish: onFinish)
        case .crownSprint: CrownSprintGame(onFinish: onFinish)
        case .reflexStrike: ReflexStrikeGame(onFinish: onFinish)
        case .sequenceRecall: SequenceRecallGame(onFinish: onFinish)
        }
    }
}

/// Which minigame a given Digimon trains with — pure, total, and stable (US-082).
///
/// Two tiers, in the manner of `MoveCatalog`: the Digimon's evolution `line`, then its `stage` as a
/// floor. What differs from moves is that this is CODE, not JSON — a game is a Swift type, so a new
/// assignment cannot be a data edit the way a new attack can, and a table in the file that also
/// names the types is more honest than a JSON key that has to match a `case`.
///
/// Assignment is by LINE rather than by individual Digimon: raising a new line is what earns a new
/// game, and the six shipped lines take the six games one each. Within a line the game is constant
/// from Digitama to Ultimate, so the training a player has learned is not taken away by evolving.
///
/// There is deliberately no "no game" ending. Every lookup returns a `MinigameKind`, because the
/// only caller is a round the user has ALREADY paid for (`TrainAction.begin` charges before the
/// round opens) and "your Digimon has no training game" would be an unrefundable dead end.
enum MinigameAssignment {
    /// The six shipped lines, one game each.
    ///
    /// The keys are `EvolutionNode.line` values; `testTheTableNamesExactlyTheShippedLines` pins them
    /// against the graph, so renaming a line in `evolutions.json` fails a test rather than silently
    /// dropping that line to the stage floor.
    ///
    /// The pairings are flavour, not mechanism: the Digital Monster Ver.1 line hits things (Button
    /// Masher), Ver.2's is about holding a charge (Power Meter), Palmon's is patient timing
    /// (Timing Bar), Ver.3's runs (Crown Sprint), Ver.4's is quick (Reflex Strike), Gazimon's
    /// is the tricky one (Sequence Recall). Any permutation would satisfy the story; this one is a
    /// first guess and safe to reshuffle after playtesting.
    static let byLine: [String: MinigameKind] = [
        "dmc-v1": .buttonMasher,
        "dmc-v2": .powerMeter,
        "palmon": .timingBar,
        "dmc-v3": .crownSprint,
        "dmc-v4": .reflexStrike,
        "gazimon": .sequenceRecall,
    ]

    /// The game for a Digimon in no shipped line — decided by how far up the ladder it is, so the
    /// ~930 roster-only Digimon still get something that escalates rather than all sharing one game.
    ///
    /// Written as an exhaustive `switch` rather than `ladderIndex % 6`, because Armor-Hybrid has NO
    /// ladder index (see `Stage.ladderIndex`) and arithmetic would have to invent one. All six games
    /// appear here, so no game is unreachable through the fallback alone.
    static func fallback(for stage: Stage?) -> MinigameKind {
        switch stage {
        // A Digitama cannot train at all today (`TrainAction` never runs on an egg), but the answer
        // is still the simplest game rather than a crash, so a future hatchling tutorial has one.
        case .digitama, .babyI: return .buttonMasher
        case .babyII: return .timingBar
        case .child: return .powerMeter
        case .adult: return .crownSprint
        case .perfect: return .reflexStrike
        case .ultimate: return .sequenceRecall
        case .armorHybrid: return .crownSprint
        // An id in neither the graph nor the roster — impossible from a saved game, but the return
        // is non-optional on purpose, so it lands on the simplest game rather than on nothing.
        case nil: return .buttonMasher
        }
    }

    /// The game for a Digimon given its `line` (nil for a roster-only Digimon in no line) and
    /// `stage`. PURE — same inputs, same game, no I/O, no clock, no randomness — so both tiers are
    /// unit-testable without a graph or a bundle.
    static func game(line: String?, stage: Stage?) -> MinigameKind {
        if let line, let kind = byLine[line] { return kind }
        return fallback(for: stage)
    }

    /// The game for a Digimon by `id`, resolving its `line` and `stage` from the graph (which carries
    /// both) and, for a roster-only entry with no graph node, its `stage` from the roster. This is
    /// how the Train button will ask (US-083); the two-argument form above is the pure core.
    static func game(for id: String, in graph: EvolutionGraph, roster: Roster) -> MinigameKind {
        let node = graph.node(id: id)
        return game(line: node?.line, stage: node?.stage ?? roster.entry(id: id)?.stage)
    }
}
