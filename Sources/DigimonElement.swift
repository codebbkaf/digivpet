import Foundation

/// The two axes a Digimon is typed on (D-2), and the counter relations between them.
///
/// PURE Foundation — nothing here draws. The SwiftUI colours live in `ElementColors.swift`, the
/// pattern `MoveTint` uses: the type stays testable without a renderer, and the renderer that
/// first needs a colour is the one that owns the mapping.
///
/// Both enums are `String`-backed so `elements.json` (US-087) can author them by name and an
/// unknown value is a DECODE failure at load rather than a silent mis-typing at battle time.
/// See `docs/elements.md` for the full chart and why `neutral` is inert.

/// This app's headline type axis — an invention, not canon. Canon supplies flavour (Agumon
/// breathes fire, so it is `fire`), never rules.
enum DigimonElement: String, Codable, CaseIterable {
    case fire, water, plant, electric, ice, wind, earth, steel, light, dark, machine, neutral

    /// The elements this one is strong against — D-2's table, verbatim.
    ///
    /// The single source of truth for the chart: "weak to" is never authored, it is this relation
    /// read backwards, so the two halves cannot drift apart. `light` and `dark` beating each other
    /// is deliberate — a mutual advantage multiplies out to nothing (US-092's arithmetic), which is
    /// how eternal rivals are expressed in a ratio engine. `neutral` beats nothing because it is
    /// the fallback for an unauthored Digimon, and a fallback must never hand out an advantage.
    var beats: Set<DigimonElement> {
        switch self {
        case .fire: return [.plant, .ice, .steel]
        case .water: return [.fire, .earth, .machine]
        case .plant: return [.water, .earth]
        case .electric: return [.water, .machine, .steel]
        case .ice: return [.plant, .wind]
        case .wind: return [.earth, .plant]
        case .earth: return [.fire, .electric]
        case .steel: return [.ice, .plant]
        case .light: return [.dark]
        case .dark: return [.light]
        case .machine: return [.plant, .ice]
        case .neutral: return []
        }
    }

    /// How this element fares against `other`.
    ///
    /// Advantage wins the tie: with light vs dark BOTH sides report `.advantage`, because this type
    /// answers "am I strong here?", not "who wins?". Cancelling the two out is the caller's
    /// arithmetic (D-2), not this type's job.
    func effectiveness(against other: DigimonElement) -> Effectiveness {
        if beats.contains(other) { return .advantage }
        if other.beats.contains(self) { return .disadvantage }
        return .even
    }

    /// Full name, for the Dex detail row.
    var displayName: String {
        switch self {
        case .fire: return "Fire"
        case .water: return "Water"
        case .plant: return "Plant"
        case .electric: return "Electric"
        case .ice: return "Ice"
        case .wind: return "Wind"
        case .earth: return "Earth"
        case .steel: return "Steel"
        case .light: return "Light"
        case .dark: return "Dark"
        case .machine: return "Machine"
        case .neutral: return "Neutral"
        }
    }

    /// The badge caption — at most five characters, because a badge shares a 42mm row with a second
    /// badge and the two must both fit without truncating. Uppercase, like the energy bars' short
    /// names (US-085).
    var badgeText: String {
        switch self {
        case .fire: return "FIRE"
        case .water: return "WATER"
        case .plant: return "PLANT"
        case .electric: return "ELEC"
        case .ice: return "ICE"
        case .wind: return "WIND"
        case .earth: return "EARTH"
        case .steel: return "STEEL"
        case .light: return "LIGHT"
        case .dark: return "DARK"
        case .machine: return "MECH"
        case .neutral: return "NEUT"
        }
    }

    /// SF Symbol drawn beside the badge text. Validity is a test's job — an unknown name renders as
    /// a blank square, which no compile can catch.
    var symbolName: String {
        switch self {
        case .fire: return "flame.fill"
        case .water: return "drop.fill"
        case .plant: return "leaf.fill"
        case .electric: return "bolt.fill"
        case .ice: return "snowflake"
        case .wind: return "wind"
        case .earth: return "mountain.2.fill"
        case .steel: return "shield.fill"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .machine: return "gearshape.fill"
        case .neutral: return "circle.fill"
        }
    }
}

/// The canon axis: a small triangle, and much weaker than the element axis by design.
enum DigimonAttribute: String, Codable, CaseIterable {
    case vaccine, data, virus, free

    /// The triangle vaccine → virus → data → vaccine. `free` is inert for the same reason
    /// `DigimonElement.neutral` is: it is what an unauthored Digimon falls back to.
    var beats: Set<DigimonAttribute> {
        switch self {
        case .vaccine: return [.virus]
        case .virus: return [.data]
        case .data: return [.vaccine]
        case .free: return []
        }
    }

    /// How this attribute fares against `other`. Same shape as the element axis, deliberately — a
    /// caller resolving a matchup uses one idiom for both.
    func effectiveness(against other: DigimonAttribute) -> Effectiveness {
        if beats.contains(other) { return .advantage }
        if other.beats.contains(self) { return .disadvantage }
        return .even
    }

    var displayName: String {
        switch self {
        case .vaccine: return "Vaccine"
        case .data: return "Data"
        case .virus: return "Virus"
        case .free: return "Free"
        }
    }

    /// At most five characters — see `DigimonElement.badgeText`.
    var badgeText: String {
        switch self {
        case .vaccine: return "VAC"
        case .data: return "DATA"
        case .virus: return "VIRUS"
        case .free: return "FREE"
        }
    }

    var symbolName: String {
        switch self {
        case .vaccine: return "cross.case.fill"
        case .data: return "cube.fill"
        case .virus: return "ladybug.fill"
        case .free: return "circle.dashed"
        }
    }
}

/// Which side of a matchup a type is on. Three cases, not a multiplier: the numbers belong to
/// `BattleModifiers` (D-4), so the chart can be re-tuned without touching the vocabulary.
enum Effectiveness: String, Codable, CaseIterable {
    case advantage, disadvantage, even
}
