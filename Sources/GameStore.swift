import Foundation
import SwiftData

/// Owns the SwiftData stack and the single `GameState` record.
///
/// There is exactly one saved game, so this deliberately exposes "the" state rather than a
/// query: `loadOrCreate` is the only way in, and it is what makes a first launch and a return
/// launch the same code path.
@MainActor
final class GameStore {
    /// Every model that gets persisted. Adding a `@Model` type means adding it here too, or it
    /// silently will not be saved.
    static let schema = Schema([GameState.self, EnergyLedger.self, DexEntry.self])

    let container: ModelContainer

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// - Parameter url: the store file. Defaults to SwiftData's usual on-disk location for the
    ///   app; tests pass a temp file so each one gets a clean store.
    convenience init(url: URL? = nil) throws {
        let configuration = url.map { ModelConfiguration(schema: Self.schema, url: $0) }
            ?? ModelConfiguration(schema: Self.schema)
        self.init(container: try ModelContainer(for: Self.schema, configurations: configuration))
    }

    /// The saved game, starting a new one at `digitamaId` if there is none yet.
    func loadOrCreate(digitamaId: String, now: Date = Date()) throws -> GameState {
        if let saved = try context.fetch(FetchDescriptor<GameState>()).first {
            return saved
        }
        return try resetGame(digitamaId: digitamaId, now: now)
    }

    /// Throws away the saved game and starts over at a fresh Digitama.
    ///
    /// This is a total wipe — lifetime energy, the battle record and the care history all go.
    /// Rebirth after death (US-029) must NOT route through here: it has to preserve
    /// `lifetimeEnergy` and the Dex, which is the whole point of them outliving a Digimon.
    @discardableResult
    func resetGame(digitamaId: String, now: Date = Date()) throws -> GameState {
        try context.delete(model: GameState.self)
        let fresh = GameState(currentDigimonId: digitamaId, now: now)
        context.insert(fresh)
        // The egg you are handed is itself a discovered Digimon. Recorded here rather than at the
        // call site so a new game and its first Dex entry are one transaction; the Dex survives the
        // `delete` above because it is a separate entity.
        recordDiscovery(id: digitamaId, now: now)
        try context.save()
        return fresh
    }

    /// Records a Digimon in the Dex the first time it is discovered.
    ///
    /// Idempotent: a Digimon already in the Dex is not duplicated and its `firstDiscovered` date is
    /// kept. Does NOT save — the caller flushes, so a discovery and the game change that produced it
    /// (a hatch, an evolution) reach disk together or not at all. Returns whether a new entry was
    /// added.
    @discardableResult
    func recordDiscovery(id: String, now: Date = Date()) -> Bool {
        // The Dex is small — one entry per Digimon ever raised — so a scan is cheaper than a
        // predicate and avoids leaning on SwiftData's unique-constraint upsert semantics.
        let existing = (try? context.fetch(FetchDescriptor<DexEntry>())) ?? []
        guard !existing.contains(where: { $0.digimonId == id }) else { return false }
        context.insert(DexEntry(digimonId: id, firstDiscovered: now))
        return true
    }

    /// Every Digimon id in the Dex, in no particular order.
    func dexIds() throws -> [String] {
        try context.fetch(FetchDescriptor<DexEntry>()).map(\.digimonId)
    }

    /// Discovered id -> when it was first discovered, which is what the Dex screen puts on an
    /// entry. Keyed rather than returned as entries so a caller cannot mutate a `@Model` it was
    /// only meant to read. `recordDiscovery` keeps ids unique, so nothing is lost collapsing them.
    func dexDiscoveries() throws -> [String: Date] {
        let entries = try context.fetch(FetchDescriptor<DexEntry>())
        return Dictionary(entries.map { ($0.digimonId, $0.firstDiscovered) },
                          uniquingKeysWith: { earliest, other in min(earliest, other) })
    }

    /// The energy credit ledger, starting a fresh one at today if there is none yet.
    ///
    /// Note what `resetGame` does NOT do: it does not touch this. A rebirth must not refund the
    /// day's cap, or today's steps would buy energy a second time for the new Digimon. See
    /// `EnergyLedger`.
    func loadOrCreateLedger(now: Date = Date(), calendar: Calendar = .current) throws -> EnergyLedger {
        if let saved = try context.fetch(FetchDescriptor<EnergyLedger>()).first {
            return saved
        }
        let fresh = EnergyLedger(day: calendar.startOfDay(for: now))
        context.insert(fresh)
        try context.save()
        return fresh
    }

    /// Flushes pending changes to disk. Mutating a `GameState` or an `EnergyLedger` marks it
    /// dirty; nothing is durable until this runs.
    func save() throws {
        try context.save()
    }
}
