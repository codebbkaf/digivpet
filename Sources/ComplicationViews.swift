import CoreGraphics
import SwiftUI
import WidgetKit

/// The watch face complication: the Digimon currently being raised, and how far its dominant energy
/// has come.
///
/// Draws ONLY what `ComplicationSnapshot` was handed. The widget runs in its own process and can
/// neither open the game's store nor decide anything about it — see `ComplicationSnapshot` for why
/// re-deriving here would be worse than stale.
///
/// Compiled into BOTH targets, unlike `Sources/Complication/DigiVPetComplication.swift`, which
/// declares the extension's `@main` and so cannot be. That is what lets the app's `-complicationDemo`
/// screen below render these exact views: nothing in the Simulator can add a complication to a watch
/// face from the command line, so screenshotting the real views from the app is the only way to see
/// what the face will show.

/// One timeline entry: a snapshot, and which step of that snapshot's pose to draw.
///
/// The snapshot is the same in every entry of a batch. The game does not change on a schedule the
/// widget can predict — hunger, evolution and death all depend on health data that has not been read
/// yet — so the app still pushes a reload when anything real changes. `step` carries the one thing
/// the widget CAN predict: which half of the walk cycle it is on (US-049).
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot
    /// Index into the pose's frame cycle. Always 0 for a held pose, which has one frame.
    var step: Int = 0
}

/// Builds the batch of entries that makes the sprite walk on the watch face (US-049).
///
/// ## Cadence
///
/// Five seconds, and that number is measured, not chosen — see `docs/widget-refresh-granularity.md`.
/// US-048 put the complication in a real face slot and read the repaint interval out of chronod:
/// 5 s was honoured *exactly* on every sample across three passes, while 1 s jittered between 1.0 and
/// 2.0 s and silently dropped frames. A two-frame walk that stutters reads worse than one that is
/// steady, so the finest reliable spacing wins over the finest possible one.
///
/// ## Horizon, and what happens when it runs out
///
/// `motionEntryCount` entries — five minutes of walking — then `.after` the last entry asks WidgetKit
/// for a fresh batch. The horizon is the thing worth thinking about, not the spacing: US-048 also
/// confirmed a whole batch is ONE budget charge however many entries it holds (the 29-minute ladder
/// cost exactly 2 `getTimeline` calls), so a 5 s batch is no more expensive than a 5 min one. What
/// costs is how often the batch is re-requested, and five minutes is a deliberate compromise: short
/// enough that a few hundred entries never have to be rendered and archived at once, long enough that
/// the reload rate stays in the same order as a widget's daily refresh budget.
///
/// **When the budget is spent, WidgetKit simply keeps showing the last entry.** That is a still
/// sprite — precisely the behaviour that shipped before this story — so running out degrades to the
/// old complication rather than to a broken one. Nothing here is load-bearing for correctness; every
/// state change still arrives by the app's own `reloadAllTimelines`.
///
/// **Open item carried from US-048:** the Always-On Display repaint rate is unmeasured and needs real
/// hardware. Assume the sprite may hold one frame with the wrist down. Nothing in the design depends
/// on the motion being visible in AOD — it is garnish on a complication that reads fine frozen.
enum ComplicationTimeline {
    /// Seconds between entries. The measured floor that is honoured exactly (US-048).
    static let frameInterval: TimeInterval = 5

    /// Entries per batch: 60 x 5 s = a five-minute horizon.
    static let motionEntryCount = 60

    /// How long a held pose sits before asking for a refresh anyway.
    ///
    /// A watch whose app has not been woken for hours would otherwise sit on one entry forever. An
    /// hour is a floor under that, not the real cadence — the app reloads the moment a refresh
    /// changes anything (`publishComplicationSnapshot`).
    static let heldRefreshInterval: TimeInterval = 3600

    /// The entries a batch starting at `start` contains.
    static func entries(for snapshot: ComplicationSnapshot, from start: Date) -> [ComplicationEntry] {
        guard snapshot.pose.animates else {
            return [ComplicationEntry(date: start, snapshot: snapshot)]
        }
        return (0..<motionEntryCount).map { step in
            ComplicationEntry(
                date: start.addingTimeInterval(Double(step) * frameInterval),
                snapshot: snapshot,
                step: step
            )
        }
    }

    /// When WidgetKit should come back for a new batch.
    ///
    /// Split out from `timeline(for:from:)` because `TimelineReloadPolicy` is opaque — it exposes no
    /// date and is not `Equatable` — so this is the only way a test can assert the plan rather than
    /// just trusting it.
    static func reloadDate(for snapshot: ComplicationSnapshot, from start: Date) -> Date {
        guard snapshot.pose.animates else {
            return start.addingTimeInterval(heldRefreshInterval)
        }
        // One `frameInterval` past the LAST entry, so the final frame gets shown for as long as the
        // fifty-nine before it rather than being cut short by the reload.
        return start.addingTimeInterval(Double(motionEntryCount) * frameInterval)
    }

    static func timeline(for snapshot: ComplicationSnapshot, from start: Date) -> Timeline<ComplicationEntry> {
        Timeline(
            entries: entries(for: snapshot, from: start),
            policy: .after(reloadDate(for: snapshot, from: start))
        )
    }

    /// The entry a face is showing at `date`: the last one whose time has come.
    ///
    /// Only the `-complicationDemo` screen needs this — WidgetKit does the same selection itself for
    /// the real complication — but doing it from the real generated array is what makes the demo a
    /// verification of this batch rather than a separate drawing of the same idea.
    static func entry(at date: Date, in entries: [ComplicationEntry]) -> ComplicationEntry? {
        entries.last { $0.date <= date } ?? entries.first
    }
}

struct ComplicationProvider: TimelineProvider {
    /// Reading the shared file, injectable so a test can point it at a temp directory.
    var load: () -> ComplicationSnapshot? = { ComplicationSnapshotStore.read() }
    /// Injectable so a test can assert entry dates against a fixed instant.
    var now: () -> Date = Date.init

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: now(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: now(), snapshot: load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        completion(ComplicationTimeline.timeline(for: load() ?? .placeholder, from: now()))
    }
}

/// The Digimon at complication scale, in the pose the app decided (US-047), on the step of that
/// pose's cycle this timeline entry asked for (US-049).
///
/// Every frame comes from the 48x64 (or 48x16) sheet via `SpriteSheetCache`, and only falls back to
/// the `Idle Frame Only` art when the sheet cannot supply the pose at all. That fallback is not
/// theoretical: an egg sheet has no sleep, hurt or angry frame (`SpriteSheet`'s `SpriteFrame`
/// subscript returns nil for `.egg`), and an egg that is asleep or sick is an ordinary state. Better
/// the right Digimon in the wrong pose than a '?'.
///
/// **This narrows PRD FR-22, deliberately.** FR-22 had the idle pose draw the one-file `Idle Frame
/// Only` art instead of decoding a sheet. It cannot, now that idle moves: the idle art is a
/// DIFFERENT drawing from sheet frame 0 (verified — they are not the same bytes), so alternating it
/// with sheet `walk2` would flicker between two art styles and read as a glitch rather than a step.
/// A walk cycle has to come from one source. The cost FR-22 was avoiding is paid once per Digimon —
/// `SpriteSheetCache` decodes and crops on first use and every later entry is a dictionary lookup —
/// and FR-22's other reason, the Digitama, is better served here than before: an egg now takes
/// `idle`/`wobble` from its own sheet and actually wobbles, where it used to hold `IdleSpriteCache`'s
/// frame-0 fallback forever.
private struct ComplicationSprite: View {
    let snapshot: ComplicationSnapshot
    /// Which step of the pose's cycle to draw. Wrapped, so any entry index is safe.
    var step: Int = 0
    var side: CGFloat

    private var image: CGImage? {
        if let sheet = SpriteSheetCache.shared.sheet(stage: snapshot.spriteStage,
                                                     name: snapshot.spriteFile) {
            let frames = cycle(from: sheet)
            if !frames.isEmpty { return frames[step % frames.count] }
        }
        return IdleSpriteCache.shared.image(stage: snapshot.spriteStage, name: snapshot.spriteFile)
    }

    /// The pose's frames as actual images, empty when this sheet has no art for the pose.
    private func cycle(from sheet: SpriteSheet) -> [CGImage] {
        switch sheet.kind {
        case .stage: return snapshot.pose.stageFrames.compactMap { sheet[$0] }
        case .egg: return snapshot.pose.eggFrames.compactMap { sheet[$0] }
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    // Pixel art. Smoothing it is a bug, complication or not.
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "questionmark")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: side, height: side)
        // The entry transition (US-049). WidgetKit animates between timeline entries, but only where
        // view IDENTITY changed — without the `.id` the two frames are the same `Image` node with new
        // contents and it cuts hard. A cross-fade rather than a slide or a scale: the sprite is 24pt
        // of pixel art in a 52pt circle, and anything that moves it lands it outside the circle. What
        // is being softened is the seam, not the sprite; the motion is carried by the two frames
        // differing, which is what a two-frame V-Pet walk has always been.
        .id(step)
        .transition(.opacity)
        // Keeps the Digimon in the face's accent colour rather than the dimmed layer, so it stays
        // the thing you see first.
        .widgetAccentable()
    }
}

/// Sprite alone, filling the circle.
struct CircularComplicationView: View {
    let snapshot: ComplicationSnapshot
    /// The timeline entry's step. Defaults to the held frame, so a caller with nothing to animate
    /// (the widget gallery placeholder, a preview) needs to say nothing.
    var step: Int = 0

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            ComplicationSprite(snapshot: snapshot, step: step, side: 24)
        }
        .accessibilityLabel(Text(snapshot.accessibilityLabel))
    }
}

/// The Clean button, drawn only when `ComplicationSnapshot.needsCleaning` (US-050).
///
/// Icon-only, matching the in-app action row from US-038 — there is no room for a word here, and the
/// accessibility label carries it for anyone who needs it. `.plain`, because the bordered styles put
/// a filled capsule behind it that reads as a second sprite at this size.
struct CleanComplicationButton: View {
    var body: some View {
        Button(intent: CleanPoopIntent()) {
            Image(systemName: "trash")
                .font(.title3)
        }
        .buttonStyle(.plain)
        .widgetAccentable()
        .accessibilityLabel("Clean")
    }
}

/// Sprite, name, and the dominant energy's progress.
struct RectangularComplicationView: View {
    let snapshot: ComplicationSnapshot
    /// See `CircularComplicationView.step`.
    var step: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            // The informational half is combined into ONE VoiceOver element, and the Clean button is
            // deliberately outside it: `children: .combine` flattens whatever it wraps into a single
            // static label, which would make the button unreachable to VoiceOver — an interactive
            // widget nobody can activate.
            information
            // US-050. The rectangular family and not the circular one: circular is a 24pt sprite
            // in a 52pt circle with no room for a second target, and a button crammed in there
            // would be missed as often as it was hit.
            if snapshot.needsCleaning {
                CleanComplicationButton()
            }
        }
    }

    private var information: some View {
        HStack(spacing: 6) {
            ComplicationSprite(snapshot: snapshot, step: step, side: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if let symbol = snapshot.dominantEnergySymbol {
                    // A gauge rather than four bars: the rectangular family has room for one line of
                    // progress, and the dominant type is the one that decides the next evolution.
                    Gauge(value: snapshot.dominantEnergyFraction) {
                        Text(symbol)
                    } currentValueLabel: {
                        Text("\(snapshot.dominantEnergyEarned)")
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                } else {
                    // A fresh egg has earned nothing and so has no dominant type. Saying so beats an
                    // empty bar aimed at a type it has not chosen.
                    Text("No energy yet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    /// The circular family's label plus the energy the rectangular one actually draws.
    private var accessibilityLabel: String {
        guard let name = snapshot.dominantEnergyName else { return snapshot.accessibilityLabel }
        return "\(snapshot.accessibilityLabel), \(name) \(snapshot.dominantEnergyEarned)"
    }
}

struct DigiVPetComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                RectangularComplicationView(snapshot: entry.snapshot, step: entry.step)
            default:
                CircularComplicationView(snapshot: entry.snapshot, step: entry.step)
            }
        }
        // A tap opens the app at this URL. watchOS opens the containing app for a complication with
        // no URL too, but naming it explicitly is what makes the behaviour testable — `simctl openurl`
        // can exercise exactly this.
        .widgetURL(DigiVPetURL.open)
    }
}


#if DEBUG
/// Both complication families side by side, drawn from whatever the app last published.
///
/// A DEBUG-only screen behind the `-complicationDemo` launch argument, in the same spirit as the
/// other demo hooks (`-dexDemo`, `-feedDemo`): it exists so a screenshot can show what the watch
/// face will, and it is compiled out of a release build entirely. It renders the SAME views the
/// extension does, so a sprite that failed to resolve here would fail there too.
/// Since US-049 it also steps through the REAL batch `ComplicationTimeline` generates, on the real
/// `frameInterval`, rather than drawing one fixed frame. Two screenshots taken more than five seconds
/// apart therefore land on different entries and show different frames — which is how US-049's
/// alternation gets verified without a watch face, and it verifies the shipping batch rather than a
/// second drawing of the same idea. The step index is on screen so a screenshot says which entry it
/// caught.
struct ComplicationDemoView: View {
    /// The published snapshot, falling back to the placeholder exactly as the provider does.
    var snapshot: ComplicationSnapshot = ComplicationSnapshotStore.read() ?? .placeholder

    /// Fixed at first draw so the batch does not regenerate underneath the `TimelineView`.
    @State private var start = Date()

    var body: some View {
        let batch = ComplicationTimeline.entries(for: snapshot, from: start)
        TimelineView(.periodic(from: start, by: ComplicationTimeline.frameInterval)) { context in
            let entry = ComplicationTimeline.entry(at: context.date, in: batch)
                ?? ComplicationEntry(date: start, snapshot: snapshot)
            VStack(spacing: 10) {
                Text(ComplicationSnapshotStore.read() == nil ? "placeholder" : "published")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("step \(entry.step) of \(batch.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                CircularComplicationView(snapshot: entry.snapshot, step: entry.step)
                    .frame(width: 52, height: 52)
                RectangularComplicationView(snapshot: entry.snapshot, step: entry.step)
                    .frame(height: 44)
            }
        }
        .padding(.horizontal, 4)
    }
}
#endif
