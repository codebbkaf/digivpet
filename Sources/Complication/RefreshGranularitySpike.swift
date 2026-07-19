import SwiftUI
import WidgetKit

// ============================================================================
//  NON-SHIPPING SPIKE CODE — US-048. DO NOT BUILD ON THIS.
//
//  This file exists to MEASURE one thing: how finely WidgetKit actually honours
//  timeline entry dates on watchOS, so US-049 can pick an alternation cadence
//  from an observation instead of a guess. It ships no feature and is wrapped in
//  `#if DEBUG` so it cannot reach a release build.
//
//  Findings live in docs/widget-refresh-granularity.md. Once US-049 has landed,
//  DELETE THIS FILE — the doc is the deliverable, this is the instrument.
//
//  Explicitly NOT attempted here: sensor-driven (gyroscope/compass) frames. A
//  widget is not a running process — WidgetKit renders entries to snapshots and
//  exits, so there is nothing alive to receive a sensor callback. Ruled out in
//  the design note in tasks/prd-vpet-enhancements.md; see it before reviving it.
// ============================================================================

#if DEBUG

/// One rung of the measurement: a spacing to probe, and how many entries to spend on it.
private struct SpikeBand {
    let label: String
    let spacing: TimeInterval
    let count: Int
}

struct SpikeEntry: TimelineEntry {
    let date: Date
    /// Which spacing this entry belongs to ("1s", "5s", …), drawn large enough to read in a screenshot.
    let band: String
    /// Position within the band, 0-based.
    let index: Int
    /// Seconds after the timeline was generated. The primary reading: compare against wall clock.
    let offset: Int
}

/// Emits one batched timeline that walks 1s → 5s → 30s → 60s → 5min spacing.
///
/// One timeline rather than five runs, because the coalescing question is about what the system does
/// with a batch — and a batch is one charge against the reload budget however many entries it holds.
struct RefreshSpikeProvider: TimelineProvider {
    /// ~29 minutes end to end. The coarse bands have to outlast the fine ones to be observable at all.
    private static let bands = [
        SpikeBand(label: "1s", spacing: 1, count: 10),
        SpikeBand(label: "5s", spacing: 5, count: 6),
        SpikeBand(label: "30s", spacing: 30, count: 6),
        SpikeBand(label: "60s", spacing: 60, count: 5),
        SpikeBand(label: "5m", spacing: 300, count: 5),
    ]

    func placeholder(in context: Context) -> SpikeEntry {
        SpikeEntry(date: Date(), band: "—", index: 0, offset: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
        completion(SpikeEntry(date: Date(), band: "snap", index: 0, offset: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        let start = Date()
        var entries: [SpikeEntry] = []
        var offset: TimeInterval = 0
        for band in Self.bands {
            for index in 0..<band.count {
                entries.append(SpikeEntry(date: start.addingTimeInterval(offset),
                                          band: band.label,
                                          index: index,
                                          offset: Int(offset.rounded())))
                offset += band.spacing
            }
        }
        // `.atEnd` so the whole ladder repeats and a second observer pass needs no reinstall.
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Deliberately plain and high-contrast: the reading is taken from a screenshot, so band and offset
/// have to survive being shrunk to a Smart Stack row.
struct RefreshSpikeView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpikeEntry

    var body: some View {
        if family == .accessoryCircular || family == .accessoryCorner {
            VStack(spacing: 0) {
                Text(entry.band).font(.system(size: 13, weight: .bold))
                Text("\(entry.offset)").font(.system(size: 17, weight: .heavy).monospacedDigit())
            }
        } else {
            HStack(spacing: 6) {
                Text(entry.band).font(.system(size: 15, weight: .heavy))
                Text("#\(entry.index)").font(.system(size: 13).monospacedDigit())
                Spacer()
                // t+seconds since the timeline was generated, beside the entry's own wall time. The
                // pair is what makes a screenshot self-dating: which entry, and when it was due.
                Text("t+\(entry.offset)").font(.system(size: 15, weight: .bold).monospacedDigit())
                Text(entry.date, style: .timer).font(.system(size: 11).monospacedDigit())
            }
        }
    }
}

struct RefreshGranularitySpikeWidget: Widget {
    static let kind = "DigiVPetRefreshSpike"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RefreshSpikeProvider()) { entry in
            RefreshSpikeView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("SPIKE refresh")
        .description("US-048 measurement only. Not a feature.")
        // `.accessoryCorner` is here and NOT on the shipping complication for one reason: the corner
        // slots are the ones a face.json edit can fill without touch input, which is how this gets
        // observed at all. See docs/widget-refresh-granularity.md.
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}

#endif
