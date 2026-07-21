import Foundation

/// A Digimon's typing on both axes: its `element` (this app's invention, the headline) and its
/// `attribute` (canon, a small triangle). See `Sources/DigimonElement.swift` for the vocabulary and
/// `docs/elements.md` for the chart.
///
/// One struct rather than two loose fields so a lookup returns a Digimon's WHOLE typing — a caller
/// can never resolve an element and forget to resolve the attribute beside it.
struct DigimonType: Codable, Equatable {
    let element: DigimonElement
    let attribute: DigimonAttribute

    /// What a Digimon nobody has typed resolves to. Both halves are the inert case on purpose: the
    /// ~870 roster-only Digimon that reach this floor must not quietly share an advantage, or
    /// "we forgot to type this one" becomes a strategy (D-2, `docs/elements.md`).
    static let unauthored = DigimonType(element: .neutral, attribute: .free)
}

/// One substring rule in the keyword tier: any id CONTAINING `keyword` (case-insensitively) is
/// typed this way, unless an earlier rule matched first.
///
/// Substring rather than prefix because the family token can sit anywhere in a name — `metal` is a
/// prefix in MetalGreymon but `seadra` is an infix in MegaSeadramon. The list is ORDERED and the
/// first match wins, which is also how collisions are resolved: `trice` is tested before `ice` so
/// Triceramon is earth rather than an ice type by accident of spelling.
struct ElementKeywordRule: Codable, Equatable {
    let keyword: String
    let element: DigimonElement
    let attribute: DigimonAttribute

    var type: DigimonType { DigimonType(element: element, attribute: attribute) }
}

/// Per-Digimon typing, with three tiers of fallback so all 1,022 roster Digimon resolve to
/// something (US-087).
///
/// Lookup order mirrors `MoveCatalog` deliberately — the Digimon's own `id`, then its `line`'s
/// default, then the ordered keyword rules, then `DigimonType.unauthored` — so there is ONE lookup
/// idiom in the codebase rather than two. The extra keyword tier exists because typing, unlike an
/// attack, can often be read off a name: a roster-only `waruseadramon` is obviously water, while
/// nothing about the name says what it throws.
struct ElementCatalog: Codable, Equatable {
    /// Types authored for a specific Digimon `id`. The top tier; every node in `evolutions.json`
    /// has one, pinned by a test.
    let types: [String: DigimonType]
    /// Fallback per evolution `line` key (`agumon`, `patamon`, …), for a node added to a line later
    /// without a typing of its own.
    let lineDefaults: [String: DigimonType]
    /// Ordered substring rules, first match wins. See `ElementKeywordRule`.
    let keywordRules: [ElementKeywordRule]

    /// The typing for a Digimon given its `id` and `line` (nil for a roster-only Digimon in no
    /// line). PURE — same inputs, same typing, no I/O — so every tier is unit-testable without a
    /// graph or a bundle.
    func type(forId id: String, line: String?) -> DigimonType {
        if let type = types[id] { return type }
        if let line, let type = lineDefaults[line] { return type }
        let name = id.lowercased()
        for rule in keywordRules where name.contains(rule.keyword.lowercased()) { return rule.type }
        return .unauthored
    }

    /// The typing for a Digimon by `id`, resolving its `line` from the graph. This is how the Dex
    /// and battle ask; the two-argument form above is the pure core it delegates to. No `roster`
    /// argument, unlike `MoveCatalog.move(for:in:roster:)` — the floor here is a keyword rule read
    /// off the id itself rather than the roster's `stage`.
    func type(for id: String, in graph: EvolutionGraph) -> DigimonType {
        type(forId: id, line: graph.node(id: id)?.line)
    }
}

extension ElementCatalog {
    /// Basename of the bundled catalog file.
    static let resourceName = "elements"

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case fileNotBundled

        var description: String {
            switch self {
            case .fileNotBundled:
                return "\(ElementCatalog.resourceName).json is not in the bundle"
            }
        }
    }

    /// Decodes the catalog from a bundle. Injectable for tests; the app uses `bundled`.
    static func load(from bundle: Bundle = .main) throws -> ElementCatalog {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.fileNotBundled
        }
        return try JSONDecoder().decode(ElementCatalog.self, from: try Data(contentsOf: url))
    }

    /// The shipped catalog, decoded once on first use. Traps like `MoveCatalog.bundled` — an
    /// undecodable authored file is a broken build, not a runtime condition.
    static let bundled: ElementCatalog = {
        do {
            return try load()
        } catch {
            fatalError("Could not load the element catalog: \(error)")
        }
    }()
}
