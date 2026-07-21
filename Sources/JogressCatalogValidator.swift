import Foundation

/// One thing wrong with the Jogress catalog (US-130).
///
/// These are all SEMANTIC errors, exactly as `GraphValidationError` and `MapValidationError` are: a
/// catalog has to decode before it can be validated, and a syntax or missing-field error never
/// reaches this type — `JogressCatalog.bundled` traps at launch, and under `xcodebuild test` the app
/// is the TEST_HOST, so the runner dies before a single test reports.
///
/// Every rule here guards a failure that is SILENT at runtime. A recipe naming an id no roster entry
/// has simply never matches, so the fusion is missing rather than broken; a duplicate pair loses the
/// second recipe to the lookup index; a result below its parents would hand the player a downgrade
/// for spending two Digimon. None of them crashes, so none of them would be found without this.
enum JogressValidationError: Error, Equatable, CustomStringConvertible {
    /// A parent id that is in no roster entry. The pair can never be assembled, so the recipe is
    /// dead data.
    case unknownParent(pair: JogressPair, parent: String)

    /// A parent that is one of the 157 idle-only Digimon. They have no animated sheet and are never
    /// playable, so the player can never own one to fuse — the same rule `edgeToDexOnlyNode` states
    /// for evolution edges.
    case dexOnlyParent(pair: JogressPair, parent: String)

    /// A result id that is in no roster entry. The fusion would consume two Digimon and produce
    /// nothing.
    case unknownResult(pair: JogressPair, result: String)

    /// A result that is idle-only. It has no walk, eat, sleep or attack frames, so the Digimon the
    /// player just spent two others on could not be raised or fought with.
    case dexOnlyResult(pair: JogressPair, result: String)

    /// `parentA == parentB`. A Jogress fuses two Digimon; a recipe naming one twice would either
    /// need the player to own the same id twice or match a single Digimon against itself.
    case sameParents(parent: String)

    /// A result strictly BELOW a parent on the Digitama -> Ultimate ladder. Equal is fine and is the
    /// ordinary case — the Color devices fuse two Ultimates into an Ultra, which this roster files
    /// at the same stage — but below means the player spent two Digimon to go backwards. Stages off
    /// the ladder (Armor-Hybrid, whose `ladderIndex` is nil) are not checked, for the same reason
    /// `invalidStageTransition` skips them.
    case resultBelowParent(
        pair: JogressPair, result: String, resultStage: Stage, parent: String, parentStage: Stage)

    /// The same unordered pair authored more than once — which covers BOTH the file listing A+B
    /// twice and the file listing A+B and B+A, because `JogressPair` makes those one key.
    /// `JogressCatalog.byPair` keeps the first, so every later recipe for that pair is unreachable.
    case duplicatePair(JogressPair, count: Int)

    /// A condition with a blank hint. Beyond the story's listed rules, and the same class of silent
    /// failure the other two validators already name: the player has no way to discover the
    /// criterion, so a fusion that will not fire reads to them as the game being broken.
    case emptyConditionHint(pair: JogressPair, metric: String)

    /// A condition naming a metric outside the `ConditionMetric` vocabulary — a typo, or a HealthKit
    /// identifier nobody has probed. Caught here rather than at decode because a typed property
    /// would make it a launch trap (see the note on `EvolutionCondition.metric`), and because an
    /// unknown metric can never be satisfied: the recipe is silently dead.
    case unknownConditionMetric(pair: JogressPair, metric: String)

    var description: String {
        switch self {
        case let .unknownParent(pair, parent):
            return "\(pair): parent '\(parent)' is in no roster entry"
        case let .dexOnlyParent(pair, parent):
            return "\(pair): parent '\(parent)' is dexOnly and can never be owned"
        case let .unknownResult(pair, result):
            return "\(pair): result '\(result)' is in no roster entry"
        case let .dexOnlyResult(pair, result):
            return "\(pair): result '\(result)' is dexOnly and has no animated sheet"
        case let .sameParents(parent):
            return "'\(parent)' is fused with itself — a Jogress needs two Digimon"
        case let .resultBelowParent(pair, result, resultStage, parent, parentStage):
            return "\(pair): result '\(result)' is a \(resultStage.displayName), below its parent '\(parent)' (\(parentStage.displayName))"
        case let .duplicatePair(pair, count):
            return "\(pair) is authored \(count) times — only the first is reachable"
        case let .emptyConditionHint(pair, metric):
            return "\(pair): condition '\(metric)' has an empty hint — the player cannot discover it"
        case let .unknownConditionMetric(pair, metric):
            return "\(pair): condition metric '\(metric)' is not in the vocabulary — the recipe is dead"
        }
    }
}

extension JogressCatalog {
    /// Every error in the catalog, in file order with the duplicate pairs last. Empty means the
    /// catalog is sound.
    ///
    /// Returns ALL errors rather than throwing on the first, like `EvolutionGraph.validate` and
    /// `MapCatalog.validate`: the errors are independent, and fixing an authored table one test run
    /// at a time is miserable.
    func validate(roster: Roster = .bundled) -> [JogressValidationError] {
        var errors: [JogressValidationError] = []
        for recipe in recipes {
            errors.append(contentsOf: validate(recipe: recipe, roster: roster))
        }
        return errors + duplicatePairErrors()
    }

    private func validate(
        recipe: JogressRecipe, roster: Roster
    ) -> [JogressValidationError] {
        let pair = recipe.pair
        var errors: [JogressValidationError] = []

        // Before every roster lookup: a blank hint and a typo'd metric are wrong on their own terms,
        // so an id that names nothing must not hide them — the author would fix the id and then meet
        // these on a second run. Same ordering, and the same reason, as the map validator's slots.
        for condition in recipe.conditions {
            if condition.hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyConditionHint(pair: pair, metric: condition.metric))
            }
            if condition.knownMetric == nil {
                errors.append(.unknownConditionMetric(pair: pair, metric: condition.metric))
            }
        }

        if recipe.parentA == recipe.parentB {
            errors.append(.sameParents(parent: recipe.parentA))
        }

        // Resolved once and reused by the ladder rule below, so a recipe with an unknown parent is
        // reported once rather than once per rule.
        var parents: [(id: String, entry: RosterEntry)] = []
        for parent in [recipe.parentA, recipe.parentB] {
            guard let entry = roster.entry(id: parent) else {
                errors.append(.unknownParent(pair: pair, parent: parent))
                continue
            }
            if entry.dexOnly {
                errors.append(.dexOnlyParent(pair: pair, parent: parent))
            }
            parents.append((parent, entry))
        }

        guard let resultEntry = roster.entry(id: recipe.result) else {
            return errors + [.unknownResult(pair: pair, result: recipe.result)]
        }
        if resultEntry.dexOnly {
            errors.append(.dexOnlyResult(pair: pair, result: recipe.result))
        }

        if let resultRung = resultEntry.stage.ladderIndex {
            for parent in parents {
                guard let parentRung = parent.entry.stage.ladderIndex, resultRung < parentRung else {
                    continue
                }
                errors.append(.resultBelowParent(
                    pair: pair, result: recipe.result, resultStage: resultEntry.stage,
                    parent: parent.id, parentStage: parent.entry.stage))
            }
        }

        return errors
    }

    /// Pairs authored more than once, each reported once, in the order the pair first appears.
    ///
    /// A count rather than a flag, like `duplicateId`: three recipes for one pair is a different
    /// mess from two, and the author wants to know how many to go and delete.
    private func duplicatePairErrors() -> [JogressValidationError] {
        var counts: [JogressPair: Int] = [:]
        for recipe in recipes {
            counts[recipe.pair, default: 0] += 1
        }
        var reported: Set<JogressPair> = []
        return recipes.compactMap { recipe in
            let pair = recipe.pair
            guard let count = counts[pair], count > 1, reported.insert(pair).inserted else {
                return nil
            }
            return .duplicatePair(pair, count: count)
        }
    }
}
