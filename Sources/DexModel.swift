import Foundation
import OSLog
import SwiftUI

/// One cell of the Dex grid: a Digimon from the roster, and when — or whether — it was met.
///
/// Carries the four fields a cell draws rather than the `RosterEntry` or `EvolutionNode` it came
/// from, because since US-063 it comes from BOTH: the flat grid is built over the 1,022-entry
/// roster, while the evolution trees are still built over the 88-node graph. The overlapping
/// fields are identical in the two types, so a row that holds them can be made either way and the
/// cell that draws it never has to know which.
struct DexRow: Identifiable, Equatable {
    let id: String
    let displayName: String
    let stage: Stage
    /// As `RosterEntry.spriteFile` / `EvolutionNode.spriteFile` — the basename `IdleSpriteCache`
    /// resolves against the flat idle folder, falling back to the stage folder.
    let spriteFile: String
    /// When this Digimon was first discovered, or nil if it never has been.
    let firstDiscovered: Date?

    var isDiscovered: Bool { firstDiscovered != nil }

    init(id: String, displayName: String, stage: Stage, spriteFile: String, firstDiscovered: Date?) {
        self.id = id
        self.displayName = displayName
        self.stage = stage
        self.spriteFile = spriteFile
        self.firstDiscovered = firstDiscovered
    }

    init(entry: RosterEntry, firstDiscovered: Date?) {
        self.init(id: entry.id, displayName: entry.displayName, stage: entry.stage,
                  spriteFile: entry.spriteFile, firstDiscovered: firstDiscovered)
    }

    init(node: EvolutionNode, firstDiscovered: Date?) {
        self.init(id: node.id, displayName: node.displayName, stage: node.stage,
                  spriteFile: node.spriteFile, firstDiscovered: firstDiscovered)
    }
}

/// One thing this Digimon can become, and what it is still waiting for.
///
/// The row and the edge's criteria travel together because the detail view needs both at once: the
/// cell draws the row, and whether that cell is drawn as EARNED is a question only the edge's
/// conditions can answer. Resolving them separately would mean walking the same edges twice and
/// pairing them back up by target id, which converging lines make ambiguous.
struct DexCandidate: Identifiable, Equatable {
    let row: DexRow
    /// The `conditions` of the edge that leads here. Empty for an edge gated only by energy, care
    /// mistakes and battle wins — which is most of the shipped graph.
    let conditions: [EvolutionCondition]

    /// The target id paired with its position in the authored list. Two edges out of one node may
    /// name the same target under different criteria, and a bare id would make those one row to
    /// `ForEach` — silently dropping a branch from the screen.
    let id: String

    init(row: DexRow, conditions: [EvolutionCondition], index: Int) {
        self.row = row
        self.conditions = conditions
        self.id = "\(index)-\(row.id)"
    }
}

extension DexRow {
    /// What this Digimon can become: one row per outgoing edge, in authored order.
    ///
    /// Resolved against a pool of already-built rows rather than straight from the graph, because a
    /// candidate is drawn as a Dex cell and a cell needs a discovery date — which only a row
    /// carries. A target the pool does not hold falls back to its node, drawn undiscovered: the
    /// tree screen's pool is one line, and two shipped ids (`piyo_tanemon`, `piyo_yuramon`) are
    /// in the graph but not the roster, so a miss is ordinary data. (`extyranomon` was a third
    /// until US-158 renamed it to the roster's `ex-tyranomon`.)
    ///
    /// Empty when the id names no node at all, which since US-063 is the common case: the grid is
    /// the 1,022-entry roster and only ~88 of those have a node. The detail view says so out loud
    /// rather than showing an empty section.
    ///
    /// An edge whose target is in neither the pool nor the graph is dropped. That is a broken edge,
    /// and reporting it is `EvolutionGraphValidator`'s job — the Dex's job is not to invent a cell
    /// for a Digimon that does not exist.
    static func evolutionCandidates(
        of id: String,
        in graph: EvolutionGraph,
        resolvedAgainst pool: [String: DexRow]
    ) -> [DexRow] {
        candidates(of: id, in: graph, resolvedAgainst: pool).map(\.row)
    }

    /// As `evolutionCandidates`, but each row still carrying the criteria of the edge that reaches
    /// it — what US-066 needs to draw a hint per branch and to mark a branch as earned.
    static func candidates(
        of id: String,
        in graph: EvolutionGraph,
        resolvedAgainst pool: [String: DexRow]
    ) -> [DexCandidate] {
        guard let node = graph.node(id: id) else { return [] }
        return node.evolutions.enumerated().compactMap { index, edge in
            let row: DexRow
            if let known = pool[edge.to] {
                row = known
            } else if let target = graph.node(id: edge.to) {
                row = DexRow(node: target, firstDiscovered: nil)
            } else {
                return nil
            }
            return DexCandidate(row: row, conditions: edge.conditions, index: index)
        }
    }
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

    /// The graph nodes `rows` was built from, in the same order — what `EvolutionTreeView` lays
    /// its columns and connectors out from. Empty for `Others`, which is drawn as a grid and has
    /// no edges to follow.
    ///
    /// Kept here rather than re-derived in the view because a section is the only thing that knows
    /// WHICH nodes it grouped; since US-063 a `DexRow` no longer carries its node, because most
    /// rows on the flat grid have no node to carry.
    let nodes: [EvolutionNode]

    init(id: String, title: String, rows: [DexRow], nodes: [EvolutionNode] = []) {
        self.id = id
        self.title = title
        self.rows = rows
        self.nodes = nodes
    }

    /// Sentinel id for the flat section. Prefixed so it cannot collide with a real line key,
    /// which `EvolutionGraphValidator` requires to be a non-empty name.
    static let othersID = "__others"

    /// False only for `Others`, which has no edges to draw and so gets a grid instead of a tree.
    var isLine: Bool { id != Self.othersID }

    var discoveredCount: Int { rows.filter(\.isDiscovered).count }
    var totalCount: Int { rows.count }

    /// The line whose tree draws `id`, or nil if nothing does.
    ///
    /// Nil is the ORDINARY answer, not an error: since US-063 the Dex is the 1,022-entry roster and
    /// only ~88 of those are in an authored line, so the ~930 roster-only entries land here. So do
    /// `dexOnly` nodes, which `DexModel.sections(of:discoveries:)` pulls into `Others` because no
    /// edge may name one — drawing a tree for one would be a lone cell with no connector, which is
    /// the empty tree US-067 asks not to offer.
    ///
    /// Matched on `rows` rather than on the graph's `line` key so the answer is the section that
    /// would actually be DRAWN. A node grouped under a line the sections did not build — a
    /// `dexOnly` one — must not resolve to a tree it was deliberately left out of.
    static func line(containing id: String, in sections: [DexSection]) -> DexSection? {
        sections.first { $0.isLine && $0.rows.contains { $0.id == id } }
    }
}

/// Drives the Dex screen: the whole roster, marked up with what the player has actually met.
///
/// The roster comes from `roster.json` and the discoveries from the store, and this joins them. It
/// never opens the store itself for the same reason `MainScreenModel` doesn't take one directly:
/// opening throws and touches the disk, neither of which belongs in a `View.init`.
///
/// TWO SOURCES, ON PURPOSE (US-063). `rows` — the flat grid that IS the screen — comes from
/// `Roster.bundled`, all 1,022 Digimon that have art on disk. `sections` comes from
/// `EvolutionGraph.bundled`, the ~88 that an authored line actually reaches, because only those
/// have edges to draw a tree from. The grid is the roster; the trees are the graph; the header
/// counts the roster.
///
/// Note what this deliberately does NOT do: touch a single sprite. Rows carry a filename, not its
/// art, so building all 1,022 rows decodes nothing — `IdleSpriteCache` is reached only from the
/// cells a `LazyVGrid` actually puts on screen.
@MainActor
final class DexModel: ObservableObject {
    /// Every Digimon in the roster, discovered first and alphabetical within each half.
    ///
    /// Discovered-first because the Dex is a trophy case: what the player has earned should not be
    /// buried among placeholders. Sorting is done once here rather than in `body`, which re-runs.
    @Published private(set) var rows: [DexRow] = []

    /// The graph, partitioned into trees: one section per evolution line, in authored order, then
    /// `Others` if the graph has any `dexOnly` nodes.
    ///
    /// NOT a partition of `rows` — see the type note. Built here rather than in `body` for the
    /// reason `rows` is: `body` re-runs, and this groups and sorts.
    @Published private(set) var sections: [DexSection] = []

    /// True once `load()` has run, so the screen can tell "no Digimon yet" from "not read yet".
    @Published private(set) var isLoaded = false

    /// What the detail sheet's hints are resolved against — the current Digimon's totals.
    ///
    /// `.unknown` until `load()` runs, and `.unknown` still if there is no saved game or the store
    /// will not open. That degrades every hint to its coldest level, which is the right direction
    /// to fail: a hint that says nothing has moved is a smaller wrong than a checkmark on a branch
    /// the player has not earned. Only accumulating and `care.*` conditions can be answered from
    /// here — a standing measurement like resting heart rate needs a live read, which the Dex does
    /// not do, so those stay `.unknown` and read as `far`.
    @Published private(set) var conditionContext: ConditionContext = .unknown

    private let roster: Roster
    private let graph: EvolutionGraph
    private let makeStore: @MainActor () throws -> GameStore
    /// Reads a `health.*` metric over a window (US-179). Held so `loadHealthReadings` can answer a
    /// standing measurement — a resting heart rate, say — that no running total can hold. Injected so
    /// a test drives it from a fixture fetcher; the Simulator has no health data.
    private let metricReader: HealthMetricReader
    private let calendar: Calendar
    /// The most recent `.value` reads, `.unknown`-safe: only real numbers are kept, so a `.noData` or
    /// `.unavailable` neither answers a standing metric nor switches on `ConditionContext`'s
    /// accumulating-metric override — the same discipline `MainScreenModel.conditionReadings` keeps.
    private var readings: [ConditionMetric: HealthReading] = [:]
    /// True once `loadHealthReadings` has read the day, so re-entering the screen does not re-query:
    /// the day's totals do not change while the Dex is open.
    private var hasReadHealth = false

    private static let log = Logger(subsystem: "com.digivpet.DigiVPet", category: "dex")

    /// - Parameter makeStore: how the Dex reaches the saved game. THE LIVE APP MUST PASS
    ///   `MainScreenModel.sharedStore` (US-193): the default opens a SECOND `GameStore` on the same
    ///   file, and two live contexts invalidate each other's `GameState` records on reset — the
    ///   `ModelContext.reset` crash. The default survives only for the `#Preview` and for tests,
    ///   which each run against their own store, never the live game's.
    init(
        roster: Roster = .bundled,
        graph: EvolutionGraph = .bundled,
        makeStore: @escaping @MainActor () throws -> GameStore = { try GameStore() },
        metricReader: HealthMetricReader = HealthMetricReader(),
        calendar: Calendar = .current
    ) {
        self.roster = roster
        self.graph = graph
        self.makeStore = makeStore
        self.metricReader = metricReader
        self.calendar = calendar
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
    func load(now: Date = Date()) {
        var discoveries: [String: Date] = [:]
        var context = ConditionContext.unknown
        do {
            let store = try makeStore()
            #if DEBUG
            seedDexDemoIfRequested(store)
            #endif
            discoveries = try store.dexDiscoveries()
            // `savedState` and not `loadOrCreate`: see `GameStore.savedState`. Nil is an ordinary
            // first launch, not an error, and leaves every hint at its coldest.
            if let state = try store.savedState() {
                // `readings` is empty until `loadHealthReadings` runs — that async pass reads the
                // day's metrics and re-resolves this context, so a standing measurement answers on
                // the detail sheet. Synchronous `load` still answers every accumulating and `care.*`
                // condition off the saved state, exactly as before US-179.
                context = ConditionContext(state: state, now: now, readings: readings)
            }
        } catch {
            Self.log.error("Could not read the Dex: \(String(describing: error))")
        }
        #if DEBUG
        conditionContext = Self.revealDemoContext ?? context
        #else
        conditionContext = context
        #endif

        rows = roster.entries
            .map { DexRow(entry: $0, firstDiscovered: discoveries[$0.id]) }
            .sorted(by: Self.discoveredFirstThenAlphabetical)
        sections = Self.sections(of: graph, discoveries: discoveries)
        isLoaded = true
    }

    /// Reads today's health metrics and re-resolves the hint context against them (US-179).
    ///
    /// Kept off the synchronous `load` — the grid and its discoveries must not wait on a health read
    /// — and driven from `DexView`'s `.task`, so the detail sheet's hints can answer a standing
    /// measurement no running total can hold. A no-op after its first run and while a `-dexRevealDemo`
    /// context is forced: the day's totals do not change while the screen is up, and the demo's
    /// literal context must not be overwritten by an empty Simulator read.
    func loadHealthReadings(now: Date = Date()) async {
        guard !hasReadHealth else { return }
        #if DEBUG
        if Self.revealDemoContext != nil { hasReadHealth = true; return }
        #endif
        let interval = HealthDay.interval(containing: now, calendar: calendar)
        let read = await metricReader.readings(of: ReadableHealthMetric.all, in: interval)
        readings = read.filter { if case .value = $0.value { return true } else { return false } }
        hasReadHealth = true
        do {
            conditionContext = try makeStore().savedState()
                .map { ConditionContext(state: $0, now: now, readings: readings) } ?? .unknown
        } catch {
            Self.log.error("Could not re-read the Dex hint context: \(String(describing: error))")
        }
    }

    /// The flat grid's order: what the player has met, then everything else, alphabetical within
    /// each half.
    private static func discoveredFirstThenAlphabetical(_ left: DexRow, _ right: DexRow) -> Bool {
        if left.isDiscovered != right.isDiscovered { return left.isDiscovered }
        return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
    }

    /// Groups the graph into the trees the Dex can open.
    ///
    /// Built from `graph.nodes` rather than from `rows` because the two want opposite orders: a
    /// tree's columns must follow authored order (so a branch reads as the JSON lists it and
    /// adding a node cannot reshuffle its siblings), whereas `rows` is deliberately sorted
    /// discovered-first for the flat grid. Sharing the sorted array would silently hand the tree
    /// an order that changes as the player discovers things.
    ///
    /// `dexOnly` entries are pulled out of their line and into `Others`. They carry a line like
    /// anything else, but no edge may name one, so on a tree they would be unreachable nodes
    /// floating beside the ladder with no connector.
    private static func sections(of graph: EvolutionGraph, discoveries: [String: Date]) -> [DexSection] {
        func row(_ node: EvolutionNode) -> DexRow {
            DexRow(node: node, firstDiscovered: discoveries[node.id])
        }

        var lineOrder: [String] = []
        var byLine: [String: [EvolutionNode]] = [:]
        var others: [DexRow] = []

        for node in graph.nodes {
            if node.dexOnly {
                others.append(row(node))
                continue
            }
            if byLine[node.line] == nil { lineOrder.append(node.line) }
            byLine[node.line, default: []].append(node)
        }

        var sections = lineOrder.map { line in
            let nodes = byLine[line] ?? []
            return DexSection(id: line, title: title(ofLine: line, in: graph),
                              rows: nodes.map(row), nodes: nodes)
        }

        // Omitted rather than shown empty when nothing is `dexOnly`, which is the roster today:
        // an "Others" row opening onto nothing is a dead end the count does not need.
        if !others.isEmpty {
            sections.append(DexSection(
                id: DexSection.othersID,
                title: "Others",
                rows: others.sorted(by: discoveredFirstThenAlphabetical)
            ))
        }
        return sections
    }

    /// Headings for the lines named after a DEVICE rather than after a Digimon (US-133 onward).
    /// `dmc-v1` is a key, not a title, and the raw key on a section header would read as a bug.
    ///
    /// Short on purpose. These are `navigationTitle`s on a 41mm watch, which truncates at about
    /// fifteen characters: "Digital Monster Ver.1" was screenshotted there and came back as
    /// "Digital Monster…", losing the one part of the name that says WHICH tree this is.
    ///
    /// Only the device lines need an entry: a line still keyed on a node id resolves through that
    /// node below, which is the older and larger half of the file.
    ///
    /// US-144's five sweep lines are titled here too, even though three of their keys ARE Digimon
    /// names, because none of those Digimon is a node yet: `diablomon`, `commandramon` and
    /// `algomon` name where each thread is GOING, not what it currently holds, so the older
    /// node-id convention would resolve them to nil and head the section with its own key. Titling
    /// them explicitly also keeps the heading stable on the day a later sweep does add the
    /// namesake node.
    static let lineTitles: [String: String] = [
        "dmc-v1": "Color Ver.1",
        "dmc-v2": "Color Ver.2",
        "dmc-v3": "Color Ver.3",
        "dmc-v4": "Color Ver.4",
        "dmc-v5": "Color Ver.5",
        "penc-nsp": "Pendulum NSp",
        "penc-ds": "Pendulum DS",
        "penc-nso": "Pendulum NSo",
        "penc-wg": "Pendulum WG",
        "penc-me": "Pendulum ME",
        "penc-vb": "Pendulum VB",
        "tamers": "Tamers Partners",
        "wanyamon": "Beast Cubs",
        "diablomon": "Network Virus",
        "commandramon": "Special Forces",
        "algomon": "Algomon Signal",
        "adventure02": "Adventure 02",
        "vital": "Vital Bracelet",
        // US-146's two. Both are named for the device their thread comes off rather than for a
        // Digimon, so neither could ever resolve through the node-id convention.
        "xros": "Xros Loader",
        "penc-sw": "Pendulum SW",
    ]

    /// A line's heading. Either an authored title above, or — by the older convention — a node id
    /// (`palmon`, the last one left), in which case the line is named after its namesake's display name,
    /// keeping the casing and any punctuation the roster already chose. A key that is neither
    /// falls back to itself rather than failing: a heading reading `patamon` is a cosmetic slip,
    /// a missing line is a lost tree.
    private static func title(ofLine line: String, in graph: EvolutionGraph) -> String {
        lineTitles[line] ?? graph.node(id: line)?.displayName ?? line
    }

    #if DEBUG
    /// Debug-only: fills in a few discoveries so the Dex can be screenshotted with BOTH halves
    /// visible. The Simulator has no HealthKit data, so a real game there never evolves far enough
    /// to discover anything past its starting egg. Unreachable without `-dexDemo`, and compiled out
    /// of release builds — the same discipline as `MainScreenModel.seedCeremonyDemoIfRequested`.
    private func seedDexDemoIfRequested(_ store: GameStore) {
        guard CommandLine.arguments.contains("-dexDemo") else { return }
        // `aquilamon` is in the roster but in no evolution line, so it is what `-dexEmptyDetailDemo`
        // opens to screenshot "No evolutions recorded." It sorts after Agumon, so seeding it does
        // not steal `-dexDetailDemo`, which takes the alphabetically first discovered row.
        for id in ["botamon", "koromon", "agumon", "greymon", "aquilamon"] {
            store.recordDiscovery(id: id)
        }
        // `-dexWidestDetailDemo` opens Gabumon, whose five candidates are the widest evolution
        // grid shipped. Seeded only under that flag so it cannot steal `-dexDetailDemo`, which
        // takes the alphabetically first discovered row (Agumon, and Gabumon sorts after it —
        // but the candidates have to be discovered too, and Angemon would not).
        if CommandLine.arguments.contains("-dexWidestDetailDemo") {
            for id in ["gabumon", "kabuterimon", "garurumon", "angemon", "yukidarumon", "vegimon"] {
                store.recordDiscovery(id: id)
            }
        }
        try? store.save()
    }

    /// Debug-only: the part-met totals `-dexRevealDemo` shows the hints against, or nil when the
    /// flag is absent.
    ///
    /// Built to put all three reveal levels of US-066 on ONE screenshot of Agumon's detail sheet,
    /// because the Simulator has no HealthKit data and a real game there earns nothing at all:
    ///
    /// - 39,000 of Greymon's 60,000 stage steps — 65%, so that hint is `close`.
    /// - 2 of its 6 training sessions — 33%, so that one is `far`.
    /// - Meramon's 1,200 active kilocalories cleared, and 0 overfeeds against a cap of 2, so BOTH
    ///   of its conditions are met and its cell draws as earned while Greymon's does not.
    ///
    /// A context literal rather than seeded state, so it cannot write a fake game to the store.
    /// Compiled out of release builds.
    private static var revealDemoContext: ConditionContext? {
        guard CommandLine.arguments.contains("-dexRevealDemo") else { return nil }
        return ConditionContext(
            stageTotals: MetricTotals(values: [
                ConditionMetric.healthSteps.rawValue: 39_000,
                ConditionMetric.healthActiveEnergy.rawValue: 1_500,
            ]),
            trainingSessionsThisStage: 2,
            overfeedsThisStage: 0)
    }
    #endif
}
