import SwiftUI

/// The map's boss, standing in the player's way until it is beaten (US-203).
///
/// Set on `MainScreenModel.pendingBossEncounter` the first time the player has walked the whole map
/// (`recorded >= totalSteps`) AND met every resident of it, and cleared when they take the one action
/// it offers: BATTLE. Unlike `WildEncounter` there is no flee — a boss is the gate on the next map,
/// not an ambush you can turn away from, so the dialog is a challenge to accept rather than a choice.
///
/// It carries what the fight needs so the face on the dialog and the face in the arena are the one
/// Digimon, exactly as `WildEncounter` does:
/// - `opponent` — the boss, already rolled: the highest-stage resident of the current map.
/// - `presentation` — how to draw it (name, stage folder, sheet), off the same node.
/// - `mapId` — which map this boss gates, captured so a win stamps the right map finished and a loss
///   takes its 1,000-step penalty off the right counter even if the selection changed meanwhile.
/// - `generator` — the seeded RNG the boss was drawn from, carried forward so accepting resolves the
///   fight from the same sequence, exactly as `PendingBattleRound` and `WildEncounter` do.
///
/// Not persisted, like the wild encounter: a boss interrupted by a force-quit is simply re-raised the
/// next time the app opens, because the conditions that raised it (steps done, all met, not yet
/// finished) still hold.
struct BossEncounter: Equatable {
    let opponent: BattleOpponent
    let presentation: DigimonPresentation
    let mapId: String
    let generator: SeededGenerator
}

/// The dialog a boss encounter puts on screen: the boss, and the one thing you can do about it.
///
/// In the shape of `WildEncounterView` — a light overlay, the sprite drawn with `IdleSpriteView` and
/// its `.interpolation(.none)` — but with a single BATTLE button and no flee, because a boss is a gate
/// the player has to pass rather than an ambush they can decline. Titled so it reads as the map's
/// final challenge and not another wild foe.
struct BossEncounterView: View {
    let encounter: BossEncounter
    let onBattle: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("Boss: \(encounter.presentation.displayName)!")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            IdleSpriteView(stage: encounter.presentation.spriteStage,
                           name: encounter.presentation.spriteFile)

            Button("Battle", action: onBattle)
                .buttonStyle(.borderedProminent)
                .font(.caption)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
