import SwiftUI

/// What one Digimon in the box is doing (US-126).
///
/// Three states rather than two flags, because "frozen" and "dead" behave differently in the one
/// way this screen is about: a frozen Digimon can be taken out and a dead one can never be, and a
/// row that expressed that as `!isActive` would offer the player a corpse to raise.
enum PartyStatus: String, Equatable, CaseIterable {
    /// The Digimon the player has out — `GameState.isActive`.
    case active
    /// In the box, waiting. Its clocks are stopped (US-125).
    case frozen
    /// Gone. Still listed, because the player owned it and the box is the record of that.
    case dead

    /// The one word the row states its status in. Short deliberately: this sits at the end of a
    /// 41mm row that already carries a name and a stage.
    var label: String {
        switch self {
        case .active: return "Out"
        case .frozen: return "Frozen"
        case .dead: return "Gone"
        }
    }

    /// The glyph beside that word. Three different ones, and different tints below, for
    /// `MapListMarks`' reason: a row's state has to be readable at a glance without reading it.
    var symbol: String {
        switch self {
        case .active: return "figure.walk.circle.fill"
        case .frozen: return "snowflake"
        case .dead: return "xmark.circle"
        }
    }
}

/// One Digimon in the box, as the party screen draws it (US-126).
///
/// A value type built from the saved records rather than a view reading the store itself, for the
/// same reason `MapListRow` is one: what this screen DOES — which rows can be tapped, what a dead
/// Digimon is allowed to offer, which row is marked — is arithmetic, and arithmetic belongs
/// somewhere a test can reach without a Simulator. The view below is only a layout of these fields.
struct PartyRow: Identifiable, Equatable {
    /// Position in the box, oldest first — which is the order `GameStore.allStates()` returns and
    /// therefore the order the player sees.
    ///
    /// The POSITION and not the Digimon's id, because a box may legitimately hold two Digimon with
    /// the same id — two Agumon raised from two eggs are two different pets — and a list keyed on a
    /// duplicate id draws one row and taps the wrong record. It is also what `MainScreenModel`
    /// activates through, so the seam between the value type and the `@Model` is one integer wide.
    ///
    /// THE ORDER MOVES WHEN A DIGIMON IS TAKEN OUT, and that is US-125 showing through rather than
    /// a defect: the box is sorted by birth date, and thawing shifts a Digimon's whole timeline
    /// forward by the span it spent frozen — so the sort is really by EFFECTIVE AGE, oldest first,
    /// and one just taken out of a long spell in the box has aged none of it. `MainScreenModel`
    /// checks a row still describes the record at its position before activating it, so a tap
    /// carried over from a stale list is refused rather than landing on the wrong Digimon.
    let id: Int

    let displayName: String

    /// The stage's own display name ("Baby I", "Ultimate"), as the row's caption spells it.
    let stageName: String

    /// The sprite subfolder and sheet filename, as `IdleSpriteView` wants them.
    let spriteStage: String
    let spriteFile: String

    let status: PartyStatus

    /// Whether tapping this row can put this Digimon out.
    ///
    /// Only a frozen one: the active row is a no-op (AC4) because it is already out, and a dead one
    /// is refused outright (AC5). Both refusals live HERE rather than only in the view's `disabled`,
    /// so they are facts a test can assert rather than a shape only a screenshot can see.
    var isSelectable: Bool { status == .frozen }

    /// What VoiceOver reads: the whole row as a sentence, since "Agumon, Child, Frozen" read as
    /// three separate labels is three separate swipes.
    var accessibilityLabel: String { "\(displayName), \(stageName), \(status.label)" }
}

extension PartyRow {
    /// The box as the party screen draws it: every owned Digimon and every unhatched Digitama, in
    /// the order the store hands them back (birth order, oldest first).
    ///
    /// - Parameters:
    ///   - states: `GameStore.allStates()`. Unhatched eggs need no special case — an egg the player
    ///     holds IS a saved `GameState` at `.digitama`, which is why tapping one is the same act as
    ///     tapping any other row and is what starts it hatching (AC6).
    ///   - graph: what turns a saved id into a name and a sprite. A record the graph does not know
    ///     still draws a row — see `presentation(for:in:roster:)`.
    ///   - roster: consulted when the graph cannot name the id, which since US-132 is the ORDINARY
    ///     case for a Jogress result: `omegamon` is one of the 780 orphans no line reaches, so a
    ///     graph-only lookup would list the Digimon the player had just fused as "omegamon" with no
    ///     art. Defaulted so every existing caller is untouched.
    static func rows(for states: [GameState], in graph: EvolutionGraph,
                     roster: Roster = .bundled) -> [PartyRow] {
        states.enumerated().map { index, state in
            let presentation = presentation(for: state, in: graph, roster: roster)
            return PartyRow(
                id: index,
                displayName: presentation.displayName,
                stageName: presentation.stage.displayName,
                spriteStage: presentation.spriteStage,
                spriteFile: presentation.spriteFile,
                status: status(of: state)
            )
        }
    }

    /// How to draw this record, falling back to the saved id and the saved stage when the graph has
    /// never heard of it.
    ///
    /// A row that vanished because the roster dropped an id would be a Digimon the player owns and
    /// cannot reach — it would still be in the box, still counting as held (US-127), and invisible.
    /// The id itself is the honest name for it, exactly as `MainScreenModel.memorial` uses it, and
    /// `IdleSpriteView` draws its own missing-art box when the file is not there either.
    private static func presentation(for state: GameState,
                                     in graph: EvolutionGraph,
                                     roster: Roster) -> DigimonPresentation {
        graph.presentation(forId: state.currentDigimonId)
            ?? roster.presentation(forId: state.currentDigimonId)
            ?? DigimonPresentation(displayName: state.currentDigimonId,
                                   stage: state.stage,
                                   spriteFile: state.currentDigimonId)
    }

    /// DEATH IS READ FIRST, ahead of `isActive`, and that ordering is the rule rather than an
    /// accident of the `if`: a Digimon can be dead AND out — that is exactly what the memorial
    /// screen is — and of the two facts, "gone" is the one that must not be drawn as a live pet.
    /// Reading the flag first would mark a corpse as the Digimon the player is raising.
    private static func status(of state: GameState) -> PartyStatus {
        if state.healthStatus == .dead { return .dead }
        return state.isActive ? .active : .frozen
    }
}

/// The party screen's sizes and tints.
///
/// Named rather than left as literals in the `body`, for `MainReadingBarLayout`'s reason: what a row is
/// allowed to cost is a decision, and a decision a test can argue with is one that stays made.
enum PartyRowLayout {
    /// Screen points per sprite pixel, so a row's Digimon is 32pt square. Twice the Dex grid's
    /// default, because a Dex cell is one of six on a line and this is one of four on a screen —
    /// and the player is being asked to recognise which of their Digimon this is, not to scan a
    /// grid.
    static let spriteScale: CGFloat = 2

    /// How far a dead Digimon's row is faded. The same 0.55 a locked map row uses, because it means
    /// the same thing in both places: still worth showing, not something to tap.
    static let deadOpacity: Double = 0.55
}

/// Every Digimon the player owns, and the one they have out (US-126).
///
/// Pushed onto `ContentView`'s existing `NavigationStack` from the action grid's Party button,
/// exactly as `MapListView` is pushed from its Map button — so it keeps a back button, and so a
/// tap that changes which Digimon is out lands the player back on the screen that Digimon is drawn
/// on. Both used to be pushed from the map strip's two ends; US-210 deleted that row and left the
/// grid as the one way out of the room.
struct PartyView: View {
    let rows: [PartyRow]

    /// What can be fused right now, or why nothing can (US-132). Carried on the party screen rather
    /// than on a screen of its own because a Jogress is a thing you do WITH the box — the pairs it
    /// offers are rows of this very list.
    let board: JogressBoard

    /// Puts this Digimon out. `MainScreenModel.activate(_:)` in the app, which moves the whole
    /// switch — both `isActive` flags and both freeze clocks — in ONE saved transaction (US-124).
    let activate: (PartyRow) -> Void

    /// Performs a fusion. `MainScreenModel.performJogress(_:)` in the app (US-132).
    let fuse: (JogressOffer) -> Void

    /// Whether the Jogress list is up. Owned here rather than expressed as a `NavigationLink` for
    /// `MapListView`'s reason: fusing has to drop BOTH levels — the pair list and this screen — so
    /// the player lands back on the main screen where the ceremony plays, and that needs a binding
    /// this view can clear.
    @State private var showsJogress = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { scroller in
            List {
                // The way to a fusion, above the box it fuses from — and drawn whether or not there
                // is one, since with nothing to fuse this row is the only thing that says why (AC2).
                if board.isAvailable {
                    Button {
                        showsJogress = true
                    } label: {
                        JogressEntryRow(board: board)
                    }
                    .buttonStyle(.plain)
                } else {
                    JogressEntryRow(board: board)
                }

                ForEach(rows) { row in
                    Button {
                        tap(row)
                    } label: {
                        PartyRowView(row: row)
                    }
                    .buttonStyle(.plain)
                    // ONLY a dead one is disabled, which is why this is not `!row.isSelectable`.
                    // A watchOS `List` draws a disabled row grey throughout, and the Digimon the
                    // player has OUT is the last row on this screen that should read as unavailable
                    // — it is the one they are looking for. The active row stays at full strength
                    // with its own mark, and the no-op is in `tap` below. A dead row, by contrast,
                    // SHOULD read as unavailable: it is being shown, not offered.
                    .disabled(row.status == .dead)
                    .id(row.id)
                }
            }
            #if DEBUG
            // Screenshot hook, the same one and the same reason as `MapListView`'s: `simctl` has no
            // scroll command, and US-126's screenshot has to show four entries including the dead
            // one — which is the fourth row and below the fold on both screens. It moves the scroll
            // position and nothing else. Compiled out of release builds.
            // KEYED ON THE ROW COUNT, which `MapListView`'s hook does not need to be: this screen is
            // pushed from the launch command before `MainScreenModel.start()` has opened the store,
            // so the first run sees an EMPTY box, returns, and — with a plain `.task` — never runs
            // again. The map list is built from the bundled catalog and is never empty.
            .task(id: rows.count) {
                guard CommandLine.arguments.contains("-partyBottomDemo"),
                      let last = rows.last else { return }
                // After a beat, for the reason `MapListView`'s hook waits: `.task` runs before the
                // rows have been measured, and scrolling to an item whose height is not settled
                // lands short of it.
                try? await Task.sleep(nanoseconds: 500_000_000)
                scroller.scrollTo(last.id, anchor: .bottom)
            }
            #endif
        }
        .navigationTitle("Party")
        .navigationDestination(isPresented: $showsJogress) {
            JogressView(offers: board.offers) { offer in
                perform(offer)
            }
        }
    }

    /// Fuses the pair, then goes back to the game — for `tap`'s reason and `MapListView.travel`'s:
    /// the point of the tap is the Digimon now standing on the screen behind this one, and the
    /// ceremony that announces it plays there.
    ///
    /// Both levels are dropped, the pair list first and then the box.
    private func perform(_ offer: JogressOffer) {
        fuse(offer)
        showsJogress = false
        dismiss()
    }

    /// Take this one out, and go back to the game — the box is an errand, like the map list, and
    /// the point of the tap is the Digimon now standing on the screen behind this one.
    ///
    /// Tapping the Digimon that is ALREADY out changes nothing and still goes back (AC4): the box is
    /// untouched — `activate` is not even called — and what the player asked for by tapping the row
    /// marked "Out" is the screen that Digimon is on. A row that swallowed the tap and stayed put
    /// would read as broken.
    private func tap(_ row: PartyRow) {
        guard row.status != .dead else { return }
        if row.isSelectable { activate(row) }
        dismiss()
    }
}

/// One row: the Digimon's sprite, its name and stage, and what it is doing.
private struct PartyRowView: View {
    let row: PartyRow

    var body: some View {
        HStack(spacing: 6) {
            // `IdleSpriteView` rather than `DigimonSpriteView`, for the reason the Dex uses it: this
            // is a LIST, and a list of two-frame loops runs one `TimelineView` schedule per row for
            // art the player is scrolling past. It draws the same frame 0 — an egg's idle, a hatched
            // Digimon's flat idle sprite — with the same `.interpolation(.none)` (AC7); smoothed
            // pixel art is a bug on every screen, not just the main one.
            IdleSpriteView(stage: row.spriteStage, name: row.spriteFile,
                           scale: PartyRowLayout.spriteScale)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                // Shrinks to half size rather than wrapping or truncating: the widest real name
                // this list carries is a Digitama's ("Gabu Digitama"), and at 0.7 the 41mm screen
                // rendered it "Gabu Digi…" beside the status column — a name the player is being
                // asked to choose by is the one thing on this row that must stay whole.
                Text(row.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(row.stageName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer(minLength: 0)

            mark
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // The whole row dims when the Digimon is gone, sprite included — a corpse is still worth
        // listing, and is still not what the player is being asked to look at.
        .opacity(row.status == .dead ? PartyRowLayout.deadOpacity : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    /// The status mark: glyph and word together, which is what makes the three states tellable
    /// apart without colour — and tinted as well, because the one the player looks for first is the
    /// Digimon they already have out.
    private var mark: some View {
        HStack(spacing: 2) {
            Image(systemName: row.status.symbol)
                .font(.system(size: 10))
            Text(row.status.label)
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        // Never squeezed: the status is one short word and it is the answer to the question this
        // screen asks. Given the choice, the NAME shrinks — it can, down to half size — and the
        // status stays whole. Without this the 41mm screen rendered "Frozen" as "Fr".
        .fixedSize()
    }

    private var tint: Color {
        switch row.status {
        case .active: return .orange
        case .frozen: return .secondary
        case .dead: return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        PartyView(rows: [
            PartyRow(id: 0, displayName: "Agumon", stageName: "Child",
                     spriteStage: "Child", spriteFile: "Agumon", status: .active),
            PartyRow(id: 1, displayName: "Gabu Digitama", stageName: "Digitama",
                     spriteStage: "Digitama", spriteFile: "Gabu_Digitama", status: .frozen),
            PartyRow(id: 2, displayName: "Greymon", stageName: "Adult",
                     spriteStage: "Adult", spriteFile: "Greymon", status: .dead),
        ], board: JogressBoard(offers: [], reason: JogressWording.noRecipe),
           activate: { _ in }, fuse: { _ in })
    }
}
