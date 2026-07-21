import SwiftUI

/// The glyphs the map list marks a row with (US-119).
///
/// Free-standing constants rather than literals inside the view, for the same reason
/// `MapBackgroundLayout`'s opacity is one: "the finished mark and the selected mark are visually
/// different from each other" is an acceptance criterion, and a test can only check it if the two
/// names are reachable without building a view graph.
enum MapListMarks {
    /// A map whose counter has crossed its total. A seal rather than a bare checkmark, because a
    /// checkmark is what half the system uses for "selected" and these two marks sit side by side.
    static let finishedSymbol = "checkmark.seal.fill"

    /// The map the player's steps are currently accruing to — "you are here", not "you are done".
    /// A walking figure says which of the two it is without a legend.
    static let selectedSymbol = "figure.walk.circle.fill"

    /// A map whose predecessor has not been finished.
    static let lockedSymbol = "lock.fill"
}

/// One map, as the list draws it (US-119).
///
/// A value type built from the catalog and the save rather than the view reading both itself: the
/// interesting parts of this screen — what counts as locked, how progress is spelled, what a locked
/// row is allowed to reveal — are arithmetic, and arithmetic belongs somewhere a test can reach it
/// without a Simulator. The view below is then only a layout of these fields.
struct MapListRow: Identifiable, Equatable {
    /// What lives in a map: how many eggs it can drop and how big its opponent pool is.
    ///
    /// Nil on a locked row, which is what "hides its Digitama and opponent pool" means here — a
    /// lock that still counted the eggs behind it would be a peephole. US-121's detail view says
    /// the same thing at length, and is unreachable from a locked row for the same reason.
    struct Contents: Equatable {
        let digitamaCount: Int
        let opponentCount: Int
    }

    /// The catalog id, which is also the id the selection is saved under.
    let id: String

    let displayName: String

    /// The imageset drawn as this row's thumbnail — the same art `MapBackgroundView` paints behind
    /// the Digimon, so the row is a picture of where you would be.
    let assetName: String

    /// Steps banked here, floored to a whole step. `MapProgress` carries a `Double` because a
    /// `HealthReading` does; nobody wants to read "1222.0" on a watch.
    let recordedSteps: Int

    let totalSteps: Int

    /// Whether this is the map steps are accruing to right now.
    let isSelected: Bool

    /// Whether the counter has ever crossed the total. Read off the finish STAMP rather than
    /// recomputed from `recordedSteps >= totalSteps`, so a map that was finished and then retuned
    /// longer in a later build stays finished — the player really did cross it.
    let isFinished: Bool

    let isLocked: Bool

    /// The one line a locked row states its condition in — "Finish Grassland". Nil when unlocked.
    let unlockLine: String?

    /// What is in this map, or nil when it is locked. See `Contents`.
    let contents: Contents?

    /// Progress, spelled exactly as US-119 asks: space, slash, space, no abbreviation, no rounding
    /// and no grouping separator.
    ///
    /// Built by interpolation rather than by a `NumberFormatter` deliberately — a formatter is
    /// LOCALE-DEPENDENT, so the same 25,000 renders as "25.000" in a German locale and as "25 000"
    /// in a French one, and the criterion names one exact string. It is a step count rather than a
    /// quantity a reader parses, so the separator buys nothing to pay for that.
    var progressText: String { "\(recordedSteps) / \(totalSteps)" }

    /// Whether tapping this row can change where the player is adventuring. A locked map cannot be
    /// travelled to, so its row is disabled AND `MapListSelector` refuses it — the disable is a
    /// view fact no test can reach, and the refusal is one every test can.
    var isSelectable: Bool { !isLocked }
}

extension MapListRow {
    /// Every map in catalog order, which is tier order, with the player's progress folded in.
    ///
    /// - Parameters:
    ///   - catalog: the sixteen maps. Injected so a test drives a two-map fixture rather than
    ///     whatever `maps.json` currently says a map is worth.
    ///   - progress: the save. Nil — which is only ever the moment before `start()` finishes —
    ///     reads as a player who has walked nowhere, so the list draws rather than disappearing.
    static func rows(in catalog: MapCatalog = .bundled, progress: MapProgress?) -> [MapListRow] {
        catalog.maps.map { map in
            let locked = !isUnlocked(map, in: catalog, progress: progress)
            return MapListRow(
                id: map.id,
                displayName: map.displayName,
                assetName: map.assetName,
                // Floored rather than rounded: a counter must never read as a step the player has
                // not taken, least of all the one that would show 3000 / 3000 on an unfinished map.
                recordedSteps: Int((progress?.recorded(forMap: map.id) ?? 0).rounded(.down)),
                totalSteps: map.totalSteps,
                isSelected: progress?.selectedMapId == map.id,
                isFinished: progress?.isFinished(forMap: map.id) ?? false,
                isLocked: locked,
                unlockLine: locked ? unlockLine(for: map, in: catalog) : nil,
                contents: locked ? nil : Contents(digitamaCount: map.digitamaSlots.count,
                                                  opponentCount: map.opponentPool.count)
            )
        }
    }

    /// Whether a map can be travelled to: the one map with no `unlockedBy` always, and any other
    /// once the map it names has been FINISHED.
    ///
    /// Deliberately a one-step check rather than a walk up the whole chain. The shipped chain is
    /// linear and a map cannot be finished without being selectable, so the two answers agree on
    /// real data; where they differ — a save hand-edited to finish map 5 without map 4 — the
    /// one-step rule is the one the row's own "Finish <previous>" line promises, and a lock that
    /// contradicts the sentence beside it is worse than a lock that opens early.
    static func isUnlocked(_ map: AdventureMap, in catalog: MapCatalog,
                           progress: MapProgress?) -> Bool {
        guard let required = map.unlockedBy else { return true }
        return progress?.isFinished(forMap: required) ?? false
    }

    /// "Finish Grassland" — the sentence a locked row states its condition in.
    ///
    /// Falls back to the raw id if the catalog has no such map, which the US-117 validator already
    /// rejects; a row that says "Finish 07_mountains" is ugly, and a row that says nothing at all
    /// is a lock with no way past it.
    private static func unlockLine(for map: AdventureMap, in catalog: MapCatalog) -> String? {
        guard let required = map.unlockedBy else { return nil }
        return "Finish \(catalog.map(id: required)?.displayName ?? required)"
    }
}

/// What a tap on a map row does to the selection (US-119 AC6).
///
/// One line, and it is here rather than inline in the view for the reason the rest of `MapListRow`
/// is: "tapping a locked map does NOT change the selection" is the criterion, and a rule that lives
/// only inside a `Button`'s closure can be checked by nothing but a screenshot.
enum MapListSelector {
    /// The selection after tapping `row`, given `current`. A locked row hands `current` straight
    /// back, unchanged.
    static func selection(tapping row: MapListRow, current: String?) -> String? {
        row.isSelectable ? row.id : current
    }
}

/// Every adventure map, what you have walked of it, and which ones are still shut (US-119).
///
/// Pushed onto `ContentView`'s existing `NavigationStack` rather than presented as a sheet, so it
/// keeps a back button and US-121 can push a detail view of its own on top of it — the same
/// arrangement the Dex has.
struct MapListView: View {
    let rows: [MapListRow]

    /// What one row opens (US-121), or nil for a map that has no detail — which is what a locked
    /// map has. `MainScreenModel.mapDetail(for:)` in the app.
    ///
    /// Defaulted so the DEBUG demo destinations and the previews can push the list without a model
    /// behind them; a nil detail simply does not navigate.
    var detail: (MapListRow) -> MapDetail? = { _ in nil }

    /// Called with the id of the map the player chose. `MainScreenModel.selectMap(_:)` in the app.
    let select: (String) -> Void

    /// The map whose detail is pushed, by id.
    ///
    /// The id and not the detail itself, because `navigationDestination(item:)` wants a `Hashable`
    /// and the detail carries conditions and a whole `ConditionContext`. Keeping the state to a
    /// `String` also means the detail is rebuilt from the CURRENT rows on every redraw, so a step
    /// credited while the screen is open moves the figure on it.
    @State private var openMapId: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { scroller in
            List {
                ForEach(rows) { row in
                    Button {
                        tap(row)
                    } label: {
                        MapListRowView(row: row)
                    }
                    .buttonStyle(.plain)
                    // A locked map is not a dead tap target that looks live: the lock is drawn on
                    // the row and the row is dimmed, so the refusal is visible before it is felt.
                    .disabled(!row.isSelectable)
                    .id(row.id)
                }
            }
            .navigationDestination(item: $openMapId) { id in
                if let row = rows.first(where: { $0.id == id }), let detail = detail(row) {
                    MapDetailView(detail: detail) { travel(to: row) }
                }
            }
            #if DEBUG
            // Screenshot hook, the same one and the same reason as `DexGridView`'s: `simctl` has no
            // scroll command, and map 16 — the map whose `50000 / 50000` is the widest figure this
            // screen ever draws, and the whole point of US-119's screenshot — is the sixteenth row.
            // It moves the scroll position and nothing else. Compiled out of release builds.
            .task {
                guard CommandLine.arguments.contains("-mapListBottomDemo"),
                      let last = rows.last else { return }
                // After a beat, for the reason `NotificationSettingsView`'s hook waits: `.task`
                // runs before the rows have been measured, and scrolling to an item whose height is
                // not settled lands short of it.
                try? await Task.sleep(nanoseconds: 500_000_000)
                scroller.scrollTo(last.id, anchor: .bottom)
            }
            #endif
        }
        .navigationTitle("Maps")
    }

    private var currentSelection: String? {
        rows.first(where: \.isSelected)?.id
    }

    /// Open the map — US-121's detail, which is where the player finds out what lives there and
    /// what its eggs are waiting for BEFORE committing their steps to it.
    ///
    /// It used to select and pop straight back (US-119). Travelling moved one step deeper when the
    /// detail arrived, and everything US-120 asked of a selection still holds of it: it is made
    /// through `MapListSelector`, it persists, it moves the background and the strip, and it ends
    /// on the main screen. A locked row cannot get this far — the button is disabled and
    /// `MapDetail.make` would refuse it anyway.
    private func tap(_ row: MapListRow) {
        guard row.isSelectable else { return }
        openMapId = row.id
    }

    /// Travel there, and go back to the game — choosing a map is an errand, not a place to stay.
    /// Both levels are dropped: the detail first, then the list, which is what puts the player back
    /// where the map they just chose is drawn behind their Digimon.
    private func travel(to row: MapListRow) {
        let next = MapListSelector.selection(tapping: row, current: currentSelection)
        if let next, next != currentSelection { select(next) }
        openMapId = nil
        dismiss()
    }
}

/// One row: the map's art, its name, how far across it you are, and its marks.
private struct MapListRowView: View {
    let row: MapListRow

    var body: some View {
        HStack(spacing: 6) {
            thumbnail

            VStack(alignment: .leading, spacing: 1) {
                Text(row.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // The widest this gets is "50000 / 50000" on a finished map 16, which is what the
                // 41mm screenshot in US-119 was taken to settle. `lineLimit(1)` with a floor rather
                // than a wrap: a progress figure broken across two lines is unreadable.
                Text(row.progressText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                subtitle
            }

            Spacer(minLength: 0)

            marks
        }
        .padding(.vertical, 2)
        // The whole row dims when it is shut, art included — the lock is the figure and the map
        // behind it is not what the player is being asked to look at yet.
        .opacity(row.isLocked ? 0.55 : 1)
    }

    /// The map's own background, small. `.scaledToFill()` and clipped, as `MapBackgroundView` does
    /// it, so the thumbnail is a crop of the real scene rather than a letterboxed one — and no
    /// `.interpolation(.none)`, because these are 822x330 photographs being drawn down, not 16x16
    /// pixel art being drawn up.
    private var thumbnail: some View {
        Image(row.assetName)
            .resizable()
            .scaledToFill()
            .frame(width: 34, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityHidden(true)
    }

    /// The third line: what lives here, or — on a locked map — the one thing to do about it.
    @ViewBuilder
    private var subtitle: some View {
        if let unlockLine = row.unlockLine {
            Text(unlockLine)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if let contents = row.contents {
            Text("\(contents.digitamaCount) eggs · \(contents.opponentCount) foes")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// The marks, stacked at the trailing edge. A map can be finished AND selected at once, so both
    /// can be on one row and they have to stay tellable apart: different glyph and different tint,
    /// not one channel doing two jobs — the same rule `DexCandidateCell` follows for earned and
    /// selected.
    @ViewBuilder
    private var marks: some View {
        VStack(spacing: 2) {
            if row.isLocked {
                Image(systemName: MapListMarks.lockedSymbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                if row.isFinished {
                    Image(systemName: MapListMarks.finishedSymbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
                if row.isSelected {
                    Image(systemName: MapListMarks.selectedSymbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MapListView(rows: MapListRow.rows(progress: MapProgress(selectedMapId: "01_grassland")),
                    select: { _ in })
    }
}
