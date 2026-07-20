import Foundation
import HealthKit
import XCTest

@testable import DigiVPet

/// Records what was asked of it, like `SpyAuthorizer` in `HealthAuthorizationTests` — the questions
/// here are about the SHAPE of the ask, so nothing else needs scripting.
private final class ReadSetSpy: HealthAuthorizing, @unchecked Sendable {
    var isHealthDataAvailable = true
    var status: HealthRequestStatus = .shouldRequest

    private(set) var requestCount = 0
    private(set) var requestedReadSets: [HealthReadSet] = []
    private(set) var statusReadSets: [HealthReadSet] = []

    func requestStatus(for readSet: HealthReadSet) async -> HealthRequestStatus {
        statusReadSets.append(readSet)
        return status
    }

    func requestReadAuthorization(for readSet: HealthReadSet) async throws {
        requestCount += 1
        requestedReadSets.append(readSet)
    }
}

/// A fetcher whose every read fails, standing in for a type the user denied or a HealthKit outage.
private struct FailingFetcher: HealthMetricSampleFetching {
    struct Boom: Error {}
    func samples(of metric: ReadableHealthMetric, in interval: DateInterval) async throws -> [HealthSample] {
        throw Boom()
    }
}

final class HealthReadSetTests: XCTestCase {

    // MARK: - Fixtures

    /// A one-node graph whose single edge carries `conditions`. Everything else on the node and
    /// edge is filler — only the conditions are under test.
    private func graph(conditions: [EvolutionCondition]) -> EvolutionGraph {
        EvolutionGraph(nodes: [
            EvolutionNode(
                id: "koromon",
                displayName: "Koromon",
                stage: .babyII,
                spriteFile: "Koromon",
                evolutions: [
                    EvolutionEdge(
                        to: "agumon", requiredEnergy: .strength, minEnergy: 10,
                        maxCareMistakes: 3, conditions: conditions)
                ]
            )
        ])
    }

    private func condition(_ metric: ConditionMetric) -> EvolutionCondition {
        EvolutionCondition(
            metric: metric, window: .stage, comparison: .atLeast, value: 1, hint: "Do the thing")
    }

    // MARK: - AC: the read set is DERIVED from the graph, never hardcoded

    /// THE AC. Authoring a condition on a metric is what puts that metric in the grant — there is
    /// no second list to remember to update, so the two cannot fall out of step.
    func testAuthoringAConditionIsWhatAddsItsTypeToTheGrant() {
        let before = HealthReadSet.deriving(from: graph(conditions: []))
        XCTAssertFalse(before.objectTypes.contains(HKQuantityType(.flightsClimbed)))

        let after = HealthReadSet.deriving(from: graph(conditions: [condition(.healthFlightsClimbed)]))
        XCTAssertTrue(after.objectTypes.contains(HKQuantityType(.flightsClimbed)),
                      "a metric named by a condition must be in the read set with no other edit")
    }

    /// Every metric across every edge, not just the first one found.
    func testEveryConditionAcrossTheGraphContributes() {
        let derived = HealthReadSet.deriving(from: EvolutionGraph(nodes: [
            EvolutionNode(
                id: "a", displayName: "A", stage: .child, spriteFile: "A",
                evolutions: [
                    EvolutionEdge(to: "b", minEnergy: 1, maxCareMistakes: 1,
                                  conditions: [condition(.healthFlightsClimbed)]),
                    EvolutionEdge(to: "c", minEnergy: 1, maxCareMistakes: 1,
                                  conditions: [condition(.healthMindfulMinutes)]),
                ]),
            EvolutionNode(
                id: "b", displayName: "B", stage: .adult, spriteFile: "B",
                evolutions: [
                    EvolutionEdge(to: "d", minEnergy: 1, maxCareMistakes: 1,
                                  conditions: [condition(.healthWorkouts), condition(.healthDaylight)]),
                ]),
        ]))

        XCTAssertEqual(Set(derived.conditionMetrics),
                       [.healthFlightsClimbed, .healthMindfulMinutes, .healthWorkouts, .healthDaylight])
    }

    /// THE guard behind the AC's "cannot forget the grant": every health metric in the vocabulary
    /// has a HealthKit type to ask for. A new `ConditionMetric` case with no mapping would be
    /// authorable and unreadable — silently, since HealthKit answers an unauthorized read with no
    /// samples rather than an error.
    func testEveryHealthMetricInTheVocabularyHasATypeToGrant() {
        for metric in ConditionMetric.allCases where metric.isHealthMetric {
            XCTAssertNotNil(metric.readObjectType, "\(metric.rawValue) has no HealthKit type to grant")
        }
    }

    /// `care.*` counters live in `GameState`. There is nothing to ask HealthKit for, and asking
    /// would mean inventing a type.
    func testCareCountersContributeNoGrant() {
        for metric in ConditionMetric.allCases where !metric.isHealthMetric {
            XCTAssertNil(metric.readObjectType, "\(metric.rawValue) must need no HealthKit grant")
        }

        let derived = HealthReadSet.deriving(from: graph(conditions: [
            condition(.careTrainingSessions), condition(.careBattleWinRatio),
        ]))
        XCTAssertTrue(derived.conditionMetrics.isEmpty)
        XCTAssertTrue(derived.additionalObjectTypes.isEmpty)
    }

    /// `health.sleep` is not readable through `HealthMetricReader` — but it still has to be
    /// GRANTED, so its type must not fall out of the ask along with its reader.
    func testSleepIsGrantedEvenThoughItsReaderRefusesIt() {
        XCTAssertNil(ReadableHealthMetric(.healthSleep), "precondition: the reader declines sleep")
        XCTAssertEqual(ConditionMetric.healthSleep.readObjectType, HKCategoryType(.sleepAnalysis))
    }

    /// An unrecognised metric string is the validator's `unknownConditionMetric` to report. Deriving
    /// the read set must not trap on it — this runs at launch, and a typo would kill the app.
    func testAnUnknownMetricStringIsSkippedRatherThanTrapping() {
        let derived = HealthReadSet.deriving(from: graph(conditions: [
            EvolutionCondition(metric: "health.notAThing", window: .stage,
                               comparison: .atLeast, value: 1, hint: "Do the thing"),
            condition(.healthFlightsClimbed),
        ]))

        XCTAssertEqual(derived.conditionMetrics, [.healthFlightsClimbed])
    }

    /// The shipped graph derives without trapping. It authors no conditions yet (US-061 does), so
    /// the assertion is deliberately about the FLOOR, not an exact count — this test must not need
    /// editing every time a condition is authored.
    func testTheShippedGraphDerivesAndAlwaysCoversTheFourEnergyTypes() {
        let bundled = HealthReadSet.bundled
        for metric in HealthMetric.allCases {
            XCTAssertTrue(bundled.objectTypes.contains(metric.objectType),
                          "\(metric) feeds an energy bar and must always be granted")
        }
    }

    // MARK: - AC: the four existing grants survive

    /// The energy half is not derived and not negotiable: a graph with no conditions at all still
    /// asks for all four, or an energy bar could never fill.
    func testAGraphWithNoConditionsStillAsksForTheFour() {
        let derived = HealthReadSet.deriving(from: graph(conditions: []))

        XCTAssertEqual(derived.energyMetrics, HealthMetric.allCases)
        XCTAssertEqual(derived.objectTypes, Set(HealthMetric.allCases.map(\.objectType)))
        XCTAssertTrue(derived.additionalObjectTypes.isEmpty,
                      "nothing new to prompt for means a returning user sees no prompt")
    }

    /// A condition on a metric the energy model ALREADY reads adds no new type — so a returning
    /// user is not re-prompted for a grant they have held since launch day.
    func testAConditionOnAnAlreadyGrantedTypeAddsNothingNew() {
        let derived = HealthReadSet.deriving(from: graph(conditions: [
            condition(.healthSteps), condition(.healthActiveEnergy),
            condition(.healthExerciseMinutes), condition(.healthSleep),
        ]))

        XCTAssertEqual(derived.objectTypes.count, 4, "the union must deduplicate, not double-count")
        XCTAssertTrue(derived.additionalObjectTypes.isEmpty)
    }

    /// THE AC: only the new types are additional. The four are already answered for, and HealthKit
    /// does not re-prompt for a type the user has answered — so this set is exactly what a returning
    /// user sees.
    func testOnlyTheGenuinelyNewTypesAreAdditional() {
        let derived = HealthReadSet.deriving(from: graph(conditions: [
            condition(.healthSteps),            // already granted
            condition(.healthFlightsClimbed),   // new
            condition(.careOverfeeds),          // not a HealthKit type at all
        ]))

        XCTAssertEqual(derived.additionalObjectTypes, [HKQuantityType(.flightsClimbed)])
    }

    /// One request, not two. Asking for the old and new sets separately would raise two system
    /// prompts back to back, which reads as a bug and invites a denial on the second.
    func testTheWholeSetGoesOutInASingleRequest() async {
        let spy = ReadSetSpy()
        let readSet = HealthReadSet.deriving(from: graph(conditions: [condition(.healthFlightsClimbed)]))
        let model = await HealthAuthorizationModel(authorizer: spy, readSet: readSet)

        await model.start()
        await model.confirmAndRequest()

        XCTAssertEqual(spy.requestCount, 1)
        XCTAssertEqual(spy.requestedReadSets.first?.objectTypes, readSet.objectTypes)
        XCTAssertEqual(spy.requestedReadSets.first?.objectTypes.count, 5)
    }

    /// The status check has to cover the WIDE set. Narrowed to the four it would answer `.answered`
    /// for every existing user, land on `.ready`, and never request the new types at all.
    func testTheStatusCheckCoversTheWholeSetNotJustTheFour() async {
        let spy = ReadSetSpy()
        let readSet = HealthReadSet.deriving(from: graph(conditions: [condition(.healthFlightsClimbed)]))
        let model = await HealthAuthorizationModel(authorizer: spy, readSet: readSet)

        await model.start()

        XCTAssertEqual(spy.statusReadSets.first?.objectTypes, readSet.objectTypes)
        XCTAssertTrue(
            spy.statusReadSets.first?.objectTypes.contains(HKQuantityType(.flightsClimbed)) ?? false)
    }

    /// A returning user who has answered for everything in the wide set is not asked again — the
    /// prompt is HealthKit's to skip, but landing on `.ready` is what stops the app re-explaining.
    func testAUserWhoHasAnsweredForEverythingIsNotReprompted() async {
        let spy = ReadSetSpy()
        spy.status = .answered
        let model = await HealthAuthorizationModel(
            authorizer: spy,
            readSet: .deriving(from: graph(conditions: [condition(.healthFlightsClimbed)])))

        await model.start()

        let phase = await model.phase
        XCTAssertEqual(phase, .ready)
        XCTAssertEqual(spy.requestCount, 0)
    }

    // MARK: - AC: a denied new type is contained

    /// A read that fails — which is what a denied type looks like once queried — is `.unavailable`,
    /// never a throw. An evolution check therefore gets a value it can judge rather than an error
    /// mid-evaluation, which is what "never blocks evolution entirely" rests on.
    func testADeniedTypeReadsUnavailableRatherThanThrowing() async {
        let reader = HealthMetricReader(fetcher: FailingFetcher())
        let window = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86_400)

        for readable in ReadableHealthMetric.all {
            let reading = await reader.read(readable, in: window)
            XCTAssertEqual(reading, .unavailable, "\(readable.metric.rawValue) must not throw")
            XCTAssertEqual(reading.energyValue, 0)
        }
    }

    /// THE AC: a denied condition metric never charges a care mistake. Structural, and deliberately
    /// so — the verdict is read off `HealthEnergySource.readings`, which is keyed by `EnergyType`
    /// and so cannot carry a condition metric at all. There is no path for one to reach the counter.
    func testACareMistakeVerdictIsReadOnlyFromTheFourEnergyTypes() {
        var readings: [EnergyType: HealthReading] = [:]
        for type in EnergyType.allCases { readings[type] = .value(1) }
        XCTAssertEqual(readings.count, 4, "the verdict's whole input is the four energy types")

        // One energy type reading real data is enough to say the day was not empty — a denied
        // evolution metric cannot change that verdict, because it is not one of these keys.
        XCTAssertEqual(CareMistakes.HealthDataVerdict(readings.values), .seen)

        readings[.spirit] = .unavailable
        XCTAssertEqual(CareMistakes.HealthDataVerdict(readings.values), .seen,
                       "an unreadable metric alongside real data is still not neglect")
    }

    // MARK: - AC: the onboarding copy explains the new types

    /// Nothing extra to ask for means no stray line promising a read the app does not do.
    func testNoExtraTypesMeansNoExtraCopy() {
        XCTAssertNil(HealthReadSet(conditionMetrics: []).additionalTypesDescription)
        XCTAssertNil(HealthReadSet(conditionMetrics: [.healthSteps]).additionalTypesDescription,
                     "a metric already granted for energy is not something new to explain")
    }

    /// The copy says what the extra readings are FOR — steering the evolution, not feeding the
    /// Digimon — which is the distinction a user needs to decide whether to grant them.
    func testTheCopyExplainsWhatTheExtraTypesAreFor() throws {
        let copy = try XCTUnwrap(
            HealthReadSet(conditionMetrics: [.healthFlightsClimbed, .healthMindfulMinutes])
                .additionalTypesDescription)

        XCTAssertTrue(copy.contains("2 more"), copy)
        XCTAssertTrue(copy.lowercased().contains("evolves into"), copy)
    }

    /// One extra type reads "1 more reading", not "1 more readings".
    func testTheCopyIsGrammaticalForASingleExtraType() throws {
        let copy = try XCTUnwrap(
            HealthReadSet(conditionMetrics: [.healthFlightsClimbed]).additionalTypesDescription)

        XCTAssertTrue(copy.contains("1 more reading,"), copy)
    }

    /// The onboarding screen builds with the real shipped set — the view takes the model's set, so
    /// a screen describing a different ask than the one raised would be a compile error, not a
    /// wording bug.
    func testTheOnboardingScreenBuildsFromAReadSet() {
        _ = HealthOnboardingView(readSet: .bundled) {}
        _ = HealthOnboardingView(readSet: HealthReadSet(conditionMetrics: [.healthWorkouts])) {}
    }

    // MARK: - AC: the launch flags still work

    /// The three debug flags survived the protocol change — they are how the Simulator reaches
    /// these screens at all, and the story's own notes forbid resetting the grant any other way.
    func testTheLaunchFlagsStillDriveTheStub() async {
        XCTAssertEqual(StubHealthAuthorizer.fromLaunchArguments(["-healthDenied"])?.outcome, .denied)
        XCTAssertEqual(
            StubHealthAuthorizer.fromLaunchArguments(["-healthUnavailable"])?.outcome, .unavailable)
        XCTAssertEqual(
            StubHealthAuthorizer.fromLaunchArguments(["-healthAnswered"])?.outcome, .answered)

        let answered = await HealthAuthorizationModel(
            authorizer: StubHealthAuthorizer(outcome: .answered),
            readSet: .deriving(from: graph(conditions: [condition(.healthFlightsClimbed)])))
        await answered.start()
        let phase = await answered.phase
        XCTAssertEqual(phase, .ready, "-healthAnswered must still skip straight past the prompt")
    }
}
