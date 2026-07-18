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

/// One timeline entry. There is only ever one: the game does not change on a schedule the widget can
/// predict — hunger, evolution and death all depend on health data that has not been read yet — so
/// the app pushes a reload instead of the widget guessing the future.
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot
}

struct ComplicationProvider: TimelineProvider {
    /// Reading the shared file, injectable so a test can point it at a temp directory.
    var load: () -> ComplicationSnapshot? = { ComplicationSnapshotStore.read() }

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: Date(), snapshot: load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = ComplicationEntry(date: Date(), snapshot: load() ?? .placeholder)
        // `.after`, not `.never`: the app reloads this the moment a refresh changes anything
        // (`publishComplicationSnapshot`), but a watch whose app has not been woken for hours would
        // otherwise sit on one entry forever. An hour is a floor under that, not the real cadence.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

/// The Digimon's idle frame at complication scale.
///
/// `Idle Frame Only` art, not the 48x64 animated sheet (PRD FR-22): a complication does not animate,
/// and `IdleSpriteCache` already falls back to frame 0 of the sheet for the Digitama, which have no
/// entry in that folder.
private struct ComplicationSprite: View {
    let snapshot: ComplicationSnapshot
    var side: CGFloat

    var body: some View {
        Group {
            if let image = IdleSpriteCache.shared.image(stage: snapshot.spriteStage, name: snapshot.spriteFile) {
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
        // Keeps the Digimon in the face's accent colour rather than the dimmed layer, so it stays
        // the thing you see first.
        .widgetAccentable()
    }
}

/// Sprite alone, filling the circle.
struct CircularComplicationView: View {
    let snapshot: ComplicationSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            ComplicationSprite(snapshot: snapshot, side: 24)
        }
        .accessibilityLabel(Text(snapshot.displayName))
    }
}

/// Sprite, name, and the dominant energy's progress.
struct RectangularComplicationView: View {
    let snapshot: ComplicationSnapshot

    var body: some View {
        HStack(spacing: 6) {
            ComplicationSprite(snapshot: snapshot, side: 28)
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

    private var accessibilityLabel: String {
        guard let name = snapshot.dominantEnergyName else { return snapshot.displayName }
        return "\(snapshot.displayName), \(name) \(snapshot.dominantEnergyEarned)"
    }
}

struct DigiVPetComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                RectangularComplicationView(snapshot: entry.snapshot)
            default:
                CircularComplicationView(snapshot: entry.snapshot)
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
struct ComplicationDemoView: View {
    /// The published snapshot, falling back to the placeholder exactly as the provider does.
    var snapshot: ComplicationSnapshot = ComplicationSnapshotStore.read() ?? .placeholder

    var body: some View {
        VStack(spacing: 10) {
            Text(ComplicationSnapshotStore.read() == nil ? "placeholder" : "published")
                .font(.caption2)
                .foregroundStyle(.secondary)
            CircularComplicationView(snapshot: snapshot)
                .frame(width: 52, height: 52)
            RectangularComplicationView(snapshot: snapshot)
                .frame(height: 44)
        }
        .padding(.horizontal, 4)
    }
}
#endif
