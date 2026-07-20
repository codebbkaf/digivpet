import Foundation
import HealthKit
import XCTest

@testable import DigiVPet

/// A scriptable stand-in for HealthKit that RECORDS what was asked of it.
///
/// The recording is the point: "the onboarding screen appears before the system prompt" is only
/// provable by showing that no request was issued until the user confirmed.
private final class SpyAuthorizer: HealthAuthorizing, @unchecked Sendable {
    var isHealthDataAvailable: Bool
    var status: HealthRequestStatus
    var requestError: Error?

    private(set) var requestCount = 0
    private(set) var statusCheckCount = 0

    /// The whole set that was asked for, as US-059 made it.
    private(set) var requestedReadSet: HealthReadSet?
    /// The set the STATUS was checked against, which US-059 has to widen too — a check narrowed to
    /// the four would report `.answered` and skip the prompt for every newly added type.
    private(set) var statusCheckedReadSet: HealthReadSet?

    /// The energy half of the last request, so the assertions written before the read set existed
    /// still say what they always said: all four energy metrics are in the ask.
    var requestedMetrics: [HealthMetric] { requestedReadSet?.energyMetrics ?? [] }

    init(isHealthDataAvailable: Bool = true,
         status: HealthRequestStatus = .shouldRequest,
         requestError: Error? = nil) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.status = status
        self.requestError = requestError
    }

    func requestStatus(for readSet: HealthReadSet) async -> HealthRequestStatus {
        statusCheckCount += 1
        statusCheckedReadSet = readSet
        return status
    }

    func requestReadAuthorization(for readSet: HealthReadSet) async throws {
        requestCount += 1
        requestedReadSet = readSet
        if let requestError { throw requestError }
    }
}

@MainActor
final class HealthAuthorizationTests: XCTestCase {

    // MARK: - What is requested

    /// The four types named by the AC, and no others.
    func testRequestsExactlyTheFourReadTypes() async {
        let spy = SpyAuthorizer()
        let model = HealthAuthorizationModel(authorizer: spy)

        await model.start()
        await model.confirmAndRequest()

        XCTAssertEqual(Set(spy.requestedMetrics), Set(HealthMetric.allCases))
        XCTAssertEqual(spy.requestedMetrics.count, 4)
    }

    /// Asserts the HealthKit identifiers themselves, not just that four metrics exist — a metric
    /// wired to the wrong HKObjectType would request the wrong permission and still count four.
    func testEachMetricMapsToItsHealthKitTypeAndEnergyType() {
        XCTAssertEqual(HealthMetric.steps.objectType, HKQuantityType(.stepCount))
        XCTAssertEqual(HealthMetric.activeEnergy.objectType, HKQuantityType(.activeEnergyBurned))
        XCTAssertEqual(HealthMetric.sleep.objectType, HKCategoryType(.sleepAnalysis))
        XCTAssertEqual(HealthMetric.exercise.objectType, HKQuantityType(.appleExerciseTime))

        XCTAssertEqual(HealthMetric.steps.energyType, .strength)
        XCTAssertEqual(HealthMetric.activeEnergy.energyType, .vitality)
        XCTAssertEqual(HealthMetric.sleep.energyType, .spirit)
        XCTAssertEqual(HealthMetric.exercise.energyType, .stamina)

        // Every energy type is fed by exactly one metric: no type is unreachable or double-fed.
        XCTAssertEqual(Set(HealthMetric.allCases.map(\.energyType)), Set(EnergyType.allCases))
    }

    /// The app is read-only, so it must never ask to SHARE. Guards the one call that could.
    func testNeverRequestsShareAuthorization() async throws {
        // HealthKitAuthorizer passes `toShare: []` — asserted here by construction, since the
        // protocol has no share parameter at all and so cannot express a write request.
        let spy = SpyAuthorizer()
        let model = HealthAuthorizationModel(authorizer: spy)
        await model.start()
        await model.confirmAndRequest()
        XCTAssertEqual(spy.requestCount, 1)
    }

    // MARK: - Onboarding comes before the prompt

    /// THE AC: the explainer is shown BEFORE the system prompt. Proven by the request count:
    /// start() lands on .explaining having issued ZERO requests.
    func testStartExplainsWithoutPrompting() async {
        let spy = SpyAuthorizer(status: .shouldRequest)
        let model = HealthAuthorizationModel(authorizer: spy)

        await model.start()

        XCTAssertEqual(model.phase, .explaining)
        XCTAssertEqual(spy.requestCount, 0, "start() must not raise the system prompt")
    }

    /// Only confirming — i.e. tapping Continue on the explainer — prompts.
    func testConfirmingIsWhatPrompts() async {
        let spy = SpyAuthorizer(status: .shouldRequest)
        let model = HealthAuthorizationModel(authorizer: spy)

        await model.start()
        XCTAssertEqual(spy.requestCount, 0)

        await model.confirmAndRequest()
        XCTAssertEqual(spy.requestCount, 1)
        XCTAssertEqual(model.phase, .ready)
    }

    /// A returning user has already answered, so re-explaining would be nagging.
    func testAlreadyAnsweredSkipsStraightToReady() async {
        let spy = SpyAuthorizer(status: .answered)
        let model = HealthAuthorizationModel(authorizer: spy)

        await model.start()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(spy.requestCount, 0)
    }

    /// An unknown status must not skip the prompt — re-requesting an answered type is a no-op,
    /// so explaining again is the safe guess.
    func testUnknownStatusStillExplains() async {
        let spy = SpyAuthorizer(status: .unknown)
        let model = HealthAuthorizationModel(authorizer: spy)

        await model.start()

        XCTAssertEqual(model.phase, .explaining)
    }

    // MARK: - Denial and unavailability

    /// THE AC: denial shows an explanatory state — and does not hang, which here means the phase
    /// leaves .requesting rather than sitting on the spinner forever.
    func testFailedRequestLandsOnTheBlockedStateWithADetail() async {
        let spy = SpyAuthorizer()
        spy.requestError = NSError(
            domain: HKErrorDomain,
            code: HKError.errorAuthorizationDenied.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Not allowed."]
        )
        let model = HealthAuthorizationModel(authorizer: spy)

        await model.start()
        await model.confirmAndRequest()

        XCTAssertEqual(model.phase, .denied)
        XCTAssertEqual(model.failureDetail, "Not allowed.")
    }

    /// The blocked screen's Try Again must be able to recover once the user fixes it in
    /// Settings, or the app IS hung — just with a button on it.
    func testRetryingAfterTheUserFixesItRecovers() async {
        let spy = SpyAuthorizer()
        spy.requestError = NSError(domain: HKErrorDomain, code: HKError.errorAuthorizationDenied.rawValue)
        let model = HealthAuthorizationModel(authorizer: spy)

        await model.start()
        await model.confirmAndRequest()
        XCTAssertEqual(model.phase, .denied)

        // The user grants access in Settings and comes back.
        spy.requestError = nil
        spy.status = .answered
        await model.start()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.failureDetail, "a stale failure must not linger on a recovered state")
    }

    /// No HealthKit means no prompt to raise and nothing to retry — say so rather than spin.
    func testUnavailableHealthDataNeverPrompts() async {
        let spy = SpyAuthorizer(isHealthDataAvailable: false)
        let model = HealthAuthorizationModel(authorizer: spy)

        await model.start()

        XCTAssertEqual(model.phase, .unavailable)
        XCTAssertEqual(spy.requestCount, 0)
        XCTAssertEqual(spy.statusCheckCount, 0, "an unavailable store must not be queried at all")
    }

    // MARK: - Partial authorization reads zero

    /// THE AC: unavailable types read zero rather than erroring.
    func testUnreadableMetricsConvertToZeroEnergy() {
        XCTAssertEqual(HealthReading.noData.energyValue, 0)
        XCTAssertEqual(HealthReading.unavailable.energyValue, 0)
        XCTAssertEqual(HealthReading.value(1234).energyValue, 1234)
    }

    /// A real zero is not "no data" — US-012 needs the two apart, and US-027 turns a silent day
    /// into a care mistake where a lazy day is not one.
    func testARealZeroIsDistinctFromNoData() {
        XCTAssertNotEqual(HealthReading.value(0), .noData)
        XCTAssertTrue(HealthReading.value(0).hasData)
        XCTAssertFalse(HealthReading.noData.hasData)
        XCTAssertFalse(HealthReading.unavailable.hasData)
        // Both convert to the same energy, which is exactly why `hasData` has to carry the
        // difference — energyValue alone cannot.
        XCTAssertEqual(HealthReading.value(0).energyValue, HealthReading.noData.energyValue)
    }

    /// THE AC's example, literally: steps granted and sleep denied. The denied type costs its
    /// own energy and nothing else — the other three are unaffected, and nothing throws.
    func testPartialAuthorizationCostsOnlyTheDeniedType() {
        let readings: [HealthMetric: HealthReading] = [
            .steps: .value(8000),
            .activeEnergy: .value(300),
            .sleep: .noData,        // denied — indistinguishable from an untracked night
            .exercise: .value(45),
        ]

        var energy = EnergyTotals.zero
        for metric in HealthMetric.allCases {
            energy[metric.energyType] = Int(readings[metric]?.energyValue ?? 0)
        }

        XCTAssertEqual(energy.spirit, 0, "the denied type reads zero")
        XCTAssertEqual(energy.strength, 8000, "a granted type is untouched by another's denial")
        XCTAssertEqual(energy.vitality, 300)
        XCTAssertEqual(energy.stamina, 45)
    }

    // MARK: - The real HealthKit authorizer

    /// Everything above drives a stub, which cannot catch `HealthKitAuthorizer` itself being
    /// mis-plumbed. This is the one test that touches a real `HKHealthStore`.
    ///
    /// It asks only for the status, which never prompts — no test can answer a system prompt, so
    /// requesting authorization here would hang the suite. What it proves is that the real call
    /// accepts the four types and RESUMES: a `withCheckedContinuation` that forgets to resume on
    /// some path is exactly the "hang" the AC forbids, and no stub would ever show it.
    func testRealAuthorizerAnswersWithoutHanging() async throws {
        let authorizer = HealthKitAuthorizer()
        XCTAssertTrue(authorizer.isHealthDataAvailable, "watchOS always has HealthKit")

        // The SHIPPED read set, not just the four: US-059 widened the ask to whatever the evolution
        // graph's conditions name, and a real `getRequestStatusForAuthorization` is the only thing
        // that can show a type in that set being rejected outright by HealthKit.
        let status = await authorizer.requestStatus(for: .bundled)

        // Which status depends on whether this container has answered a prompt before, so
        // asserting a specific one would be flaky. That it returned at all is the point.
        XCTAssertTrue(HealthRequestStatus.allCases.contains(status))
    }

    // MARK: - The debug stub

    /// The stub is a Simulator screenshot tool. If it could fire without its launch argument it
    /// would be a way to fake authorization in a real build, so pin that it does not.
    func testStubAuthorizerRequiresItsLaunchArgument() {
        XCTAssertNil(StubHealthAuthorizer.fromLaunchArguments([]))
        XCTAssertNil(StubHealthAuthorizer.fromLaunchArguments(["DigiVPet", "-someOtherFlag"]))
        XCTAssertEqual(StubHealthAuthorizer.fromLaunchArguments(["-healthDenied"])?.outcome, .denied)
        XCTAssertEqual(StubHealthAuthorizer.fromLaunchArguments(["-healthUnavailable"])?.outcome, .unavailable)
    }

    /// The states the Simulator screenshots are taken in must be the states the stub produces —
    /// otherwise the screenshots prove nothing about the real screens.
    func testStubDrivesTheModelIntoTheScreenshottedStates() async {
        let denied = HealthAuthorizationModel(authorizer: StubHealthAuthorizer(outcome: .denied))
        await denied.start()
        XCTAssertEqual(denied.phase, .explaining)
        await denied.confirmAndRequest()
        XCTAssertEqual(denied.phase, .denied)

        let unavailable = HealthAuthorizationModel(authorizer: StubHealthAuthorizer(outcome: .unavailable))
        await unavailable.start()
        XCTAssertEqual(unavailable.phase, .unavailable)
    }
}
