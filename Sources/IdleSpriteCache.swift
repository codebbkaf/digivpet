import CoreGraphics
import Foundation
import SwiftUI

/// Decodes the single 16x16 idle sprite that represents a Digimon in the Dex.
///
/// Separate from `SpriteSheetCache` because the Dex draws a DIFFERENT asset: the flat
/// `Idle Frame Only` folder holds one 16x16 PNG per Digimon, which `SpriteSheet` rejects outright
/// (it only accepts 48x64 and 48x16). Keeping the two caches apart also keeps the main screen's
/// 12-frame sheets out of memory when all the Dex needs is one frame each.
///
/// Nothing is decoded until a sprite is actually asked for, which is what makes a 22-entry — and
/// eventually 865-entry — grid affordable: a `LazyVGrid` only builds the cells it shows, so only
/// those cells reach this cache. Results are memoised, misses included, so scrolling a Digimon
/// back into view is a dictionary lookup rather than another file open.
final class IdleSpriteCache {
    static let shared = IdleSpriteCache()

    private struct Key: Hashable {
        let stage: String
        let name: String
    }

    private let decode: (String, String) -> CGImage?
    private var cache: [Key: CGImage?] = [:]
    private let lock = NSLock()

    /// - Parameter decode: folder + filename -> decoded PNG. Injectable so a test can count
    ///   decodes and hand back synthetic images; defaults to the bundled sprite folder.
    init(decode: @escaping (String, String) -> CGImage? = { SpriteLoader.loadSheet(stage: $0, name: $1) }) {
        self.decode = decode
    }

    /// This Digimon's idle frame, or nil when neither art source resolves.
    ///
    /// - Parameters:
    ///   - stage: the node's stage folder, used only for the fallback below.
    ///   - name: the node's `spriteFile`, which names the same PNG in both folders.
    func image(stage: String, name: String) -> CGImage? {
        let key = Key(stage: stage, name: name)
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let image = resolve(stage: stage, name: name)
        cache[key] = image
        return image
    }

    /// Prefers the flat idle folder, and falls back to frame 0 of the animated stage sheet.
    ///
    /// The fallback exists for the Digitama, which have no entry in `Idle Frame Only` at all — the
    /// folder covers hatched Digimon only. Their sheet's frame 0 IS the egg's idle frame (US-004),
    /// so the fallback draws the same thing the folder would have, not an arbitrary pose.
    private func resolve(stage: String, name: String) -> CGImage? {
        if let flat = decode(SpriteLoader.idleFrameOnlyFolder, name),
           flat.width == SpriteSheet.frameSize, flat.height == SpriteSheet.frameSize {
            return flat
        }
        return decode(stage, name).flatMap(SpriteSheet.init(sheet:))?.frames.first
    }
}

/// One Digimon's still idle frame, at Dex scale.
///
/// Unlike `DigimonSpriteView` this never animates: a grid of two-frame loops would run dozens of
/// `TimelineView` schedules at once for art the user is scrolling past.
struct IdleSpriteView: View {
    let stage: String
    let name: String
    /// Screen points per sprite pixel.
    var scale: CGFloat = 2
    var cache: IdleSpriteCache = .shared

    private var side: CGFloat { CGFloat(SpriteSheet.frameSize) * scale }

    var body: some View {
        Group {
            if let image = cache.image(stage: stage, name: name) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
            } else {
                // Missing art, which is not the same as an undiscovered Digimon — the Dex draws
                // that case itself, and deliberately differently, so the two never get confused.
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.tertiary, lineWidth: 1)
            }
        }
        .frame(width: side, height: side)
    }
}
