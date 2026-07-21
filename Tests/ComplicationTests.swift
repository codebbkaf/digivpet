import Foundation
import SwiftData
import WidgetKit
import XCTest

@testable import DigiVPet

/// Same fixed-zone calendar and hand-written instants as `MainScreenTests`: a complication test that
/// only passed in the machine's own timezone would be no test at all.
private enum Fixture {
    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = losAngeles
        formatter.timeZone = losAngeles.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("bad fixture date \(iso)")
        }
        return date
    }

    static let morning = date("2026-07-17 08:00")
}

private final class FixtureSampleFetcher: HealthSampleFetching, @unchecked Sendable {
    var samples: [QuantityMetric: [HealthSample]] = [:]

    func samples(of metric: QuantityMetric, in interval: DateInterval) async throws -> [HealthSample] {
        samples[metric] ?? []
    }
}

private final class FixtureSleepFetcher: SleepSampleFetching, @unchecked Sendable {
    func sleepSamples(in window: DateInterval) async throws -> [SleepSample] { [] }
}

@MainActor
final class ComplicationTests: XCTestCase {
    private var scratch: URL!
    private var storeURL: URL { scratch.appendingPathComponent("Complication.store") }
    /// Stands in for the app group container. The real one needs a signed entitlement, which a test
    /// bundle does not have — what is under test here is what gets WRITTEN and read back, and a
    /// directory is a directory.
    private var sharedDirectory: URL { scratch }
    private var steps: FixtureSampleFetcher!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        steps = FixtureSampleFetcher()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        try super.tearDownWithError()
    }

    private func makeModel(now: @escaping () -> Date = { Fixture.morning }) -> MainScreenModel {
        let source = HealthEnergySource(
            todayReader: TodayHealthReader(fetcher: steps, calendar: Fixture.losAngeles),
            sleepReader: LastNightSleepReader(fetcher: FixtureSleepFetcher(),
                                              calendar: Fixture.losAngeles)
        )
        return MainScreenModel(
            makeStore: { [storeURL] in try GameStore(url: storeURL) },
            graph: .bundled,
            energySource: source,
            calendar: Fixture.losAngeles,
            now: now,
            chooseStartingDigitama: { $0.first }
        )
    }

    private func walk(_ count: Double) {
        steps.samples[.steps] = [
            HealthSample(start: Fixture.date("2026-07-17 07:00"),
                         end: Fixture.date("2026-07-17 07:30"),
                         value: count)
        ]
    }

    // MARK: - What the complication is given to draw

    /// THE AC ("renders the current Digimon's 16x16 idle sprite"): the snapshot names the SAVED
    /// Digimon's art, not the starting egg's, and that art resolves to a real 16x16 image.
    func testTheSnapshotNamesTheSavedDigimonsIdleSprite() async throws {
        let store = try GameStore(url: storeURL)
        let saved = try store.loadOrCreate(digitamaId: "agu_digitama", now: Fixture.morning)
        saved.currentDigimonId = "greymon"
        saved.stage = .adult
        try store.save()

        let model = makeModel()
        await model.start()

        let snapshot = try XCTUnwrap(model.complicationSnapshot)
        XCTAssertEqual(snapshot.displayName, "Greymon")
        XCTAssertEqual(snapshot.spriteStage, "Adult")
        XCTAssertEqual(snapshot.spriteFile, "Greymon")

        // The complication draws through `IdleSpriteCache`, so resolving the name the snapshot
        // carries is the only thing that proves the art actually exists — a snapshot naming a
        // missing file would look identical to this one.
        let image = try XCTUnwrap(IdleSpriteCache().image(stage: snapshot.spriteStage,
                                                          name: snapshot.spriteFile))
        XCTAssertEqual(image.width, SpriteSheet.frameSize)
        XCTAssertEqual(image.height, SpriteSheet.frameSize)
    }

    /// A Digitama has no entry in `Idle Frame Only` at all, so this is the case where the
    /// complication would silently fall back to a '?' if the cache's egg fallback ever broke.
    func testAnEggsSnapshotStillResolvesToASprite() async throws {
        let model = makeModel()
        await model.start()

        let snapshot = try XCTUnwrap(model.complicationSnapshot)
        XCTAssertEqual(snapshot.spriteStage, "Digitama")
        let image = try XCTUnwrap(IdleSpriteCache().image(stage: snapshot.spriteStage,
                                                          name: snapshot.spriteFile))
        XCTAssertEqual(image.width, SpriteSheet.frameSize)
    }

    /// THE AC ("rectangular family shows sprite plus dominant energy progress"): the dominant type
    /// and its progress toward the current node's gate reach the snapshot.
    func testTheSnapshotCarriesDominantEnergyProgress() async throws {
        let model = makeModel()
        // 4000 steps at 100 steps/point is 40 Strength, against the egg's 50-point hatch gate. The
        // egg's bars aim at their SHARE of the total gate (US-017), so this is a real fraction and
        // not a 0 or a 1 that any arithmetic would produce.
        walk(4000)
        await model.start()

        let snapshot = try XCTUnwrap(model.complicationSnapshot)
        // The short name and not the display name: the face labels the gauge with where the energy
        // came from, and spells the type out in the accessibility label beside it (US-085).
        XCTAssertEqual(snapshot.dominantEnergySymbol, "STEP")
        XCTAssertEqual(snapshot.dominantEnergySymbol, EnergyType.strength.shortName)
        XCTAssertEqual(snapshot.dominantEnergyName, "Strength")
        XCTAssertEqual(snapshot.dominantEnergyEarned, 40)

        let progress = try XCTUnwrap(model.energyProgress)
        let goal = try XCTUnwrap(progress.goals.first { $0.type == .strength })
        XCTAssertEqual(snapshot.dominantEnergyFraction, progress.fraction(of: goal), accuracy: 0.0001)
        XCTAssertGreaterThan(snapshot.dominantEnergyFraction, 0)
        XCTAssertLessThan(snapshot.dominantEnergyFraction, 1)
    }

    /// A brand-new egg has earned nothing, and there is no dominant type to show. The complication
    /// must be told that rather than being handed an arbitrary type at zero — which is exactly what
    /// it would get if this defaulted instead of staying nil.
    func testAFreshEggHasNoDominantEnergy() async throws {
        let model = makeModel()
        await model.start()

        let snapshot = try XCTUnwrap(model.complicationSnapshot)
        XCTAssertNil(snapshot.dominantEnergySymbol)
        XCTAssertNil(snapshot.dominantEnergyName)
        XCTAssertEqual(snapshot.dominantEnergyFraction, 0)
        XCTAssertEqual(snapshot.dominantEnergyEarned, 0)
    }

    /// The two snapshots this file spells its labels out in — it is shared with the widget
    /// extension, which does not compile `EnergyType` — have to say what `EnergyType` says. Nothing
    /// else ties the two together, so a rename that missed them would ship a stale label to the
    /// gallery and to the `-complicationEnergyDemo` screenshot.
    func testTheHardCodedSnapshotLabelsMatchTheEnergyTypes() {
        XCTAssertEqual(ComplicationSnapshot.placeholder.dominantEnergySymbol,
                       EnergyType.strength.shortName)
        XCTAssertEqual(ComplicationSnapshot.placeholder.dominantEnergyName,
                       EnergyType.strength.displayName)

        // The demo exists to photograph the WIDEST label, so it has to still be the widest one.
        // Since US-113 that is Vitality's "KCAL" and no longer Spirit's, which is now "Zz": three
        // labels are tied at four characters and KCAL is the widest of the three in points.
        let longest = ComplicationSnapshot.longestEnergyLabel.dominantEnergySymbol
        XCTAssertEqual(longest, EnergyType.vitality.shortName)
        XCTAssertEqual(ComplicationSnapshot.longestEnergyLabel.dominantEnergyName,
                       EnergyType.vitality.displayName)
        // Tied, so no single case can be asserted as THE longest — but nothing may be longer than
        // what the demo photographs, which is the property the screenshot depends on.
        XCTAssertEqual(longest?.count, EnergyType.allCases.map(\.shortName.count).max())
    }

    // MARK: - Crossing the process boundary

    /// The whole point of the file: what the app writes is what a SEPARATE process reads back. Every
    /// field is checked, because a round trip that dropped one would still decode.
    func testTheSnapshotSurvivesTheRoundTripThroughTheSharedFile() throws {
        let written = ComplicationSnapshot(
            displayName: "Greymon",
            spriteStage: "Adult",
            spriteFile: "Greymon",
            dominantEnergySymbol: "STEP",
            dominantEnergyName: "Strength",
            dominantEnergyFraction: 0.4,
            dominantEnergyEarned: 40,
            // Deliberately not the default: a `pose` that failed to encode would round-trip
            // invisibly if the fixture used `.idle`.
            pose: .sick,
            published: Fixture.morning
        )
        XCTAssertTrue(ComplicationSnapshotStore.write(written, to: sharedDirectory))

        let read = try XCTUnwrap(ComplicationSnapshotStore.read(from: sharedDirectory))
        XCTAssertEqual(read, written)
    }

    /// Before the app has ever published, there is nothing to read — and reading must return nil
    /// rather than trapping, because that is the widget's first-ever render.
    func testAnUnpublishedComplicationReadsNothing() {
        XCTAssertNil(ComplicationSnapshotStore.read(from: sharedDirectory))
    }

    /// A missing app group container (the entitlement absent or unsigned) must degrade to "published
    /// nowhere", never to a crash — the app has a game to keep running either way.
    func testPublishingWithoutASharedContainerFailsQuietly() {
        XCTAssertFalse(ComplicationSnapshotStore.write(.placeholder, to: nil))
        XCTAssertNil(ComplicationSnapshotStore.read(from: nil))
    }

    /// THE AC ("tapping opens the app"): the widget's URL uses the scheme the app registers. If these
    /// two ever drift the tap opens nothing at all, silently.
    func testTheComplicationTapURLUsesTheAppsRegisteredScheme() throws {
        let url = try XCTUnwrap(DigiVPetURL.open)
        XCTAssertEqual(url.scheme, DigiVPetURL.scheme)

        let plist = try XCTUnwrap(Bundle(for: MainScreenModel.self).infoDictionary)
        let types = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains(DigiVPetURL.scheme),
                      "the app's Info.plist claims \(schemes), not \(DigiVPetURL.scheme)")
    }

    /// The gallery preview and a never-published watch both draw the placeholder, so its art has to
    /// be real. A placeholder naming a missing sprite renders as a '?' in the gallery.
    func testThePlaceholderNamesRealArt() throws {
        let image = try XCTUnwrap(IdleSpriteCache().image(stage: ComplicationSnapshot.placeholder.spriteStage,
                                                          name: ComplicationSnapshot.placeholder.spriteFile))
        XCTAssertEqual(image.width, SpriteSheet.frameSize)
        XCTAssertEqual(image.height, SpriteSheet.frameSize)
    }

    // MARK: - US-047: the pose

    /// THE AC ("pose mapping is explicit and total"): every state maps, and every state maps to
    /// something. Written as the full truth table of the four inputs — 16 rows — rather than as five
    /// happy-path cases, because the mapping's only real risk is a combination nobody pictured.
    func testThePoseMappingIsTotal() {
        for isDead in [true, false] {
            for isSick in [true, false] {
                for isAsleep in [true, false] {
                    for hasPoop in [true, false] {
                        let pose = ComplicationPose.pose(isDead: isDead, isSick: isSick,
                                                         isAsleep: isAsleep, hasPoop: hasPoop)
                        let expected: ComplicationPose
                        if isDead { expected = .dead }
                        else if isSick { expected = .sick }
                        else if isAsleep { expected = .sleeping }
                        else if hasPoop { expected = .messy }
                        else { expected = .idle }
                        XCTAssertEqual(pose, expected,
                                       "dead:\(isDead) sick:\(isSick) asleep:\(isAsleep) poop:\(hasPoop)")
                    }
                }
            }
        }
    }

    /// THE AC ("precedence when two apply at once"): the four overlaps that actually happen in play,
    /// spelled out one by one so a reordered `if` chain fails here with a readable name rather than
    /// only inside the loop above.
    func testAMoreSeriousStateOutranksALesserOne() {
        // The AC's own example. Sickness is about the Digimon; the mess is about the floor.
        XCTAssertEqual(ComplicationPose.pose(isDead: false, isSick: true, isAsleep: false, hasPoop: true),
                       .sick)
        // Matches `restingAnimation`, where sickness already wins over sleep.
        XCTAssertEqual(ComplicationPose.pose(isDead: false, isSick: true, isAsleep: true, hasPoop: false),
                       .sick)
        // A dead Digimon is not asleep, however the sleep window reads the clock.
        XCTAssertEqual(ComplicationPose.pose(isDead: true, isSick: true, isAsleep: true, hasPoop: true),
                       .dead)
        // Poop is paused during sleep but persists into it, so this pairing is ordinary.
        XCTAssertEqual(ComplicationPose.pose(isDead: false, isSick: false, isAsleep: true, hasPoop: true),
                       .sleeping)
    }

    /// THE AC ("dead -> a DISTINCT held frame"): no two poses draw the same pixels. Two states that
    /// shared a frame would be indistinguishable on a face that has no room for a caption.
    func testEveryPoseHoldsADistinctFrame() {
        let frames = ComplicationPose.allCases.map(\.frame)
        XCTAssertEqual(Set(frames).count, ComplicationPose.allCases.count,
                       "two poses share a frame: \(frames)")
    }

    /// The frames the poses name have to EXIST in the shipped art, not just in the enum. A stage
    /// sheet is 48x64 so all twelve are there — this is what would catch the mapping being pointed
    /// at an index the sheet does not hold.
    func testEveryPoseResolvesToRealArt() throws {
        let sheet = try XCTUnwrap(SpriteSheetCache().sheet(stage: "Adult", name: "Greymon"))
        for pose in ComplicationPose.allCases {
            let frame = try XCTUnwrap(sheet[pose.frame], "no art for \(pose)")
            XCTAssertEqual(frame.width, SpriteSheet.frameSize)
            XCTAssertEqual(frame.height, SpriteSheet.frameSize)
        }
    }

    /// The pose reaches the snapshot off the REAL game state, not just off the mapping function —
    /// this is the wiring between `healthStatus`/`poopCount` and the four booleans.
    func testTheSnapshotCarriesThePoseDerivedFromTheGame() async throws {
        let model = makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)

        // A plain awake, healthy, clean Digimon.
        model.isAsleep = false
        XCTAssertEqual(model.complicationSnapshot?.pose, .idle)

        state.poopCount = 2
        XCTAssertEqual(model.complicationSnapshot?.pose, .messy)

        model.isAsleep = true
        XCTAssertEqual(model.complicationSnapshot?.pose, .sleeping)

        state.healthStatus = .sick
        XCTAssertEqual(model.complicationSnapshot?.pose, .sick)

        state.healthStatus = .dead
        XCTAssertEqual(model.complicationSnapshot?.pose, .dead)
    }

    /// THE AC ("republished when the underlying state changes, so the pose is not stale"): cleaning
    /// is the only ACTION that moves the pose, and the snapshot it would publish has already stopped
    /// saying `.messy` by the time `clean()` returns.
    func testCleaningTakesTheMessOffTheComplication() async throws {
        let model = makeModel()
        await model.start()
        let state = try XCTUnwrap(model.state)
        model.isAsleep = false

        state.poopCount = 4
        XCTAssertEqual(model.complicationSnapshot?.pose, .messy)

        XCTAssertTrue(model.clean())
        XCTAssertEqual(model.complicationSnapshot?.pose, .idle)
    }

    /// The upgrade case `init(from:)` exists for: the snapshot already on disk was written before
    /// poses existed. It must still decode, as `.idle`, rather than dropping the whole complication
    /// back to the placeholder until the next refresh.
    func testASnapshotWrittenBeforePosesExistedStillDecodes() throws {
        let legacy = """
        {"displayName":"Greymon","spriteStage":"Adult","spriteFile":"Greymon",\
        "dominantEnergyFraction":0.4,"dominantEnergyEarned":40,"published":774000000}
        """
        let decoded = try JSONDecoder().decode(ComplicationSnapshot.self,
                                               from: Data(legacy.utf8))
        XCTAssertEqual(decoded.pose, .idle)
        XCTAssertEqual(decoded.displayName, "Greymon")
        XCTAssertNil(decoded.dominantEnergySymbol)
    }

    /// The pose is drawn, so VoiceOver cannot see it. Idle says nothing extra on purpose: "Agumon,
    /// idle" on every ordinary day is noise that would bury the day it matters.
    func testVoiceOverIsToldWhatTheDigimonIsDoing() {
        var snapshot = ComplicationSnapshot.placeholder
        snapshot.pose = .sick
        XCTAssertEqual(snapshot.accessibilityLabel, "Agumon, sick")

        snapshot.pose = .idle
        XCTAssertEqual(snapshot.accessibilityLabel, "Agumon")
    }

    // MARK: - US-050: cleaning from the watch face

    private func messySnapshot(poopCount: Int, pose: ComplicationPose) -> ComplicationSnapshot {
        ComplicationSnapshot(
            displayName: "Greymon",
            spriteStage: "Adult",
            spriteFile: "Greymon",
            dominantEnergySymbol: "STEP",
            dominantEnergyName: "Strength",
            dominantEnergyFraction: 0.4,
            dominantEnergyEarned: 40,
            pose: pose,
            poopCount: poopCount,
            published: Fixture.morning
        )
    }

    /// THE AC ("the button appears only when there is poop to clean").
    ///
    /// The `.sick` row is the one that matters and is why the snapshot carries a COUNT rather than
    /// being read off the pose: sickness outranks the mess, so a button keyed off `.messy` would
    /// disappear from a sick Digimon standing in four poops — the case with the most to clean.
    func testTheCleanButtonAppearsExactlyWhenThereIsAMess() {
        XCTAssertFalse(messySnapshot(poopCount: 0, pose: .idle).needsCleaning)
        XCTAssertTrue(messySnapshot(poopCount: 1, pose: .messy).needsCleaning)
        XCTAssertTrue(messySnapshot(poopCount: 4, pose: .messy).needsCleaning)
        XCTAssertTrue(messySnapshot(poopCount: 4, pose: .sick).needsCleaning)
        XCTAssertTrue(messySnapshot(poopCount: 4, pose: .sleeping).needsCleaning)
        // The gallery preview has no game behind it and must not offer to clean one.
        XCTAssertFalse(ComplicationSnapshot.placeholder.needsCleaning)
    }

    /// The count has to SURVIVE the file, or the widget process decides the button's visibility from
    /// a field that decoded back to zero and the button never appears on a real watch.
    func testThePoopCountCrossesTheProcessBoundary() throws {
        let written = messySnapshot(poopCount: 3, pose: .messy)
        XCTAssertTrue(ComplicationSnapshotStore.write(written, to: sharedDirectory))
        let read = try XCTUnwrap(ComplicationSnapshotStore.read(from: sharedDirectory))
        XCTAssertEqual(read.poopCount, 3)
        XCTAssertEqual(read, written)
    }

    /// A snapshot written by the version before this one has no `poopCount`, and must decode as
    /// zero rather than failing outright — the same upgrade path `pose` has.
    func testASnapshotWrittenBeforePoopCountsExistedStillDecodes() throws {
        let legacy = """
        {"displayName":"Greymon","spriteStage":"Adult","spriteFile":"Greymon",\
        "dominantEnergyFraction":0.4,"dominantEnergyEarned":40,"pose":"messy",\
        "published":774000000}
        """
        let decoded = try JSONDecoder().decode(ComplicationSnapshot.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.poopCount, 0)
        XCTAssertFalse(decoded.needsCleaning)
        XCTAssertEqual(decoded.pose, .messy)
    }

    /// The optimistic redraw: `.messy` is ranked below every other non-idle pose, so cleaning can
    /// only leave `.idle` — and it must leave every other pose alone, because those are about the
    /// Digimon and cleaning does not touch it.
    func testCleaningASnapshotClearsTheMessAndNothingElse() {
        XCTAssertEqual(messySnapshot(poopCount: 4, pose: .messy).cleaned().pose, .idle)
        XCTAssertEqual(messySnapshot(poopCount: 4, pose: .sick).cleaned().pose, .sick)
        XCTAssertEqual(messySnapshot(poopCount: 4, pose: .sleeping).cleaned().pose, .sleeping)
        XCTAssertEqual(messySnapshot(poopCount: 4, pose: .dead).cleaned().pose, .dead)

        let cleaned = messySnapshot(poopCount: 4, pose: .messy).cleaned()
        XCTAssertEqual(cleaned.poopCount, 0)
        XCTAssertFalse(cleaned.needsCleaning)
        // Everything that is not about the mess is untouched.
        XCTAssertEqual(cleaned.displayName, "Greymon")
        XCTAssertEqual(cleaned.dominantEnergyEarned, 40)
    }

    /// THE AC ("pending poop notifications are cancelled, exactly as in-app cleaning does") for the
    /// FACE's half: the tap withdraws the notice immediately rather than leaving it on the wrist
    /// until the app next happens to run.
    func testTappingCleanOnTheFaceWithdrawsTheMessNotice() {
        var cancelled = 0
        XCTAssertTrue(ComplicationCleanRequest.record(now: Fixture.morning,
                                                      in: sharedDirectory,
                                                      cancelNotice: { cancelled += 1 }))
        XCTAssertEqual(cancelled, 1)
    }

    /// The tap redraws the face at once, without waiting for the app: the recorded request and the
    /// rewritten snapshot are both there the instant `record` returns.
    func testTappingCleanOnTheFaceRedrawsItImmediately() throws {
        XCTAssertTrue(ComplicationSnapshotStore.write(messySnapshot(poopCount: 4, pose: .messy),
                                                      to: sharedDirectory))

        XCTAssertTrue(ComplicationCleanRequest.record(now: Fixture.morning,
                                                      in: sharedDirectory,
                                                      cancelNotice: {}))

        XCTAssertEqual(CleanRequestStore.pending(in: sharedDirectory), Fixture.morning)
        let redrawn = try XCTUnwrap(ComplicationSnapshotStore.read(from: sharedDirectory))
        XCTAssertEqual(redrawn.poopCount, 0)
        XCTAssertEqual(redrawn.pose, .idle)
    }

    /// A watch with no app group container must not pretend the tap worked: nothing recorded, and
    /// crucially nothing redrawn — a face showing a clean screen over a mess the app will never
    /// hear about is worse than a button that visibly did nothing.
    func testTappingCleanWithoutASharedContainerChangesNothing() {
        var cancelled = 0
        XCTAssertFalse(ComplicationCleanRequest.record(now: Fixture.morning,
                                                       in: nil,
                                                       cancelNotice: { cancelled += 1 }))
        XCTAssertEqual(cancelled, 0)
        XCTAssertNil(CleanRequestStore.pending(in: nil))
    }

    /// THE AC ("tapping it zeroes the poop count through the SAME model path as the in-app Clean
    /// button"): the end-to-end round trip. A request left by the face is picked up by an ordinary
    /// `refresh()` and the saved game comes back clean — through `clean()`, which is also what
    /// restamps `poopUpdatedAt` so the mess does not immediately re-accrue.
    func testARequestFromTheFaceIsAppliedByTheNextRefresh() async throws {
        let model = makeModel()
        model.complicationDirectory = sharedDirectory
        await model.start()
        let state = try XCTUnwrap(model.state)
        model.isAsleep = false

        // Accrued by the real clock rather than hand-set: twelve hours is four 3h intervals, which
        // is the ceiling.
        state.poopUpdatedAt = Fixture.morning.addingTimeInterval(-12 * 60 * 60)
        state.advancePoop(isAsleep: false, now: Fixture.morning)
        XCTAssertEqual(model.poopCount, PoopClock.maximumPoops)

        XCTAssertTrue(ComplicationCleanRequest.record(now: Fixture.morning,
                                                      in: sharedDirectory,
                                                      cancelNotice: {}))
        await model.refresh()

        XCTAssertEqual(model.poopCount, 0)
        XCTAssertEqual(state.poopCount, 0)
        // Re-armed, so a screen left to fill again earns a fresh notice — the same thing the in-app
        // button does, because it is the same method.
        XCTAssertFalse(state.poopNotified)
        // The timestamp moved to the clean, not left twelve hours back, or `advancePoop` later in
        // that very refresh would have put all four straight back.
        XCTAssertEqual(state.poopUpdatedAt, Fixture.morning)
        // Consumed: a second refresh must not clean again.
        XCTAssertNil(CleanRequestStore.pending(in: sharedDirectory))
    }

    /// A request is worth ONE attempt. Left on disk it would be retried on every refresh forever,
    /// silently cancelling the mess notice long after the user stopped asking.
    func testAFaceRequestIsConsumedEvenWhenThereIsNothingToClean() async throws {
        let model = makeModel()
        model.complicationDirectory = sharedDirectory
        await model.start()
        model.isAsleep = false
        XCTAssertEqual(model.poopCount, 0)

        XCTAssertTrue(CleanRequestStore.record(at: Fixture.morning, in: sharedDirectory))
        // False: the request was found, but `clean()` had nothing to do.
        XCTAssertFalse(model.applyPendingCleanRequest())
        XCTAssertNil(CleanRequestStore.pending(in: sharedDirectory))
        // And with no request waiting it is a no-op rather than a spurious clean.
        XCTAssertFalse(model.applyPendingCleanRequest())
    }
}

/// The app group US-034 adds is not free: it moves `NSPersistentContainer.defaultDirectoryURL()`,
/// and with it SwiftData's default store, into the shared container. `GameStore` pins its own path
/// so that cannot happen — an app that gained a complication must not lose the game it had saved.
@MainActor
final class DefaultStoreLocationTests: XCTestCase {
    func testTheSavedGameStaysInTheAppsOwnContainer() throws {
        let url = GameStore.defaultStoreURL()
        XCTAssertEqual(url.lastPathComponent, "default.store")
        XCTAssertFalse(url.path.contains("Shared/AppGroup"),
                       "the saved game moved into the app group container: \(url.path)")
        XCTAssertTrue(url.path.contains("Application Support"), url.path)
    }
}

/// US-049: the batch of entries that makes the sprite walk.
///
/// Everything here is pure timeline arithmetic against a fixed instant — no WidgetKit host, no
/// waiting, no real clock. `ComplicationProvider.now` is injected for the same reason every other
/// clock in this project is.
final class ComplicationTimelineTests: XCTestCase {
    /// A snapshot in a given pose, with the placeholder's harmless everything-else.
    private func snapshot(pose: ComplicationPose) -> ComplicationSnapshot {
        ComplicationSnapshot(
            displayName: "Agumon",
            spriteStage: "Child",
            spriteFile: "Agumon",
            dominantEnergySymbol: "STEP",
            dominantEnergyName: "Strength",
            dominantEnergyFraction: 0.5,
            dominantEnergyEarned: 25,
            pose: pose,
            published: Fixture.morning
        )
    }

    // MARK: - The animated batch

    func testTheIdleBatchHasTheDocumentedEntryCountAndHorizon() {
        let entries = ComplicationTimeline.entries(for: snapshot(pose: .idle), from: Fixture.morning)

        XCTAssertEqual(entries.count, ComplicationTimeline.motionEntryCount)
        XCTAssertEqual(entries.count, 300)
        XCTAssertEqual(entries.first?.date, Fixture.morning)
        // 300 entries at 1 s means the last one lands at t+299, one second short of five minutes —
        // the SAME horizon 60 entries at 5 s gave, which is what keeps the reload rate unchanged.
        XCTAssertEqual(entries.last?.date, Fixture.morning.addingTimeInterval(299))
    }

    func testTheIdleBatchIsSpacedAtTheMeasuredFrameInterval() {
        let entries = ComplicationTimeline.entries(for: snapshot(pose: .idle), from: Fixture.morning)

        // The cadence is the measured one from docs/widget-refresh-granularity.md, not an assumption.
        XCTAssertEqual(ComplicationTimeline.frameInterval, 1)
        for (earlier, later) in zip(entries, entries.dropFirst()) {
            XCTAssertEqual(later.date.timeIntervalSince(earlier.date),
                           ComplicationTimeline.frameInterval,
                           accuracy: 0.0001)
        }
    }

    func testTheIdleBatchAlternatesWalk1AndWalk2() {
        let entries = ComplicationTimeline.entries(for: snapshot(pose: .idle), from: Fixture.morning)
        let frames = entries.map { entry in
            ComplicationPose.idle.stageFrames[entry.step % ComplicationPose.idle.stageFrames.count]
        }

        XCTAssertEqual(Array(frames.prefix(6)), [.walk1, .walk2, .walk1, .walk2, .walk1, .walk2])
        // And it never falls out of step across the whole horizon.
        for (index, frame) in frames.enumerated() {
            XCTAssertEqual(frame, index.isMultiple(of: 2) ? .walk1 : .walk2, "entry \(index)")
        }
    }

    func testTheBatchReloadsOneFrameAfterItsLastEntry() {
        let reload = ComplicationTimeline.reloadDate(for: snapshot(pose: .idle), from: Fixture.morning)
        let entries = ComplicationTimeline.entries(for: snapshot(pose: .idle), from: Fixture.morning)

        // t+300: the last entry (t+299) gets its full second before the batch is replaced.
        XCTAssertEqual(reload, Fixture.morning.addingTimeInterval(300))
        // And that is one `frameInterval` past the last entry whatever the two constants become.
        XCTAssertEqual(reload,
                       entries.last?.date.addingTimeInterval(ComplicationTimeline.frameInterval))
    }

    // MARK: - Suppression in held poses

    func testHeldPosesGetOneEntryAndNoAlternation() {
        // Sleeping, sick and dead are the three US-049 names. `messy` holds too — its frame is
        // `angry`, and the sheet has no second angry frame.
        for pose in [ComplicationPose.sleeping, .sick, .dead, .messy] {
            let entries = ComplicationTimeline.entries(for: snapshot(pose: pose), from: Fixture.morning)

            XCTAssertEqual(entries.count, 1, "\(pose) should not walk")
            XCTAssertEqual(entries.first?.step, 0, "\(pose)")
            XCTAssertFalse(pose.animates, "\(pose)")
            // One frame in the cycle means there is nothing for a step to advance to, whatever the
            // entry index — this is what actually stops a dead Digimon appearing to walk.
            XCTAssertEqual(pose.stageFrames, [pose.frame], "\(pose)")
        }
    }

    func testOnlyIdleAnimates() {
        // Total over the enum, so a pose added later cannot quietly default into walking.
        for pose in ComplicationPose.allCases {
            XCTAssertEqual(pose.animates, pose == .idle, "\(pose)")
        }
    }

    // MARK: - The whole timeline

    /// `ComplicationProvider.getTimeline` is a one-line hand-off to `ComplicationTimeline`, and
    /// calling it needs a `TimelineProviderContext`, which has no public initialiser and cannot be
    /// faked without undefined behaviour. So the assertion lands one level down, on the value the
    /// provider hands back verbatim.
    func testTheTimelineCarriesTheBatchAndItsReloadDate() {
        let timeline = ComplicationTimeline.timeline(for: snapshot(pose: .idle), from: Fixture.morning)

        XCTAssertEqual(timeline.entries.count, ComplicationTimeline.motionEntryCount)
        XCTAssertEqual(timeline.entries.map(\.step), Array(0..<ComplicationTimeline.motionEntryCount))
        // Every entry carries the SAME snapshot — only the step advances. The widget must never
        // invent state the app has not published.
        XCTAssertEqual(Set(timeline.entries.map(\.snapshot.pose)), [.idle])
    }

    func testTheTimelineHoldsOneEntryForASleepingDigimon() {
        let timeline = ComplicationTimeline.timeline(for: snapshot(pose: .sleeping), from: Fixture.morning)

        XCTAssertEqual(timeline.entries.count, 1)
        XCTAssertEqual(timeline.entries.first?.snapshot.pose, .sleeping)
        XCTAssertEqual(timeline.entries.first?.date, Fixture.morning)
    }

    /// A held pose still comes back in an hour, so a watch whose app has not woken does not sit on
    /// one entry forever.
    func testAHeldPoseReloadsOnTheHourlyFloor() {
        let reload = ComplicationTimeline.reloadDate(for: snapshot(pose: .sleeping), from: Fixture.morning)
        XCTAssertEqual(reload, Fixture.morning.addingTimeInterval(3600))
    }

    // MARK: - What the demo screen selects

    func testTheEntryShowingAtAGivenMomentIsTheLastOneDue() {
        let entries = ComplicationTimeline.entries(for: snapshot(pose: .idle), from: Fixture.morning)

        XCTAssertEqual(ComplicationTimeline.entry(at: Fixture.morning, in: entries)?.step, 0)
        // Nine-tenths of a second in, entry 1 is not due yet.
        XCTAssertEqual(ComplicationTimeline.entry(at: Fixture.morning.addingTimeInterval(0.9), in: entries)?.step, 0)
        XCTAssertEqual(ComplicationTimeline.entry(at: Fixture.morning.addingTimeInterval(1), in: entries)?.step, 1)
        XCTAssertEqual(ComplicationTimeline.entry(at: Fixture.morning.addingTimeInterval(12), in: entries)?.step, 12)
        // Past the horizon the last entry holds — which is exactly how running out of budget looks.
        XCTAssertEqual(ComplicationTimeline.entry(at: Fixture.morning.addingTimeInterval(9999), in: entries)?.step, 299)
        // Before the batch even starts, the first entry rather than nil.
        XCTAssertEqual(ComplicationTimeline.entry(at: Fixture.morning.addingTimeInterval(-60), in: entries)?.step, 0)
    }

    // MARK: - Drift guard

    /// `ComplicationPose` restates the idle cycle because the widget extension does not compile
    /// `DigimonSpriteView.swift`. Restated definitions drift; this is what stops it silently.
    func testTheComplicationIdleCycleMatchesTheAppsIdleAnimation() {
        XCTAssertEqual(ComplicationPose.idle.stageFrames, SpriteAnimation.idle.stageFrames)
        XCTAssertEqual(ComplicationPose.idle.eggFrames, SpriteAnimation.idle.eggFrames)
        // And the held poses borrow the app's own single-frame form.
        for pose in ComplicationPose.allCases where !pose.animates {
            XCTAssertEqual(pose.stageFrames, SpriteAnimation.still(pose.frame).stageFrames, "\(pose)")
        }
    }

}
