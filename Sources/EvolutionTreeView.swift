import SwiftUI

/// Where every Digimon in one evolution line sits on a stage-ordered grid, and which pairs of
/// them a connecting line has to be drawn between.
///
/// Pulled out of the view because it is arithmetic, not layout: a test can check that a branch
/// really does put two nodes in one column and that the converging edge is still drawn, without
/// standing up a view graph. The view turns these integer grid coordinates into points by
/// multiplying by a fixed cell size, so the connectors need no `GeometryReader` or anchor
/// preferences to find their endpoints — they are known before anything is drawn.
struct EvolutionTreeLayout: Equatable {
    /// One stage's worth of the line, top to bottom.
    struct Column: Equatable, Identifiable {
        let stage: Stage
        let nodes: [EvolutionNode]

        var id: String { stage.rawValue }
    }

    /// A grid cell: which column, and how far down it.
    struct Position: Equatable {
        let column: Int
        let row: Int
    }

    /// One edge, resolved to the two cells it joins.
    ///
    /// Both ends are positions rather than ids because that is all the view needs, and it means a
    /// connector cannot name a node the layout never placed.
    struct Connector: Equatable, Identifiable {
        let from: Position
        let to: Position

        var id: String { "\(from.column).\(from.row)-\(to.column).\(to.row)" }
    }

    /// Stages in ladder order, each holding at least one node. Stages the line never reaches are
    /// absent entirely rather than empty: a gap column would be dead width on a 42mm screen.
    let columns: [Column]

    /// Every edge between two placed nodes.
    let connectors: [Connector]

    /// The tallest column, which is how many rows the grid needs.
    var rowCount: Int { columns.map(\.nodes.count).max() ?? 0 }

    /// - Parameter nodes: one line's nodes. Ordering within a column follows the order given,
    ///   which for the bundled graph is authored order — so a branch reads in the order the JSON
    ///   lists it rather than alphabetically, and adding a node cannot reshuffle its siblings.
    init(nodes: [EvolutionNode]) {
        // `ladderIndex` rather than `Stage.allCases`: Armor-Hybrid is off the ladder and has no
        // rung, so it is not a column on a stage-ordered tree at all. No line ships one yet; when
        // one does it needs a deliberate answer, not a silent slot after Ultimate.
        let ranked = Stage.allCases.compactMap { stage in stage.ladderIndex.map { ($0, stage) } }
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        columns = ranked.compactMap { stage in
            let atStage = nodes.filter { $0.stage == stage }
            return atStage.isEmpty ? nil : Column(stage: stage, nodes: atStage)
        }

        var positions: [String: Position] = [:]
        for (column, entry) in columns.enumerated() {
            for (row, node) in entry.nodes.enumerated() {
                positions[node.id] = Position(column: column, row: row)
            }
        }

        // An edge pointing outside this line — or at a node whose stage is off the ladder — has no
        // second endpoint here, so it is dropped rather than drawn to nowhere. Nothing in the
        // shipped roster does that; `line` is a grouping key the engine does not read, so it can.
        connectors = columns.flatMap(\.nodes).flatMap { node -> [Connector] in
            guard let from = positions[node.id] else { return [] }
            return node.evolutions.compactMap { edge in
                positions[edge.to].map { Connector(from: from, to: $0) }
            }
        }
    }
}

/// One evolution line drawn as a tree: stages left to right, branches stacked within a stage.
///
/// The grid is fixed-size rather than flexible, and that is what lets the connectors be plain
/// `Path`s over the same coordinate space the cells are placed in. A flexible grid would need each
/// cell to report its frame back up through a preference before a single line could be drawn.
struct EvolutionTreeView: View {
    /// One line's nodes, in authored order — the edges the columns and connectors are laid out
    /// from.
    let nodes: [EvolutionNode]

    /// The same Digimon as `rows`, discovered and not. Both, because the two halves of a cell come
    /// from different places: the node carries the edges, and only the row carries the discovery
    /// date `DexDetailView` shows. Since US-063 a `DexRow` no longer carries its node, because the
    /// flat grid's rows are roster entries and most of those have no node at all.
    let rows: [DexRow]

    @State private var selected: DexRow?

    private let layout: EvolutionTreeLayout
    private let rowsById: [String: DexRow]

    /// Cell geometry. 32pt of art plus padding is the same cell the Dex grid uses, so a Digimon is
    /// the size the user already knows it at; the column gap is what the connectors are drawn in.
    private static let cellWidth: CGFloat = 34
    private static let cellHeight: CGFloat = 34
    private static let columnGap: CGFloat = 18
    private static let rowGap: CGFloat = 6

    private static var columnStride: CGFloat { cellWidth + columnGap }
    private static var rowStride: CGFloat { cellHeight + rowGap }

    init(nodes: [EvolutionNode], rows: [DexRow]) {
        self.nodes = nodes
        self.rows = rows
        self.layout = EvolutionTreeLayout(nodes: nodes)
        self.rowsById = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    // Under the cells, so a line never crosses a sprite it happens to pass near.
                    connectors

                    // A real `HStack` of `VStack`s rather than offset cells, even though the
                    // connectors compute their own coordinates either way. Fixed cell sizes make
                    // the two identical to the pixel — but `.offset` moves a view without moving
                    // its layout frame, so an offset column is unreachable by `scrollTo` and, more
                    // to the point, by VoiceOver's spatial ordering.
                    HStack(alignment: .top, spacing: Self.columnGap) {
                        ForEach(layout.columns) { entry in
                            VStack(spacing: Self.rowGap) {
                                ForEach(entry.nodes) { node in
                                    cell(for: node)
                                        .frame(width: Self.cellWidth, height: Self.cellHeight)
                                }
                            }
                            .frame(width: Self.cellWidth, alignment: .top)
                            .id(entry.id)
                        }
                    }
                }
                .frame(width: gridSize.width, height: gridSize.height, alignment: .topLeading)
                .padding(.horizontal, 4)
            }
            #if DEBUG
            .onAppear { scrollToTheBranchIfRequested(scroller) }
            #endif
        }
        .sheet(item: $selected) { row in
            // This line's rows are the pool, which covers every candidate: no shipped edge crosses
            // a line, and one that ever did would resolve off the graph and draw as undiscovered.
            DexDetailView(row: row, pool: rowsById)
        }
    }

    #if DEBUG
    /// Debug-only: scrolls to the last stage, which is the only way to screenshot the branch on a
    /// seven-column tree — `simctl` has no scroll command any more than it has a tap. Compiled out
    /// of release builds, exactly like `DexView.selectFirstDiscoveredIfRequested`.
    private func scrollToTheBranchIfRequested(_ scroller: ScrollViewProxy) {
        guard CommandLine.arguments.contains("-dexTreeScrollDemo"),
              let last = layout.columns.last else { return }
        scroller.scrollTo(last.id, anchor: .trailing)
    }
    #endif

    private var gridSize: CGSize {
        CGSize(
            width: max(CGFloat(layout.columns.count) * Self.columnStride - Self.columnGap, 0),
            height: max(CGFloat(layout.rowCount) * Self.rowStride - Self.rowGap, 0)
        )
    }

    private var connectors: some View {
        Path { path in
            for connector in layout.connectors {
                path.move(to: point(connector.from, edge: 1))
                path.addLine(to: point(connector.to, edge: 0))
            }
        }
        .stroke(.tertiary, lineWidth: 1)
        .frame(width: gridSize.width, height: gridSize.height, alignment: .topLeading)
    }

    /// The middle of a cell's right (`edge: 1`) or left (`edge: 0`) side — a connector leaves one
    /// cell's trailing edge and arrives at the next one's leading edge, so the line lives in the
    /// column gap and only slants where a branch changes row.
    private func point(_ position: EvolutionTreeLayout.Position, edge: CGFloat) -> CGPoint {
        CGPoint(
            x: CGFloat(position.column) * Self.columnStride + edge * Self.cellWidth,
            y: CGFloat(position.row) * Self.rowStride + Self.cellHeight / 2
        )
    }

    @ViewBuilder
    private func cell(for node: EvolutionNode) -> some View {
        let row = rowsById[node.id]

        Button {
            selected = row
        } label: {
            EvolutionTreeCell(row: row)
        }
        .buttonStyle(.plain)
        // Undiscovered nodes stay non-tappable: the tree shows the SHAPE of a line before it is
        // earned, which is the point of drawing one, but there is still nothing to open.
        .disabled(row?.isDiscovered != true)
    }
}

/// One node of the tree: its idle sprite once met, a "?" until then.
///
/// Deliberately the same two cases, and the same "?", as the Dex grid's cell — the tree replaces
/// that grid in US-042, and a node that reads differently in the two screens would look like a
/// different kind of unknown rather than the same one.
private struct EvolutionTreeCell: View {
    let row: DexRow?

    var body: some View {
        Group {
            if let row, row.isDiscovered {
                IdleSpriteView(stage: row.stage.rawValue, name: row.spriteFile)
            } else {
                Text("?")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
    }
}

#if DEBUG
/// Debug-only host so the tree can be screenshotted before US-042 puts it on the Dex screen.
///
/// It seeds its own discoveries rather than reading the store for the usual reason: the Simulator
/// has no HealthKit data, so a real game there never evolves far enough to discover anything past
/// its egg, and a tree of nothing but "?" would not show that a discovered node draws its sprite.
/// The Agumon line is the one that branches (Greymon / Meramon, converging at MetalGreymon).
struct EvolutionTreeDemoView: View {
    private static let discovered: Set<String> = ["agu_digitama", "botamon", "koromon", "agumon", "greymon"]

    var body: some View {
        let nodes = EvolutionGraph.bundled.nodes.filter { $0.line == "agumon" }
        EvolutionTreeView(
            nodes: nodes,
            rows: nodes.map {
                DexRow(node: $0, firstDiscovered: Self.discovered.contains($0.id) ? .now : nil)
            })
            .navigationTitle("Agumon")
    }
}
#endif

#Preview {
    let nodes = EvolutionGraph.bundled.nodes.filter { $0.line == "agumon" }
    EvolutionTreeView(
        nodes: nodes,
        rows: nodes.map { DexRow(node: $0, firstDiscovered: $0.stage.ladderIndex ?? 0 < 4 ? .now : nil) })
}
