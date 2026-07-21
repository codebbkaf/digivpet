import SwiftUI

/// The glyphs and the fixed wording the map detail draws (US-121).
///
/// Free-standing for the same reason `MapListMarks` is: "a slot the player has never owned draws a
/// `?`" and "a slot whose conditions are all met is marked as ready" are acceptance criteria, and a
/// test can only check them if the strings are reachable without building a view graph.
enum MapDetailMarks {
    /// What a Digitama the player has never owned is drawn as. A "?" and NOT a silhouette, which is
    /// the call `DexCell` already makes for an undiscovered Digimon and for the same reason: a
    /// silhouette would have to be derived from the sprite, which means decoding the very art this
    /// screen is withholding.
    static let unknownName = "?"

    /// A slot whose conditions all hold but which has not dropped yet. Neither the Dex's green
    /// `checkmark.circle.fill` (that marks ONE condition, and this row's conditions each carry
    /// their own) nor the list's `checkmark.seal.fill` (that means finished, and this is the
    /// opposite — something still to come).
    static let readySymbol = "sparkles"

    /// Said out loud beside the glyph. A drop is the one thing on this screen the player can act
    /// on, and a bare sparkle beside a "?" is decoration until something names it.
    static let readyLabel = "Ready to find"

    /// The heading over the slots. "Digitama" and not "Eggs": the game calls them Digitama
    /// everywhere else the player can read, down to the roster's own display names.
    static let digitamaHeading = "Digitama"

    static let opponentsHeading = "Opponents"

    /// The travel button, and what it says once the player is already here. The second is not a
    /// hidden button — a control that vanishes once used reads as a bug, and "you are here" is
    /// information the screen otherwise does not carry.
    static let travelLabel = "Travel here"
    static let hereLabel = "You are here"
}

/// One map, opened (US-121): what lives in it, and what it can still hand over.
///
/// A value built from the catalog, the roster, the Dex and the player's counters — the same
/// arrangement `MapListRow` uses, and for the same reason. The interesting parts of this screen are
/// all decisions: which Digitama may be named, which is ready to find, which stage an opponent
/// belongs under. Decisions belong somewhere a test can reach them without a Simulator, and the
/// view below is then only a layout of these fields.
struct MapDetail: Equatable, Identifiable {
    /// One Digimon that can be fought here.
    struct Opponent: Identifiable, Equatable {
        /// The roster id, which is also its Dex id.
        let id: String
        let displayName: String
        /// As `RosterEntry.spriteFile` — the basename `IdleSpriteCache` resolves under the stage
        /// folder.
        let spriteFile: String
        let stage: Stage
    }

    /// The opponents of one stage, drawn under one heading.
    struct OpponentGroup: Identifiable, Equatable {
        let stage: Stage
        /// In the order the pool authors them, which is the order US-116 wrote and US-122 bands.
        let opponents: [Opponent]

        var id: String { stage.rawValue }
    }

    /// One Digitama slot: an egg this map can drop, and what it is waiting for.
    struct DigitamaSlotDetail: Identifiable, Equatable {
        /// What a Digitama the player has met is allowed to show. Nil is the whole of the
        /// withholding rule — there is no other field to forget to check, and a `?` row cannot
        /// accidentally carry a name because there is nowhere on it to put one.
        struct Revealed: Equatable {
            let displayName: String
            let spriteFile: String
            /// Always `.digitama` for shipped data — the US-117 validator rejects a slot naming
            /// anything else — but read off the roster rather than assumed, because it is what
            /// `IdleSpriteView` resolves the art folder from.
            let stage: Stage
        }

        let digitamaId: String

        /// The art and the name, or nil while this egg is still a "?".
        let revealed: Revealed?

        /// The criteria to draw as hint rows. **Empty on a revealed slot**, which is AC4's "with no
        /// hint rows" said where a test can see it: an egg the player already has is not something
        /// they are still working towards, and listing its conditions would read as a second copy
        /// still to be earned.
        let conditions: [EvolutionCondition]

        /// Every condition holds, and the egg is not in hand yet — so the next drop check can hand
        /// it over. Deliberately false once revealed: "ready" is a promise about something that has
        /// not happened, and an egg already owned has had it happen.
        let isReady: Bool

        var isRevealed: Bool { revealed != nil }

        var id: String { digitamaId }
    }

    /// The map id, which is also the id the selection is saved under.
    let id: String

    let displayName: String
    let assetName: String
    let recordedSteps: Int
    let totalSteps: Int

    /// Whether the player's steps are already accruing here, which is what turns the travel button
    /// into a statement.
    let isSelected: Bool

    /// The pool, grouped by stage in ladder order. Empty groups are absent rather than drawn empty.
    let opponentGroups: [OpponentGroup]

    /// Every slot, in the order the catalog authors them.
    let digitama: [DigitamaSlotDetail]

    /// What the player's counters currently say. Carried on the detail rather than passed beside it
    /// so that the screen has ONE input: every hint line on it is a function of these conditions and
    /// this context, and a view that had to be handed both could be handed a mismatched pair.
    let context: ConditionContext

    /// Progress, spelled exactly as the list spells it — see `MapListRow.progressText`. The two
    /// screens name the same figure and must not disagree about how it reads.
    var progressText: String { "\(recordedSteps) / \(totalSteps)" }

    /// Every opponent, flattened back out. What a test counts against the pool the catalog authored.
    var opponents: [Opponent] { opponentGroups.flatMap(\.opponents) }
}

extension MapDetail {
    /// The detail of the map `row` names, or **nil if it is locked** (AC6).
    ///
    /// Nil rather than a detail with its contents stripped: `MapListRow` already hides a locked
    /// map's eggs and opponents, and a second, quieter way of saying the same thing is a second
    /// place for it to be got wrong. "A locked map has no reachable detail view" is then one fact
    /// about one function, and the view's disabled row is belt to its braces.
    ///
    /// - Parameters:
    ///   - row: the row that was tapped. The lock decision is READ off it rather than recomputed —
    ///     `MapListRow.isUnlocked` is where that rule lives, and a screen that decided it a second
    ///     way could open a detail for a map whose row says it is shut.
    ///   - catalog: the maps. Injected so a test drives a fixture rather than whatever `maps.json`
    ///     currently says a map holds.
    ///   - roster: where an opponent id and a Digitama id resolve to a name, a stage and art.
    ///   - discovered: every Digimon id the player has ever raised — `GameStore.dexIds()`. The Dex
    ///     is the record of "has ever owned" the game already keeps, and it survives death and
    ///     rebirth, which is exactly the span AC4 names.
    ///   - context: the player's counters, for the reveal levels of the hint lines.
    static func make(
        for row: MapListRow,
        in catalog: MapCatalog = .bundled,
        roster: Roster = .bundled,
        discovered: Set<String>,
        context: ConditionContext
    ) -> MapDetail? {
        guard !row.isLocked, let map = catalog.map(id: row.id) else { return nil }
        return MapDetail(
            id: map.id,
            displayName: map.displayName,
            assetName: map.assetName,
            recordedSteps: row.recordedSteps,
            totalSteps: map.totalSteps,
            isSelected: row.isSelected,
            opponentGroups: groups(of: map, roster: roster),
            digitama: map.digitamaSlots.map { slot(from: $0, roster: roster,
                                                  discovered: discovered, context: context) },
            context: context)
    }

    /// The pool, resolved and grouped.
    ///
    /// `Stage.allCases` drives the order rather than `ladderIndex`, because Armor-Hybrid has no
    /// rung — sorting on the index would have to invent one for it, and `allCases` is already
    /// authored in ladder order with the side branch last.
    ///
    /// An id the roster does not know is DROPPED, not drawn as a blank: the US-117 validator
    /// already rejects one, so it cannot reach a shipped map, and a row with no name and no art is
    /// worse than an opponent the player never sees. Duplicates collapse to their first mention —
    /// two rows with one id are one row to `ForEach`, which silently loses whichever it likes.
    private static func groups(of map: AdventureMap, roster: Roster) -> [OpponentGroup] {
        var seen: Set<String> = []
        let opponents = map.opponentPool.compactMap { id -> Opponent? in
            guard seen.insert(id).inserted, let entry = roster.entry(id: id) else { return nil }
            return Opponent(id: entry.id, displayName: entry.displayName,
                            spriteFile: entry.spriteFile, stage: entry.stage)
        }
        let byStage = Dictionary(grouping: opponents, by: \.stage)
        return Stage.allCases.compactMap { stage in
            guard let members = byStage[stage], !members.isEmpty else { return nil }
            return OpponentGroup(stage: stage, opponents: members)
        }
    }

    /// One slot, with the reveal rule applied.
    ///
    /// A slot whose id the roster does not know stays a "?" whatever the Dex says — it is not that
    /// the player has not met it, it is that there is no art and no name to draw. Its conditions
    /// are still listed, so a data fault shows up as an egg nobody can name rather than as a slot
    /// that quietly vanished.
    private static func slot(
        from slot: DigitamaSlot,
        roster: Roster,
        discovered: Set<String>,
        context: ConditionContext
    ) -> DigitamaSlotDetail {
        let entry = roster.entry(id: slot.digitamaId)
        let revealed = discovered.contains(slot.digitamaId) ? entry.map {
            DigitamaSlotDetail.Revealed(displayName: $0.displayName, spriteFile: $0.spriteFile,
                                        stage: $0.stage)
        } : nil
        return DigitamaSlotDetail(
            digitamaId: slot.digitamaId,
            revealed: revealed,
            conditions: revealed == nil ? slot.conditions : [],
            isReady: revealed == nil && ConditionReveal.allMet(slot.conditions, in: context))
    }
}

/// What lives in one map, and what it can still hand over (US-121).
///
/// Pushed onto the same `NavigationStack` `MapListView` sits on, so it keeps a back button — the
/// arrangement the Dex's own detail has.
struct MapDetailView: View {
    let detail: MapDetail

    /// Travel here: select this map and go back to the game. The map list hands this down rather
    /// than the detail selecting for itself, so `MapListSelector` stays the one place a tap becomes
    /// a selection.
    let travel: () -> Void

    var body: some View {
        ScrollViewReader { scroller in
            List {
                Section {
                    header
                    travelButton
                }

                Section(MapDetailMarks.digitamaHeading) {
                    ForEach(detail.digitama) { slot in
                        DigitamaSlotRow(slot: slot, context: detail.context)
                            .id(slot.id)
                    }
                }

                ForEach(detail.opponentGroups) { group in
                    Section(group.stage.displayName) {
                        ForEach(group.opponents) { opponent in
                            OpponentRow(opponent: opponent)
                                .id(opponent.id)
                        }
                    }
                }
            }
            #if DEBUG
            // Screenshot hook, the same one and the same reason as `MapListView`'s: `simctl` has no
            // scroll command, and neither of the two things US-121 has to photograph is above the
            // fold — the MIX of revealed and withheld slots, and the pool under its stage headings.
            // One flag apiece; both move the scroll position and nothing else, and both are
            // compiled out of release builds.
            .task {
                let arguments = CommandLine.arguments
                let target: String? = arguments.contains("-mapDetailSlotsDemo")
                    ? detail.digitama.last?.id
                    // The FIRST opponent of the LAST group, not the last of it: anchored to the
                    // bottom that puts the group's own heading on screen with the tail of the
                    // group before it, which is the only way one shot can show that the pool really
                    // is grouped rather than merely ordered.
                    : arguments.contains("-mapDetailFoesDemo")
                        ? detail.opponentGroups.last?.opponents.first?.id : nil
                guard let target else { return }
                // After a beat, for the reason `MapListView`'s hook waits: `.task` runs before the
                // rows have been measured, and scrolling to an item whose height is not settled
                // lands short of it.
                try? await Task.sleep(nanoseconds: 500_000_000)
                scroller.scrollTo(target, anchor: .bottom)
            }
            #endif
        }
        .navigationTitle(detail.displayName)
    }

    /// The map's own art and how far across it the player is — the two things the list row showed,
    /// at the size a screen of its own can afford.
    private var header: some View {
        HStack(spacing: 6) {
            Image(detail.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(detail.progressText)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("\(detail.digitama.count) eggs · \(detail.opponents.count) foes")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    /// One tap to make this the map the player's steps go to. Disabled rather than absent once they
    /// are already here — see `MapDetailMarks.hereLabel`.
    @ViewBuilder
    private var travelButton: some View {
        if detail.isSelected {
            Label(MapDetailMarks.hereLabel, systemImage: MapListMarks.selectedSymbol)
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        } else {
            Button(action: travel) {
                Label(MapDetailMarks.travelLabel, systemImage: MapListMarks.selectedSymbol)
                    .font(.system(size: 12))
            }
        }
    }
}

/// One Digitama slot: the egg once it has been met, a "?" and its criteria until then.
private struct DigitamaSlotRow: View {
    let slot: MapDetail.DigitamaSlotDetail
    let context: ConditionContext

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                art

                VStack(alignment: .leading, spacing: 1) {
                    // Only a revealed slot has a name to put here. A withheld one leaves the column
                    // to the ready mark and the hints: the tile beside it is ALREADY the "?", and
                    // the first screenshot of this row drew the glyph twice side by side, which
                    // read as a rendering fault rather than as one withheld egg.
                    if let revealed = slot.revealed {
                        Text(revealed.displayName)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    if slot.isReady {
                        Label(MapDetailMarks.readyLabel, systemImage: MapDetailMarks.readySymbol)
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            // A revealed slot carries none of these — see `DigitamaSlotDetail.conditions`.
            ForEach(Array(slot.conditions.enumerated()), id: \.offset) { _, condition in
                ConditionHintRow(condition: condition, context: context)
            }
        }
        .padding(.vertical, 2)
    }

    /// The egg, or the "?" that stands in for one. The same two cases `DexCell` draws, in the same
    /// order and with the same reasoning — including `IdleSpriteView`'s `.interpolation(.none)`,
    /// which is what keeps 16x16 art from being smoothed on the way up.
    @ViewBuilder
    private var art: some View {
        if let revealed = slot.revealed {
            IdleSpriteView(stage: revealed.stage.rawValue, name: revealed.spriteFile)
        } else {
            Text(MapDetailMarks.unknownName)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 32, height: 32)
        }
    }
}

/// One opponent: its idle sprite and its name. Nothing is withheld here — an opponent is what the
/// map throws at the player, and a "?" would be hiding the one thing the section is for.
private struct OpponentRow: View {
    let opponent: MapDetail.Opponent

    var body: some View {
        HStack(spacing: 6) {
            IdleSpriteView(stage: opponent.stage.rawValue, name: opponent.spriteFile)

            Text(opponent.displayName)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
}

#Preview {
    NavigationStack {
        MapDetailView(
            detail: MapDetail.make(
                for: MapListRow.rows(progress: PlayerProfile(selectedMapId: "01_grassland"))[0],
                discovered: ["agu_digitama"],
                context: .unknown)!,
            travel: {})
    }
}
