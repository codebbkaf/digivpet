import CoreGraphics
import XCTest

@testable import DigiVPet

/// US-187 — every Digimon has HP, Attack and Agility, shown on the Dex detail sheet as dash bars.
///
/// `ConsumptionConfigTests` owns the per-stage table and its ladder; this file owns the roster-wide
/// guarantee (every playable, non-dexOnly Digimon resolves all three stats, each > 0) and the
/// screen's rule — the stats for a discovered playable entry, nothing for an unmet, `dexOnly` or
/// egg one.
final class DexStatBarsTests: XCTestCase {
    private let roster = Roster.bundled
    private let config = ConsumptionConfig.bundled

    private func row(_ id: String, discovered: Bool) throws -> DexRow {
        let entry = try XCTUnwrap(roster.entry(id: id), "\(id) is not in the roster")
        return DexRow(entry: entry, firstDiscovered: discovered ? Date(timeIntervalSince1970: 0) : nil)
    }

    // MARK: - AC: every playable Digimon has all three stats, each > 0

    /// THE AC, stated over the WHOLE roster: every non-dexOnly Digimon that can fight (Baby I and
    /// up — an egg never battles) resolves HP, Attack and Agility off its stage, and each is
    /// strictly positive. A zero anywhere would draw an empty bar and lose a fight without a hit.
    func testEveryPlayableNonDexOnlyDigimonHasAllThreePositiveStats() {
        var battlers = 0
        for entry in roster.entries where !entry.dexOnly && entry.stage != .digitama {
            let stats = config.stats(for: entry)
            XCTAssertNotNil(stats, "\(entry.id) (\(entry.stage.rawValue)) resolves no battle stats")
            guard let stats else { continue }
            XCTAssertGreaterThan(stats.baseHP, 0, "\(entry.id) has non-positive HP")
            XCTAssertGreaterThan(stats.baseAttack, 0, "\(entry.id) has non-positive Attack")
            XCTAssertGreaterThan(stats.baseAgility, 0, "\(entry.id) has non-positive Agility")
            battlers += 1
        }
        // A guard on the guard: if a refactor ever made `stats(for:)` return nil for everyone the
        // loop above would pass vacuously, so pin that the roster really does carry a body of
        // battlers (868 playable today, minus the ~51 Digitama that do not fight).
        XCTAssertGreaterThan(battlers, 700, "the roster resolved almost no battlers — check the table")
    }

    /// A Digitama and a `dexOnly` entry are the two kinds that never fight, so both resolve to nil
    /// rather than to a bar of zeros. Stated over the whole roster so a new egg or idle-only sprite
    /// cannot slip a phantom stat block onto a Digimon that has no business fighting.
    func testEggsAndDexOnlyEntriesResolveNoStats() {
        for entry in roster.entries where entry.dexOnly || entry.stage == .digitama {
            XCTAssertNil(config.stats(for: entry),
                         "\(entry.id) (\(entry.stage.rawValue), dexOnly=\(entry.dexOnly)) has stats")
        }
    }

    // MARK: - AC: shown on the sheet for a discovered playable entry, hidden otherwise

    func testADiscoveredPlayableEntryShowsTheStatsTheConfigResolves() throws {
        let entry = try XCTUnwrap(roster.entry(id: "agumon"))
        let stats = try XCTUnwrap(DexStatBars.stats(for: row("agumon", discovered: true),
                                                    roster: roster, config: config))

        XCTAssertEqual(stats, config.stats(for: entry))
    }

    func testAnUndiscoveredEntryShowsNoStatBlock() throws {
        let unmet = try row("agumon", discovered: false)
        XCTAssertNil(DexStatBars.stats(for: unmet, roster: roster, config: config))
    }

    /// The rule stated over the whole roster: presence is EXACTLY "discovered AND a battler", in
    /// both directions, mirroring `DexMoveRowTests`' whole-roster presence check for the attack row.
    func testPresenceIsExactlyDiscoveryAndBattlerAcrossTheWholeRoster() {
        for entry in roster.entries {
            let met = DexRow(entry: entry, firstDiscovered: Date(timeIntervalSince1970: 0))
            let unmet = DexRow(entry: entry, firstDiscovered: nil)
            let isBattler = !entry.dexOnly && entry.stage != .digitama

            XCTAssertNil(DexStatBars.stats(for: unmet, roster: roster, config: config),
                         "\(entry.id) leaked its stats before it was ever met")
            if isBattler {
                XCTAssertNotNil(DexStatBars.stats(for: met, roster: roster, config: config),
                                "\(entry.id) was met and playable but showed no stat block")
            } else {
                XCTAssertNil(DexStatBars.stats(for: met, roster: roster, config: config),
                             "\(entry.id) is no battler but drew a stat block")
            }
        }
    }

    // MARK: - AC: three labelled bars, no numbers

    /// The block draws exactly three stats, each with a value, a distinct tint and a label — the
    /// "three labelled dash bars" the AC asks for. A bar's length is its value, so a value read
    /// through `BattleStat` is what the sheet renders.
    func testThreeStatsEachHaveAValueTintAndLabel() {
        let stats = StageStats(baseHP: 9, baseAttack: 7, baseAgility: 5, trainingCap: 8)
        let all = BattleStat.allCases

        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.map { $0.value(in: stats) }, [9, 7, 5])
        XCTAssertEqual(Set(all.map(\.symbol)).count, 3, "each stat needs its own glyph")
        XCTAssertEqual(Set(all.map(\.accessibilityName)),
                       ["Health", "Attack", "Agility"])
    }

    // MARK: - the block's height budget

    func testTheStatBlockFitsItsStatedBudget() {
        XCTAssertEqual(StatBarsLayout.budget,
                       3 * StatBarsLayout.barHeight + 2 * StatBarsLayout.rowSpacing)
        // The icon has to fit its bar's height so the row does not clip.
        XCTAssertLessThanOrEqual(StatBarsLayout.barHeight, StatBarsLayout.iconSize + 4)
    }
}
