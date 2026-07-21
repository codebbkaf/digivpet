import SwiftUI

/// The colours the two type axes are drawn in.
///
/// Kept OUT of `DigimonElement.swift` for the reason `MoveTint.color` is kept out of
/// `MoveCatalog`: the vocabulary is pure Foundation and draws nothing, so it stays testable and
/// decodable without SwiftUI. Both switches are exhaustive with no `default:` — adding an element
/// is a compile error here until it is given a colour, rather than silently drawing grey.
extension DigimonElement {
    var color: Color {
        switch self {
        case .fire: return .red
        case .water: return .blue
        case .plant: return .green
        case .electric: return .yellow
        case .ice: return .cyan
        case .wind: return .mint
        case .earth: return .brown
        case .steel: return .gray
        case .light: return .white
        case .dark: return .purple
        case .machine: return .indigo
        // Distinct from `.gray` so the inert fallback never reads as Steel at a glance.
        case .neutral: return .secondary
        }
    }
}

extension DigimonAttribute {
    var color: Color {
        switch self {
        case .vaccine: return .green
        case .data: return .blue
        case .virus: return .purple
        case .free: return .gray
        }
    }
}
