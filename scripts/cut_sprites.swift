#!/usr/bin/env swift
//
// cut_sprites.swift — slice Digimon V-Pet sprite sheets into individual frames.
//
// Sheet layout (verified against LCD Checklist.xlsx):
//   Stage sheets are 48x64 = a 3-column x 4-row grid of 16x16 frames = 12 frames,
//   in row-major order:
//     01 walk1   02 walk2   03 eat1
//     04 eat2    05 sleep1  06 sleep2
//     07 refuse  08 happy   09 angry
//     10 hurt1   11 hurt2   12 attack
//
//   Digitama (egg) sheets are 48x16 = 3 frames of 16x16 (egg1..egg3).
//
// Usage:
//   swift scripts/cut_sprites.swift --demo    # 3 Digimon per stage (the 3 seed lines)
//   swift scripts/cut_sprites.swift --all     # every animated sheet in every stage
//
// Output: sprites_cut/<Stage>/<Name>/01_walk1.png ...
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let frameSize = 16
let columns = 3

let stageFrameNames = [
    "walk1", "walk2", "eat1",
    "eat2", "sleep1", "sleep2",
    "refuse", "happy", "angry",
    "hurt1", "hurt2", "attack",
]
// Verified by inspecting the cut output: frame 3 is not a wobble — it is the egg
// cracking open with the Digimon emerging. That is the hatch animation (US-011).
let eggFrameNames = ["idle", "wobble", "hatch"]

/// The 3 seed evolution lines from the PRD (US-007). Chosen so the demo cut
/// yields three complete, fully-animated Agumon / Gabumon / Palmon chains.
let demoSelection: [(stage: String, names: [String])] = [
    ("Digitama", ["Agu_Digitama", "Gabu_Digitama", "Pal_Digitama"]),
    ("Baby I", ["Botamon", "Punimon", "Yuramon"]),
    ("Baby II", ["Koromon", "Tsunomon", "Tanemon"]),
    ("Child", ["Agumon", "Gabumon", "Palmon"]),
    ("Adult", ["Greymon", "Garurumon", "Togemon"]),
    ("Perfect", ["MetalGreymon", "WereGarurumon", "Lilimon"]),
    ("Ultimate-Super Ultimate", ["WarGreymon", "MetalGarurumon", "Rosemon"]),
]

let allStages = [
    "Digitama", "Baby I", "Baby II", "Child",
    "Adult", "Perfect", "Ultimate-Super Ultimate",
]

let spriteRoot = "16x16 Digimon Sprites"
let outputRoot = "sprites_cut"

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return image
}

func writePNG(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

struct CutResult {
    var written = 0
    var skipped: [String] = []
    var failed: [String] = []
}

/// Slice one sheet into its frames. Returns the number of frames written.
@discardableResult
func cut(sheetPath: String, stage: String, name: String, into result: inout CutResult) -> Int {
    guard let image = loadImage(sheetPath) else {
        result.failed.append("\(stage)/\(name): could not decode")
        return 0
    }

    let width = image.width
    let height = image.height
    let rows = height / frameSize

    // Validate the sheet is a shape we understand rather than emitting garbage frames.
    guard width == frameSize * columns, height % frameSize == 0, rows == 4 || rows == 1 else {
        result.failed.append("\(stage)/\(name): unexpected size \(width)x\(height) (expected 48x64 or 48x16)")
        return 0
    }

    let names = (rows == 1) ? eggFrameNames : stageFrameNames
    let outDir = "\(outputRoot)/\(stage)/\(name)"
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

    var written = 0
    for index in 0..<(rows * columns) {
        // Row-major: x = (i % 3) * 16, y = (i / 3) * 16. CGImage.cropping uses a
        // top-left origin, which matches the sheet's reading order directly.
        let rect = CGRect(
            x: (index % columns) * frameSize,
            y: (index / columns) * frameSize,
            width: frameSize,
            height: frameSize
        )
        guard let frame = image.cropping(to: rect) else {
            result.failed.append("\(stage)/\(name): crop failed at frame \(index + 1)")
            continue
        }
        let label = String(format: "%02d_%@", index + 1, names[index])
        if writePNG(frame, to: "\(outDir)/\(label).png") {
            written += 1
        } else {
            result.failed.append("\(stage)/\(name): write failed for \(label)")
        }
    }
    return written
}

// MARK: - Run

let args = CommandLine.arguments
let mode = args.contains("--all") ? "all" : "demo"

var result = CutResult()
var sheetCount = 0

func process(stage: String, names: [String]) {
    for name in names {
        let path = "\(spriteRoot)/\(stage)/\(name).png"
        guard FileManager.default.fileExists(atPath: path) else {
            result.skipped.append("\(stage)/\(name): no such file")
            continue
        }
        let n = cut(sheetPath: path, stage: stage, name: name, into: &result)
        if n > 0 {
            sheetCount += 1
            result.written += n
        }
    }
}

if mode == "demo" {
    print("Cutting DEMO set (3 Digimon per stage — the 3 seed evolution lines)\n")
    for entry in demoSelection {
        process(stage: entry.stage, names: entry.names)
    }
} else {
    print("Cutting ALL animated sheets\n")
    for stage in allStages {
        let dir = "\(spriteRoot)/\(stage)"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let names = files.filter { $0.hasSuffix(".png") }.map { String($0.dropLast(4)) }.sorted()
        process(stage: stage, names: names)
    }
}

print("Sheets cut:    \(sheetCount)")
print("Frames written: \(result.written)")

if !result.skipped.isEmpty {
    print("\nSkipped (\(result.skipped.count)):")
    for s in result.skipped.prefix(20) { print("  - \(s)") }
}
if !result.failed.isEmpty {
    print("\nFAILED (\(result.failed.count)):")
    for f in result.failed.prefix(20) { print("  - \(f)") }
    exit(1)
}
print("\nOutput: \(outputRoot)/")
