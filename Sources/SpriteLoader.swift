import CoreGraphics
import Foundation
import ImageIO

/// Loads Digimon sprite sheets from the bundled `16x16 Digimon Sprites` folder reference.
///
/// Sheets are addressed by stage subfolder + filename, which is why the sprites ship as a
/// folder reference rather than an asset catalog: an asset catalog would flatten the stage
/// structure and lose the filenames the evolution graph refers to.
///
/// This type only decodes whole sheets. Slicing a sheet into its 12 frames happens in
/// `SpriteFrame` (US-004), which decodes each sheet once and caches the cropped frames.
enum SpriteLoader {
    /// Root of the bundled sprite folder reference.
    static let spriteRoot = "16x16 Digimon Sprites"

    /// URL of a sprite sheet, or nil when no such file is bundled.
    static func url(stage: String, name: String, in bundle: Bundle = .main) -> URL? {
        // `url(forResource:)` treats an empty name like nil and returns an arbitrary PNG from
        // the directory, so an empty spriteFile would silently load the wrong Digimon.
        guard !name.isEmpty, !stage.isEmpty else { return nil }
        return bundle.url(forResource: name, withExtension: "png", subdirectory: "\(spriteRoot)/\(stage)")
    }

    /// Decodes a sprite sheet. Returns nil for a missing or undecodable file — never crashes,
    /// so a bad graph edge degrades to a placeholder instead of taking the app down.
    static func loadSheet(stage: String, name: String, in bundle: Bundle = .main) -> CGImage? {
        guard let url = url(stage: stage, name: name, in: bundle),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
