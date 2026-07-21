import Foundation
import UIKit

/// One thing wrong with the map catalog (US-117).
///
/// These are all SEMANTIC errors, exactly as `GraphValidationError` is: a catalog has to decode
/// before it can be validated, and a syntax or missing-field error never reaches this type —
/// `MapCatalog.bundled` traps at launch, and under `xcodebuild test` the app is the TEST_HOST, so
/// the runner dies before a single test reports.
///
/// Every rule here guards a failure that is SILENT at runtime. A map whose art is missing draws an
/// empty room; an opponent id that names nothing makes US-122's pick return nil on that map; a
/// Digitama slot that names a Child is an egg that can never hatch. None of them crashes, so none
/// of them would be found without this.
enum MapValidationError: Error, Equatable, CustomStringConvertible {
    /// A map's `assetName` resolves to no imageset, so `MapBackgroundView` paints nothing and the
    /// map is a name with no place behind it.
    case missingAsset(map: String, assetName: String)

    /// An opponent id that is in no roster entry. US-122 draws opponents from this pool, so the id
    /// is simply skipped — a pool of five that is really a pool of four, quietly.
    case unknownOpponent(map: String, opponent: String)

    /// An opponent that is one of the 157 idle-only Digimon. They have no animated sheet, so a
    /// battle against one has no attack frame to play — the same rule `edgeToDexOnlyNode` states
    /// for evolution edges.
    case dexOnlyOpponent(map: String, opponent: String)

    /// A Digitama slot naming an id no roster entry has. The slot can never award anything.
    case unknownDigitama(map: String, digitamaId: String)

    /// A Digitama slot naming a real Digimon that is not an egg. A map drops eggs, and awarding a
    /// Perfect straight into the box would skip every stage the player was meant to raise it
    /// through.
    case notADigitama(map: String, digitamaId: String, stage: Stage)

    /// An `unlockedBy` naming no map. The map is unlockable by nothing, so it is locked forever,
    /// and US-119's one-line "Finish <previous map name>" has no name to print.
    case unknownUnlockedBy(map: String, unlockedBy: String)

    /// A cycle in the unlock chain, reported once with its members sorted. Every map in a cycle
    /// waits on a map that (transitively) waits on it, so none of them is ever reachable — and the
    /// walk US-119 does over the chain would not terminate.
    case unlockCycle(maps: [String])

    /// A slot condition with a blank hint. The player has no way to discover what to do, so the
    /// egg reads to them as a random drop — the same failure `emptyConditionHint` names for an
    /// evolution edge, and the reason `DigitamaSlot` reuses `EvolutionCondition` at all.
    case emptyConditionHint(map: String, digitamaId: String, metric: String)

    /// A slot every one of whose conditions is a metric that is usually empty on real hardware
    /// (handwashing, toothbrushing, dietary water, daylight, audio exposure and the two rare
    /// events — see `ConditionMetric.isSparseOnHardware`). US-128's rule, and the same one
    /// `EvolutionCondition` already states for edges: such a metric may be a bonus gate but never
    /// the ONLY one. It bites harder for a slot than for an edge, because a slot is the sole route
    /// to its egg — gated solely on an empty metric, that egg is unreachable on a watch-only device.
    case soleSparseCondition(map: String, digitamaId: String)

    var description: String {
        switch self {
        case let .missingAsset(map, assetName):
            return "\(map): assetName '\(assetName)' is not an imageset — the room would be empty"
        case let .unknownOpponent(map, opponent):
            return "\(map): opponent '\(opponent)' is in no roster entry"
        case let .dexOnlyOpponent(map, opponent):
            return "\(map): opponent '\(opponent)' is dexOnly and has no animated sheet"
        case let .unknownDigitama(map, digitamaId):
            return "\(map): Digitama slot '\(digitamaId)' is in no roster entry"
        case let .notADigitama(map, digitamaId, stage):
            return "\(map): Digitama slot '\(digitamaId)' is a \(stage.rawValue), not an egg"
        case let .unknownUnlockedBy(map, unlockedBy):
            return "\(map): unlockedBy names no map ('\(unlockedBy)') — it can never unlock"
        case let .unlockCycle(maps):
            return "unlock cycle: \(maps.joined(separator: " -> ")) — none of them is reachable"
        case let .emptyConditionHint(map, digitamaId, metric):
            return "\(map)/\(digitamaId): condition '\(metric)' has an empty hint — the player cannot discover it"
        case let .soleSparseCondition(map, digitamaId):
            return "\(map)/\(digitamaId): every condition is a metric that is usually empty on real hardware — the egg would be unreachable"
        }
    }
}

extension MapCatalog {
    /// Answers "does this map's art exist?".
    ///
    /// Injectable for the same reason `EvolutionGraph.SpriteExistsCheck` is: a hand-built fixture
    /// names art that need not ship, and a test for the OTHER rules must not fail on that.
    typealias AssetExistsCheck = (String) -> Bool

    /// Resolves art the way `MapBackgroundView` does — `UIImage(named:)` is the same lookup
    /// `Image(_:)` performs, so a name that drifted from `Assets.xcassets` is caught here rather
    /// than found at a glance on the watch.
    static func assetExists() -> AssetExistsCheck {
        { !$0.isEmpty && UIImage(named: $0) != nil }
    }

    /// Every error in the catalog, in map order with the unlock cycles last. Empty means the
    /// catalog is sound.
    ///
    /// Returns ALL errors rather than throwing on the first, like `EvolutionGraph.validate`: the
    /// errors are independent, and fixing 170 opponent ids one test run at a time is miserable.
    func validate(
        roster: Roster = .bundled,
        assetExists: AssetExistsCheck = MapCatalog.assetExists()
    ) -> [MapValidationError] {
        var errors: [MapValidationError] = []
        for map in maps {
            errors.append(contentsOf: validate(map: map, roster: roster, assetExists: assetExists))
        }
        return errors + unlockCycleErrors()
    }

    private func validate(
        map: AdventureMap, roster: Roster, assetExists: AssetExistsCheck
    ) -> [MapValidationError] {
        var errors: [MapValidationError] = []

        if !assetExists(map.assetName) {
            errors.append(.missingAsset(map: map.id, assetName: map.assetName))
        }

        for opponent in map.opponentPool {
            guard let entry = roster.entry(id: opponent) else {
                errors.append(.unknownOpponent(map: map.id, opponent: opponent))
                continue
            }
            if entry.dexOnly {
                errors.append(.dexOnlyOpponent(map: map.id, opponent: opponent))
            }
        }

        for slot in map.digitamaSlots {
            errors.append(contentsOf: validate(slot: slot, in: map, roster: roster))
        }

        // The cycle walk is done once over the whole catalog below; this is only the dangling
        // pointer, which is per-map.
        if let unlockedBy = map.unlockedBy, self.map(id: unlockedBy) == nil {
            errors.append(.unknownUnlockedBy(map: map.id, unlockedBy: unlockedBy))
        }

        return errors
    }

    private func validate(
        slot: DigitamaSlot, in map: AdventureMap, roster: Roster
    ) -> [MapValidationError] {
        // Before the roster lookup: a blank hint is wrong on its own terms, so an id that names
        // nothing must not hide it — the author would fix the id and then meet the hint error on a
        // second run.
        var errors: [MapValidationError] = slot.conditions
            .filter { $0.hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { .emptyConditionHint(map: map.id, digitamaId: slot.digitamaId, metric: $0.metric) }

        // Also independent of the roster: a slot gated SOLELY on empty-on-hardware metrics is an
        // egg no watch-only player can earn, whatever the id resolves to. Fires only when there IS
        // at least one condition and every one of them is a known sparse metric — a slot pairing a
        // sparse metric with a real one (shipped `06_industrial/pulse_digitama`: steps + handwashing)
        // is fine, and an empty-condition slot is a free drop rather than an unreachable one.
        if !slot.conditions.isEmpty,
           slot.conditions.allSatisfy({ $0.knownMetric?.isSparseOnHardware == true }) {
            errors.append(.soleSparseCondition(map: map.id, digitamaId: slot.digitamaId))
        }

        guard let entry = roster.entry(id: slot.digitamaId) else {
            return errors + [.unknownDigitama(map: map.id, digitamaId: slot.digitamaId)]
        }
        if entry.stage != .digitama {
            errors.append(
                .notADigitama(map: map.id, digitamaId: slot.digitamaId, stage: entry.stage))
        }
        return errors
    }

    /// Walks the `unlockedBy` chain up from every map, reporting each cycle once.
    ///
    /// Every map is a start, not just the ones nothing points at: a cycle with no map hanging off
    /// it is reachable from no other walk, and it is exactly the case a "walk from the starting
    /// map" check cannot see.
    private func unlockCycleErrors() -> [MapValidationError] {
        var errors: [MapValidationError] = []
        var reported: Set<String> = []

        for map in maps {
            var walked: [String] = []
            var current: AdventureMap? = map
            while let step = current {
                if let start = walked.firstIndex(of: step.id) {
                    let cycle = walked[start...].sorted()
                    // Keyed on the members so the same cycle found from four different maps is
                    // one finding, not four.
                    if reported.insert(cycle.joined(separator: ",")).inserted {
                        errors.append(.unlockCycle(maps: cycle))
                    }
                    break
                }
                walked.append(step.id)
                current = step.unlockedBy.flatMap { self.map(id: $0) }
            }
        }
        return errors
    }
}
