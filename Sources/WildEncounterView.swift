import SwiftUI

/// A wild Digimon the player has walked into, waiting to be fought or fled (US-201).
///
/// Set on `MainScreenModel.pendingWildEncounter` the moment a refresh finds the player has walked
/// 500 steps into their map since the last encounter, and cleared when they pick BATTLE or FLEE.
/// It carries everything the two choices need so neither has to draw an opponent a second time:
/// - `opponent` — the wild Digimon, already rolled, a non-`GameState` foe from the current map's pool.
/// - `presentation` — how to draw it in the dialog (name, stage folder, sheet), pulled off the same
///   node so the face on the dialog and the face in the arena are the one Digimon.
/// - `mapId` — which map's counter the flee/loss penalty comes off, captured so a map switched
///   between the encounter opening and being answered cannot send the penalty to the wrong place.
/// - `generator` — the seeded RNG the opponent was drawn from, carried forward so accepting resolves
///   the fight from the same sequence, exactly as `PendingBattleRound` carries it between the
///   pre-battle round and the fight.
///
/// Not persisted, like the pending battle and training rounds: an encounter interrupted by a
/// force-quit is simply over, and the steps that bought it are still on the map's counter to earn the
/// next one.
struct WildEncounter: Equatable {
    let opponent: BattleOpponent
    let presentation: DigimonPresentation
    let mapId: String
    let generator: SeededGenerator
}

/// The dialog a wild encounter puts on screen: the foe, and the two things you can do about it.
///
/// A light overlay in the shape of `DigitamaDropBanner` rather than a full ceremony — an ambush is a
/// moment, not a place — but with two buttons instead of a tap-to-dismiss, because BATTLE and FLEE
/// lead to different outcomes and the player has to choose. The sprite is drawn with `IdleSpriteView`,
/// which carries the `.interpolation(.none)` every sprite in the game uses.
struct WildEncounterView: View {
    let encounter: WildEncounter
    let onBattle: () -> Void
    let onFlee: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("A wild \(encounter.presentation.displayName)!")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            IdleSpriteView(stage: encounter.presentation.spriteStage,
                           name: encounter.presentation.spriteFile)

            HStack(spacing: 8) {
                Button("Flee", role: .cancel, action: onFlee)
                Button("Battle", action: onBattle)
                    .buttonStyle(.borderedProminent)
            }
            .font(.caption)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
