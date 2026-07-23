import Foundation

/// One thing wrong with the evolution graph.
///
/// These are all SEMANTIC errors — a graph has to decode before it can be validated. A syntax or
/// unknown-enum error never reaches this type: `EvolutionGraph.bundled` traps at launch, and under
/// `xcodebuild test` the app is the TEST_HOST, so the runner dies before a single test reports.
/// See the note on `EvolutionGraph.bundled` for how to read that failure.
enum GraphValidationError: Error, Equatable, CustomStringConvertible {
    /// An edge names a node that does not exist — the line dead-ends into nothing.
    case unknownEdgeTarget(from: String, to: String)

    /// A node's `spriteFile` resolves to no file on disk, so it would render as a placeholder.
    case missingSprite(node: String, path: String)

    /// A node's `spriteFile` is empty. Called out separately because it is not merely absent art:
    /// `Bundle.url(forResource:)` treats an empty name like nil and hands back an ARBITRARY png
    /// from the directory, so this is how a node silently becomes the wrong Digimon (see
    /// `SpriteLoader.url`, which guards it). Reported here rather than left to a nil load, since a
    /// caller that does not guard would "find" art and pass.
    case emptySpriteFile(node: String)

    /// A node's `line` is blank. The Dex groups trees by line (US-041), so a blank one is its own
    /// nameless group: the Digimon does not appear in the tree a user would look for it in, and
    /// nothing at runtime complains. A missing `line` key cannot reach here — the decoder rejects
    /// it — so this catches only `""`.
    case emptyLine(node: String)

    /// An edge that does not advance exactly one rung of the Digitama -> Ultimate ladder.
    /// Stages off the ladder (Armor-Hybrid, whose `ladderIndex` is nil) are not checked.
    case invalidStageTransition(from: String, to: String, fromStage: Stage, toStage: Stage)

    /// A non-terminal node with no fallback edge. US-020 takes the `isDefault` edge once the time
    /// gate passes and nothing else qualifies; without one the Digimon is permanently stuck.
    case noDefaultEdge(node: String)

    /// More than one fallback on a node — US-020's choice would come down to edge order.
    case multipleDefaultEdges(node: String, count: Int)

    /// Two nodes share an id. `EvolutionGraph.byId` silently keeps the first, so the second is
    /// unreachable: every edge pointing at that id resolves to the wrong Digimon.
    case duplicateId(String, count: Int)

    /// An edge names one of the 157 idle-only Digimon. They have no animated sheet, so making one
    /// playable means slicing 12 frames out of a lone 16x16 sprite.
    case edgeToDexOnlyNode(from: String, to: String)

    /// An edge out of a hatched node with no `requiredEnergy`. Only a Digitama's hatch edge may
    /// omit it (US-018 hatches on TOTAL energy, so no single type gates it); anywhere else the
    /// edge has no dominant-type gate and US-019 cannot decide a branch.
    case missingRequiredEnergy(from: String, to: String)

    /// A Digitama edge that names a `requiredEnergy`. It would be data that lies: US-018 ignores
    /// it, and a later reader would eventually "fix" the engine to respect it and break hatching.
    case typeGatedHatch(from: String, to: String, energy: EnergyType)

    /// A condition names a metric outside the `ConditionMetric` vocabulary — a typo, or a
    /// HealthKit identifier nobody has probed. Caught here rather than at decode because a typed
    /// property would make it a launch trap (see the note on `EvolutionCondition.metric`), and
    /// because an unknown metric can never be satisfied: the edge is silently dead.
    case unknownConditionMetric(from: String, to: String, metric: String)

    /// A condition whose (metric, window) pair the evaluator answers ONLY with `.unknown`, whatever
    /// the game state — `care.battleCount` over a `stage` window, say, a counter kept per day and
    /// per lifetime but never per stage. `ConditionEvaluator.isSatisfied` fails an unknown value
    /// whichever way the comparison points, so the branch is silently dead: the `isDefault` fallback
    /// keeps the Digimon unstuck, but this edge can never be the one taken. This is the same bug
    /// class `MapValidationError.unanswerableConditionWindow` guards for Digitama slots (US-186 fixed
    /// the last of those in `maps.json`) — see also `ConditionMetric.canBeAnswered(over:)`.
    case unanswerableConditionWindow(from: String, to: String, metric: String, window: ConditionWindow)

    /// A condition threshold below zero. No metric in either family can go negative, so this only
    /// ever means a sign typo — and on an `atMost` condition it makes the edge permanently unusable.
    case negativeConditionValue(from: String, to: String, metric: String, value: Double)

    /// A condition with a blank hint. The player has no way to discover the criterion, so the
    /// evolution reads to them as random.
    case emptyConditionHint(from: String, to: String, metric: String)

    /// `care.battleWinRatio` outside 0.0–1.0. It is a FRACTION of battles won, so `0.8` is 80%;
    /// `80` is the mistake this catches, and it would make the edge unreachable forever.
    case battleWinRatioOutOfRange(from: String, to: String, value: Double)

    var description: String {
        switch self {
        case let .unknownEdgeTarget(from, to):
            return "\(from) -> \(to): no node has id '\(to)'"
        case let .missingSprite(node, path):
            return "\(node): spriteFile does not exist on disk (\(path))"
        case let .emptySpriteFile(node):
            return "\(node): spriteFile is empty — it would load an arbitrary sprite"
        case let .emptyLine(node):
            return "\(node): line is empty — it would not appear in any Dex tree"
        case let .invalidStageTransition(from, to, fromStage, toStage):
            return "\(from) -> \(to): \(fromStage.rawValue) to \(toStage.rawValue) does not advance exactly one stage"
        case let .noDefaultEdge(node):
            return "\(node): non-terminal node has no isDefault edge — it can get stuck"
        case let .multipleDefaultEdges(node, count):
            return "\(node): \(count) isDefault edges — the fallback is ambiguous"
        case let .duplicateId(id, count):
            return "'\(id)' is declared \(count) times — all but the first are unreachable"
        case let .edgeToDexOnlyNode(from, to):
            return "\(from) -> \(to): '\(to)' is dexOnly and has no animated sheet"
        case let .missingRequiredEnergy(from, to):
            return "\(from) -> \(to): no requiredEnergy, but only a Digitama's hatch edge may omit it"
        case let .typeGatedHatch(from, to, energy):
            return "\(from) -> \(to): a hatch must not be gated on \(energy.rawValue) — US-018 hatches on total energy"
        case let .unknownConditionMetric(from, to, metric):
            return "\(from) -> \(to): condition metric '\(metric)' is not in the vocabulary — the edge can never qualify"
        case let .unanswerableConditionWindow(from, to, metric, window):
            return "\(from) -> \(to): condition '\(metric)' cannot be answered over a \(window.rawValue) window — the edge can never qualify"
        case let .negativeConditionValue(from, to, metric, value):
            return "\(from) -> \(to): condition '\(metric)' has a negative value (\(value))"
        case let .emptyConditionHint(from, to, metric):
            return "\(from) -> \(to): condition '\(metric)' has an empty hint — the player cannot discover it"
        case let .battleWinRatioOutOfRange(from, to, value):
            return "\(from) -> \(to): battleWinRatio \(value) is outside 0.0–1.0 — it is a fraction, not a percentage"
        }
    }
}

extension EvolutionGraph {
    /// Answers "does this node's art exist?".
    ///
    /// Injectable because the check is the one part of validation that touches the world: a model
    /// fixture has no art on disk, and a test for the OTHER rules must not fail on that.
    typealias SpriteExistsCheck = (EvolutionNode) -> Bool

    /// Resolves art the way the app does — under the stage folder, or the flat `Idle Frame Only`
    /// folder for a dexOnly node, whose art is not filed by stage.
    static func spriteExists(in bundle: Bundle = .main) -> SpriteExistsCheck {
        { node in
            let folder = node.dexOnly ? SpriteLoader.idleFrameOnlyFolder : node.stage.rawValue
            return SpriteLoader.url(stage: folder, name: node.spriteFile, in: bundle) != nil
        }
    }

    /// Every error in the graph, in node order. Empty means the graph is sound.
    ///
    /// Returns ALL errors rather than throwing on the first: fixing a roster one error per test
    /// run is miserable, and the errors are independent.
    func validate(spriteExists: SpriteExistsCheck = EvolutionGraph.spriteExists()) -> [GraphValidationError] {
        var errors: [GraphValidationError] = []

        // Duplicates are found against `nodes` (the file as authored), not `byId`, which keeps
        // only the first of a pair and so cannot see them.
        let countsById = Dictionary(nodes.map { ($0.id, 1) }, uniquingKeysWith: +)
        for id in countsById.keys.sorted() where countsById[id]! > 1 {
            errors.append(.duplicateId(id, count: countsById[id]!))
        }

        for node in nodes {
            errors.append(contentsOf: validate(node: node, spriteExists: spriteExists))
        }
        return errors
    }

    private func validate(node: EvolutionNode, spriteExists: SpriteExistsCheck) -> [GraphValidationError] {
        var errors: [GraphValidationError] = []

        if node.line.isEmpty {
            errors.append(.emptyLine(node: node.id))
        }

        if node.spriteFile.isEmpty {
            errors.append(.emptySpriteFile(node: node.id))
        } else if !spriteExists(node) {
            let folder = node.dexOnly ? SpriteLoader.idleFrameOnlyFolder : node.stage.rawValue
            errors.append(.missingSprite(node: node.id, path: "\(folder)/\(node.spriteFile).png"))
        }

        if !node.evolutions.isEmpty {
            let defaults = node.evolutions.filter(\.isDefault).count
            if defaults == 0 {
                errors.append(.noDefaultEdge(node: node.id))
            } else if defaults > 1 {
                errors.append(.multipleDefaultEdges(node: node.id, count: defaults))
            }
        }

        for edge in node.evolutions {
            errors.append(contentsOf: validate(edge: edge, from: node))
        }
        return errors
    }

    private func validate(edge: EvolutionEdge, from node: EvolutionNode) -> [GraphValidationError] {
        var errors: [GraphValidationError] = []

        switch (node.stage, edge.requiredEnergy) {
        case (.digitama, .some(let energy)):
            errors.append(.typeGatedHatch(from: node.id, to: edge.to, energy: energy))
        case (_, .none) where node.stage != .digitama:
            errors.append(.missingRequiredEnergy(from: node.id, to: edge.to))
        default:
            break
        }

        // Before the target lookup: a condition is wrong on its own terms, so a dead `to` must not
        // hide it — the author would fix the target and then meet the condition error on a
        // second run.
        for condition in edge.conditions {
            errors.append(contentsOf: validate(condition: condition, on: edge, from: node))
        }

        guard let target = self.node(id: edge.to) else {
            // Everything below reads the target, so there is nothing further to say about it.
            return errors + [.unknownEdgeTarget(from: node.id, to: edge.to)]
        }

        if target.dexOnly {
            errors.append(.edgeToDexOnlyNode(from: node.id, to: edge.to))
        }

        // A nil ladderIndex means "off the ladder" (Armor-Hybrid), which is unknown rather than
        // wrong — treating it as a rung would make every edge touching it a false error.
        if let from = node.stage.ladderIndex, let to = target.stage.ladderIndex, to != from + 1 {
            errors.append(.invalidStageTransition(
                from: node.id, to: edge.to, fromStage: node.stage, toStage: target.stage))
        }
        return errors
    }

    private func validate(
        condition: EvolutionCondition, on edge: EvolutionEdge, from node: EvolutionNode
    ) -> [GraphValidationError] {
        var errors: [GraphValidationError] = []

        if condition.hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyConditionHint(
                from: node.id, to: edge.to, metric: condition.metric))
        }

        guard let metric = condition.knownMetric else {
            // The range rules below are per-metric, and an unknown metric has no unit to judge
            // `value` against — reporting "negative steps" for a metric that is not steps would
            // point the author at the wrong field.
            return errors + [.unknownConditionMetric(
                from: node.id, to: edge.to, metric: condition.metric)]
        }

        if !metric.canBeAnswered(over: condition.window) {
            errors.append(.unanswerableConditionWindow(
                from: node.id, to: edge.to, metric: condition.metric, window: condition.window))
        }

        if metric == .careBattleWinRatio {
            // Subsumes the negative check: -0.5 is out of range for the same reason 80 is, and
            // one error naming the real rule beats two naming half of it each.
            if !(0.0...1.0).contains(condition.value) {
                errors.append(.battleWinRatioOutOfRange(
                    from: node.id, to: edge.to, value: condition.value))
            }
        } else if condition.value < 0 {
            errors.append(.negativeConditionValue(
                from: node.id, to: edge.to, metric: condition.metric, value: condition.value))
        }

        return errors
    }
}
