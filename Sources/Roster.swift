import Foundation

/// One Digimon in the Dex — every sprite that exists on disk, whether or not any line reaches it.
///
/// Deliberately NOT an `EvolutionNode`, and deliberately carrying neither `line` nor `evolutions`:
///
///   - `line` groups a node into a tree the Dex draws. ~950 of the 1,022 entries belong to no
///     authored line, and `EvolutionNode.line` is `decode`, not `decodeIfPresent`, so putting them
///     in `evolutions.json` would fail the whole graph load — which fatalErrors at launch.
///   - no `evolutions` because an entry here makes no claim about what it becomes. A missing field
///     says "nobody authored this"; an empty `[]` would say "this is terminal", which is a
///     different and mostly false statement.
///
/// The two files answer different questions and are kept apart on purpose: `evolutions.json` is
/// "what can this become", `roster.json` is "what exists". A Digimon in a line appears in both,
/// keyed by the same `id`.
struct RosterEntry: Codable, Equatable, Identifiable {
    /// Matches `EvolutionNode.id` for the entries a line reaches, which is how a Dex tile finds
    /// its graph node (and vice versa).
    let id: String
    let displayName: String
    let stage: Stage

    /// Filename without extension. Under `16x16 Digimon Sprites/<stage.rawValue>/`, except for a
    /// `dexOnly` entry, whose art is in the flat `Idle Frame Only/` folder instead — the same
    /// split `EvolutionGraph.spriteExists` resolves.
    let spriteFile: String

    /// Variant suffix parsed off the filename (`X`, `Black`, `Virus`, `2006`, ...), nil for a base
    /// form.
    let variant: String?

    /// True for the Digimon that exist only as a single idle frame, with no animated sheet. They
    /// fill the Dex but are never playable and are never named by an edge.
    let dexOnly: Bool

    init(
        id: String,
        displayName: String,
        stage: Stage,
        spriteFile: String,
        variant: String? = nil,
        dexOnly: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.stage = stage
        self.spriteFile = spriteFile
        self.variant = variant
        self.dexOnly = dexOnly
    }

    // Hand-written for the same reason as `EvolutionNode`'s: `variant` and `dexOnly` are omitted
    // by the generator when they say nothing, and synthesized Codable would reject that. `stage`
    // is NOT in that set — it is `decode`, so an entry the generator could not resolve a stage
    // for (`"stage": null`) fails the load loudly instead of quietly defaulting to a rung it is
    // not on and being filed under the wrong Dex heading forever.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            stage: try container.decode(Stage.self, forKey: .stage),
            spriteFile: try container.decode(String.self, forKey: .spriteFile),
            variant: try container.decodeIfPresent(String.self, forKey: .variant),
            dexOnly: try container.decodeIfPresent(Bool.self, forKey: .dexOnly) ?? false
        )
    }
}

/// The full roster, decoded from the bundled `roster.json`.
///
/// Generated, never hand-edited: `python3 scripts/build_roster.py` derives it from the sprite tree
/// (see README.md). Hand-authored data belongs in `evolutions.json` or, for a dexOnly entry's
/// stage, in `scripts/dex_only_stages.json`.
struct Roster: Codable, Equatable {
    /// Every entry, in ladder order then by id — so a Dex grid can draw them as they come.
    let entries: [RosterEntry]

    private let byId: [String: RosterEntry]

    private enum CodingKeys: String, CodingKey {
        case entries
    }

    init(entries: [RosterEntry]) {
        self.entries = entries
        self.byId = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(entries: try container.decode([RosterEntry].self, forKey: .entries))
    }

    /// The entry with this id, or nil if the roster has none.
    func entry(id: String) -> RosterEntry? {
        byId[id]
    }

    /// Every entry at a stage, in roster order.
    func entries(at stage: Stage) -> [RosterEntry] {
        entries.filter { $0.stage == stage }
    }
}

extension Roster {
    /// Basename of the bundled roster file.
    static let resourceName = "roster"

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case fileNotBundled

        var description: String {
            switch self {
            case .fileNotBundled:
                return "\(Roster.resourceName).json is not in the bundle"
            }
        }
    }

    /// Decodes the roster from a bundle. Injectable for tests; the app uses `bundled`.
    static func load(from bundle: Bundle = .main) throws -> Roster {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.fileNotBundled
        }
        return try JSONDecoder().decode(Roster.self, from: try Data(contentsOf: url))
    }

    /// The shipped roster, decoded once on first use.
    ///
    /// Traps like `EvolutionGraph.bundled`, and for the same reason — an undecodable generated
    /// file is a broken build, not a runtime condition. See that property's note about how this
    /// looks under `xcodebuild test` (the test runner dies before reporting; the real diagnostic
    /// is the "Could not load the roster" line and the JSON path it names).
    static let bundled: Roster = {
        do {
            return try load()
        } catch {
            fatalError("Could not load the roster: \(error)")
        }
    }()
}
