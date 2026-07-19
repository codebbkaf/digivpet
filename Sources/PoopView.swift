import SwiftUI

/// One poop, drawn in SwiftUI rather than sliced from a sheet.
///
/// **There is no poop sprite in the asset pack.** Every one of the 865 files is a Digimon, so there
/// is nothing to reference and inventing a `spriteFile` path would be a broken bundle reference that
/// only shows up as a blank square at runtime. Three stacked ellipses, widest at the base, is the
/// classic V-Pet coil and reads at 8pt where anything more detailed would be mud.
///
/// Sized in points rather than in sprite pixels because it is NOT pixel art — it is a vector shape
/// standing in for one, so it has no pixel grid to line up with and nothing to gain from
/// `.interpolation(.none)`. The size is picked to sit a little under a 5x sprite's 80pt, so a pile
/// of four reads as litter on the ground beside the Digimon rather than as a second character.
struct PoopShape: View {
    /// The width of the widest (bottom) coil. The whole shape scales off this.
    static let baseWidth: CGFloat = 7

    var body: some View {
        // Negative spacing so the coils overlap into one solid heap instead of three separate
        // blobs with daylight between them.
        VStack(spacing: -1.5) {
            Ellipse().frame(width: Self.baseWidth * 0.45, height: 2.5)
            Ellipse().frame(width: Self.baseWidth * 0.72, height: 3)
            Ellipse().frame(width: Self.baseWidth, height: 3.5)
        }
        .foregroundStyle(Color.brown)
    }
}

/// The mess on the ground: one `PoopShape` per poop (US-052).
///
/// One shape per poop rather than a count badge, because the whole point of poop in a V-Pet is that
/// neglect is visible at a glance without reading anything — and `PoopClock.maximumPoops` is four
/// precisely so that a full row still fits beside the Digimon.
///
/// VoiceOver gets the number instead, as one element: four identical unlabelled shapes would
/// otherwise be four meaningless stops.
struct PoopPile: View {
    let count: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<max(count, 0), id: \.self) { _ in
                PoopShape()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Poop")
        .accessibilityValue("\(count)")
    }
}

#Preview {
    PoopPile(count: PoopClock.maximumPoops)
}
