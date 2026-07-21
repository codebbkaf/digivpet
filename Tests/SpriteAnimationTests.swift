import CoreGraphics
import Foundation
import XCTest

@testable import DigiVPet

final class SpriteAnimationTests: XCTestCase {
    // MARK: - Loop frames

    func testNamedLoopsCycleTheirTwoFrames() {
        XCTAssertEqual(SpriteAnimation.idle.stageFrames, [.walk1, .walk2])
        XCTAssertEqual(SpriteAnimation.eat.stageFrames, [.eat1, .eat2])
        XCTAssertEqual(SpriteAnimation.sleep.stageFrames, [.sleep1, .sleep2])
        XCTAssertEqual(SpriteAnimation.hurt.stageFrames, [.hurt1, .hurt2])
        XCTAssertEqual(SpriteAnimation.still(.refuse).stageFrames, [.refuse])
    }

    /// The loops must resolve to the actual art at those indices, not just to the right enum
    /// cases — identity against the cached crops proves the view draws walk1/walk2 for idle.
    func testIdleLoopResolvesToTheWalkFramesOfTheSheet() throws {
        let sheet = try XCTUnwrap(SpriteSheetCache.shared.sheet(stage: "Child", name: "Agumon"))
        let frames = SpriteAnimation.idle.frames(from: sheet)

        XCTAssertEqual(frames.count, 2)
        XCTAssertTrue(frames[0] === sheet[.walk1])
        XCTAssertTrue(frames[1] === sheet[.walk2])
    }

    // MARK: - Eggs

    /// An egg's idle is its own idle -> wobble. It must never borrow walk1/walk2, whose
    /// indices on a 48x16 sheet land on idle and the HATCH.
    func testEggIdleUsesEggFramesAndNotTheWalkIndices() throws {
        let egg = try XCTUnwrap(SpriteSheetCache.shared.sheet(stage: "Digitama", name: "Agu_Digitama"))
        let frames = SpriteAnimation.idle.frames(from: egg)

        XCTAssertEqual(frames.count, 2)
        XCTAssertTrue(frames[0] === egg[EggFrame.idle])
        XCTAssertTrue(frames[1] === egg[EggFrame.wobble])
        XCTAssertFalse(frames.contains { $0 === egg.frames[EggFrame.hatch.rawValue] })
    }

    /// An egg has no eat/sleep/hurt/pose art at all, so those resolve to nothing and the view
    /// shows its placeholder rather than falling back to a frame that means something else.
    func testEggHasNoArtForTheOtherLoops() throws {
        let egg = try XCTUnwrap(SpriteSheetCache.shared.sheet(stage: "Digitama", name: "Agu_Digitama"))

        XCTAssertTrue(SpriteAnimation.eat.frames(from: egg).isEmpty)
        XCTAssertTrue(SpriteAnimation.sleep.frames(from: egg).isEmpty)
        XCTAssertTrue(SpriteAnimation.hurt.frames(from: egg).isEmpty)
        XCTAssertTrue(SpriteAnimation.still(.attack).frames(from: egg).isEmpty)
    }

    // MARK: - Timing

    func testFrameDurationIs500ms() {
        XCTAssertEqual(SpriteAnimation.frameDuration, 0.5)
    }

    /// The loop advances one frame per 500ms and wraps, without waiting real time.
    func testFrameIndexAdvancesEvery500msAndWraps() {
        func index(atSecond second: TimeInterval) -> Int {
            SpriteAnimation.frameIndex(
                at: Date(timeIntervalSinceReferenceDate: second),
                count: 2
            )
        }

        XCTAssertEqual(index(atSecond: 0.0), 0)
        XCTAssertEqual(index(atSecond: 0.49), 0)
        XCTAssertEqual(index(atSecond: 0.5), 1)
        XCTAssertEqual(index(atSecond: 0.99), 1)
        XCTAssertEqual(index(atSecond: 1.0), 0)
        XCTAssertEqual(index(atSecond: 1.5), 1)
    }

    /// A held pose has one frame; the index must stay put rather than divide by zero or wrap
    /// off the end.
    func testSingleFrameAndEmptyLoopsStayAtIndexZero() {
        let now = Date(timeIntervalSinceReferenceDate: 7.3)
        XCTAssertEqual(SpriteAnimation.frameIndex(at: now, count: 1), 0)
        XCTAssertEqual(SpriteAnimation.frameIndex(at: now, count: 0), 0)
    }

    /// Dates before the 2001 reference date tick negative, where a bare `%` would return a
    /// negative index and crash the frame lookup.
    func testFrameIndexIsNeverNegative() {
        for second in stride(from: -3.0, through: 0.0, by: 0.25) {
            let index = SpriteAnimation.frameIndex(at: Date(timeIntervalSinceReferenceDate: second), count: 2)
            XCTAssertTrue(index == 0 || index == 1, "index \(index) out of range at \(second)s")
        }
    }

    // MARK: - US-068: the sick loop

    /// AC1's first half: `.sick` really is the hurt loop, frames 9 <-> 10, and not some third pair.
    func testTheSickLoopIsTheHurtLoopsFrames() {
        XCTAssertEqual(SpriteAnimation.sick.stageFrames, [.hurt1, .hurt2])
        XCTAssertEqual(SpriteAnimation.sick.stageFrames.map(\.rawValue), [9, 10])
        XCTAssertEqual(SpriteAnimation.sick.stageFrames, SpriteAnimation.hurt.stageFrames)
    }

    /// AC1's second half — the whole point of the story. Same art as the battle's flinch, held
    /// strictly longer, which is the only thing on screen telling "ailing" from "being struck".
    func testTheSickLoopIsSlowerThanTheBattleHurtLoop() {
        XCTAssertGreaterThan(SpriteAnimation.sick.frameDuration, SpriteAnimation.hurt.frameDuration)
        XCTAssertEqual(SpriteAnimation.sick.frameDuration, 1.5)
        XCTAssertEqual(SpriteAnimation.hurt.frameDuration, SpriteAnimation.frameDuration)
    }

    /// Every other loop keeps the shared V-Pet beat — the slow cadence is `.sick`'s alone, so AC3's
    /// "a healthy Digimon is visually unchanged" holds at the timing layer too.
    func testEveryOtherLoopKeepsTheSharedCadence() {
        for animation: SpriteAnimation in [.idle, .eat, .sleep, .hurt, .still(.attack)] {
            XCTAssertEqual(animation.frameDuration, 0.5, "\(animation) must keep the shared beat")
        }
    }

    /// The slower cadence has to reach the INDEX as well as the schedule, or the sick sprite would
    /// be redrawn on its own slow tick while still stepping at the walk's speed.
    func testTheSickLoopAdvancesOnItsOwnCadence() {
        func index(atSecond second: TimeInterval) -> Int {
            SpriteAnimation.frameIndex(at: Date(timeIntervalSinceReferenceDate: second),
                                       count: 2,
                                       duration: SpriteAnimation.sick.frameDuration)
        }

        XCTAssertEqual(index(atSecond: 0.0), 0)
        // Where the battle loop would already have flipped twice, the sick one has not moved.
        XCTAssertEqual(index(atSecond: 1.49), 0)
        XCTAssertEqual(index(atSecond: 1.5), 1)
        XCTAssertEqual(index(atSecond: 3.0), 0)
    }

    /// An egg still has no illness art, so a sick Digitama draws the placeholder rather than
    /// borrowing indices 9 and 10 — which on a 48x16 sheet do not exist at all.
    func testAnEggHasNoArtForTheSickLoop() throws {
        let egg = try XCTUnwrap(SpriteSheetCache.shared.sheet(stage: "Digitama", name: "Agu_Digitama"))
        XCTAssertTrue(SpriteAnimation.sick.frames(from: egg).isEmpty)
    }

    // MARK: - US-102: poses are two-frame loops

    /// The whole story in one assertion: a pose is its own frame paired with walk1, in that order.
    /// Pose first, because a refusal that stepped before it shook its head would read backwards.
    func testAPoseIsItsFramePairedWithWalk1() {
        for frame: SpriteFrame in [.refuse, .happy, .angry, .attack] {
            XCTAssertEqual(SpriteAnimation.pose(frame).stageFrames, [frame, .walk1],
                           "\(frame) must loop against walk1")
        }
    }

    /// `.still(_)` stays a held single frame — it is still what the dead Digimon and the battle
    /// result screen use, and a corpse must not twitch.
    func testStillIsUnchangedAndStillOneFrame() {
        for frame: SpriteFrame in [.refuse, .happy, .angry, .attack, .hurt2] {
            XCTAssertEqual(SpriteAnimation.still(frame).stageFrames, [frame])
        }
    }

    /// Asking to animate walk1 against walk1 is harmless rather than a special case needing a
    /// guard: two identical frames animate as a still.
    func testPosingWalk1AgainstItselfNeedsNoGuard() {
        XCTAssertEqual(SpriteAnimation.pose(.walk1).stageFrames, [.walk1, .walk1])
    }

    func testAPoseKeepsTheSharedVPetBeat() {
        for frame: SpriteFrame in [.refuse, .happy, .angry, .attack] {
            XCTAssertEqual(SpriteAnimation.pose(frame).frameDuration, SpriteAnimation.frameDuration)
        }
    }

    /// AC: on a synthetic 48x64 stage sheet each pose resolves to two DISTINCT crops, the first
    /// being the pose's own frame. Synthetic rather than Agumon's so every cell is a known,
    /// different colour — identical art would make "distinct" impossible to tell from a stuck rect.
    func testEachPoseResolvesToTwoDistinctFramesOfAStageSheet() throws {
        let sheet = try XCTUnwrap(SpriteSheet(sheet: try checkerStageSheet()))

        for frame: SpriteFrame in [.refuse, .happy, .angry, .attack] {
            let frames = SpriteAnimation.pose(frame).frames(from: sheet)

            XCTAssertEqual(frames.count, 2, "\(frame)")
            XCTAssertTrue(frames[0] === sheet[frame], "\(frame) must be drawn first")
            XCTAssertTrue(frames[1] === sheet[.walk1], "\(frame) must be followed by walk1")
            XCTAssertNotEqual(try pixels(of: frames[0]), try pixels(of: frames[1]),
                              "\(frame) and walk1 must be different art")
        }
    }

    /// A two-frame pose loop alternates on the shared beat, exactly as the eat and sleep loops do.
    func testAPoseLoopAlternatesOnEveryHalfSecond() {
        let count = SpriteAnimation.pose(.happy).stageFrames.count
        let indices = [0.0, 0.5, 1.0, 1.5].map { second in
            SpriteAnimation.frameIndex(at: Date(timeIntervalSinceReferenceDate: second),
                                       count: count,
                                       duration: SpriteAnimation.pose(.happy).frameDuration)
        }

        XCTAssertEqual(indices, [0, 1, 0, 1])
    }

    /// An egg cannot look happy or attack, so a pose falls through to the placeholder exactly as
    /// `.still` already does — never to indices 6-11, which on a 48x16 sheet do not exist.
    func testAnEggHasNoArtForAPose() throws {
        let egg = try XCTUnwrap(SpriteSheetCache.shared.sheet(stage: "Digitama", name: "Agu_Digitama"))

        for frame: SpriteFrame in [.refuse, .happy, .angry, .attack, .walk1] {
            XCTAssertTrue(SpriteAnimation.pose(frame).eggFrames.isEmpty, "\(frame)")
            XCTAssertTrue(SpriteAnimation.pose(frame).frames(from: egg).isEmpty, "\(frame)")
        }
    }

    /// `restingPoses` is a `Set<SpriteAnimation>`, so the new case must not have cost the enum its
    /// `Hashable` conformance — and a pose must not collide with the `.still` of the same frame.
    func testPosesRemainHashableAndDistinctFromStills() {
        let poses: Set<SpriteAnimation> = [.idle, .sleep, .sick, .still(.hurt2),
                                           .pose(.happy), .pose(.attack)]

        XCTAssertTrue(poses.contains(.pose(.happy)))
        XCTAssertFalse(poses.contains(.pose(.refuse)))
        XCTAssertFalse(poses.contains(.still(.happy)))
        XCTAssertNotEqual(SpriteAnimation.pose(.happy), SpriteAnimation.still(.happy))
    }

    // MARK: - US-068 AC5: the resting pose is a pure function of health

    /// No store, no clock, no view: the four answers, from the two inputs, in one place.
    func testTheRestingLoopIsDecidedByHealthAndTheSleepWindowAlone() {
        XCTAssertEqual(SpriteAnimation.resting(for: .sick, isAsleep: false), .sick)
        XCTAssertEqual(SpriteAnimation.resting(for: .healthy, isAsleep: false), .idle)
        XCTAssertEqual(SpriteAnimation.resting(for: .healthy, isAsleep: true), .sleep)
        XCTAssertEqual(SpriteAnimation.resting(for: .dead, isAsleep: false), .still(.hurt2))
    }

    /// Sickness outranks the sleep window: an ill Digimon looks ill at 3am too, because the illness
    /// is the thing the user has to act on and the sleep loop would hide it until morning.
    func testSicknessOutranksTheSleepWindow() {
        XCTAssertEqual(SpriteAnimation.resting(for: .sick, isAsleep: true), .sick)
        XCTAssertEqual(SpriteAnimation.resting(for: .dead, isAsleep: true), .still(.hurt2))
    }

    /// Being alive and well is the ONLY thing that walks. Stated as a sweep over every status so a
    /// status added later cannot quietly start pacing about while it is unwell.
    func testOnlyAHealthyAwakeDigimonWalks() {
        for health in HealthStatus.allCases {
            for isAsleep in [true, false] {
                let walks = SpriteAnimation.resting(for: health, isAsleep: isAsleep) == .idle
                XCTAssertEqual(walks, health == .healthy && !isAsleep,
                               "\(health), asleep: \(isAsleep)")
            }
        }
    }

    // MARK: - Helpers

    /// A 48x64 stage sheet whose twelve 16x16 cells are each a different shade, so a crop can be
    /// told from its neighbour by pixels alone.
    private func checkerStageSheet() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 48,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 48 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for frame in SpriteFrame.allCases {
            let shade = CGFloat(frame.rawValue) / CGFloat(SpriteFrame.allCases.count)
            context.setFillColor(CGColor(red: shade, green: 1 - shade, blue: 0.5, alpha: 1))
            context.fill(frame.sourceRect)
        }
        return try XCTUnwrap(context.makeImage())
    }

    /// Cropped frames share the sheet's backing buffer, so their raw data provider is the whole
    /// sheet — they have to be drawn to be compared.
    private func pixels(of image: CGImage) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(context.data)
        return Data(bytes: data, count: image.width * image.height * 4)
    }
}
