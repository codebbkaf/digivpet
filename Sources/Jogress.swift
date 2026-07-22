import Foundation

/// One fusion the player could perform right now (US-132).
///
/// A value built from the box, the recipes and the roster — the arrangement `PartyRow`, `MapListRow`
/// and `MapDetail` all use, and for the same reason: which pairs are offered, what a pair fuses
/// into and which egg comes back are decisions, and a decision belongs somewhere a test can reach
/// without a Simulator. The views below are only a layout of these fields.
struct JogressOffer: Identifiable, Equatable {
    /// One of the two Digimon going in.
    struct Parent: Equatable {
        /// Position in the box — the same integer `PartyRow.id` is, indexing the same
        /// `GameStore.allStates()` list, so the two screens agree on what "the third row" means.
        ///
        /// A POSITION and not the Digimon's id for `PartyRow.id`'s reason: a box may legitimately
        /// hold two Digimon with the same id. And it is checked against the live box before a fusion
        /// runs, because taking a Digimon out REORDERS the box (US-125's thaw moves a birth date),
        /// so an offer carried across a switch must not consume whichever Digimon slid into the slot.
        let rowId: Int

        /// The roster id of the Digimon as it stands now — which is what the recipe matched on, and
        /// what the staleness check re-matches on.
        let digimonId: String

        let displayName: String
        /// As `RosterEntry.spriteFile` — the basename `IdleSpriteView` resolves under the stage folder.
        let spriteFile: String
        let stage: Stage

        /// The Digitama this parent hatched from (US-127). Carried onto the offer because it is what
        /// the fusion hands back: exactly one of the two comes home as an unhatched egg.
        let originDigitamaId: String

        var spriteStage: String { stage.rawValue }
    }

    /// The two parents, in box order — first the one nearer the top of the party list. Two named
    /// fields rather than an array, so "a Jogress is exactly two Digimon" is a fact of the type
    /// rather than a count every reader has to trust.
    let first: Parent
    let second: Parent

    let resultId: String
    let resultDisplayName: String
    let resultSpriteFile: String
    let resultStage: Stage

    var parents: [Parent] { [first, second] }
    var resultSpriteStage: String { resultStage.rawValue }

    /// Distinct per PAIR, not per result: three shipped results are reachable by two different pairs
    /// (Chaosdramon, Tlalocmon, Cernumon), so a list keyed on the result alone would draw one row
    /// where the player owns both routes.
    var id: String { "\(first.rowId)+\(second.rowId)>\(resultId)" }

    /// What the row says the fusion is: "WarGreymon + MetalGarurumon".
    var title: String { "\(first.displayName) + \(second.displayName)" }

    /// The whole offer as one sentence for VoiceOver, for `PartyRow.accessibilityLabel`'s reason —
    /// three labels to swipe between is three swipes.
    var accessibilityLabel: String { "\(title), fuses into \(resultDisplayName)" }
}

/// The fixed wording of the Jogress entry point (US-132).
///
/// Free-standing like `MapDetailMarks`, because "when no such pair exists the entry point states why
/// in one line" is an acceptance criterion, and a test can only check the lines if they are reachable
/// without building a view graph.
enum JogressWording {
    /// The name of the act, as the devices themselves call it.
    static let title = "Jogress"

    /// Fewer than two living Digimon in the box — which is the ordinary state of a new game, and the
    /// first thing this screen has to be able to say without vanishing.
    static let needsTwo = "Jogress needs two living Digimon in your box."

    /// Two or more, but no pair of them is a recipe.
    static let noRecipe = "None of your Digimon fuse with each other."

    /// A pair that IS a recipe but whose conditions are not all met yet, phrased through the very
    /// hint line the Dex and the map detail use — so a player reads one promise about one condition
    /// rather than two wordings of it.
    static func notReady(_ pairTitle: String, hint: String) -> String {
        "\(pairTitle): \(hint)"
    }

    /// What the entry point says when there IS something to fuse. Counted, because the row is a way
    /// in and the number is the reason to take it.
    static func ready(_ count: Int) -> String {
        count == 1 ? "1 pair ready" : "\(count) pairs ready"
    }
}

/// What the party screen's Jogress entry point offers, and what it says when it offers nothing
/// (US-132 AC1/AC2).
///
/// `offers` and `reason` are exclusive by construction: an available board carries no reason, and an
/// unavailable one always carries one. That is AC2 as a property of the type — the entry point cannot
/// end up drawing an empty list with nothing to explain it, because there is no such value.
struct JogressBoard: Equatable {
    /// Every pair the player could fuse this instant, in box order.
    let offers: [JogressOffer]

    /// The one line stating why there is nothing to fuse, or nil when there is.
    let reason: String?

    var isAvailable: Bool { !offers.isEmpty }

    init(offers: [JogressOffer], reason: String?) {
        self.offers = offers
        self.reason = offers.isEmpty ? (reason ?? JogressWording.noRecipe) : nil
    }
}

extension JogressBoard {
    /// The pairs in this box that match a recipe, are both alive, and whose conditions all hold.
    ///
    /// - Parameters:
    ///   - states: `GameStore.allStates()`, in the order `PartyRow.id` indexes.
    ///   - catalog: the shipped recipes (US-131).
    ///   - roster: what turns the three ids into names and sprites. A pair whose parents or whose
    ///     RESULT the roster cannot draw is skipped rather than offered — the US-130 validator makes
    ///     that unreachable for shipped data, and an offer that led to an unnameable Digimon would be
    ///     a fusion the player could not be shown the outcome of.
    ///   - context: the player's counters, per parent. A closure rather than one value because a
    ///     recipe's conditions are asked of BOTH parents — see below.
    ///
    /// **A DEAD DIGIMON IS NEVER A PARENT** (AC1). It stays in the box as a record of what the player
    /// raised, and consuming it would be raising it again.
    ///
    /// **A CONDITION MUST HOLD FOR BOTH PARENTS.** Every shipped recipe has an empty condition list —
    /// the Color devices gate a Jogress on owning both parents and nothing further — so this rule is
    /// inert today and the choice is about what a later authored gate would MEAN. A Jogress is a thing
    /// the two of them do together, so a criterion met by one of them is met by half the fusion; and
    /// of the two readings, the strict one cannot accidentally offer a fusion the data meant to gate.
    static func make(
        for states: [GameState],
        catalog: JogressCatalog,
        roster: Roster,
        context: (GameState) -> ConditionContext
    ) -> JogressBoard {
        let living = states.enumerated().filter { !$0.element.isDead }
        guard living.count >= 2 else {
            return JogressBoard(offers: [], reason: JogressWording.needsTwo)
        }

        var offers: [JogressOffer] = []
        // The FIRST pair that matched a recipe and was held back, so the reason names something the
        // player can act on rather than the generic line. First rather than best, because the box is
        // in a fixed order and a reason that moved about between redraws would read as noise.
        var blocked: String?

        for outer in living.indices {
            for inner in living.index(after: outer)..<living.endIndex {
                let (indexA, a) = living[outer]
                let (indexB, b) = living[inner]
                guard let recipe = catalog.recipe(for: a.currentDigimonId, and: b.currentDigimonId),
                      let entryA = roster.entry(id: a.currentDigimonId),
                      let entryB = roster.entry(id: b.currentDigimonId),
                      let result = roster.entry(id: recipe.result) else { continue }

                let contextA = context(a)
                let contextB = context(b)
                guard ConditionReveal.allMet(recipe.conditions, in: contextA),
                      ConditionReveal.allMet(recipe.conditions, in: contextB) else {
                    if blocked == nil {
                        blocked = JogressWording.notReady(
                            "\(entryA.displayName) + \(entryB.displayName)",
                            hint: firstUnmetLine(recipe.conditions, in: [contextA, contextB]))
                    }
                    continue
                }

                offers.append(JogressOffer(
                    first: JogressOffer.Parent(rowId: indexA, state: a, entry: entryA),
                    second: JogressOffer.Parent(rowId: indexB, state: b, entry: entryB),
                    resultId: result.id,
                    resultDisplayName: result.displayName,
                    resultSpriteFile: result.spriteFile,
                    resultStage: result.stage))
            }
        }
        return JogressBoard(offers: offers, reason: blocked)
    }

    /// The hint for the first condition that fails for either parent, phrased by `ConditionReveal` —
    /// so the line warms up as the player gets closer, exactly as the Dex's and the map detail's do.
    private static func firstUnmetLine(_ conditions: [EvolutionCondition],
                                       in contexts: [ConditionContext]) -> String {
        for condition in conditions {
            for context in contexts where !ConditionEvaluator.isSatisfied(condition, in: context) {
                return ConditionReveal.line(for: condition, in: context)
            }
        }
        // Unreachable: this is only called for a pair `allMet` refused, so some condition failed
        // somewhere. The generic line rather than a trap, because a wrong word on a hint is not
        // worth taking the screen away from the player.
        return JogressWording.noRecipe
    }
}

private extension JogressOffer.Parent {
    /// Built from the saved record and its roster entry together: the id and the origin are facts
    /// about the SAVE, the name, stage and sprite are facts about the ROSTER, and neither knows both.
    init(rowId: Int, state: GameState, entry: RosterEntry) {
        self.init(rowId: rowId,
                  digimonId: state.currentDigimonId,
                  displayName: entry.displayName,
                  spriteFile: entry.spriteFile,
                  stage: entry.stage,
                  originDigitamaId: state.originDigitamaId)
    }
}

/// What one performed Jogress did (US-132), handed back by `GameStore.performJogress`.
///
/// The result is the live `@Model` the caller now has to draw, and the two ids beside it are what
/// the screen has to say happened: an egg came back, and two Digimon did not.
struct JogressOutcome {
    /// The fused Digimon, inserted, active and saved.
    let result: GameState

    /// The Digitama handed back to the box — one of the two parents' origins (AC4), chosen with the
    /// injected generator.
    let returnedDigitamaId: String

    /// The ids of the two Digimon consumed, in the order they were passed. For the log and for a
    /// test to assert against; nothing in the store holds them any more.
    let consumedIds: [String]
}
