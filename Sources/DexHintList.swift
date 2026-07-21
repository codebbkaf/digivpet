import Foundation

/// What the Dex detail sheet's condition list says, given which branch — if any — the player has
/// tapped.
///
/// A value rather than view code, for the reason `ConditionReveal` is one: US-111's "select,
/// re-select, cross-select" behaviour is then pinnable as a pure function of
/// `(selection, candidates)`, with no sheet to present and no store to seed. The view's whole job
/// is to draw `heading` and walk `lines`.
struct DexHintList: Equatable {
    /// One drawn row: a criterion, warmed up through `ConditionReveal` by `ConditionHintRow`, or a
    /// plain sentence with no criterion behind it.
    ///
    /// The plain case exists for exactly one situation — a selected branch gated by nothing at all.
    /// The flat list drops such a branch silently, because it contributes no criteria to flatten;
    /// but a branch the player has ASKED about has to answer, and a heading over nothing reads as a
    /// bug in the same way "No evolutions recorded." was written to avoid.
    enum Line: Equatable {
        case condition(EvolutionCondition)
        case plain(String)

        /// The text this line draws. The condition case goes through `ConditionReveal` exactly as
        /// `ConditionHintRow` does, so a test can read what the sheet says without rendering it.
        func text(in context: ConditionContext) -> String {
            switch self {
            case .condition(let condition):
                return ConditionReveal.line(for: condition, in: context)
            case .plain(let sentence):
                return sentence
            }
        }
    }

    let heading: String
    let lines: [Line]

    /// Every string this section draws, heading included — what US-111 checks a withheld candidate
    /// name against.
    func text(in context: ConditionContext) -> [String] {
        [heading] + lines.map { $0.text(in: context) }
    }
}

extension DexHintList {
    /// The heading over the flattened all-branches list.
    static let flatHeading = "It wants"

    /// The heading while one branch is selected. The wording changing is load-bearing, not
    /// decoration: the list is a strict subset of the flat one and nothing else on screen says so,
    /// so a player who missed their own tap would read a short list as "this is all it wants".
    static let branchHeading = "To become this"

    /// What a selected branch with no criteria says. Deliberately not a promise that the branch
    /// will be taken — `requiredEnergy`, `minEnergy` and `maxCareMistakes` still gate it and
    /// `EvolutionEngine` still decides — and deliberately in `ConditionHint`'s register, since it
    /// sits in the same list as those lines. No digit, for the same reason no hint has one.
    static let nothingRequired = "Nothing in particular. This is where it drifts on its own."

    /// The list to draw: one branch's own criteria when the player has tapped one, the flattened
    /// all-branches list otherwise.
    ///
    /// Nil means draw no section at all, which is the flat list over branches gated only by energy
    /// and care — most of the graph. A heading over nothing is the "No evolutions recorded."
    /// mistake in a second place. A SELECTED branch never returns nil: it answers, with
    /// `nothingRequired` if that is the answer.
    ///
    /// A selection naming no candidate falls back to the flat list rather than to nothing, so a
    /// branch that disappears out from under a selection degrades to the default view.
    static func list(
        selecting selection: DexCandidate.ID?,
        from candidates: [DexCandidate]
    ) -> DexHintList? {
        if let selection, let candidate = candidates.first(where: { $0.id == selection }) {
            return branch(candidate)
        }
        return flat(candidates)
    }

    /// One branch's criteria, in authored order and untouched — no deduplication, because there is
    /// nothing here to deduplicate ACROSS: these are one edge's conditions and the player asked for
    /// this edge.
    private static func branch(_ candidate: DexCandidate) -> DexHintList {
        guard !candidate.conditions.isEmpty else {
            return DexHintList(heading: branchHeading, lines: [.plain(nothingRequired)])
        }
        return DexHintList(heading: branchHeading, lines: candidate.conditions.map(Line.condition))
    }

    /// Every criterion on every branch out of here, in authored order, first mention only.
    ///
    /// Flattened across the branches because this is the DEFAULT view, and the default is asked to
    /// answer "what is this Digimon watching" without being asked about any one branch. Most branch
    /// targets are undiscovered and `DexCandidateCell` withholds their names, so a per-branch list
    /// shown unbidden would be a column of "?" headings — and worse, it would tell the player
    /// exactly how many criteria stand between them and each unnamed thing. That reasoning is why
    /// flat is what the sheet opens on, and US-111 did not overturn it: it made the per-branch list
    /// something the player ASKS for, one branch at a time, by tapping the "?" they care about.
    /// Asking about one is a different thing from being handed all of them.
    ///
    /// Deduplicated on the criterion itself and not on its text, so two branches gated on the same
    /// metric at DIFFERENT thresholds still each get their line — those are genuinely two things to
    /// know, and collapsing them would hide one behind the other's checkmark. The deduplication is
    /// this list's alone: it exists because the branches were merged, and a selected branch was
    /// never merged with anything.
    private static func flat(_ candidates: [DexCandidate]) -> DexHintList? {
        var seen: Set<String> = []
        let conditions = candidates.flatMap(\.conditions).filter { condition in
            seen.insert("\(condition.metric)|\(condition.window)|\(condition.comparison)|\(condition.value)").inserted
        }
        guard !conditions.isEmpty else { return nil }
        return DexHintList(heading: flatHeading, lines: conditions.map(Line.condition))
    }
}
