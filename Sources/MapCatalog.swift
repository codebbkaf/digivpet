import Foundation

/// One Digitama a map can hand over, and what the player has to do to find it (US-116, US-128).
///
/// The conditions reuse `EvolutionCondition` wholesale rather than getting a parallel type: the
/// vocabulary, the windows, the comparisons and the hint contract are all the same question asked
/// of the same counters, and a second spelling of it would mean a second evaluator, a second set of
/// validator rules and a second place for a metric to go stale. `ConditionReveal` therefore already
/// knows how to phrase these, which is what US-121 leans on to draw a `?` slot's hints exactly the
/// way the Dex draws an evolution's.
///
/// ALL conditions must hold, like an edge's — an empty list is a slot with no gate at all, which the
/// US-117 validator is free to have an opinion about but this type does not.
struct DigitamaSlot: Codable, Equatable {
    /// A roster id at `Stage.digitama`. Checked by the US-117 validator, not here — an id that
    /// names nothing has to be a reported finding rather than a decode failure, for the reason
    /// `EvolutionCondition.metric` is a `String`.
    let digitamaId: String

    let conditions: [EvolutionCondition]

    init(digitamaId: String, conditions: [EvolutionCondition] = []) {
        self.digitamaId = digitamaId
        self.conditions = conditions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            digitamaId: try container.decode(String.self, forKey: .digitamaId),
            conditions: try container.decodeIfPresent(
                [EvolutionCondition].self, forKey: .conditions) ?? []
        )
    }
}

/// One of the sixteen places a Digimon can adventure in (US-116).
///
/// A map is a **place your steps go**, not a backdrop: `totalSteps` is how far it is across,
/// `opponentPool` is what lives there, and `digitamaSlots` is what can be found there. The art is
/// only `assetName`.
///
/// Shipped as data in `maps.json` for the same reason `evolutions.json` and `roster.json` are —
/// retuning a map's length or its opponents is a data edit, and nothing in this type has to be
/// recompiled to do it.
struct AdventureMap: Codable, Equatable, Identifiable {
    /// Stable key, persisted as the player's selected map and as the key of their per-map progress
    /// (US-118, US-123). It is the asset name today, and it is a SEPARATE field from `assetName`
    /// anyway: art can be renamed or replaced, and a save that keyed progress off the filename
    /// would silently lose it when that happened.
    let id: String

    /// What the map is called on screen. Kept short — the US-120 strip puts it on one line beside
    /// a progress figure on a 41mm watch.
    let displayName: String

    /// The imageset in `Resources/Assets.xcassets`, drawn by `MapBackgroundView` behind the sprite
    /// slot. Verified to resolve by `MapCatalogTests` and by the US-117 validator.
    let assetName: String

    /// 1–5, rising with the map's opponent band: tier 1 is Baby II–Child, tier 5 is Ultimate.
    /// US-122 uses it to clamp the band its progress ratio selects.
    let tier: Int

    /// How many steps cross this map. `MapProgress.recorded >= totalSteps` is what "finished"
    /// means (US-118) — and the counter keeps climbing past it, so this is a finish line rather
    /// than a cap.
    let totalSteps: Int

    /// The map that must be finished first, or nil for the one map that is open from the start.
    /// The shipped file forms a single linear chain; the US-117 validator rejects an id that names
    /// no map and any cycle.
    let unlockedBy: String?

    /// Roster ids of the Digimon that can be fought here, across the map's whole stage band.
    /// US-122 picks from this rather than from the whole roster, banding by progress.
    let opponentPool: [String]

    /// The eggs this map can drop, each with its own conditions (US-128). Every Digitama on disk
    /// appears in exactly one map's slots.
    let digitamaSlots: [DigitamaSlot]

    init(
        id: String,
        displayName: String,
        assetName: String,
        tier: Int,
        totalSteps: Int,
        unlockedBy: String? = nil,
        opponentPool: [String] = [],
        digitamaSlots: [DigitamaSlot] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.assetName = assetName
        self.tier = tier
        self.totalSteps = totalSteps
        self.unlockedBy = unlockedBy
        self.opponentPool = opponentPool
        self.digitamaSlots = digitamaSlots
    }

    // Hand-written for the same reason `RosterEntry`'s is: the fields that say nothing when absent
    // are omitted from the file (`unlockedBy` on the first map, and an empty pool or slot list),
    // and synthesized Codable would reject the omission. Everything that MUST be authored —
    // `id`, `displayName`, `assetName`, `tier`, `totalSteps` — is a strict `decode`, so a map with
    // no length or no art fails the load loudly instead of shipping as a 0-step map with a blank
    // room.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            assetName: try container.decode(String.self, forKey: .assetName),
            tier: try container.decode(Int.self, forKey: .tier),
            totalSteps: try container.decode(Int.self, forKey: .totalSteps),
            unlockedBy: try container.decodeIfPresent(String.self, forKey: .unlockedBy),
            opponentPool: try container.decodeIfPresent([String].self, forKey: .opponentPool) ?? [],
            digitamaSlots: try container.decodeIfPresent(
                [DigitamaSlot].self, forKey: .digitamaSlots) ?? []
        )
    }
}

/// The sixteen shipped maps, decoded from the bundled `maps.json`.
///
/// In the shape of `Roster` on purpose, down to the private id index and the fatalError-on-bad-data
/// `bundled`: these are the same kind of object — a shipped table the game reads and never writes.
struct MapCatalog: Codable, Equatable {
    /// Every map, in the order the file authors them, which is tier order and is the order the
    /// US-119 list draws. The unlock chain follows the same order.
    let maps: [AdventureMap]

    private let byId: [String: AdventureMap]

    private enum CodingKeys: String, CodingKey {
        case maps
    }

    init(maps: [AdventureMap]) {
        self.maps = maps
        self.byId = Dictionary(maps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(maps: try container.decode([AdventureMap].self, forKey: .maps))
    }

    /// The map with this id, or nil if the catalog has none.
    func map(id: String) -> AdventureMap? {
        byId[id]
    }

    /// The one map that is unlocked from the start — the first with no `unlockedBy`.
    ///
    /// Not `maps.first`: file order is a convenience, and the map that is open from the start is
    /// the one the unlock chain says is, which is what US-120 shows as its prompt on a save that
    /// has never chosen anywhere to go.
    var startingMap: AdventureMap? {
        maps.first { $0.unlockedBy == nil }
    }

    /// Every map at a tier, in catalog order.
    func maps(atTier tier: Int) -> [AdventureMap] {
        maps.filter { $0.tier == tier }
    }
}

extension MapCatalog {
    /// Basename of the bundled catalog file.
    static let resourceName = "maps"

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case fileNotBundled

        var description: String {
            switch self {
            case .fileNotBundled:
                return "\(MapCatalog.resourceName).json is not in the bundle"
            }
        }
    }

    /// Decodes the catalog from a bundle. Injectable for tests; the app uses `bundled`.
    static func load(from bundle: Bundle = .main) throws -> MapCatalog {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw LoadError.fileNotBundled
        }
        return try JSONDecoder().decode(MapCatalog.self, from: try Data(contentsOf: url))
    }

    /// The shipped catalog, decoded once on first use.
    ///
    /// Traps like `Roster.bundled` and `EvolutionGraph.bundled`, for the same reason: an undecodable
    /// shipped file is a broken build, not a runtime condition. Degrading to an empty catalog would
    /// present as "there are no maps", which looks like a design decision rather than a crash.
    static let bundled: MapCatalog = {
        do {
            return try load()
        } catch {
            fatalError("Could not load the map catalog: \(error)")
        }
    }()
}
