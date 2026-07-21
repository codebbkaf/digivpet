import Foundation
import SwiftData

/// Something the store was asked to do that it cannot.
enum GameStoreError: Error, Equatable {
    /// `activate(_:)` was handed a `GameState` this store does not hold — one belonging to a
    /// different store, or one never inserted into a context. Refused rather than adopted, because
    /// activating a record the store cannot see would freeze the player's real Digimon and leave
    /// nothing active in its place.
    case stateNotInStore
}

/// Owns the SwiftData stack and the player's saved `GameState` records.
///
/// Since US-124 the store may hold SEVERAL Digimon, of which exactly one is ACTIVE — the one the
/// player has out — and the rest are frozen in the box. That invariant belongs here rather than on
/// `GameState`, because it is a fact about the whole store: `activate(_:)` is the only way to move
/// it, and it moves both records in one saved transaction so a crash cannot land between them.
///
/// `loadOrCreate` is still the only way in, and it is what makes a first launch and a return launch
/// the same code path; `savedState()` still means "the Digimon on screen", which is now the active
/// record rather than the only one.
@MainActor
final class GameStore {
    /// Every model that gets persisted. Adding a `@Model` type means adding it here too, or it
    /// silently will not be saved.
    static let schema = Schema([GameState.self, EnergyLedger.self, MetricLedger.self, DexEntry.self,
                                PlayerProfile.self,
                                // Drained by `loadOrCreateProfile` and written by nothing. Listed
                                // so a store from before US-123 can still be READ — see
                                // `MapProgress`.
                                MapProgress.self])

    let container: ModelContainer

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// - Parameter url: the store file. Defaults to `defaultStoreURL`; tests pass a temp file so
    ///   each one gets a clean store.
    convenience init(url: URL? = nil) throws {
        let configuration = ModelConfiguration(schema: Self.schema, url: url ?? Self.defaultStoreURL())
        self.init(container: try ModelContainer(for: Self.schema, configurations: configuration))
    }

    /// Where the saved game lives: Application Support inside the APP's OWN container.
    ///
    /// Spelled out rather than left to SwiftData's default, because that default is not stable.
    /// `NSPersistentContainer.defaultDirectoryURL()` moves the store into the app group container as
    /// soon as the app has an app-groups entitlement — which US-034 added for the complication — so
    /// a build that gained a complication would silently stop finding the game it had already saved
    /// and hand the user a fresh egg. Observed: the test host's store jumped to
    /// `Shared/AppGroup/.../default.store` the moment the entitlement landed.
    ///
    /// The complication reads a published `ComplicationSnapshot` from the group container, never
    /// this — the widget must not open a second store on it (see `ComplicationSnapshot`), so nothing
    /// wants the store shared.
    static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        let directory = URL.applicationSupportDirectory
        // CoreData would create this itself; doing it here keeps the failure at the store's own
        // door rather than inside SwiftData, where it reads as a corrupt-store error.
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // The name SwiftData itself uses, so an install that saved under the old default opens the
        // same file rather than starting over.
        return directory.appendingPathComponent("default.store")
    }

    /// The active saved game, starting a new one at `digitamaId` if the box is empty.
    func loadOrCreate(digitamaId: String, now: Date = Date()) throws -> GameState {
        if let saved = try activeState() { return saved }
        // Digimon in the box but none of them active is a state nothing here can produce —
        // `activate` moves both records in one transaction and a fresh record is born active — but
        // it is worth recovering from rather than falling through, because `resetGame` below would
        // DELETE Digimon the player still owns. Adopting the oldest is the one answer that loses
        // nothing.
        if let stranded = try allStates().first {
            try activate(stranded, now: now)
            return stranded
        }
        return try resetGame(digitamaId: digitamaId, now: now)
    }

    /// The Digimon the player has out, or nil if there is none — WITHOUT starting one.
    ///
    /// For the read-only screens. The Dex reads the player's totals to warm up its evolution hints
    /// (US-066), and it must not be the thing that hatches a game: opening a side screen before
    /// ever tapping the egg would otherwise create and save a Digimon the player never chose.
    ///
    /// Since US-124 this is the ACTIVE record rather than "the only one". Every existing caller
    /// wanted the Digimon on screen, which is what it still returns.
    func savedState() throws -> GameState? {
        try activeState()
    }

    /// Every saved Digimon, active and frozen alike, oldest first.
    ///
    /// Sorted by birth so the box has a stable order that does not depend on what SwiftData hands
    /// back — US-126's party list reads this, and a list that reshuffles between launches is a bug
    /// the player would see.
    func allStates() throws -> [GameState] {
        try context.fetch(FetchDescriptor<GameState>(sortBy: [SortDescriptor(\.birthDate)]))
    }

    /// The Digimon the player has out, or nil if the box is empty.
    func activeState() throws -> GameState? {
        try allStates().first(where: \.isActive)
    }

    /// Puts `state` out and freezes whichever Digimon was out before, in ONE saved transaction.
    ///
    /// Both flips happen against the context before a single `save()`, so the store on disk goes
    /// straight from "A is out" to "B is out": there is no moment at which it holds zero active or
    /// two. Every record is written rather than just the two involved, so a store that had somehow
    /// drifted into two active comes back correct instead of staying broken.
    ///
    /// A `state` this store does not hold is refused BEFORE anything is mutated, and a `save` that
    /// fails puts every flag back the way it was — so a failed activate leaves the box exactly as
    /// it stood, which is the other half of "can never leave zero active or two".
    ///
    /// Activating the Digimon already out is a no-op that still saves. Cheap, and it means a party
    /// screen does not have to special-case the row the player is already on.
    ///
    /// SINCE US-125 THIS IS ALSO WHERE THE FREEZE CLOCK MOVES, and it belongs in the same
    /// transaction for exactly the reason the flags do: `frozenSince` and `isActive` are two halves
    /// of one fact, and a store that saved one without the other would either measure a spell that
    /// never happened or lose one that did. `now` is a parameter for the same reason it is one
    /// everywhere else — a test must be able to freeze a Digimon for thirty days without waiting.
    ///
    /// - Parameter now: the instant of the switch. The thaw shifts the newly active Digimon's whole
    ///   timeline forward by the span between its freeze and this.
    func activate(_ state: GameState, now: Date = Date()) throws {
        let states = try allStates()
        guard states.contains(where: { $0.persistentModelID == state.persistentModelID }) else {
            throw GameStoreError.stateNotInStore
        }
        let wasActive = Set(states.filter(\.isActive).map(\.persistentModelID))

        // Paired with the record it was taken from, so a failed save can be undone precisely — the
        // ones that did nothing (already frozen, already out) are absent rather than undone as
        // no-ops.
        var changes: [(GameState, FreezeChange)] = []
        for record in states {
            let isTarget = record.persistentModelID == state.persistentModelID
            record.isActive = isTarget
            let change = isTarget ? record.thaw(at: now) : record.freeze(at: now)
            if let change { changes.append((record, change)) }
        }
        do {
            try context.save()
        } catch {
            for (record, change) in changes {
                record.undo(change)
            }
            for record in states {
                record.isActive = wasActive.contains(record.persistentModelID)
            }
            throw error
        }
    }

    /// Throws away the saved game and starts over at a fresh Digitama.
    ///
    /// This is a total wipe — lifetime energy, the battle record and the care history all go.
    /// Rebirth after death is `rebirth(digitamaId:now:)` and not this: it wraps this to get the
    /// fresh egg, but carries `lifetimeEnergy` across, which is the whole point of it outliving a
    /// Digimon.
    ///
    /// Since US-123 the lifetime total lives on `PlayerProfile`, so wiping it is an explicit line
    /// here rather than a consequence of deleting the `GameState`. Map progress is NOT wiped: it
    /// outlives the Digimon that walked it, which is why it moved off the state in the first place.
    ///
    /// Since US-124 the box may hold several Digimon, and a total wipe means all of them: the
    /// delete below is unqualified on purpose. The fresh egg is born active, so the store comes out
    /// of this holding exactly one record and that record is out.
    @discardableResult
    func resetGame(digitamaId: String, now: Date = Date()) throws -> GameState {
        // Before the delete, or the migration inside it would have no Digimon left to read the
        // legacy lifetime total off — a reset on a store that has never opened a profile would
        // silently start the player's history over.
        let profile = try loadOrCreateProfile()
        try context.delete(model: GameState.self)
        let fresh = GameState(currentDigimonId: digitamaId, now: now)
        context.insert(fresh)
        profile.lifetimeEnergy = .zero
        // The egg you are handed is itself a discovered Digimon, and one the player now owns.
        // Recorded here rather than at the call site so a new game, its first Dex entry and the
        // profile's note of the egg are one transaction; both survive the `delete` above because
        // they are separate entities.
        recordDiscovery(id: digitamaId, now: now)
        profile.record(ownedDigitama: digitamaId)
        try context.save()
        return fresh
    }

    /// Starts the next Digimon after this one has died, carrying over what outlives it.
    ///
    /// The difference from `resetGame` is the whole point of US-029: the lifetime energy is read
    /// BEFORE the wipe and put back after it, so a death costs the user its Digimon and not its
    /// progress. Since US-123 it is read off `PlayerProfile` rather than off the corpse — which is
    /// what makes the same rule work for US-124's box of several Digimon, where there is no single
    /// corpse to read. The Dex needs no carrying — it is a separate entity, so the `delete` inside
    /// `resetGame` never touches it — and neither does the `EnergyLedger`, which must keep today's
    /// cap so the steps already spent on the dead Digimon cannot be earned twice.
    @discardableResult
    func rebirth(digitamaId: String, now: Date = Date()) throws -> GameState {
        let profile = try loadOrCreateProfile()
        let carried = profile.lifetimeEnergy
        let fresh = try resetGame(digitamaId: digitamaId, now: now)
        profile.lifetimeEnergy = carried
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

    /// The per-metric credit ledger, starting a fresh one at today if there is none yet.
    ///
    /// Untouched by `resetGame` for the same reason `loadOrCreateLedger` is: a rebirth must not
    /// re-bank today's steps for the new Digimon. See `MetricLedger`.
    func loadOrCreateMetricLedger(now: Date = Date(), calendar: Calendar = .current) throws -> MetricLedger {
        if let saved = try context.fetch(FetchDescriptor<MetricLedger>()).first {
            return saved
        }
        let fresh = MetricLedger(day: calendar.startOfDay(for: now))
        context.insert(fresh)
        try context.save()
        return fresh
    }

    /// The player's profile, MIGRATING an older save onto a fresh one if there is none yet.
    ///
    /// The only way in, exactly like `loadOrCreate`, so there is one place that can decide a profile
    /// exists and one place the migration can run. Untouched by `resetGame` except for the lifetime
    /// total it explicitly wipes: the sixteen maps outlive the Digimon that walked them, so a death
    /// must not send the player back to the start of the grassland.
    ///
    /// THE MIGRATION, which runs exactly once — on the first open after this build lands, because
    /// after it there is a profile and the fetch above returns:
    /// - `lifetimeEnergy` is copied off the saved `GameState`'s legacy column. A store written by
    ///   the previous build has the player's whole earnings there and nowhere else.
    /// - the map fields are copied off the `MapProgress` record US-118 wrote, which is then deleted:
    ///   two records answering "where am I adventuring" is one too many, and the one that loses is
    ///   the one nothing writes.
    /// - `ownedDigitamaIds` is seeded from the Dex, which has recorded every egg the moment it was
    ///   handed over since US-016 — so "ever owned" is a fact the old save already knows, not a
    ///   guess. Filtered through the roster's stages rather than by the id's shape, because
    ///   `_digitama` is a naming convention and not a schema.
    ///
    /// - Parameter roster: injected only so a test can seed the Dex filter; the shipped file is the
    ///   default, as everywhere else.
    func loadOrCreateProfile(roster: Roster = .bundled) throws -> PlayerProfile {
        if let saved = try context.fetch(FetchDescriptor<PlayerProfile>()).first {
            return saved
        }
        let fresh = PlayerProfile()
        let states = try allStates()
        if let state = states.first {
            fresh.lifetimeEnergy = state.legacyLifetimeEnergy
        }
        // US-124: a store written before the box existed holds exactly ONE Digimon, and it is the
        // one the player is raising. Stamped explicitly so the record on disk says so, rather than
        // leaning on `isActive`'s nil-reads-as-active default for the rest of its life. Guarded on
        // the count because this is a migration and not a repair: if a later build ever calls this
        // on a store that already has a box, the record it happens to fetch first is not
        // necessarily the one that was out.
        if states.count == 1, let only = states.first {
            only.isActive = true
        }
        if let progress = try context.fetch(FetchDescriptor<MapProgress>()).first {
            fresh.adopt(progress)
        }
        for stale in try context.fetch(FetchDescriptor<MapProgress>()) {
            context.delete(stale)
        }
        for id in try dexIds() where roster.entry(id: id)?.stage == .digitama {
            fresh.record(ownedDigitama: id)
        }
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
