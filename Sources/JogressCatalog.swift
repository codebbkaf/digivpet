import Foundation

/// The two parents of a Jogress, as ONE unordered value (US-130).
///
/// A Jogress is a fusion, not an arrow: WarGreymon + MetalGarurumon and MetalGarurumon + WarGreymon
/// are the same act, and the player picks two rows in a party list with no idea which one the file
/// happened to call `parentA`. Canonicalising the pair here — rather than looking both ways at every
/// call site — is what makes "A+B and B+A resolve to the same recipe" a property of the TYPE instead
/// of a rule every caller has to remember. It is also what collapses "the file lists both A+B and
/// B+A" and "the file lists A+B twice" into one validator finding: by construction they are the same
/// key.
struct JogressPair: Hashable, CustomStringConvertible {
    /// The lexicographically smaller id, whichever side of the file it was authored on.
    let first: String
    /// The lexicographically larger id.
    let second: String

    init(_ a: String, _ b: String) {
        if a <= b {
            first = a
            second = b
        } else {
            first = b
            second = a
        }
    }

    /// Both ids, in canonical order.
    var ids: [String] { [first, second] }

    /// True if this pair names the given id on either side.
    func contains(_ id: String) -> Bool { first == id || second == id }

    var description: String { "\(first) + \(second)" }
}

/// One Jogress fusion: two owned Digimon become a third (US-130, authored in US-131).
///
/// The conditions reuse `EvolutionCondition` for the same reason `DigitamaSlot` does — it is the
/// same question asked of the same counters, and a second spelling would mean a second evaluator,
/// a second set of validator rules and a second place for a metric to go stale. `ConditionReveal`
/// therefore already knows how to phrase a recipe's gate, which is what US-132's entry point leans
/// on to tell the player why a pair is not yet fusable.
///
/// ALL conditions must hold, like an edge's. An empty list is a fusion gated only on owning both
/// parents, which is the ordinary case for the Color devices' Jogress: the difficulty was getting
/// two Ultimates into the box at once, not clearing a further hurdle afterwards.
struct JogressRecipe: Codable, Equatable {
    /// A roster id. Which of the two is `parentA` is a fact about the FILE and nothing else —
    /// `pair` is what the game matches on. Checked against the roster by the validator, not here:
    /// an id that names nothing has to be a reported finding rather than a decode failure, for the
    /// reason `EvolutionCondition.metric` is a `String`.
    let parentA: String

    /// The other parent. `parentA == parentB` is a validator finding, not a decode failure.
    let parentB: String

    /// The roster id the two become. May be at the SAME stage as its parents — the Color devices'
    /// Jogress fuses two Ultimates into an Ultra, which this roster files under one folder — so the
    /// validator only rejects a result strictly BELOW a parent's rung.
    let result: String

    let conditions: [EvolutionCondition]

    /// The unordered key this recipe is looked up by.
    var pair: JogressPair { JogressPair(parentA, parentB) }

    init(
        parentA: String,
        parentB: String,
        result: String,
        conditions: [EvolutionCondition] = []
    ) {
        self.parentA = parentA
        self.parentB = parentB
        self.result = result
        self.conditions = conditions
    }

    // Hand-written for the same reason `AdventureMap`'s is: `conditions` says nothing when absent
    // and is omitted from the file, and synthesized Codable would reject the omission. The three
    // ids are strict `decode`, so a recipe missing a parent or a result fails the load loudly
    // instead of shipping as a fusion into "".
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            parentA: try container.decode(String.self, forKey: .parentA),
            parentB: try container.decode(String.self, forKey: .parentB),
            result: try container.decode(String.self, forKey: .result),
            conditions: try container.decodeIfPresent(
                [EvolutionCondition].self, forKey: .conditions) ?? []
        )
    }
}

/// The shipped Jogress recipes, decoded from the bundled `jogress.json`.
///
/// In the shape of `Roster` and `MapCatalog` on purpose, down to the private index and the
/// fatalError-on-bad-data `bundled`: these are the same kind of object — a shipped table the game
/// reads and never writes.
struct JogressCatalog: Codable, Equatable {
    /// Every recipe, in the order the file authors them.
    let recipes: [JogressRecipe]

    /// Keyed by the UNORDERED pair, which is what makes the lookup order-free. A duplicate key
    /// keeps the FIRST recipe, like `Roster.byId` — and the validator reports it, because the
    /// second one would otherwise be silently unreachable.
    private let byPair: [JogressPair: JogressRecipe]

    private enum CodingKeys: String, CodingKey {
        case recipes
    }

    init(recipes: [JogressRecipe]) {
        self.recipes = recipes
        self.byPair = Dictionary(
            recipes.map { ($0.pair, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(recipes: try container.decode([JogressRecipe].self, forKey: .recipes))
    }

    /// The recipe these two Digimon fuse by, in either order, or nil if they do not fuse.
    func recipe(for a: String, and b: String) -> JogressRecipe? {
        byPair[JogressPair(a, b)]
    }

    /// Every recipe this Digimon is a parent of, in catalog order. US-132's entry point walks the
    /// box with this to find the pairs a player could fuse.
    func recipes(involving id: String) -> [JogressRecipe] {
        recipes.filter { $0.pair.contains(id) }
    }
}

extension JogressCatalog {
    /// Basename of the bundled recipe file.
    static let resourceName = "jogress"

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case fileNotBundled

        var description: String {
            switch self {
            case .fileNotBundled:
                return "\(JogressCatalog.resourceName).json is not in the bundle"
            }
        }
    }

    /// Decodes the catalog from a bundle. Injectable for tests; the app uses `bundled`.
    static func load(from bundle: Bundle = .main) throws -> JogressCatalog {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.fileNotBundled
        }
        return try JSONDecoder().decode(JogressCatalog.self, from: try Data(contentsOf: url))
    }

    /// The shipped catalog, decoded once on first use.
    ///
    /// Traps like `Roster.bundled`, `EvolutionGraph.bundled` and `MapCatalog.bundled`, for the same
    /// reason: an undecodable shipped file is a broken build, not a runtime condition. Degrading to
    /// an empty catalog would present as "nothing fuses", which looks like a design decision rather
    /// than a crash.
    static let bundled: JogressCatalog = {
        do {
            return try load()
        } catch {
            fatalError("Could not load the Jogress catalog: \(error)")
        }
    }()
}
