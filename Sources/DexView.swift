import SwiftUI

/// The field guide: every Digimon in the roster, with the ones you have raised filled in.
///
/// The top level is ONE flat grid over all 1,022 roster entries (US-063), not the list of evolution
/// lines it was through US-042. The list only ever showed the ~88 Digimon an authored line reaches,
/// so the other ~930 that have art on disk were invisible — and "how much of the roster have I
/// met?" is the question the Dex exists to answer, which a list of eight line names cannot.
///
/// What made the list affordable was that its rows were text. The grid gets there a different way:
/// `LazyVGrid` builds only the cells on screen, and a cell is the only thing that reaches
/// `IdleSpriteCache`, so scrolling past 1,022 entries decodes the dozen or so actually visible.
/// Opening the Dex still decodes nothing at all.
///
/// The trees have not gone away — `model.sections` still holds them, and US-067 is what puts a way
/// back to them on this screen. Until then they are reachable only from `-dexLineDemo`.
struct DexView: View {
    @StateObject private var model: DexModel

    #if DEBUG
    @State private var showsLineDemo = CommandLine.arguments.contains("-dexLineDemo")
    #endif

    /// As in `ContentView`: passed in rather than defaulted, because building one is a
    /// `@MainActor` call and a default argument would run in this non-isolated `init`.
    init(model: @autoclosure @escaping () -> DexModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        DexGridView(rows: model.rows, selectsDemoRow: true)
            .navigationTitle("\(model.discoveredCount)/\(model.totalCount)")
            #if DEBUG
            // Debug-only: `simctl` cannot tap a cell, so an opened line is unscreenshottable
            // without a way to push one from the launch command — the same reason `-dexDemo` exists
            // to push this screen at all. Compiled out of release builds.
            .navigationDestination(isPresented: $showsLineDemo) {
                if let section = demoSection { destination(for: section) }
            }
            #endif
            .onAppear {
                if !model.isLoaded { model.load() }
            }
    }

    /// A line gets its tree; `Others` has no edges to draw, so it gets a flat grid.
    @ViewBuilder
    private func destination(for section: DexSection) -> some View {
        if section.isLine {
            EvolutionTreeView(nodes: section.nodes, rows: section.rows)
                .navigationTitle(section.title)
        } else {
            DexGridView(rows: section.rows)
                .navigationTitle(section.title)
        }
    }

    #if DEBUG
    /// The line `-dexLineDemo` opens: Agumon's, because it is the one shipped line that branches,
    /// so a screenshot of it shows a fork and its converging connectors rather than a straight
    /// ladder. Falls back to the first line so the arg still lands somewhere if that changes.
    private var demoSection: DexSection? {
        model.sections.first { $0.id == "agumon" } ?? model.sections.first
    }
    #endif
}

/// A flat grid of Dex cells: the Dex root over the whole roster, and `Others` over the graph nodes
/// no line draws.
///
/// A `LazyVGrid` inside a `ScrollView`, which is what makes 1,022 entries affordable: only the
/// cells on screen are built, so only their sprites are ever decoded.
struct DexGridView: View {
    let rows: [DexRow]

    /// Whether `-dexDetailDemo` opens a detail sheet over this grid. True only for the Dex root,
    /// so the flag lands on one screen rather than re-firing on every grid pushed after it.
    var selectsDemoRow = false

    @State private var selected: DexRow?

    /// Three 32pt columns fit a 41mm watch, the narrowest screen the app supports.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    /// What the detail sheet resolves a row's evolution candidates against.
    ///
    /// Computed rather than built in an `init` because `rows` arrives empty and is replaced once
    /// `model.load()` runs, so a dictionary built at init would still be the empty one. It is
    /// evaluated only inside the `sheet` closure, so the cost is paid when a sheet opens, not on
    /// every scroll — and 1,022 inserts is microseconds either way.
    private var rowsById: [String: DexRow] {
        Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(rows) { row in
                        Button {
                            selected = row
                        } label: {
                            DexCell(row: row)
                        }
                        .buttonStyle(.plain)
                        // Undiscovered entries are still tappable, but there is nothing to tell.
                        .disabled(!row.isDiscovered)
                        .id(row.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            #if DEBUG
            // Both hooks, because the grid appears BEFORE it has any rows: `DexView.onAppear` is
            // what calls `model.load()`, and this view's own `onAppear` beats it. Firing on
            // `rows.count` as well is what makes the flags land on the loaded grid rather than on
            // an empty one.
            .onAppear { applyScreenshotFlags(scroller) }
            .onChange(of: rows.count) { _, _ in applyScreenshotFlags(scroller) }
            #endif
        }
        .sheet(item: $selected) { row in
            DexDetailView(row: row, pool: rowsById)
        }
    }

    #if DEBUG
    private func applyScreenshotFlags(_ scroller: ScrollViewProxy) {
        selectFirstDiscoveredIfRequested()
        scrollToTheEndIfRequested(scroller)
    }

    /// Debug-only: sets exactly the state a tap sets, so the detail sheet can be screenshotted.
    /// `simctl` has no touch command and Simulator UI scripting needs an accessibility grant this
    /// machine does not have, so a real tap cannot be synthesised. Compiled out of release builds.
    private func selectFirstDiscoveredIfRequested() {
        guard selectsDemoRow else { return }
        if CommandLine.arguments.contains("-dexDetailDemo") {
            selected = rows.first { $0.isDiscovered }
        } else if CommandLine.arguments.contains("-dexEmptyDetailDemo") {
            // A roster entry in no evolution line, which is ~930 of the 1,022 — the only way to see
            // the "No evolutions recorded." branch, since `-dexDetailDemo` lands on Agumon and
            // Agumon branches three ways.
            selected = rows.first { $0.id == "aquilamon" }
        }
    }

    /// Debug-only: jumps to the last cell of the grid, 340-odd rows down. `simctl` has no scroll
    /// command any more than it has a tap, so this is the only way to see that the far end of a
    /// 1,022-cell grid builds and draws at all — the same trick, and the same reason, as
    /// `EvolutionTreeView.scrollToTheBranchIfRequested`. Compiled out of release builds.
    private func scrollToTheEndIfRequested(_ scroller: ScrollViewProxy) {
        guard CommandLine.arguments.contains("-dexScrollDemo"), let last = rows.last else { return }
        scroller.scrollTo(last.id, anchor: .bottom)
    }
    #endif
}

/// One grid cell: the Digimon's idle sprite, or a placeholder if it has never been met.
private struct DexCell: View {
    let row: DexRow

    var body: some View {
        Group {
            if row.isDiscovered {
                IdleSpriteView(stage: row.stage.rawValue, name: row.spriteFile)
            } else {
                // A "?" rather than a silhouette: a silhouette would have to be derived from the
                // sprite, which would mean decoding the very art this screen is withholding.
                Text("?")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        // The unmet cell is dimmed as a whole, tile and all. On a grid that is mostly unmet — 1,022
        // entries against the handful one game discovers — a "?" alone reads as the pattern and the
        // met sprites as the exception; dropping the tile back makes the met ones the figure.
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(.white.opacity(row.isDiscovered ? 0.08 : 0.03)))
        .opacity(row.isDiscovered ? 1 : 0.55)
    }
}

/// What is known about one discovered Digimon, and what it can still become.
struct DexDetailView: View {
    let row: DexRow

    /// Rows to resolve this entry's edge targets against, keyed by id — the surrounding grid's or
    /// tree's rows. A candidate needs a discovery date to know whether to show its art, and only a
    /// row carries one.
    ///
    /// Defaults to empty, which degrades to every candidate drawn as undiscovered rather than to no
    /// section at all: the names are the part being withheld, and withholding one the player has
    /// actually earned is a smaller wrong than losing the whole list.
    var pool: [String: DexRow] = [:]

    var graph: EvolutionGraph = .bundled

    /// Cheap enough to recompute as `body` re-runs: at most three edges and a dictionary hit each.
    private var candidates: [DexRow] {
        DexRow.evolutionCandidates(of: row.id, in: graph, resolvedAgainst: pool)
    }

    /// Three columns, as on the Dex grid, so one to three candidates are a single line that fits a
    /// 41mm screen and a fourth wraps onto a second line the sheet scrolls to reach.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    /// Tightened in US-064 so a row of candidates clears the fold on a 41mm watch, which has about
    /// 215pt of height and lost 55 of it to the sheet's own close-button chrome. The hero dropped
    /// from 4x to 3x and the stage and date merged onto one 10pt line. Screenshots on 41mm settled
    /// each of those, not arithmetic: the first two attempts put the section below the fold and
    /// then clipped the tiles halfway.
    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                IdleSpriteView(stage: row.stage.rawValue, name: row.spriteFile, scale: 3)

                Text(row.displayName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                evolutions
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Stage and first sighting on one line, which is worth a whole 13pt line of a 215pt screen.
    /// "met" rather than "first met" so the pair still fits 41mm without wrapping.
    private var subtitle: String {
        guard let firstDiscovered = row.firstDiscovered else { return row.stage.displayName }
        let date = firstDiscovered.formatted(date: .abbreviated, time: .omitted)
        return "\(row.stage.displayName) · met \(date)"
    }

    @ViewBuilder
    private var evolutions: some View {
        Divider()

        Text("Evolves into")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

        if candidates.isEmpty {
            // Said out loud rather than left as a bare heading. Most of the roster has no authored
            // line, so an empty section here would be the common case and would read as a bug.
            Text("No evolutions recorded.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        } else {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(candidates) { candidate in
                    DexCandidateCell(row: candidate)
                }
            }
        }
    }
}

/// One Digimon this entry can evolve into: its art and name once met, a bare "?" until then.
///
/// The name is withheld, not just the sprite. A Dex that named the thing you have not found yet
/// would be answering the question the Dex exists to make you go and answer.
private struct DexCandidateCell: View {
    let row: DexRow

    var body: some View {
        VStack(spacing: 0) {
            if row.isDiscovered {
                IdleSpriteView(stage: row.stage.rawValue, name: row.spriteFile)

                Text(row.displayName)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("?")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(.white.opacity(row.isDiscovered ? 0.08 : 0.03)))
        .opacity(row.isDiscovered ? 1 : 0.55)
    }
}

#Preview {
    NavigationStack {
        DexView(model: DexModel())
    }
}
