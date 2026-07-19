#!/usr/bin/env swift

// Builds the 1024x1024 App Icon from `Resources/digi_icon.png`.
//
// Three things the icon pipeline has to get right, none of which `sips` does:
//   - Nearest-neighbour scaling. The source is 16x16-style pixel art; a smoothed upscale is a bug
//     here for the same reason `.interpolation(.none)` is mandatory on sprites.
//   - An integer scale factor. 1024 is not a multiple of 216, so scaling straight to 1024 would
//     land pixel edges on fractional boundaries and shimmer. We scale 4x to 864x856 and centre
//     that on the canvas instead.
//   - No alpha channel. Apple rejects app icons containing transparency, so the artwork is
//     composited onto an opaque background sampled from the source's own corner pixel — that way
//     the padding is invisible rather than a black or white frame around the art.
//
// Run from the repo root: swift scripts/make_appicon.swift

import AppKit
import CoreGraphics
import Foundation

let side = 1024
let src = "Resources/digi_icon.png"
let dst = "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

guard let data = NSData(contentsOfFile: src),
      let source = CGImageSourceCreateWithData(data, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("error: cannot read \(src)\n", stderr)
    exit(1)
}

// Sample the top-left pixel for the background. It is the art's own matte, so the padded region
// reads as part of the icon instead of a border.
func cornerColor(of image: CGImage) -> (CGFloat, CGFloat, CGFloat) {
    var px = [UInt8](repeating: 0, count: 4)
    let space = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8,
                              bytesPerRow: 4, space: space, bitmapInfo: info) else {
        return (0.13, 0.13, 0.18)
    }
    ctx.draw(image, in: CGRect(x: 0, y: -CGFloat(image.height - 1),
                               width: CGFloat(image.width), height: CGFloat(image.height)))
    // A transparent corner tells us nothing; fall back to the dark navy the art is drawn against.
    guard px[3] > 0 else { return (0.13, 0.13, 0.18) }
    return (CGFloat(px[0]) / 255, CGFloat(px[1]) / 255, CGFloat(px[2]) / 255)
}

let (r, g, b) = cornerColor(of: image)

let space = CGColorSpaceCreateDeviceRGB()
// .noneSkipLast: opaque output, no alpha channel in the written file.
guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fputs("error: cannot create canvas\n", stderr)
    exit(1)
}

ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

let scale = min(side / image.width, side / image.height)  // integer factor, 4 for a 216x214 source
let w = image.width * scale
let h = image.height * scale
ctx.interpolationQuality = .none
ctx.draw(image, in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))

guard let out = ctx.makeImage() else {
    fputs("error: cannot render\n", stderr)
    exit(1)
}

try? FileManager.default.createDirectory(atPath: (dst as NSString).deletingLastPathComponent,
                                         withIntermediateDirectories: true)
guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dst) as CFURL,
                                                 "public.png" as CFString, 1, nil) else {
    fputs("error: cannot open \(dst)\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("error: cannot write \(dst)\n", stderr)
    exit(1)
}

print("wrote \(dst) — \(side)x\(side), art scaled \(scale)x to \(w)x\(h)")
