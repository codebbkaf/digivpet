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
    static let schema = Schema([GameState.self])

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
        try context.save()
        return fresh
    }

    /// Flushes pending changes to disk. Mutating a `GameState` marks it dirty; nothing is
    /// durable until this runs.
    func save() throws {
        try context.save()
    }
}
