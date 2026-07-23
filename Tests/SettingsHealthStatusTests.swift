import SwiftUI
import XCTest

@testable import DigiVPet

/// US-215 — the Settings screen's data-collection status row.
///
/// The row is a pure view of `HealthAuthorizationModel.Phase`, so everything about it is assertable
/// here: which phase reads as which status, what each of the three stub outcomes produces end to
/// end, and that the privacy promise is literally the onboarding screen's string. That the row is
/// legible on a watch is a Simulator screenshot, recorded in progress.txt rather than faked here.
@MainActor
final class SettingsHealthStatusTests: XCTestCase {

    // MARK: - The mapping

    /// Every phase has a status, and the three the player can be parked in are the three the row
    /// is meant to distinguish. Exhaustive by hand: a new phase would compile against `init(phase:)`
    /// only after someone decided what it means here, and this pins what was decided.
    func testEveryPhaseMapsToAStatus() {
        XCTAssertEqual(HealthCollectionStatus(phase: .ready), .collecting)
        XCTAssertEqual(HealthCollectionStatus(phase: .explaining), .notCollecting)
        XCTAssertEqual(HealthCollectionStatus(phase: .requesting), .notCollecting)
        XCTAssertEqual(HealthCollectionStatus(phase: .denied), .notCollecting)
        XCTAssertEqual(HealthCollectionStatus(phase: .unavailable), .unavailable)
        XCTAssertEqual(HealthCollectionStatus(phase: .checking), .checking)
    }

    /// The strings the row shows. Pinned because they are the whole feature — a status row that
    /// says the wrong words is the bug this story exists to prevent.
    func testEachStatusHasItsOwnWords() {
        XCTAssertEqual(HealthCollectionStatus.collecting.title, "Collecting health data")
        XCTAssertEqual(HealthCollectionStatus.notCollecting.title, "Not collecting")
        XCTAssertEqual(HealthCollectionStatus.unavailable.title, "Unavailable")

        let titles = Set(HealthCollectionStatus.allCases.map(\.title))
        XCTAssertEqual(titles.count, HealthCollectionStatus.allCases.count,
                       "two statuses reading the same is a row that cannot be told apart")
        for status in HealthCollectionStatus.allCases {
            XCTAssertFalse(status.detail.isEmpty, "\(status) says nothing under its headline")
        }
    }

    // MARK: - The three stub outcomes (AC3)

    /// `-healthAnswered`: the user answered on a previous launch, so the app is reading.
    func testAnsweredReadsAsCollecting() async {
        let model = HealthAuthorizationModel(authorizer: StubHealthAuthorizer(outcome: .answered))
        await model.start()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.collectionStatus, .collecting)
        XCTAssertEqual(model.collectionStatus.title, "Collecting health data")
    }

    /// `-healthDenied`: unanswered at launch, and still nothing coming in after the request fails.
    /// Both halves matter — the row must not flip to "collecting" just because the prompt was raised.
    func testDeniedReadsAsNotCollectingBeforeAndAfterTheRequest() async {
        let model = HealthAuthorizationModel(authorizer: StubHealthAuthorizer(outcome: .denied))
        await model.start()

        XCTAssertEqual(model.phase, .explaining)
        XCTAssertEqual(model.collectionStatus, .notCollecting)

        await model.confirmAndRequest()

        XCTAssertEqual(model.phase, .denied)
        XCTAssertEqual(model.collectionStatus, .notCollecting)
        XCTAssertEqual(model.collectionStatus.title, "Not collecting")
    }

    /// `-healthUnavailable`: no HealthKit on the device. Distinct from "not collecting", because
    /// there is nothing the player could do about it.
    func testUnavailableReadsAsUnavailable() async {
        let model = HealthAuthorizationModel(authorizer: StubHealthAuthorizer(outcome: .unavailable))
        await model.start()

        XCTAssertEqual(model.phase, .unavailable)
        XCTAssertEqual(model.collectionStatus, .unavailable)
        XCTAssertEqual(model.collectionStatus.title, "Unavailable")
        XCTAssertNotEqual(model.collectionStatus, .notCollecting)
    }

    // MARK: - What the screen is built from (AC2)

    /// The status the screen shows is the one it was handed, not one it went and computed. Driven
    /// through the very expression `ContentView` passes, so a call site that started feeding the
    /// screen a different state would fail here rather than only under someone's thumb.
    func testTheScreenShowsTheStatusItWasHanded() async {
        let model = HealthAuthorizationModel(authorizer: StubHealthAuthorizer(outcome: .answered))
        await model.start()

        let settings = NotificationSettings(defaults: isolatedDefaults())
        let view = SettingsView(settings: settings, healthStatus: model.collectionStatus)

        XCTAssertEqual(view.healthStatus, .collecting)
        XCTAssertEqual(view.healthStatus, model.collectionStatus)
    }

    /// AC4: the promise Settings repeats is the same string the pre-prompt screen made, not a
    /// paraphrase of it. One constant is the only way that stays true through an edit.
    func testThePrivacyPromiseIsTheOnboardingScreensOwnString() {
        XCTAssertEqual(HealthCopy.neverLeavesTheWatch, "Never leaves this watch.")
    }

    // MARK: - The screenshot bypass

    /// The gate's DEBUG bypass is a screenshot tool. If it could fire without its launch argument it
    /// would be a way to skip health onboarding in a real run, so pin that it cannot.
    func testTheGateOnlyShowsTheAppRegardlessWithItsFlag() {
        typealias Gate = HealthAuthorizationGate<EmptyView>
        XCTAssertFalse(Gate.showsContentRegardless([]))
        XCTAssertFalse(Gate.showsContentRegardless(["DigiVPet", "-healthDenied"]))
        XCTAssertTrue(Gate.showsContentRegardless(["DigiVPet", "-settingsDemo", "-healthDenied"]))
    }

    /// A test's own defaults suite, so the notification toggles this screen also holds are not
    /// read from — or written to — the simulator's real preferences.
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SettingsHealthStatusTests.\(UUID().uuidString)")!
    }
}
