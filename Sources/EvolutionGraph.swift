import Foundation

/// One edge: "this node can become `to`, if these conditions hold".
///
/// The conditions are evaluated by the evolution engine (US-019); this type only carries them.
struct EvolutionEdge: Codable, Equatable {
    /// The `id` of the node evolved into. May name a node any number of other nodes also point
    /// at — converging lines are ordinary data, not a special case.
    let to: String

    /// Which energy type must be dominant for this edge to qualify.
    ///
    /// Nil means "no dominant-type gate", which is ONLY for a Digitama's hatch edge: hatching
    /// (US-018) is driven by total energy across all four types, so no single type gates it and
    /// naming one here would be a lie that a later reader would eventually "fix" into a bug.
    /// Every edge out of a hatched node carries this. US-009's validator should enforce that.
    let requiredEnergy: EnergyType?

    /// Energy threshold for this edge. Compared against the per-stage total (US-019 pins down
    /// the exact comparison); on a Digitama's hatch edge it is the 50-total hatch threshold.
    let minEnergy: Int

    /// The edge is blocked once care mistakes exceed this — neglect closes off the good lines.
    let maxCareMistakes: Int

    /// Battle wins required, when the edge is gated on them at all. Nil means ungated.
    let minBattleWins: Int?

    /// The edge taken when the time gate has passed and nothing else qualifies, so a Digimon is
    /// never permanently stuck (US-020). Exactly one edge per non-terminal node sets this.
    let isDefault: Bool

    /// Extra criteria, ALL of which must hold. Empty (the default, and every shipped edge today)
    /// means the edge is gated only by the fields above.
    ///
    /// This is the growth point: `requiredEnergy` / `minEnergy` / `maxCareMistakes` /
    /// `minBattleWins` are a fixed four, whereas a condition names its metric as data, so a new
    /// criterion is a JSON edit rather than a new field on this struct. See `EvolutionCondition`.
    let conditions: [EvolutionCondition]

    init(
        to: String,
        requiredEnergy: EnergyType? = nil,
        minEnergy: Int,
        maxCareMistakes: Int,
        minBattleWins: Int? = nil,
        isDefault: Bool = false,
        conditions: [EvolutionCondition] = []
    ) {
        self.to = to
        self.requiredEnergy = requiredEnergy
        self.minEnergy = minEnergy
        self.maxCareMistakes = maxCareMistakes
        self.minBattleWins = minBattleWins
        self.isDefault = isDefault
        self.conditions = conditions
    }

    // Hand-written so an omitted `isDefault` or `conditions` decodes as false / []. Synthesized
    // Codable has no concept of a default value: it would reject every edge that leaves the key
    // out — which today is every edge in the shipped file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            to: try container.decode(String.self, forKey: .to),
            requiredEnergy: try container.decodeIfPresent(EnergyType.self, forKey: .requiredEnergy),
            minEnergy: try container.decode(Int.self, forKey: .minEnergy),
            maxCareMistakes: try container.decode(Int.self, forKey: .maxCareMistakes),
            minBattleWins: try container.decodeIfPresent(Int.self, forKey: .minBattleWins),
            isDefault: try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false,
            conditions: try container.decodeIfPresent(
                [EvolutionCondition].self, forKey: .conditions) ?? []
        )
    }
}

/// One Digimon in the graph.
struct EvolutionNode: Codable, Equatable, Identifiable {
    /// Unique key edges point at. Distinct from `spriteFile` so art can be renamed or shared
    /// without rewriting every edge.
    let id: String
    let displayName: String
    let stage: Stage

    /// Which evolution line this node belongs to, e.g. `agumon`, `patamon`. Purely a grouping
    /// key: the Dex draws one tree per line (US-041), and nothing in the evolution engine reads
    /// it, so an edge may still cross lines if a roster ever wants that.
    ///
    /// Every node carries one. There is no "unassigned" — a node with no line is invisible to
    /// the Dex tree, which is a silent disappearance rather than a visible error, so the decoder
    /// below requires the key and `validate()` rejects an empty one.
    let line: String

    /// Filename without extension under `16x16 Digimon Sprites/<stage.rawValue>/`, which is all
    /// `SpriteLoader.loadSheet(stage:name:)` needs. US-009 checks it exists on disk.
    let spriteFile: String

    /// Variant suffix parsed off the filename (`X`, `Black`, `Virus`, `2006`, ...), or nil for
    /// the base form. Variants are separate nodes, per the PRD — this labels them.
    let variant: String?

    /// True for the 157 Digimon that exist only in `Idle Frame Only/` with no animated sheet.
    /// They can appear in the Dex but must never be playable or named by an edge: animating one
    /// would mean slicing a sheet that does not exist.
    let dexOnly: Bool

    /// Outgoing edges. Multiple edges = a branching node; empty = terminal (Ultimate, or a line
    /// not yet authored).
    let evolutions: [EvolutionEdge]

    /// `line` defaults ONLY here, for the many fixtures that build a node to exercise something
    /// unrelated to grouping. The decoder deliberately does not default it: a fixture with the
    /// wrong line is a test that reads oddly, whereas a shipped node with the wrong line is a
    /// Digimon missing from its tree.
    init(
        id: String,
        displayName: String,
        stage: Stage,
        line: String = "test",
        spriteFile: String,
        variant: String? = nil,
        dexOnly: Bool = false,
        evolutions: [EvolutionEdge] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.stage = stage
        self.line = line
        self.spriteFile = spriteFile
        self.variant = variant
        self.dexOnly = dexOnly
        self.evolutions = evolutions
    }

    // As on EvolutionEdge: hand-written so `dexOnly` and `evolutions` may be omitted. A
    // terminal node leaves `evolutions` out entirely rather than writing `[]`. `line` is NOT in
    // that set — it is `decode`, not `decodeIfPresent`, so a node missing it fails the whole
    // load rather than quietly joining a default line and vanishing from the Dex tree.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            stage: try container.decode(Stage.self, forKey: .stage),
            line: try container.decode(String.self, forKey: .line),
            spriteFile: try container.decode(String.self, forKey: .spriteFile),
            variant: try container.decodeIfPresent(String.self, forKey: .variant),
            dexOnly: try container.decodeIfPresent(Bool.self, forKey: .dexOnly) ?? false,
            evolutions: try container.decodeIfPresent([EvolutionEdge].self, forKey: .evolutions) ?? []
        )
    }
}

/// The whole evolution tree, decoded from the bundled `evolutions.json`.
///
/// The graph is data, not code: adding a Digimon means adding a node to the JSON, never editing
/// a Swift file. See `docs/evolutions-schema.md` for the file format.
struct EvolutionGraph: Codable, Equatable {
    /// Every node, in authored order.
    ///
    /// This is the file as written, duplicate ids included — `byId` silently keeps the first of
    /// a duplicate pair, so reporting duplicates is US-009's job and it needs to see them.
    let nodes: [EvolutionNode]

    private let byId: [String: EvolutionNode]

    private enum CodingKeys: String, CodingKey {
        case nodes
    }

    init(nodes: [EvolutionNode]) {
        self.nodes = nodes
        self.byId = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(nodes: try container.decode([EvolutionNode].self, forKey: .nodes))
    }

    /// The node with this id, or nil if no node has it (which US-009 reports as a broken edge).
    func node(id: String) -> EvolutionNode? {
        byId[id]
    }

    /// Every node with an edge pointing at `id`.
    ///
    /// Edges are stored on the parent, so converging lines are only visible by scanning. Fine at
    /// 865 nodes and used off the hot path; index it if that changes.
    func parents(of id: String) -> [EvolutionNode] {
        nodes.filter { node in node.evolutions.contains { $0.to == id } }
    }

    /// Every node at a stage — e.g. the Digitama to pick a new game's egg from (US-018).
    func nodes(at stage: Stage) -> [EvolutionNode] {
        nodes.filter { $0.stage == stage }
    }
}

extension EvolutionGraph {
    /// Basename of the bundled graph file.
    static let resourceName = "evolutions"

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case fileNotBundled

        var description: String {
            switch self {
            case .fileNotBundled:
                return "\(EvolutionGraph.resourceName).json is not in the bundle"
            }
        }
    }

    /// Decodes the graph from a bundle. Injectable for tests; the app uses `bundled`.
    static func load(from bundle: Bundle = .main) throws -> EvolutionGraph {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.fileNotBundled
        }
        return try JSONDecoder().decode(EvolutionGraph.self, from: try Data(contentsOf: url))
    }

    /// The shipped graph, decoded once on first use.
    ///
    /// This traps rather than degrading to an empty graph, which would look like "you have no
    /// Digimon" — an unreadable graph is a broken build, not a runtime condition, and US-009's
    /// validator test is what keeps it from ever reaching a user. Contrast a missing sprite,
    /// which is one Digimon's art and correctly degrades to a placeholder.
    ///
    /// BEWARE when this fires under `xcodebuild test`: the app is the TEST_HOST, so trapping at
    /// launch kills the runner before a single test reports, and xcodebuild blames it on
    /// "Early unexpected exit ... test runner crashed before establishing connection" — which
    /// names neither this file nor the graph. The real diagnostic is in the log above it:
    /// grep for "Could not load the evolution graph", which gives the exact JSON path
    /// (e.g. `nodes[1].evolutions[0].requiredEnergy`). A whole suite going red for one JSON
    /// typo is the cost of catching a broken graph at launch instead of mid-game.
    static let bundled: EvolutionGraph = {
        do {
            return try load()
        } catch {
            fatalError("Could not load the evolution graph: \(error)")
        }
    }()
}
