# Widget timeline refresh granularity — US-048 spike

**Status: MEASURED (non-AOD). The AOD floor is still unknown and needs hardware.**

Measured on: 2026-07-20
Environment: Apple Watch Series 9 (45mm) Simulator, watchOS 10.4 (build 21T214), Xcode 26.4.1, macOS 15 (Darwin 25.4.0)
Physical watch available: none

US-049 wants to alternate sprite frames using batched timeline entries, and the
cadence had to come from an observation rather than a guess. This is the
observation.

---

## The measured floor

**Roughly 1–2 seconds, jittery. Anything at 5 s or coarser is honoured exactly.**

WidgetKit did **not** coalesce a single batched timeline of 32 entries. Every entry
produced its own repaint, including the ten spaced one second apart. Measured
repaint intervals, taken from `com.apple.chrono:timelineLiveView` "Evaluated inner
view" events with the complication live in a watch face slot:

| Authored spacing | Observed repaint intervals | Verdict |
|---|---|---|
| 1 s   | 1.00, 1.01, 1.01, 1.01, 1.01 (pass 1)<br>2.00, 2.01 (pass 2)<br>1.87, 1.81, 1.72, 1.10, 1.00, 1.03, 1.05, 2.00 (pass 3) | honoured, but jitters between ~1.0 s and ~2.0 s |
| 5 s   | 5.02, 5.03, 5.03, 5.04, 5.04, 5.04 | exact |
| 30 s  | 29.66, 29.81, 29.84, 30.06, 30.20, 30.28 | exact |
| 60 s  | 59.68, 59.75, 60.14, 60.19, 60.49 | exact |
| 5 min | 300.28 | exact |

The 1 s band is the only one that is not reliably 1:1. It is not *coalesced to a
floor* so much as *served late* — the renderer sometimes runs two entries together
and sometimes hits 1.00 s dead on, with no stable pattern across three passes.
Treat 1 s as "best effort, expect to lose some frames" and 2 s as the conservative
number.

**One timeline, one charge.** The whole 29-minute ladder above ran from a single
`getTimeline` delivery — chronod logged exactly 2 `Request began for
DigiVPetRefreshSpike` calls across the entire session, and all 32 entries were
accepted verbatim (`entry count: 32`, date range matching the authored ladder
end to end). Batching is genuinely one budget charge however many entries it holds.

## The AOD floor

**Unknown, and not measurable in the Simulator.**

AOD is toggled from the Simulator's *Features* menu, which needs a GUI this
environment cannot drive (see "What is still blocked"). `xcrun simctl ui` exposes
only `appearance`, `increase_contrast` and content size — there is no AOD option.
More importantly, AOD render throttling is display-hardware behaviour that a
simulator is not a trustworthy model of even if it could be toggled.

**Measure the AOD floor on a real watch and nowhere else.** Expect it to be much
coarser than the active-display numbers above; the render session does advertise
`wantsLowLuminanceContent=true`, so the plumbing exists, but nothing here says at
what rate it repaints when the wrist is down.

---

## How the complication was put on a face without touch

This is the part worth not rediscovering — the previous attempt got 90% of the way
and stopped one key short.

A widget that is not on a watch face is **never asked for a timeline**; it only
ever gets `placeholder` calls and every chronod log line reads `on no host`. So the
spike could not be run until the complication was actually installed in a slot, and
installing one is normally a touch interaction.

It does not have to be. The selected face is plain JSON on the host filesystem:

```
~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/NanoTimeKit/
  CollectionStores/GlobalStores/LibraryFaces/Faces/<FACE-UUID>/face.json
```

Shut the device down, edit, boot. The working slot encoding is:

```json
"complications": {
  "top left": {
    "app": "com.digivpet.DigiVPet",
    "type": 56,
    "descriptor": {
      "extensionBundleIdentifier": "com.digivpet.DigiVPet.Widget",
      "containerBundleIdentifier": "com.digivpet.DigiVPet",
      "kind": "DigiVPetRefreshSpike"
    }
  }
}
```

**`"type": 56` is the whole trick.** Without it NanoTimeKit classifies the slot as
a `Remote` (iPhone-side) complication awaiting migration, which on a watch-only app
never resolves — the slot draws empty and the widget stays `on no host` forever.
56 is `NTKComplicationTypeWidget`, the native "Apricot" kind. It was not guessed;
it was read straight out of the framework:

```bash
xcrun otool -arch arm64 -tV \
  ".../watchOS 10.4.simruntime/.../NanoTimeKit.framework/NanoTimeKit" \
  | grep -A3 "+\[NTKApricotComplicationController _acceptsComplicationType:family:forDevice:\]:"
```

```
+[NTKApricotComplicationController _acceptsComplicationType:family:forDevice:]:
    cmp  x2, #0x38     ; 0x38 == 56
    cset w0, eq
    ret
```

That method accepts exactly one type, so there is no ambiguity. The earlier lead in
this doc — chronod's `nativeContainerBundleIdentifier` — was a red herring: it is a
runtime property of `CHSWidgetDescriptor`, not a face-JSON key.

The default Crosswind face's `top left` slot is a **corner** slot, so the widget
must declare `.accessoryCorner`. The spike does; the shipping complication
deliberately does not.

Confirmation it worked, in ascending order of how convincing it is:

1. `ClockFace [NanoTimeKit:Tritium] [SceneHosting] Presentation: [1]
   <BLSHPresentationEntry ... scene::<FACE-UUID>-top-left-com.digivpet.DigiVPet.Widget-DigiVPetRefreshSpike>`
2. `chronod [widgetRendererSession] <WidgetRenderSession-...-DigiVPetRefreshSpike...>`
   — a live render session, and the `on no host` tag gone.
3. A screenshot of the face showing the spike in the top-left corner reading band
   `5s` / offset `25`, taken at 09:09:56 against a timeline generated at 09:09:31.
   t+25 lands exactly on the screenshot second.

## Reading the result: use the logs, not screenshots

```bash
xcrun simctl spawn <UDID> log stream --style compact \
  --predicate 'subsystem == "com.apple.chrono"'
```

The repaint events are `com.apple.chrono:timelineLiveView` … `Evaluated inner view
with result: LIVE - view sequence number: N, reasons: [timelineAdvancedOrNewArchive]`.
The sequence number increments once per entry actually shown, so consecutive
timestamps give the real repaint interval with no screenshot timing error and no
29-minute wall-clock wait per reading. Every number in the table above came from
this. Keep the spike view anyway — it is what proves a repainted entry is also a
*rendered* one, which the logs alone do not show.

**Gotcha that cost time twice.** Foregrounding the app flushes a pending
`WidgetCenter.reloadAllTimelines()` when it next backgrounds, which starts a *fresh*
ladder mid-measurement. A 2.31 s gap in the first run looked like coalescing and was
actually the start of a new timeline. Check `Request began for <Kind>` counts before
believing any delta; if the count went up, the ladder restarted.

---

## What is still blocked

Synthetic touch. `simctl` has no touch/tap/swipe/crown command, `osascript` gets
`-1728` (not allowed assistive access), and `CGEvent(...).post(tap:)` is swallowed
with `AXIsProcessTrusted() == false`. This is a TCC grant only a human at the
machine can give. It no longer blocks the measurement — the face-store edit routes
around it — but it does block the Features menu, and therefore AOD.

---

## What this means for US-049

**US-049 is viable. Build it.** The earlier worry — that the floor might be coarser
than about two minutes, making a "walk cycle" a stale complication with extra steps
— is dead. The floor is seconds, not minutes.

Recommended cadence: **alternate walk1/walk2 on 5-second entries.**

- 5 s is the finest spacing that was honoured *exactly* on every single sample,
  across all three passes. 1 s technically works but drops frames unpredictably,
  and a two-frame walk cycle that stutters looks worse than one that is steady.
- 5 s is a comfortable read for a two-frame sprite loop — fast enough to be alive,
  slow enough not to look frantic on a watch face.
- Budget: the entire ladder was one charge. A batch of N entries at 5 s costs the
  same as a batch of N entries at 5 min, so the horizon is the thing to spend
  thought on, not the spacing.

Do still suppress alternation for held-pose states (sleeping, sick, dead) as US-049
already specifies — that is a correctness requirement, not a cadence one.

**Carry this open item into US-049:** the AOD repaint rate is unmeasured. Whatever
cadence ships, assume the sprite may hold a single frame when the wrist is down,
and do not make the design depend on motion being visible in AOD.

## What US-049 actually shipped (2026-07-20)

**Superseded on 2026-07-21 by US-107 — see "What US-107 shipped" below. This section is the record
of what 5 s looked like, not the current cadence.**

`ComplicationTimeline` in `Sources/ComplicationViews.swift`, built on the numbers above:

- **5 s spacing**, as recommended — the finest interval honoured exactly on every sample.
- **60 entries, a five-minute horizon**, then `.after` the last entry asks for a fresh batch. The
  horizon and not the spacing is what costs, since a batch is one charge however many entries it
  holds. Five minutes keeps the reload rate in the same order as the daily refresh budget without
  ever asking WidgetKit to archive several hundred entries at once.
- **When the budget runs out, the last entry simply keeps showing** — a still sprite, which is the
  behaviour that shipped before US-049. Degrading to the old complication rather than a broken one is
  the whole reason nothing about correctness rides on this batch; every real state change still
  arrives through the app's own `reloadAllTimelines`.
- **Held poses get one entry**, so sleeping, sick and dead never appear to walk.

The AOD open item above is carried forward unchanged and is still the one thing here that needs real
hardware. Nothing in the shipped design depends on the motion being visible with the wrist down.

## The instrument is gone (2026-07-21)

`RefreshGranularitySpike.swift` and its `#if DEBUG` entry in `DigiVPetComplicationBundle` were
**removed on 2026-07-21** (US-106). It was kept past US-049 in case it could be re-pointed at the
AOD question; it could not, because that needs a real watch and not a second widget. This document
is what the spike produced, and it stands on its own.

**The AOD repaint floor is still unmeasured**, exactly as it has been since US-048. Everything above
was measured with the display awake. If a later story needs the wrist-down number, rebuild the
instrument from the method described here — the entry-band design is written down, it is a page of
code, and reconstructing it on demand is cheaper than carrying a dead widget that offers itself in
the picker on every DEBUG install.

## What US-107 shipped: 1 s / 300 entries (2026-07-21)

The cadence changed from 5 s / 60 entries to **1 s / 300 entries**. The horizon did not move — it is
the same five minutes, so the reload rate is unchanged and only the spacing got finer. That is the
affordable direction, because a batch is one budget charge however many entries it holds (measured
above). Keeping 60 entries at 1 s would have been a one-minute horizon, 1440 reloads a day, and a
frozen still sprite once the budget ran out.

**The 300-entry batch was accepted verbatim, in both families.** Read on Apple Watch Series 9 (45mm),
watchOS 10.4, with the complication live in a face slot:

```
DigiVPetComplication:accessoryCircular    ... entry count: 300; date range: 15:44:30 to 15:49:29
DigiVPetComplication:accessoryRectangular ... entry count: 300; date range: 15:44:30 to 15:49:29
```

299 s end to end, which is 300 entries at exactly 1 s. Seven reloads across the session all
delivered 300; nothing was coalesced or truncated, so the 2 s / 150 fallback US-107 authorised was
not needed. The two `succeeded with 1 entries` lines in the same log are the held-pose path, read
before the published pose was edited from `sleeping` to `idle` — a live confirmation that a sleeping
Digimon still gets exactly one entry.

Repaints on the face were sampled by screenshotting the top-left circular slot 36 times at ~0.30 s
and diffing the crop. The sprite alternated with gaps of **0.90, 0.91, 1.22, 0.89, 1.19, 0.93 s** —
1 s repaints within one sample of the sampling error, no 2 s stalls in that window. The US-048
warning still stands as the general case (1 s is best-effort and *can* be served late); this is one
window, not a refutation of it.

**AOD remains unmeasured.** It has needed real hardware since US-048 and still does. Everything here
was measured with the display awake, so the wrist-down behaviour of this faster cadence is unknown
by construction. Nothing in the design depends on it.

### Two notes for whoever runs this rig next

- **The shipping complication is not `accessoryCorner`**, so the Crosswind `top left` slot US-048
  used is useless for it: chronod answers `CHSErrorDomain Code=1100 "No matching descriptor was
  found for the kind and family specified."` and the widget stays `on no host`. Author a face with
  circular/rectangular slots instead — a `face.json` with `"bundle id":
  "com.apple.NTKInfographModularFaceBundle"`, the same `"type": 56` descriptor in `top left`,
  `middle` and the three `bottom *` slots, plus a `manifest.plist` entry and `selected-uuid.string`
  pointing at the new face UUID. Slots the face does not have are ignored, so listing all of them is
  the cheap way to hit one. The `"style": 44` copied from Crosswind was left as-is and did not stop
  the face loading.
- **`log stream` misses the boot-time reload**, which is the interesting one. Use
  `log show --last 4m` after the device is up instead. Reading a batch also needs a cache miss:
  chronod will not re-request while an archive is valid (an hour, for a held pose), so delete
  `.../PluginKitPlugin/<UUID>/SystemData/com.apple.chrono/timelines/DigiVPetComplication` before
  booting.

## Ruled out, permanently

**Sensor-driven (gyroscope/compass) widget frames.** Not attempted and not to be
attempted later. A widget is not a running process — WidgetKit calls the provider,
renders entries to snapshots, and exits; nothing is alive to receive a sensor
callback when the user is looking at the face. See the design note in
`tasks/prd-vpet-enhancements.md`.
