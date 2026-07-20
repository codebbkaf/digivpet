import Foundation

/// What the Digimon is doing, as one held frame the complication can draw.
///
/// A decided pose rather than the raw inputs (`HealthStatus`, `isAsleep`, `poopCount`) for the same
/// reason the dominant type arrives already chosen: `HealthStatus` lives in `GameState`, which is
/// SwiftData, which the widget process must not link. The app decides, the widget draws.
///
/// A pose, not a `SpriteAnimation`: `SpriteAnimation` lives in `DigimonSpriteView.swift`, which the
/// widget extension does not compile (it is a whole SwiftUI view built on the app's frame timer). The
/// two-frame idle cycle below is therefore restated here rather than shared — `ComplicationTests`
/// asserts the two definitions agree, so they cannot drift apart unnoticed.
enum ComplicationPose: String, Codable, CaseIterable {
    case idle
    case sleeping
    case sick
    case messy
    case dead

    /// The one sheet frame this pose holds.
    ///
    /// `sick` and `dead` take the two hurt frames rather than sharing one, because the AC asks for a
    /// distinct held frame per state and a complication has no caption to tell them apart.
    var frame: SpriteFrame {
        switch self {
        case .idle: return .walk1
        case .sleeping: return .sleep1
        case .sick: return .hurt1
        case .messy: return .angry
        case .dead: return .hurt2
        }
    }

    /// Whether this pose is a loop the timeline should step through, or one frame held still.
    ///
    /// Only `idle` moves. Sleeping, sick and dead are the states US-049 explicitly requires to hold
    /// — a Digimon that appears to walk while it is asleep or dead is worse than a still one, because
    /// the motion actively contradicts what the pose is trying to say. `messy` holds too, for a duller
    /// reason: its frame is `angry`, and the sheet has no second angry frame to alternate with.
    var animates: Bool { self == .idle }

    /// The frames this pose cycles through on a 48x64 stage sheet, in order.
    ///
    /// One element for every held pose, so a caller never has to branch on `animates` to draw.
    var stageFrames: [SpriteFrame] {
        switch self {
        case .idle: return [.walk1, .walk2]
        case .sleeping, .sick, .messy, .dead: return [frame]
        }
    }

    /// The same cycle on a 48x16 Digitama sheet, which only has the idle wobble.
    ///
    /// Empty for every other pose, exactly as `SpriteAnimation.eggFrames` is: an egg's index 2 is the
    /// hatch, so borrowing stage indices would draw the egg cracking open as part of standing still.
    /// An empty result sends the caller to the idle art, which is what a sleeping egg already drew.
    var eggFrames: [EggFrame] {
        switch self {
        case .idle: return [.idle, .wobble]
        case .sleeping, .sick, .messy, .dead: return []
        }
    }

    /// How VoiceOver says this pose, or nil for `idle` — which is the absence of news, not news.
    ///
    /// Without this the pose is the one thing on the complication a VoiceOver user cannot get at:
    /// it is carried entirely by which pixels are drawn, and the sprite is `Image(decorative:)`.
    var spokenDescription: String? {
        switch self {
        case .idle: return nil
        case .sleeping: return "asleep"
        case .sick: return "sick"
        case .messy: return "needs cleaning"
        case .dead: return "has died"
        }
    }

    /// The total mapping from every state that can change the pose, in precedence order.
    ///
    /// Death, sickness and sleep rank in that order because `MainScreenModel.restingAnimation`
    /// already ranks them that way on the main screen, and two screens disagreeing about what a sick
    /// sleeping Digimon is doing would be a bug in one of them.
    ///
    /// The mess ranks LAST of the non-idle poses, below sleep. It is the least severe of the four —
    /// nothing about the Digimon itself — and it is the only one that already has its own way of
    /// reaching the user's wrist (US-054 notifies when the screen fills). Sickness and death have no
    /// such notice, so the glance is the only thing that carries them.
    static func pose(isDead: Bool, isSick: Bool, isAsleep: Bool, hasPoop: Bool) -> ComplicationPose {
        if isDead { return .dead }
        if isSick { return .sick }
        if isAsleep { return .sleeping }
        if hasPoop { return .messy }
        return .idle
    }
}

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

    /// What the Digimon is doing, already decided by the app. See `ComplicationPose`.
    var pose: ComplicationPose = .idle

    /// How many poops are on screen, 0...`PoopClock.maximumPoops`.
    ///
    /// Carried as a NUMBER even though nothing on the complication draws a pile, because `pose`
    /// cannot answer the question the Clean button asks. The pose ranks the mess below death,
    /// sickness and sleep (see `ComplicationPose.pose`), so a sick Digimon standing in four poops
    /// poses `.sick` — and a button keyed off `.messy` would vanish exactly when there was most to
    /// clean. This says only whether there is a mess, which is the whole of the button's rule.
    var poopCount: Int = 0

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

    /// The Digimon and what it is doing, spoken. Just the name when it is doing nothing notable.
    var accessibilityLabel: String {
        guard let pose = pose.spokenDescription else { return displayName }
        return "\(displayName), \(pose)"
    }

    /// Whether the face should offer the Clean button. There is nothing to clean at zero, and a
    /// button that did nothing would be worse than no button on a screen this small.
    var needsCleaning: Bool { poopCount > 0 }

    /// This snapshot as it will look once the app has applied a Clean tapped on the face.
    ///
    /// Drawn optimistically rather than waiting for the app to wake — see `ComplicationCleanRequest`
    /// — so this has to answer "what pose replaces `.messy`" without re-deriving anything. It does
    /// not have to guess: `.messy` is ranked BELOW death, sickness and sleep, so a snapshot posing
    /// `.messy` is one in which none of those is true, and taking the mess away can only leave
    /// `.idle`. Any other pose is about the Digimon itself and cleaning does not touch it.
    func cleaned() -> ComplicationSnapshot {
        var copy = self
        copy.poopCount = 0
        if copy.pose == .messy { copy.pose = .idle }
        return copy
    }

    /// Hand-written only so `pose` can be MISSING from the file.
    ///
    /// The synthesised decoder requires every non-optional key, so on the launch that first installs
    /// this version the snapshot already on disk — written before `pose` existed — would fail to
    /// decode outright and the complication would drop to the Agumon placeholder until the next
    /// refresh republished it. Defaulting the one new key costs eight lines and nobody sees the gap.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        spriteStage = try container.decode(String.self, forKey: .spriteStage)
        spriteFile = try container.decode(String.self, forKey: .spriteFile)
        dominantEnergySymbol = try container.decodeIfPresent(String.self, forKey: .dominantEnergySymbol)
        dominantEnergyName = try container.decodeIfPresent(String.self, forKey: .dominantEnergyName)
        dominantEnergyFraction = try container.decode(Double.self, forKey: .dominantEnergyFraction)
        dominantEnergyEarned = try container.decode(Int.self, forKey: .dominantEnergyEarned)
        pose = try container.decodeIfPresent(ComplicationPose.self, forKey: .pose) ?? .idle
        // Defaulted for the same reason `pose` is: a snapshot written by the previous version has
        // no such key, and requiring it would drop the face to the Agumon placeholder for one
        // refresh. Zero is also the safe default — it hides the Clean button rather than offering
        // one with nothing behind it.
        poopCount = try container.decodeIfPresent(Int.self, forKey: .poopCount) ?? 0
        published = try container.decode(Date.self, forKey: .published)
    }

    /// Restored because writing `init(from:)` suppresses the memberwise initialiser.
    init(
        displayName: String,
        spriteStage: String,
        spriteFile: String,
        dominantEnergySymbol: String?,
        dominantEnergyName: String?,
        dominantEnergyFraction: Double,
        dominantEnergyEarned: Int,
        pose: ComplicationPose = .idle,
        poopCount: Int = 0,
        published: Date
    ) {
        self.displayName = displayName
        self.spriteStage = spriteStage
        self.spriteFile = spriteFile
        self.dominantEnergySymbol = dominantEnergySymbol
        self.dominantEnergyName = dominantEnergyName
        self.dominantEnergyFraction = dominantEnergyFraction
        self.dominantEnergyEarned = dominantEnergyEarned
        self.pose = pose
        self.poopCount = poopCount
        self.published = published
    }
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
