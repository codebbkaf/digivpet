import CoreGraphics
import SwiftUI

/// What a Digimon is doing on screen: a named loop, or a single frame held still.
///
/// A pose is modelled as a one-frame loop rather than a separate type, so every screen drives
/// `DigimonSpriteView` the same way whether the art moves or not.
/// `Hashable` so a caller can hold a SET of poses — `MainScreenModel.restingPoses` is one, and a
/// set says "any resting pose" far more legibly than a chain of `==`.
enum SpriteAnimation: Hashable {
    /// walk1 -> walk2 on a stage sheet; idle -> wobble on a Digitama.
    case idle
    case eat
    case sleep
    case hurt
    /// The SAME hurt frames as `.hurt`, held far longer each (US-068).
    ///
    /// A separate case rather than a parameter on `.hurt`, because the two mean different things and
    /// only the cadence tells them apart on screen: `.hurt` is the flinch of being struck in a
    /// battle, `.sick` is an ailing Digimon labouring on the spot. Sharing the art is deliberate —
    /// the sheet has no illness frames, and hurt is what "unwell" looks like in this pack.
    case sick
    /// One frame, held. Refuse, attack, happy and angry are poses, not loops.
    case still(SpriteFrame)

    /// How long each frame is held, for every loop but `.sick`. The V-Pet cadence comes from all of
    /// them sharing this one value.
    static let frameDuration: TimeInterval = 0.5

    /// How long a SICK Digimon holds each of its two frames: three times the normal beat.
    ///
    /// Slower than `frameDuration` on purpose and by a wide margin — a hurt loop at the battle's
    /// pace reads as being hit over and over, which is a different story from being ill.
    static let sickFrameDuration: TimeInterval = 1.5

    /// How long each frame of THIS loop is held.
    var frameDuration: TimeInterval {
        switch self {
        case .sick: return Self.sickFrameDuration
        case .idle, .eat, .sleep, .hurt, .still: return Self.frameDuration
        }
    }

    /// The loop's frames on a 48x64 stage sheet.
    var stageFrames: [SpriteFrame] {
        switch self {
        case .idle: return [.walk1, .walk2]
        case .eat: return [.eat1, .eat2]
        case .sleep: return [.sleep1, .sleep2]
        case .hurt, .sick: return [.hurt1, .hurt2]
        case .still(let frame): return [frame]
        }
    }

    /// The loop's frames on a 48x16 Digitama sheet, which only has an idle wobble — an egg
    /// cannot eat, sleep or be hurt, so those loops have no art and yield a placeholder.
    ///
    /// Deliberately never falls back to `stageFrames`: an egg's index 2 is the hatch, so
    /// reusing walk1/walk2 indices would draw the egg cracking open as part of its idle.
    var eggFrames: [EggFrame] {
        switch self {
        case .idle: return [.idle, .wobble]
        case .eat, .sleep, .hurt, .sick, .still: return []
        }
    }

    /// This loop's frames from a decoded sheet, empty when the sheet has no art for it.
    func frames(from sheet: SpriteSheet) -> [CGImage] {
        switch sheet.kind {
        case .stage: return stageFrames.compactMap { sheet[$0] }
        case .egg: return eggFrames.compactMap { sheet[$0] }
        }
    }

    /// Which frame of a `count`-frame loop is showing at `date`.
    ///
    /// Derived from wall-clock time rather than a stored counter, so a view rebuilt mid-loop
    /// picks up where the animation actually is instead of snapping back to frame 0.
    static func frameIndex(at date: Date, count: Int, duration: TimeInterval = frameDuration) -> Int {
        guard count > 1 else { return 0 }
        let tick = Int((date.timeIntervalSinceReferenceDate / duration).rounded(.down))
        // Dates before the reference date tick negative, where % alone would too.
        return ((tick % count) + count) % count
    }

    /// The loop a Digimon rests on given its health and whether it is in its sleep window.
    ///
    /// A pure function, taking the two facts it depends on rather than reading a model, so US-068's
    /// "the animation choice is a pure function of healthStatus" can be asserted with no store, no
    /// clock and no view. `MainScreenModel.restingAnimation` is a call to this and nothing else.
    ///
    /// SICKNESS WINS OVER SLEEP: an ill Digimon looks ill whatever the hour, because the illness is
    /// the thing the user has to act on and the sleep loop would hide it until morning.
    static func resting(for health: HealthStatus, isAsleep: Bool) -> SpriteAnimation {
        switch health {
        case .dead: return .still(.hurt2)
        case .sick: return .sick
        case .healthy: return isAsleep ? .sleep : .idle
        }
    }
}

/// Renders one Digimon's sprite, animating it if the pose is a loop.
///
/// Frames come from `SpriteSheetCache`, so the sheet is decoded and cropped once no matter how
/// many of these are on screen or how long they animate.
struct DigimonSpriteView: View {
    /// Stage subfolder and sheet filename, as the evolution graph names them.
    let stage: String
    let name: String
    var animation: SpriteAnimation = .idle
    /// Screen points per sprite pixel. 16x16 art is unreadable at 1x on a watch.
    var scale: CGFloat = 4
    /// Points to shift the sprite horizontally from where it was laid out; US-037's wander.
    ///
    /// An `.offset`, deliberately, not padding or a spacer: offset moves the drawing WITHOUT
    /// re-running layout, so a walking Digimon cannot shove the name above it or the caption below
    /// it around as it goes.
    var offset: CGFloat = 0
    /// Mirrors the sprite horizontally. Every sheet in the pack is drawn facing LEFT, so this is
    /// what a caller sets to show the Digimon walking right.
    var flipped: Bool = false
    var cache: SpriteSheetCache = .shared

    private var side: CGFloat { CGFloat(SpriteSheet.frameSize) * scale }

    var body: some View {
        let frames = cache.sheet(stage: stage, name: name).map { animation.frames(from: $0) } ?? []

        Group {
            if frames.isEmpty {
                placeholder
            } else if frames.count == 1 {
                // A held pose needs no schedule; a TimelineView here would redraw forever
                // to show the same frame.
                image(frames[0])
            } else {
                // The loop's OWN cadence, not the shared one: a sick Digimon labours through the
                // same two frames at a third of the speed, and both the schedule and the index have
                // to agree about that or the view would redraw three times to show one frame.
                TimelineView(.periodic(from: .now, by: animation.frameDuration)) { context in
                    image(frames[SpriteAnimation.frameIndex(at: context.date,
                                                            count: frames.count,
                                                            duration: animation.frameDuration)])
                }
            }
        }
        .frame(width: side, height: side)
        .offset(x: offset)
    }

    private func image(_ frame: CGImage) -> some View {
        Image(decorative: frame, scale: 1)
            // Stays on the Image, ahead of the mirroring below, so `.interpolation(.none)` is what
            // governs how these 16 pixels are sampled no matter which way the sprite faces. Pixel
            // art smoothed on one heading and crisp on the other would be worse than either.
            .interpolation(.none)
            .resizable()
            // A mirror, not a resize: x of exactly -1 maps every source pixel onto exactly one
            // destination pixel, so there is nothing for a filter to blur even where one applies.
            .scaleEffect(x: flipped ? -1 : 1)
    }

    /// Shown when the sheet is missing, malformed, or has no art for this loop. A visible gap
    /// beats a crash, and beats silently drawing a frame that means something else.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(.secondary, lineWidth: 1)
            .overlay {
                Text("?")
                    .font(.system(size: side / 2, weight: .bold))
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview {
    VStack {
        DigimonSpriteView(stage: "Child", name: "Agumon")
        DigimonSpriteView(stage: "Digitama", name: "Agu_Digitama", scale: 2)
        DigimonSpriteView(stage: "Child", name: "NotADigimon", scale: 2)
    }
}
