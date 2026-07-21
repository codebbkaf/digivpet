import Foundation

/// A Digimon's attack identity: the projectile it throws in an ordinary exchange, and its named
/// signature move for a finishing blow.
///
/// This is DATA, decoded from `moves.json` — authoring a Digimon's attack is a JSON edit, never a
/// code change (US-070). The two symbols are SF Symbol names, so a projectile is a glyph rather than
/// a new image asset; `tint` is a closed set so the file cannot name a colour the renderer has no
/// mapping for. US-072/US-073 render these; nothing here draws.
struct Move: Codable, Equatable {
    /// SF Symbol thrown on an ordinary turn, e.g. `flame.fill`. Its validity is a test's job —
    /// an unknown name renders as a blank square, which no decode can catch.
    let projectileSymbol: String
    /// The colour the projectile (and signature) is drawn in.
    let tint: MoveTint
    /// The named finisher shown as a banner on the knockout turn, e.g. "Pepper Breath".
    let signatureName: String
    /// SF Symbol for the finisher — larger than the ordinary projectile when drawn (US-073).
    let signatureSymbol: String

    /// The floor every lookup is guaranteed to reach, so a battle never renders an EMPTY projectile
    /// even against a malformed file. Reached only if `stageDefaults` is somehow incomplete — the
    /// bundled file covers every stage, pinned by a test — but the return stays non-optional so a
    /// caller can never be handed "no move".
    static let placeholder = Move(
        projectileSymbol: "circle.fill",
        tint: .white,
        signatureName: "Strike",
        signatureSymbol: "circle.fill"
    )
}

/// The tint an attack is drawn in — a closed set of named colours.
///
/// A string would let `moves.json` ship a colour the renderer cannot map, which would fail SILENTLY
/// at draw time. As an enum an unknown tint is a DECODE failure instead, caught at load the way a
/// bad `roster.json` stage is. The names match SwiftUI's system colours so the mapping is trivial.
enum MoveTint: String, Codable, CaseIterable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray, white
}

/// Per-Digimon attack identity, with two tiers of fallback so all 1,022 roster Digimon resolve to
/// something (US-070).
///
/// Lookup order: the Digimon's own `id`, then its `line`'s default, then its `stage`'s default. The
/// stage tier is the guaranteed floor — the bundled file authors one move for every `Stage`, so a
/// roster-only Digimon in no authored line (~930 of them) still throws something characteristic of
/// its rung rather than nothing.
struct MoveCatalog: Codable, Equatable {
    /// Moves authored for a specific Digimon `id`. The top lookup tier.
    let moves: [String: Move]
    /// Fallback move per evolution `line` key (`agumon`, `patamon`, …), used when a Digimon in that
    /// line has no `id` entry of its own.
    let lineDefaults: [String: Move]
    /// Fallback move per `Stage.rawValue`, the floor when a Digimon is in no authored line. The
    /// bundled file covers every stage.
    let stageDefaults: [String: Move]

    /// The move for a Digimon given its `line` (nil for a roster-only Digimon in no line) and
    /// `stage`. PURE — same inputs, same move, no I/O — so both fallback tiers are unit-testable
    /// without a graph or a bundle.
    func move(forId id: String, line: String?, stage: Stage?) -> Move {
        if let move = moves[id] { return move }
        if let line, let move = lineDefaults[line] { return move }
        if let stage, let move = stageDefaults[stage.rawValue] { return move }
        return Move.placeholder
    }

    /// The move for a Digimon by `id`, resolving its `line` and `stage` from the graph (which carries
    /// both) and, for a roster-only entry with no graph node, its `stage` from the roster. This is
    /// how battle and the Dex ask; the two-argument form above is the pure core it delegates to.
    func move(for id: String, in graph: EvolutionGraph, roster: Roster) -> Move {
        let node = graph.node(id: id)
        return move(forId: id, line: node?.line, stage: node?.stage ?? roster.entry(id: id)?.stage)
    }
}

extension MoveCatalog {
    /// Basename of the bundled catalog file.
    static let resourceName = "moves"

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case fileNotBundled

        var description: String {
            switch self {
            case .fileNotBundled:
                return "\(MoveCatalog.resourceName).json is not in the bundle"
            }
        }
    }

    /// Decodes the catalog from a bundle. Injectable for tests; the app uses `bundled`.
    static func load(from bundle: Bundle = .main) throws -> MoveCatalog {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.fileNotBundled
        }
        return try JSONDecoder().decode(MoveCatalog.self, from: try Data(contentsOf: url))
    }

    /// The shipped catalog, decoded once on first use. Traps like `EvolutionGraph.bundled` and
    /// `Roster.bundled` — an undecodable authored file is a broken build, not a runtime condition
    /// (see `EvolutionGraph.bundled` for how a trap here surfaces under `xcodebuild test`).
    static let bundled: MoveCatalog = {
        do {
            return try load()
        } catch {
            fatalError("Could not load the move catalog: \(error)")
        }
    }()
}
