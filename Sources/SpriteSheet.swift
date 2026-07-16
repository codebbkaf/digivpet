import CoreGraphics
import Foundation

/// A frame of an animated stage sheet (48x64 = a 3x4 grid of 16x16 frames, row-major).
///
/// Raw values are the frame's index in the sheet, so the order of these cases is the sheet
/// layout itself and must not be reordered. Verified against the art, not just the xlsx:
/// `eat1` has an open mouth, `sleep1`/`sleep2` have closed eyes, `angry` has an angry brow.
enum SpriteFrame: Int, CaseIterable {
    case walk1 = 0
    case walk2 = 1
    case eat1 = 2
    case eat2 = 3
    case sleep1 = 4
    case sleep2 = 5
    case refuse = 6
    case happy = 7
    case angry = 8
    case hurt1 = 9
    case hurt2 = 10
    case attack = 11

    var sourceRect: CGRect { SpriteSheet.sourceRect(forIndex: rawValue) }
}

/// A frame of a Digitama sheet (48x16 = 3 frames).
///
/// Separate from `SpriteFrame` because an egg's frames are not a prefix of a stage sheet's:
/// egg index 2 is the hatch, where a stage sheet's index 2 is `eat1`. Sharing one enum would
/// let `sheet[.eat1]` silently hand back the hatch frame.
enum EggFrame: Int, CaseIterable {
    case idle = 0
    case wobble = 1
    /// Not a second wobble — the egg cracking open with the Digimon emerging.
    case hatch = 2

    var sourceRect: CGRect { SpriteSheet.sourceRect(forIndex: rawValue) }
}

/// The frames of one sprite sheet, cropped once at load.
///
/// `cropping(to:)` references the source sheet's backing buffer rather than copying pixels,
/// so holding all 12 crops costs about one decode. Build this once per Digimon (via
/// `SpriteSheetCache`) and index it per tick — never re-crop while animating.
struct SpriteSheet {
    static let frameSize = 16
    static let columns = 3

    /// Which layout a sheet turned out to be. Drives which frame enum can index it.
    enum Kind: Equatable {
        /// 48x64 — the 12 animation frames.
        case stage
        /// 48x16 — the 3 Digitama frames.
        case egg
    }

    let kind: Kind
    /// 12 frames for a stage sheet, 3 for an egg, in sheet order.
    let frames: [CGImage]

    /// Frame index -> source rect, row-major from the sheet's top-left.
    /// `cropping(to:)` uses a top-left origin, which matches the sheet's reading order.
    static func sourceRect(forIndex index: Int) -> CGRect {
        CGRect(
            x: (index % columns) * frameSize,
            y: (index / columns) * frameSize,
            width: frameSize,
            height: frameSize
        )
    }

    /// Crops a decoded sheet into its frames.
    ///
    /// Returns nil for any sheet that is not 48x64 or 48x16 rather than emitting garbage
    /// frames — the same validation the `cut_sprites.swift` dev tool applies.
    init?(sheet: CGImage) {
        let rows = sheet.height / Self.frameSize
        guard sheet.width == Self.frameSize * Self.columns,
              sheet.height % Self.frameSize == 0,
              rows == 4 || rows == 1
        else { return nil }

        var frames: [CGImage] = []
        frames.reserveCapacity(rows * Self.columns)
        for index in 0..<(rows * Self.columns) {
            guard let frame = sheet.cropping(to: Self.sourceRect(forIndex: index)) else { return nil }
            frames.append(frame)
        }

        self.kind = (rows == 1) ? .egg : .stage
        self.frames = frames
    }

    /// The animation frames of a stage sheet. Nil on an egg, which has none of them —
    /// so asking a Digitama for `.attack` yields a placeholder instead of a crash.
    subscript(frame: SpriteFrame) -> CGImage? {
        kind == .stage ? frames[frame.rawValue] : nil
    }

    /// The 3 Digitama frames. Nil on a stage sheet, whose first 3 frames are walk/eat.
    subscript(frame: EggFrame) -> CGImage? {
        kind == .egg ? frames[frame.rawValue] : nil
    }
}

/// Decodes each sprite sheet at most once and caches its cropped frames.
///
/// Both the decode and the 12 crops are paid on the first request for a Digimon; every later
/// request is a dictionary lookup. Failures are cached too, so a missing sprite does not
/// re-hit the disk on every animation tick.
final class SpriteSheetCache {
    static let shared = SpriteSheetCache()

    private struct Key: Hashable {
        let stage: String
        let name: String
    }

    private let decode: (String, String) -> CGImage?
    private var cache: [Key: SpriteSheet?] = [:]
    private let lock = NSLock()

    /// - Parameter decode: sheet decoder, injectable so tests can count decodes and supply
    ///   synthetic sheets. Defaults to loading from the bundled sprite folder.
    init(decode: @escaping (String, String) -> CGImage? = { SpriteLoader.loadSheet(stage: $0, name: $1) }) {
        self.decode = decode
    }

    /// The cropped frames for a Digimon, or nil if its sheet is missing or malformed.
    func sheet(stage: String, name: String) -> SpriteSheet? {
        let key = Key(stage: stage, name: name)
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let sheet = decode(stage, name).flatMap(SpriteSheet.init(sheet:))
        cache[key] = sheet
        return sheet
    }
}
