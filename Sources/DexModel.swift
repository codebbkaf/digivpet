import Foundation
import OSLog
import SwiftUI

/// One cell of the Dex grid: a Digimon from the roster, and when — or whether — it was met.
struct DexRow: Identifiable, Equatable {
    let node: EvolutionNode
    /// When this Digimon was first discovered, or nil if it never has been.
    let firstDiscovered: Date?

    var id: String { node.id }
    var isDiscovered: Bool { firstDiscovered != nil }
}

/// One entry in the Dex's list of lines: either an evolution line, drawn as a tree, or the flat
/// "Others" catch-all.
///
/// The two are one type rather than two because the list has to add their counts up: every row is
/// in exactly one section, so `discoveredCount` over all sections is the header's count. A
/// separate "and also these" collection alongside the lines is the shape that lets a Digimon fall
/// into both or neither without anything noticing.
struct DexSection: Identifiable, Equatable {
    /// The `line` key, or `othersID`.
    let id: String
    /// What the list shows: the line's namesake Digimon, or "Others".
    let title: String
    /// Authored order for a line, so the tree's columns read as the JSON lists them; discovered-
    /// first then alphabetical for Others, which is a grid and has no structure to preserve.
    let rows: [DexRow]

    /// Sentinel id for the flat section. Prefixed so it cannot collide with a real line key,
    /// which `EvolutionGraphValidator` requires to be a non-empty name.
    static let othersID = "__others"

    /// False only for `Others`, which has no edges to draw and so gets a grid instead of a tree.
    var isLine: Bool { id != Self.othersID }

    var discoveredCount: Int { rows.filter(\.isDiscovered).count }
    var totalCount: Int { rows.count }
}

/// Drives the Dex screen: the whole roster, marked up with what the player has actually met.
///
/// The roster comes from the graph and the discoveries from the store, and this joins them. It
/// never opens the store itself for the same reason `MainScreenModel` doesn't take one directly:
/// opening throws and touches the disk, neither of which belongs in a `View.init`.
///
/// Note what this deliberately does NOT do: touch a single sprite. Rows carry the node, not its
/// art, so building all 865 rows decodes nothing — `IdleSpriteCache` is reached only from the
/// cells a `LazyVGrid` actually puts on screen.
@MainActor
final class DexModel: ObservableObject {
    /// Every Digimon in the roster, discovered first and alphabetical within each half.
    ///
    /// Discovered-first because the Dex is a trophy case: what the player has earned should not be
    /// buried among placeholders. Sorting is done once here rather than in `body`, which re-runs.
    @Published private(set) var rows: [DexRow] = []

    /// The same rows, partitioned into what the screen actually lists: one section per evolution
    /// line, in authored order, then `Others` if the roster has any `dexOnly` entries.
    ///
    /// Built here rather than in `body` for the reason `rows` is: `body` re-runs, and this groups
    /// and sorts 865 entries.
    @Published private(set) var sections: [DexSection] = []

    /// True once `load()` has run, so the screen can tell "no Digimon yet" from "not read yet".
    @Published private(set) var isLoaded = false

    private let graph: EvolutionGraph
    private let makeStore: @MainActor () throws -> GameStore

    private static let log = Logger(subsystem: "com.digivpet.DigiVPet", category: "dex")

    init(
        graph: EvolutionGraph = .bundled,
        makeStore: @escaping @MainActor () throws -> GameStore = { try GameStore() }
    ) {
        self.graph = graph
        self.makeStore = makeStore
    }

    /// How many of the roster have been met, and how many there are — the header's count.
    // `filter(_:).count` rather than `count(where:)`, which is watchOS 11+ and this app is 10.0.
    var discoveredCount: Int { rows.filter(\.isDiscovered).count }
    var totalCount: Int { rows.count }

    /// Reads the Dex and builds the grid's rows.
    ///
    /// A store that will not open degrades to an all-undiscovered Dex rather than an error screen:
    /// the roster is still worth showing, and the Dex is a side screen — losing it must not be
    /// louder than losing the game itself.
    func load() {
        var discoveries: [String: Date] = [:]
        do {
            let store = try makeStore()
            #if DEBUG
            seedDexDemoIfRequested(store)
            #endif
            discoveries = try store.dexDiscoveries()
        } catch {
            Self.log.error("Could not read the Dex: \(String(describing: error))")
        }

        rows = graph.nodes
            .map { DexRow(node: $0, firstDiscovered: discoveries[$0.id]) }
            .sorted { left, right in
                if left.isDiscovered != right.isDiscovered { return left.isDiscovered }
                return left.node.displayName.localizedCaseInsensitiveCompare(right.node.displayName)
                    == .orderedAscending
            }
        sections = Self.sections(of: graph, discoveries: discoveries)
        isLoaded = true
    }

    /// Groups the roster the way the screen lists it.
    ///
    /// Built from `graph.nodes` rather than from `rows` because the two want opposite orders: a
    /// tree's columns must follow authored order (so a branch reads as the JSON lists it and
    /// adding a node cannot reshuffle its siblings), whereas `rows` is deliberately sorted
    /// discovered-first for the flat grid. Sharing the sorted array would silently hand the tree
    /// an order that changes as the player discovers things.
    ///
    /// `dexOnly` entries are pulled out of their line and into `Others`. They carry a line like
    /// anything else, but no edge may name one, so on a tree they would be unreachable nodes
    /// floating beside the ladder with no connector — and listing them in both places would
    /// double-count them against the header.
    private static func sections(of graph: EvolutionGraph, discoveries: [String: Date]) -> [DexSection] {
        func row(_ node: EvolutionNode) -> DexRow {
            DexRow(node: node, firstDiscovered: discoveries[node.id])
        }

        var lineOrder: [String] = []
        var byLine: [String: [DexRow]] = [:]
        var others: [DexRow] = []

        for node in graph.nodes {
            if node.dexOnly {
                others.append(row(node))
                continue
            }
            if byLine[node.line] == nil { lineOrder.append(node.line) }
            byLine[node.line, default: []].append(row(node))
        }

        var sections = lineOrder.map { line in
            DexSection(id: line, title: title(ofLine: line, in: graph), rows: byLine[line] ?? [])
        }

        // Omitted rather than shown empty when nothing is `dexOnly`, which is the roster today:
        // an "Others" row opening onto nothing is a dead end the count does not need.
        if !others.isEmpty {
            sections.append(DexSection(
                id: DexSection.othersID,
                title: "Others",
                rows: others.sorted { left, right in
                    if left.isDiscovered != right.isDiscovered { return left.isDiscovered }
                    return left.node.displayName
                        .localizedCaseInsensitiveCompare(right.node.displayName) == .orderedAscending
                }
            ))
        }
        return sections
    }

    /// A line's heading. The key is a node id by convention (`agumon`, `patamon`), so the line is
    /// named after its namesake's display name — which keeps the casing and any punctuation the
    /// roster already chose. A key naming no node falls back to itself rather than failing: a
    /// heading reading `patamon` is a cosmetic slip, a missing line is a lost tree.
    private static func title(ofLine line: String, in graph: EvolutionGraph) -> String {
        graph.node(id: line)?.displayName ?? line
    }

    #if DEBUG
    /// Debug-only: fills in a few discoveries so the Dex can be screenshotted with BOTH halves
    /// visible. The Simulator has no HealthKit data, so a real game there never evolves far enough
    /// to discover anything past its starting egg. Unreachable without `-dexDemo`, and compiled out
    /// of release builds — the same discipline as `MainScreenModel.seedCeremonyDemoIfRequested`.
    private func seedDexDemoIfRequested(_ store: GameStore) {
        guard CommandLine.arguments.contains("-dexDemo") else { return }
        for id in ["botamon", "koromon", "agumon", "greymon"] {
            store.recordDiscovery(id: id)
        }
        try? store.save()
    }
    #endif
}
