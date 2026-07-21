import SwiftUI
import UIKit
import XCTest
@testable import DigiVPet

/// US-086. Pins D-2's counter chart and the two deliberate oddities in it (`neutral`/`free` inert,
/// light and dark beating each other) so a later re-tune cannot quietly remove them.
final class ElementTests: XCTestCase {

    /// Every element that is beaten by `element`, read backwards out of `beats`. The "weak to"
    /// column is never authored, so this is the only way to obtain it — which is the point.
    private func beatenBy(_ element: DigimonElement) -> Set<DigimonElement> {
        Set(DigimonElement.allCases.filter { $0.beats.contains(element) })
    }

    private let inertElements: Set<DigimonElement> = [.neutral]

    // MARK: - The vocabulary

    func testElementHasTheTwelveCasesFromD2() {
        XCTAssertEqual(DigimonElement.allCases.map(\.rawValue),
                       ["fire", "water", "plant", "electric", "ice", "wind",
                        "earth", "steel", "light", "dark", "machine", "neutral"])
    }

    func testAttributeHasTheFourCanonCases() {
        XCTAssertEqual(DigimonAttribute.allCases.map(\.rawValue),
                       ["vaccine", "data", "virus", "free"])
    }

    /// The raw values are the wire format of `elements.json` (US-087), so moving one silently
    /// re-types every Digimon authored under the old name.
    func testRawValuesRoundTripThroughCodable() throws {
        for element in DigimonElement.allCases {
            let data = try JSONEncoder().encode([element])
            XCTAssertEqual(String(data: data, encoding: .utf8), "[\"\(element.rawValue)\"]")
            XCTAssertEqual(try JSONDecoder().decode([DigimonElement].self, from: data), [element])
        }
        for attribute in DigimonAttribute.allCases {
            let data = try JSONEncoder().encode([attribute])
            XCTAssertEqual(try JSONDecoder().decode([DigimonAttribute].self, from: data), [attribute])
        }
    }

    func testAnUnknownNameIsADecodeFailureRatherThanASilentFallback() {
        let json = Data("[\"lightning\"]".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([DigimonElement].self, from: json))
        XCTAssertThrowsError(try JSONDecoder().decode([DigimonAttribute].self, from: Data("[\"vacine\"]".utf8)))
    }

    // MARK: - Presentation

    func testBadgeTextFitsFiveCharactersAndIsDistinct() {
        let badges = DigimonElement.allCases.map(\.badgeText) + DigimonAttribute.allCases.map(\.badgeText)
        for badge in badges {
            XCTAssertFalse(badge.isEmpty)
            XCTAssertLessThanOrEqual(badge.count, 5, "\(badge) would truncate on a 42mm badge row")
            XCTAssertTrue(badge.allSatisfy(\.isASCII), "\(badge) must render in the system font")
        }
        XCTAssertEqual(Set(badges).count, badges.count, "two types sharing a badge are unreadable")
    }

    func testDisplayNamesAreDistinctAndNonEmpty() {
        let names = DigimonElement.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.contains(where: \.isEmpty))
        let attributeNames = DigimonAttribute.allCases.map(\.displayName)
        XCTAssertEqual(Set(attributeNames).count, attributeNames.count)
        XCTAssertFalse(attributeNames.contains(where: \.isEmpty))
    }

    /// An unknown SF Symbol renders as a blank square — no compile or decode catches it, so it has
    /// to be caught here, against the real symbol table.
    func testEverySymbolNameIsARealSFSymbol() {
        for element in DigimonElement.allCases {
            XCTAssertNotNil(UIImage(systemName: element.symbolName),
                            "\(element.rawValue): '\(element.symbolName)' is not an SF Symbol")
        }
        for attribute in DigimonAttribute.allCases {
            XCTAssertNotNil(UIImage(systemName: attribute.symbolName),
                            "\(attribute.rawValue): '\(attribute.symbolName)' is not an SF Symbol")
        }
        // Guards the assertion itself: if UIImage(systemName:) started returning a placeholder for
        // everything, the loops above would pass while drawing nothing.
        XCTAssertNil(UIImage(systemName: "definitely.not.a.real.sf.symbol.zzz"))
    }

    /// The colour lives in a SwiftUI extension, not in the pure type. Exhaustive switches mean a
    /// new case cannot compile without one; this pins that they are also visually distinguishable.
    func testEveryTypeHasADistinctColour() {
        let elementColours = DigimonElement.allCases.map(\.color)
        XCTAssertEqual(Set(elementColours).count, DigimonElement.allCases.count)
        XCTAssertNotEqual(DigimonElement.steel.color, DigimonElement.neutral.color)
        let attributeColours = DigimonAttribute.allCases.map(\.color)
        XCTAssertEqual(Set(attributeColours).count, DigimonAttribute.allCases.count)
    }

    // MARK: - The chart

    func testBeatsMatchesD2Exactly() {
        XCTAssertEqual(DigimonElement.fire.beats, [.plant, .ice, .steel])
        XCTAssertEqual(DigimonElement.water.beats, [.fire, .earth, .machine])
        XCTAssertEqual(DigimonElement.plant.beats, [.water, .earth])
        XCTAssertEqual(DigimonElement.electric.beats, [.water, .machine, .steel])
        XCTAssertEqual(DigimonElement.ice.beats, [.plant, .wind])
        XCTAssertEqual(DigimonElement.wind.beats, [.earth, .plant])
        XCTAssertEqual(DigimonElement.earth.beats, [.fire, .electric])
        XCTAssertEqual(DigimonElement.steel.beats, [.ice, .plant])
        XCTAssertEqual(DigimonElement.light.beats, [.dark])
        XCTAssertEqual(DigimonElement.dark.beats, [.light])
        XCTAssertEqual(DigimonElement.machine.beats, [.plant, .ice])
        XCTAssertEqual(DigimonElement.neutral.beats, [])
    }

    /// D-2's "therefore weak to" column, which the code never authors — derived here so the two
    /// halves of the published table are proven to agree.
    func testWeakToColumnMatchesD2WhenReadBackwards() {
        XCTAssertEqual(beatenBy(.fire), [.water, .earth])
        XCTAssertEqual(beatenBy(.water), [.plant, .electric])
        XCTAssertEqual(beatenBy(.plant), [.fire, .ice, .wind, .steel, .machine])
        XCTAssertEqual(beatenBy(.electric), [.earth])
        XCTAssertEqual(beatenBy(.ice), [.fire, .steel, .machine])
        XCTAssertEqual(beatenBy(.wind), [.ice])
        XCTAssertEqual(beatenBy(.earth), [.water, .plant, .wind])
        XCTAssertEqual(beatenBy(.steel), [.fire, .electric])
        XCTAssertEqual(beatenBy(.light), [.dark])
        XCTAssertEqual(beatenBy(.dark), [.light])
        XCTAssertEqual(beatenBy(.machine), [.water, .electric])
        XCTAssertEqual(beatenBy(.neutral), [])
    }

    func testNoElementBeatsItself() {
        for element in DigimonElement.allCases {
            XCTAssertFalse(element.beats.contains(element), "\(element.rawValue) beats itself")
            XCTAssertEqual(element.effectiveness(against: element), .even)
        }
    }

    func testNeutralNeitherBeatsNorIsBeatenByAnything() {
        XCTAssertTrue(DigimonElement.neutral.beats.isEmpty)
        XCTAssertTrue(beatenBy(.neutral).isEmpty)
        for element in DigimonElement.allCases {
            XCTAssertEqual(DigimonElement.neutral.effectiveness(against: element), .even,
                           "the unauthored fallback must never hand out an advantage")
            XCTAssertEqual(element.effectiveness(against: .neutral), .even)
        }
    }

    func testFreeNeitherBeatsNorIsBeatenByAnything() {
        XCTAssertTrue(DigimonAttribute.free.beats.isEmpty)
        for attribute in DigimonAttribute.allCases {
            XCTAssertFalse(attribute.beats.contains(.free))
            XCTAssertEqual(DigimonAttribute.free.effectiveness(against: attribute), .even)
            XCTAssertEqual(attribute.effectiveness(against: .free), .even)
        }
    }

    /// No element is strictly best or strictly worst: pick any typed Digimon and there is both a
    /// matchup it wins and one it loses.
    func testEveryNonInertElementBeatsOneAndIsBeatenByOne() {
        for element in DigimonElement.allCases where !inertElements.contains(element) {
            XCTAssertFalse(element.beats.isEmpty, "\(element.rawValue) is strictly worst")
            XCTAssertFalse(beatenBy(element).isEmpty, "\(element.rawValue) is strictly best")
        }
    }

    func testEffectivenessAgreesWithBeatsInBothDirections() {
        for attacker in DigimonElement.allCases {
            for defender in DigimonElement.allCases {
                let result = attacker.effectiveness(against: defender)
                if attacker.beats.contains(defender) {
                    XCTAssertEqual(result, .advantage, "\(attacker.rawValue) vs \(defender.rawValue)")
                } else if defender.beats.contains(attacker) {
                    XCTAssertEqual(result, .disadvantage, "\(attacker.rawValue) vs \(defender.rawValue)")
                } else {
                    XCTAssertEqual(result, .even, "\(attacker.rawValue) vs \(defender.rawValue)")
                }
            }
        }
    }

    /// The one asymmetry: light and dark are BOTH advantaged. Cancelling the pair out is US-092's
    /// arithmetic — this type answers "am I strong here?", not "who wins?".
    func testLightAndDarkBothReportAdvantage() {
        XCTAssertEqual(DigimonElement.light.effectiveness(against: .dark), .advantage)
        XCTAssertEqual(DigimonElement.dark.effectiveness(against: .light), .advantage)
    }

    /// Every other pairing IS reciprocal, so the mutual case above is provably the only one.
    func testLightVersusDarkIsTheOnlyMutualAdvantage() {
        var mutual: [String] = []
        for attacker in DigimonElement.allCases {
            for defender in DigimonElement.allCases where attacker != defender {
                if attacker.beats.contains(defender) && defender.beats.contains(attacker) {
                    mutual.append("\(attacker.rawValue)/\(defender.rawValue)")
                }
            }
        }
        XCTAssertEqual(Set(mutual), ["light/dark", "dark/light"])
    }

    // MARK: - The attribute triangle

    func testAttributeTriangleIsVaccineVirusData() {
        XCTAssertEqual(DigimonAttribute.vaccine.effectiveness(against: .virus), .advantage)
        XCTAssertEqual(DigimonAttribute.virus.effectiveness(against: .data), .advantage)
        XCTAssertEqual(DigimonAttribute.data.effectiveness(against: .vaccine), .advantage)
        XCTAssertEqual(DigimonAttribute.virus.effectiveness(against: .vaccine), .disadvantage)
        XCTAssertEqual(DigimonAttribute.data.effectiveness(against: .virus), .disadvantage)
        XCTAssertEqual(DigimonAttribute.vaccine.effectiveness(against: .data), .disadvantage)
    }

    func testNoAttributeBeatsItselfAndTheTriangleHasNoMutualPair() {
        for attribute in DigimonAttribute.allCases {
            XCTAssertFalse(attribute.beats.contains(attribute))
            XCTAssertEqual(attribute.effectiveness(against: attribute), .even)
            for other in DigimonAttribute.allCases where other != attribute {
                XCTAssertFalse(attribute.beats.contains(other) && other.beats.contains(attribute),
                               "a triangle cannot have a mutual pair")
            }
        }
    }
}
