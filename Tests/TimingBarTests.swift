import Foundation
import SwiftUI
import XCTest

@testable import DigiVPet

/// US-076 — the timing bar: where the marker is, and what stopping it there is worth.
///
/// Everything here is pure. No view is hosted and nothing waits a sweep — the sweep is arithmetic on
/// an elapsed time, which is exactly what "sweep speed and zone width are injectable so tests never
/// wait real time" has to buy.

// MARK: - AC4: the grade at each zone boundary

final class TimingBarGradeTests: XCTestCase {

    /// The zone used throughout: half the bar, so the edges land on 0.0625 (perfect), 0.125 (great)
    /// and 0.25 (the zone's lip) from the centre — all exactly representable, so a boundary can be
    /// asserted AT the line rather than a whisker either side of it.
    private let zone: CGFloat = 0.5

    private var edges: (perfect: CGFloat, great: CGFloat, zone: CGFloat) {
        TimingBarGame.bandEdges(zoneWidth: zone)
    }

    /// The three edges, by value. Asserted here so the boundary tests below are reading a pinned
    /// geometry rather than agreeing with whatever the code happens to compute.
    func testTheBandsAreAQuarterAndAHalfOfTheZone() {
        XCTAssertEqual(edges.zone, 0.25)
        XCTAssertEqual(edges.great, 0.125)
        XCTAssertEqual(edges.perfect, 0.0625)
        XCTAssertLessThan(edges.perfect, edges.great)
        XCTAssertLessThan(edges.great, edges.zone)
    }

    /// AC2's first half: dead centre is a perfect.
    func testTheCentreOfTheBarIsPerfect() {
        XCTAssertEqual(TimingBarGame.grade(at: 0.5, zoneWidth: zone), .perfect)
    }

    /// AC2's second half: outside the zone is a miss, on both sides and at both ends of the bar.
    func testAnythingOutsideTheZoneIsAMiss() {
        for position: CGFloat in [0, 0.05, 0.2, 0.24, 0.76, 0.8, 0.95, 1] {
            XCTAssertEqual(TimingBarGame.grade(at: position, zoneWidth: zone), .miss,
                           "\(position) should have missed")
        }
    }

    /// AC4 at the perfect edge: on the line is perfect, a hair past it is great. Asserted on BOTH
    /// sides of centre, since the bands are symmetric and a `position - 0.5` without the `abs` would
    /// pass on one side only.
    func testThePerfectEdgeIsInclusiveAndTurnsGreatJustPastIt() {
        for sign: CGFloat in [-1, 1] {
            let edge = 0.5 + sign * edges.perfect
            XCTAssertEqual(TimingBarGame.grade(at: edge, zoneWidth: zone), .perfect, "at \(edge)")
            XCTAssertEqual(TimingBarGame.grade(at: edge + sign * 0.001, zoneWidth: zone), .great,
                           "just past \(edge)")
        }
    }

    /// AC4 at the great edge: on the line is great, a hair past it is good.
    func testTheGreatEdgeIsInclusiveAndTurnsGoodJustPastIt() {
        for sign: CGFloat in [-1, 1] {
            let edge = 0.5 + sign * edges.great
            XCTAssertEqual(TimingBarGame.grade(at: edge, zoneWidth: zone), .great, "at \(edge)")
            XCTAssertEqual(TimingBarGame.grade(at: edge + sign * 0.001, zoneWidth: zone), .good,
                           "just past \(edge)")
        }
    }

    /// AC4 at the lip: the last point inside the zone still pays, and the first point outside it
    /// pays nothing. This is the boundary the whole game is about.
    func testTheZoneLipIsInclusiveAndMissesJustPastIt() {
        for sign: CGFloat in [-1, 1] {
            let edge = 0.5 + sign * edges.zone
            XCTAssertEqual(TimingBarGame.grade(at: edge, zoneWidth: zone), .good, "at \(edge)")
            XCTAssertEqual(TimingBarGame.grade(at: edge + sign * 0.001, zoneWidth: zone), .miss,
                           "just past \(edge)")
        }
    }

    /// The bands are ordered outward and never skip: sweeping the whole bar sees miss, good, great,
    /// perfect, great, good, miss and nothing else, in that order.
    func testGradesDegradeSymmetricallyOutwardFromTheCentre() {
        let sampled = stride(from: CGFloat(0), through: 1, by: 0.001)
            .map { TimingBarGame.grade(at: $0, zoneWidth: zone) }
        var runs: [TrainingResult] = []
        for grade in sampled where runs.last != grade { runs.append(grade) }

        XCTAssertEqual(runs, [.miss, .good, .great, .perfect, .great, .good, .miss])
    }

    /// AC3, from the zone's side: one stop, four widths, and the grade falls a rung with each
    /// narrowing until it misses. This is what makes `zoneWidth` a difficulty knob rather than
    /// decoration.
    func testANarrowerZoneIsStrictlyHarder() {
        let stop: CGFloat = 0.6

        XCTAssertEqual(TimingBarGame.grade(at: stop, zoneWidth: 1), .perfect)
        XCTAssertEqual(TimingBarGame.grade(at: stop, zoneWidth: 0.5), .great)
        XCTAssertEqual(TimingBarGame.grade(at: stop, zoneWidth: 0.25), .good)
        XCTAssertEqual(TimingBarGame.grade(at: stop, zoneWidth: 0.1), .miss)
    }

    /// An injected width outside 0...1 cannot make a zone wider than the bar, or an inverted one.
    func testAnAbsurdZoneWidthIsClamped() {
        XCTAssertEqual(TimingBarGame.bandEdges(zoneWidth: 4).zone, 0.5)
        XCTAssertEqual(TimingBarGame.grade(at: 0, zoneWidth: 4), .good)
        XCTAssertEqual(TimingBarGame.grade(at: 1, zoneWidth: 4), .good)

        XCTAssertEqual(TimingBarGame.bandEdges(zoneWidth: -1).zone, 0)
        XCTAssertEqual(TimingBarGame.grade(at: 0.4, zoneWidth: -1), .miss)
    }

    /// Every grade is reachable from some stop — a band that no position can land in would be a
    /// grade the game can never award.
    func testEveryGradeIsReachable() {
        let reached = Set(stride(from: CGFloat(0), through: 1, by: 0.001)
            .map { TimingBarGame.grade(at: $0, zoneWidth: zone) })

        XCTAssertEqual(reached, Set(TrainingResult.allCases))
    }
}

// MARK: - AC1 / AC3: the sweep

final class TimingBarSweepTests: XCTestCase {

    /// The marker starts at the left end, reaches the right end at the half period, and is back at
    /// the left at the end of the period — one bounce, not a wrap.
    func testTheMarkerBouncesBetweenTheEndsOfTheBar() {
        let sweep: TimeInterval = 4

        XCTAssertEqual(TimingBarGame.position(at: 0, sweepDuration: sweep), 0)
        XCTAssertEqual(TimingBarGame.position(at: 1, sweepDuration: sweep), 0.5)
        XCTAssertEqual(TimingBarGame.position(at: 2, sweepDuration: sweep), 1)
        XCTAssertEqual(TimingBarGame.position(at: 3, sweepDuration: sweep), 0.5)
        XCTAssertEqual(TimingBarGame.position(at: 4, sweepDuration: sweep), 0, accuracy: 1e-12)
    }

    /// It never leaves the bar, at any point of any sweep.
    func testTheMarkerNeverLeavesTheBar() {
        for step in 0...2000 {
            let position = TimingBarGame.position(at: TimeInterval(step) * 0.017, sweepDuration: 1.8)
            XCTAssertGreaterThanOrEqual(position, 0)
            XCTAssertLessThanOrEqual(position, 1)
        }
    }

    /// The sweep repeats: the same point of a later period is the same place on the bar.
    func testTheSweepRepeatsEveryPeriod() {
        for offset in stride(from: 0.0, to: 4.0, by: 0.25) {
            XCTAssertEqual(TimingBarGame.position(at: offset, sweepDuration: 4),
                           TimingBarGame.position(at: offset + 12, sweepDuration: 4),
                           accuracy: 1e-9, "\(offset) drifted across periods")
        }
    }

    /// AC3: sweep speed is what makes the game hard. The same wall-clock instant lands somewhere
    /// different — and grades differently — depending only on the injected speed.
    func testSweepSpeedIsWhatDecidesWhereAGivenInstantLands() {
        XCTAssertEqual(TimingBarGame.position(at: 1, sweepDuration: 4), 0.5)
        XCTAssertEqual(TimingBarGame.position(at: 1, sweepDuration: 2), 1)

        XCTAssertEqual(TimingBarGame.grade(stoppingAt: 1, sweepDuration: 4, zoneWidth: 0.5), .perfect)
        XCTAssertEqual(TimingBarGame.grade(stoppingAt: 1, sweepDuration: 2, zoneWidth: 0.5), .miss)
    }

    /// A degenerate sweep parks the marker dead centre rather than dividing by zero.
    func testANonPositiveSweepParksTheMarkerInTheMiddle() {
        XCTAssertEqual(TimingBarGame.position(at: 3, sweepDuration: 0), 0.5)
        XCTAssertEqual(TimingBarGame.position(at: 3, sweepDuration: -1), 0.5)
    }

    /// Time before the round began is the start of the round, not a position off the left end.
    func testNegativeElapsedTimeIsTheStartOfTheSweep() {
        XCTAssertEqual(TimingBarGame.position(at: -5, sweepDuration: 4), 0)
    }

    /// AC1 end to end, through the one call `tap()` makes: a tap at the moment the marker crosses
    /// the centre is a perfect, and one a quarter-period later is a miss — same round, same zone,
    /// only the timing different.
    func testWhenYouTapIsTheWholeGame() {
        let sweep: TimeInterval = 4
        let zone: CGFloat = 0.5

        XCTAssertEqual(TimingBarGame.grade(stoppingAt: 1, sweepDuration: sweep, zoneWidth: zone),
                       .perfect)
        XCTAssertEqual(TimingBarGame.grade(stoppingAt: 2, sweepDuration: sweep, zoneWidth: zone),
                       .miss)
        XCTAssertEqual(TimingBarGame.grade(stoppingAt: 0, sweepDuration: sweep, zoneWidth: zone),
                       .miss)
        XCTAssertEqual(TimingBarGame.grade(stoppingAt: 3, sweepDuration: sweep, zoneWidth: zone),
                       .perfect)
    }
}

// MARK: - The game as a minigame

@MainActor
final class TimingBarGameTests: XCTestCase {

    /// It is a `TrainingMinigame` in the way US-075 means: buildable knowing only the protocol.
    func testItConformsThroughTheProtocolAlone() {
        let game = makeGame(TimingBarGame.self) { _ in }

        XCTAssertEqual(type(of: game).title, "Timing Bar")
        XCTAssertFalse(game.zoneWidth.isZero, "a zone nothing can land in")
    }

    /// AC3: both knobs are settable at the call site, so a round can be driven in milliseconds
    /// without a second initialiser.
    func testSweepSpeedAndZoneWidthAreInjectable() {
        var game = makeGame(TimingBarGame.self) { _ in }
        XCTAssertEqual(game.sweepDuration, 1.8)
        XCTAssertEqual(game.zoneWidth, 0.25)

        game.sweepDuration = 0.01
        game.zoneWidth = 0.9
        game.resultDuration = 0.01
        game.roundTimeout = 0.05

        XCTAssertEqual(game.sweepDuration, 0.01)
        XCTAssertEqual(game.zoneWidth, 0.9)
        XCTAssertEqual(game.resultDuration, 0.01)
        XCTAssertEqual(game.roundTimeout, 0.05)
    }

    /// The default zone is hittable but not free: at the shipped speed, the window for a perfect is
    /// a fraction of a second and most of the sweep is a miss. Guards against a later tweak quietly
    /// making the bar impossible or automatic.
    func testTheShippedBarIsNeitherImpossibleNorAutomatic() {
        let game = makeGame(TimingBarGame.self) { _ in }
        let grades = stride(from: 0.0, to: game.sweepDuration, by: 0.001).map {
            TimingBarGame.grade(stoppingAt: $0,
                                sweepDuration: game.sweepDuration,
                                zoneWidth: game.zoneWidth)
        }

        let share = { (grade: TrainingResult) in
            Double(grades.filter { $0 == grade }.count) / Double(grades.count)
        }
        XCTAssertEqual(share(.miss), 0.75, accuracy: 0.01, "the zone is not a quarter of the sweep")
        XCTAssertGreaterThan(share(.perfect), 0.05, "a perfect is unhittable")
        XCTAssertLessThan(share(.perfect), 0.08, "a perfect is free")
    }

    /// The grade the bar produces is a value `TrainAction` already knows how to pay out — the game
    /// itself knows nothing about energy or stats.
    func testAGradeOffTheBarIsWhatTheActionPaysOut() {
        let state = GameState(currentDigimonId: "hero", stage: .babyI,
                              now: Date(timeIntervalSinceReferenceDate: 600_000))
        state.trainCharges = 1
        TrainAction.begin(state, isAsleep: false)

        TrainAction.finish(state, result: TimingBarGame.grade(at: 0.5, zoneWidth: 0.25))

        XCTAssertEqual(state.strengthStat, TrainingResult.perfect.strengthGain)
        XCTAssertEqual(state.stageTrainingSessions, 1)
    }

    /// Every grade is announced in its own colour, so the end of a round reads at a glance.
    func testEachGradeIsAnnouncedInItsOwnColour() {
        XCTAssertEqual(Set(TrainingResult.allCases.map(\.tint)).count, 4)
    }

    private func makeGame<Game: TrainingMinigame>(
        _ type: Game.Type, onFinish: @escaping (TrainingResult) -> Void
    ) -> Game {
        Game(onFinish: onFinish)
    }
}
