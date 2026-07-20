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
            DexDetailView(row: row)
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
        guard selectsDemoRow, CommandLine.arguments.contains("-dexDetailDemo") else { return }
        selected = rows.first { $0.isDiscovered }
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

/// What is known about one discovered Digimon.
struct DexDetailView: View {
    let row: DexRow

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                IdleSpriteView(stage: row.stage.rawValue, name: row.spriteFile, scale: 4)

                Text(row.displayName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Text(row.stage.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let firstDiscovered = row.firstDiscovered {
                    Text("First met \(firstDiscovered.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    NavigationStack {
        DexView(model: DexModel())
    }
}
