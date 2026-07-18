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
            published: Date()
        )
    }

    /// Publishes the snapshot and asks WidgetKit to redraw.
    ///
    /// Called at the end of `refresh()`, which is the one path a background wake and a foregrounding
    /// share (US-033) — so a Digimon that hatched, evolved or sickened while the app was shut reaches
    /// the watch face without the user opening anything.
    func publishComplicationSnapshot() {
        guard let complicationSnapshot else { return }
        guard ComplicationSnapshotStore.write(complicationSnapshot) else { return }
        // Only after a successful write: reloading a timeline that would re-read the same stale file
        // spends the widget's refresh budget for nothing.
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
