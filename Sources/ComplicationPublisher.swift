import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

extension MainScreenModel {
    /// This game as the complication sees it, or nil before the store has opened.
    ///
    /// Everything comes from the model's OWN accessors — `presentation` off the graph and
    /// `energyProgress` off the current node's edges — so the complication shows the same Digimon
    /// and the same bar the main screen does, and re-aims itself on an evolution without anything
    /// here noticing.
    var complicationSnapshot: ComplicationSnapshot? {
        guard let state, let presentation else { return nil }
        let dominant = state.dominantEnergyType
        let goal = dominant.flatMap { type in energyProgress?.goals.first { $0.type == type } }
        return ComplicationSnapshot(
            displayName: presentation.displayName,
            spriteStage: presentation.spriteStage,
            spriteFile: presentation.spriteFile,
            dominantEnergySymbol: dominant?.symbol,
            dominantEnergyName: dominant?.displayName,
            // No dominant type means no bar rather than an empty one aimed at an arbitrary type.
            dominantEnergyFraction: goal.flatMap { energyProgress?.fraction(of: $0) } ?? 0,
            dominantEnergyEarned: goal?.earned ?? 0,
            pose: complicationPose,
            // The same count the in-app pile draws from, so the face's Clean button and the app's
            // are offered and withheld on identical grounds.
            poopCount: poopCount,
            published: Date()
        )
    }

    /// What the watch face should show this Digimon doing.
    ///
    /// The mapping itself lives in `ComplicationPose` — shared with the widget target and testable
    /// without a model — so all this does is name the four inputs. `isAsleep` comes from the model
    /// rather than from `state` because the sleep window is derived per refresh and is not saved.
    var complicationPose: ComplicationPose {
        ComplicationPose.pose(
            isDead: state?.healthStatus == .dead,
            isSick: state?.healthStatus == .sick,
            isAsleep: isAsleep,
            hasPoop: poopCount > 0
        )
    }

    /// Publishes the snapshot and asks WidgetKit to redraw.
    ///
    /// Called at the end of `refresh()`, which is the one path a background wake and a foregrounding
    /// share (US-033) — so a Digimon that hatched, evolved or sickened while the app was shut reaches
    /// the watch face without the user opening anything.
    func publishComplicationSnapshot() {
        guard let complicationSnapshot else { return }
        guard ComplicationSnapshotStore.write(complicationSnapshot, to: complicationDirectory) else { return }
        // Only after a successful write: reloading a timeline that would re-read the same stale file
        // spends the widget's refresh budget for nothing.
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Applies a Clean tapped on the WATCH FACE, if one is waiting.
    ///
    /// The whole of US-050 on this side of the boundary. The face cannot touch the store (see
    /// `CleanRequestStore` for why it is a cannot, not a should-not), so it leaves a request and
    /// this runs the ordinary `clean()` — the same method the in-app button calls, with the same
    /// restamp, the same notification cancel and the same republish. There is deliberately no
    /// second cleaning rule anywhere.
    ///
    /// Called at the TOP of `refresh()`, before `advancePoop`. `clean()` restamps `poopUpdatedAt`
    /// to now, so whatever accrued between the tap and this refresh is forgiven rather than found
    /// waiting — the user cleaned, and a screen already dirty again when they open the app would
    /// read as the tap having done nothing. It is at most one 3h interval either way.
    ///
    /// - Returns: whether a request was found AND had something to clean, so a test can tell the
    ///   two apart from the outside.
    @discardableResult
    func applyPendingCleanRequest() -> Bool {
        guard CleanRequestStore.take(in: complicationDirectory) != nil else { return false }
        return clean()
    }
}
