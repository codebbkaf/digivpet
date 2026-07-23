import SwiftUI

/// One equal-width dash in a `DashBar`: `solid` when the unit is earned, `outline` (a stroked
/// border, no fill) when it is not.
enum Dash: Equatable {
    case solid
    case outline
}

/// The pure layout of a dash bar — `total` dashes, the first `filled` solid and the rest outline.
///
/// Free-standing rather than computed inside the view, in the same spirit as `EnergyBarLayout`: a
/// test should be able to count solid against outline without standing up a view graph, and every
/// clamping rule the AC names lives here where it can be checked directly.
enum DashBarLayout {
    /// `total` dashes, `min(max(filled, 0), total)` of them solid and the remainder outline.
    ///
    /// `filled` is clamped to `0...total`: a value past the top must not draw a phantom dash the
    /// bar has no room for (a battle charge count read mid-tick can momentarily exceed the cap), and
    /// a negative one must not steal from the outline count. `total <= 0` draws nothing — an empty
    /// bar, not a crash on the `0..<total` range.
    static func dashes(filled: Int, total: Int) -> [Dash] {
        guard total > 0 else { return [] }
        let solid = min(max(filled, 0), total)
        return (0..<total).map { $0 < solid ? .solid : .outline }
    }
}

/// The single visual language for every value bar in the app (US-171): progress as `total`
/// equal-width dashes, the first `filled` solid and the rest outline-only, with no digits anywhere.
/// Meat, battle charges, sleep and the rest all render through this so one glance reads the same
/// everywhere.
struct DashBar: View {
    let filled: Int
    let total: Int

    /// The dash colour. A parameter with a default so meat, charges and sleep can each carry their
    /// own hue while sharing the shape.
    var tint: Color = .primary

    /// Deliberately short — sixteen of these have to share a 176pt screen — so the bar reads as a
    /// row of ticks rather than a stack of pills.
    var dashHeight: CGFloat = 6

    /// The width of the divider line drawn between adjacent segments (US-195). NOT layout spacing —
    /// the segments themselves touch (`HStack` spacing 0) so the bar reads as one solid rule; this
    /// `divider`-many points are then *carved out* of each fill at its trailing edge so the boundary
    /// between two segments stays legible as a thin line rather than a gap that spaces the dashes out.
    var spacing: CGFloat = 2

    private var dashes: [Dash] { DashBarLayout.dashes(filled: filled, total: total) }

    /// What the accessibility label speaks and what the solid count reflects: the visible value,
    /// which is `filled` bounded by the bar it is drawn into. Speaking the raw `filled` would tell a
    /// VoiceOver user "17 of 16", a value the sighted bar cannot show.
    private var clampedFilled: Int { min(max(filled, 0), total) }

    var body: some View {
        // GeometryReader so the dash width is DERIVED from the width the bar is handed, never a
        // fixed 16pt that would overflow the moment `total` climbs. The segments now TOUCH — the
        // HStack spacing is 0 and the full width is split evenly — so the bar reads as one solid
        // rule (US-195) rather than a row of spaced-out pills. The `spacing`-wide divider is not
        // added as layout space; it is punched out of each fill's trailing edge below.
        GeometryReader { geometry in
            let count = dashes.count
            let dashWidth = count > 0 ? geometry.size.width / CGFloat(count) : 0

            HStack(spacing: 0) {
                ForEach(Array(dashes.enumerated()), id: \.offset) { index, dash in
                    dashShape(for: dash)
                        .frame(width: dashWidth)
                        // The divider between this segment and the next: a `spacing`-wide line
                        // carved out of a SOLID fill's trailing edge so the background shows through
                        // as a thin rule. `destinationOut` erases rather than paints, so the divider
                        // reads against any container colour and never spaces the dashes apart.
                        // Only solid fills need it — two touching outline boxes already show a 2pt
                        // boundary where their inset `strokeBorder`s meet, so punching them too would
                        // just knock the right wall off every empty tick.
                        .overlay(alignment: .trailing) {
                            if index < count - 1, dash == .solid {
                                Rectangle()
                                    .frame(width: spacing)
                                    .blendMode(.destinationOut)
                            }
                        }
                }
            }
            // Left-aligned within the reader so a bar handed more width than its dashes need does
            // not float in the middle of the column.
            .frame(maxWidth: .infinity, alignment: .leading)
            // Flatten so the divider punch-out composites against the dashes alone, not the whole
            // view tree behind the bar.
            .compositingGroup()
            // Round only the outer ends: interior segments butt together as square rectangles so
            // the run of solids reads as one continuous bar split by the divider lines.
            .clipShape(RoundedRectangle(cornerRadius: dashHeight / 3))
        }
        .frame(height: dashHeight)
        // total==0 renders nothing: no dashes, no border, and — for VoiceOver — no bar element at
        // all, so an absent value is silence rather than "0 of 0".
        .opacity(total > 0 ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(total <= 0)
        .accessibilityLabel("\(clampedFilled) of \(total)")
    }

    @ViewBuilder
    private func dashShape(for dash: Dash) -> some View {
        // Square-cornered so touching segments form one continuous bar; the whole row is clipped to
        // a rounded rect in `body`, which rounds only the two outer ends.
        switch dash {
        case .solid:
            Rectangle().fill(tint)
        case .outline:
            // strokeBorder, not stroke: the border is inset so a 1pt line does not spill past the
            // dash's own frame and touch its neighbour.
            Rectangle().strokeBorder(tint, lineWidth: 1)
        }
    }
}

/// One arc of a `DashRing` — the wedge of a circle segment `index` occupies out of `total`, drawn as
/// a stroked arc with a small angular `gapDegrees` carved off each end so adjacent segments read as
/// distinct ticks rather than one continuous ring.
///
/// `inset` is half the ring's line width, subtracted from the radius so the stroke — which straddles
/// the path centreline — stays inside the frame rather than spilling past it.
struct DashRingSegment: Shape {
    let index: Int
    let total: Int
    let gapDegrees: Double
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard total > 0 else { return path }
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Segments march clockwise from the top (12 o'clock, -90°), the same reading order a clock
        // fills, so the first earned charge lights the top tick.
        let sweep = 360.0 / Double(total)
        let start = -90.0 + sweep * Double(index) + gapDegrees / 2
        let end = -90.0 + sweep * Double(index + 1) - gapDegrees / 2
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        return path
    }
}

/// A `DashBar` wrapped into a ring (US-199): `total` equal arcs around a circle, the first `filled`
/// solid in `tint` and the rest a faint outline in the same hue, split by small gaps — the circular
/// twin of `DashBar`, meant to sit AROUND the button that spends the charge it counts.
///
/// Used as an `.overlay` on a 30pt `ActionButtonFace`: the default `diameter` is a touch larger than
/// the face so the ring encircles it, and because it is an overlay it never changes the button's own
/// tap size or the grid's spacing. Decorative for VoiceOver — the button it wraps carries the spoken
/// "N of M" value — so this view is `accessibilityHidden`.
struct DashRing: View {
    let filled: Int
    let total: Int

    /// The arc hue, matched to the button's action: red for Train, purple for Battle, blue for Clean.
    var tint: Color = .primary

    /// The ring's outer size. Four points wider than `ActionButtonFace.diameter` so the ring's outer
    /// edge sits ~2pt beyond the face — clear of the glyph, and only just into the 4pt grid gap so two
    /// adjacent rings meet rather than overlap.
    var diameter: CGFloat = ActionButtonFace.diameter + 4

    /// The arc weight. Thin, so the ring reads as a hairline of ticks rather than a second disc.
    var lineWidth: CGFloat = 2.5

    /// The angular gap carved between adjacent segments, in degrees — the ring's version of the
    /// `DashBar`'s 2pt divider line.
    var gapDegrees: Double = 8

    /// The visible solid count: `filled` bounded by the ring it is drawn into, so a charge count read
    /// mid-tick that overshoots the cap cannot light a phantom arc.
    private var solid: Int { min(max(filled, 0), total) }

    var body: some View {
        ZStack {
            ForEach(0..<max(total, 0), id: \.self) { index in
                DashRingSegment(index: index, total: total,
                                gapDegrees: gapDegrees, inset: lineWidth / 2)
                    // A solid arc is the full tint; an unearned one is the same hue faint, the ring's
                    // answer to the `DashBar` outline — present but plainly empty.
                    .stroke(tint.opacity(index < solid ? 1 : 0.25),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }
        .frame(width: diameter, height: diameter)
        // total==0 draws nothing, matching `DashBar`: an absent charge economy is silence, not an
        // empty ring.
        .opacity(total > 0 ? 1 : 0)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 8) {
        DashBar(filled: 6, total: 16, tint: .orange)
        DashBar(filled: 3, total: 5, tint: .red)
        DashBar(filled: 0, total: 8)

        HStack(spacing: 16) {
            DashRing(filled: 3, total: 10, tint: .red)
            DashRing(filled: 7, total: 10, tint: .purple)
            DashRing(filled: 5, total: 8, tint: .blue)
        }
    }
    .padding()
}
