import Foundation

/// The little the complication needs to draw itself, in a form that crosses a process boundary.
///
/// The widget extension is a SEPARATE PROCESS with its own container, so it cannot read the app's
/// SwiftData store, and it must not open a second `GameStore` on the same file — two stores mean two
/// in-memory `EnergyLedger`s crediting the same steps twice, which is the bug `GameSession` exists to
/// prevent. So the app, which already owns the one game, publishes this snapshot after every refresh
/// and the widget only ever READS it. Nothing here is derived on the widget side.
///
/// Deliberately free of `GameState`, `EnergyType` and the graph: those pull in SwiftData and the
/// whole evolution model, and a widget that decoded the graph would be re-deriving state the app has
/// already settled. The dominant type arrives as its glyph and its name, already chosen.
struct ComplicationSnapshot: Codable, Equatable {
    /// The Digimon's name, for the accessibility label and the rectangular family.
    var displayName: String
    /// Sprite subfolder, as `IdleSpriteCache` wants it.
    var spriteStage: String
    /// Sprite filename, as `IdleSpriteCache` wants it.
    var spriteFile: String

    /// The single glyph of the dominant energy type, or nil for a Digimon that has earned none yet
    /// — a fresh egg genuinely has no leaning, and picking one for it would invent a branch.
    var dominantEnergySymbol: String?
    /// The dominant type's `displayName`, spoken by VoiceOver where a glyph would not read well.
    var dominantEnergyName: String?
    /// How full the dominant type's bar is, 0...1. Zero when there is no dominant type.
    var dominantEnergyFraction: Double
    /// Points earned of the dominant type this stage, shown as a number beside the bar.
    var dominantEnergyEarned: Int

    /// When the app last published this. The widget shows what it is given without asking how old
    /// it is; this is here so a stale complication can be recognised in a screenshot or a log.
    var published: Date

    /// What the widget gallery and a first-ever launch draw, before any game has been published.
    ///
    /// A real bundled sprite rather than a blank: the gallery preview renders this, and an empty
    /// preview is indistinguishable from a broken one.
    static let placeholder = ComplicationSnapshot(
        displayName: "Agumon",
        spriteStage: "Child",
        spriteFile: "Agumon",
        dominantEnergySymbol: "力",
        dominantEnergyName: "Strength",
        dominantEnergyFraction: 0.5,
        dominantEnergyEarned: 25,
        published: .distantPast
    )
}

/// The app's own URL scheme, which is how a complication tap gets back to it.
///
/// Registered under `CFBundleURLTypes` in `project.yml`. Shared by both targets so the widget cannot
/// drift onto a scheme the app does not claim — an unclaimed scheme fails silently, opening nothing.
enum DigiVPetURL {
    static let scheme = "digivpet"

    /// Opens the app on whatever screen it was last on. There is one screen worth deep-linking to,
    /// so this carries no route.
    static let open = URL(string: "\(scheme)://open")
}

/// Where the snapshot lives: a JSON file in the app group container both processes can see.
///
/// A file rather than `UserDefaults` for no deep reason beyond being able to point a test at a temp
/// directory and read back exactly what was written.
enum ComplicationSnapshotStore {
    /// Must match the `com.apple.security.application-groups` entitlement on BOTH targets in
    /// `project.yml`. Without it on either side `containerURL` returns nil and the app publishes
    /// nowhere while the widget reads nothing — it builds and runs fine either way, so only looking
    /// at a real complication catches it.
    static let appGroup = "group.com.digivpet.DigiVPet"

    static let fileName = "complication-snapshot.json"

    /// The shared directory, or nil when the entitlement is missing or unsigned.
    static func sharedDirectory(
        for appGroup: String = appGroup,
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// Writes the snapshot. Returns whether it landed — a missing container is not fatal, it just
    /// means the complication keeps showing what it last saw.
    @discardableResult
    static func write(_ snapshot: ComplicationSnapshot, to directory: URL? = sharedDirectory()) -> Bool {
        guard let directory else { return false }
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        return (try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)) != nil
    }

    /// The last published snapshot, or nil if the app has never published one.
    static func read(from directory: URL? = sharedDirectory()) -> ComplicationSnapshot? {
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(fileName))
        else { return nil }
        return try? JSONDecoder().decode(ComplicationSnapshot.self, from: data)
    }
}
