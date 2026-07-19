# Widget timeline refresh granularity — US-048 spike

**Status: INCOMPLETE. No floor was measured. Do not treat any number below as a finding.**

Measured on: 2026-07-20
Environment: Apple Watch Series 9 (45mm) Simulator, watchOS 10.4 (build 21T214), Xcode 26.4.1, macOS 15 (Darwin 25.4.0)
Physical watch available: none

This document exists because US-049 wants to alternate sprite frames using batched
timeline entries, and the cadence has to come from an observation rather than a
guess. **It did not get one.** What follows is what the attempt established, so the
next attempt starts where this one stopped instead of at the beginning.

---

## The measured floor

**Unknown.** Not measured, not estimated, not inferred.

## The AOD floor

**Unknown**, and unmeasurable in the Simulator at all — see below.

---

## What blocked it

The spike needs the widget to be **live on a watch face**, because a widget that is
not on a host is never asked for a timeline. chronod's own log says so in as many
words — every reference to the spike widget for the whole session was tagged
`on no host`, and the only calls that ever reached
`DigiVPetComplicationExtension` were `placeholder` requests, never `getTimeline`.

Putting a widget on a face is a touch interaction, and this environment has no way
to perform one:

- `simctl` has no touch, tap, swipe, or Digital Crown command. Its full subcommand
  list was checked; the closest things are `io` (screenshot/video only) and `ui`
  (appearance/content-size only).
- Synthetic input from the host is refused. `osascript` gets `-1728` (not allowed
  assistive access), and a direct `CGEvent(...).post(tap: .cghidEventTap)` is
  swallowed — `AXIsProcessTrusted()` returns `false` and the cursor does not move.
  This is a TCC grant only a human at the machine can give.

**Always-On Display is blocked twice over**: it is toggled from the Simulator's
*Features* menu, which is the same unavailable GUI, and AOD render throttling is a
display-hardware behaviour that a simulator is not a trustworthy model of anyway.
**The AOD floor should be measured on a real watch and nowhere else**, whatever
happens with the non-AOD number.

---

## What was established, and is worth keeping

### The spike instrument exists and works

`Sources/Complication/RefreshGranularitySpike.swift`, `#if DEBUG` only, registered
in the widget bundle beside the shipping complication. It emits ONE batched
timeline walking five spacings — 1s ×10, 5s ×6, 30s ×6, 60s ×5, 5min ×5, about 29
minutes end to end, `.atEnd` so it repeats. Every entry draws its band, its index
within the band, and `t+<seconds since the timeline was generated>`, which is what
makes a screenshot self-dating: it says which entry is showing and when that entry
was due.

Confirmed working as far as it can be: the build is green on watchOS 10.4, chronod
ingests both widget kinds, and it rendered placeholders successfully for
`accessoryCorner`, `accessoryCircular`, `accessoryCircularExtraLarge` and
`accessoryRectangular`.

### A watch face complication CAN be installed by editing the sim's face store

This is the part worth not rediscovering. There is no touch needed — the selected
face is plain JSON on the host filesystem:

```
~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/NanoTimeKit/
  CollectionStores/GlobalStores/LibraryFaces/Faces/<FACE-UUID>/face.json
```

Shut the device down, edit, boot. The slot schema was recovered from
`NanoTimeKit`'s own validation errors, one key per attempt:

```json
"complications": {
  "top left": {
    "app": "com.digivpet.DigiVPet",
    "extension": "com.digivpet.DigiVPet.Widget",
    "complication descriptor": {
      "identifier": "widget-com.digivpet.DigiVPet.Widget-DigiVPetRefreshSpike",
      "kind": "DigiVPetRefreshSpike",
      "displayName": "SPIKE refresh",
      "supportedFamilies": ["accessoryCorner", "accessoryCircular", "accessoryRectangular"]
    }
  }
}
```

The identifier format is `widget-<extensionBundleID>-<kind>`, confirmed against the
descriptor manifest nanotimekitd logs at boot. The default Crosswind face's
`top left` slot is a **corner** slot, so the widget must declare
`.accessoryCorner` — the spike does, and the shipping complication deliberately
does not.

**Where it stops.** With the above, NanoTimeKit places the widget in the slot but
classifies it as a **`Remote`** complication (an iPhone-side one awaiting
migration) rather than the local **`Apricot`** kind that system widgets get:

```
NTKCrosswindFace [... top-left:Remote (com.digivpet.DigiVPet.Widget,
                  widget-com.digivpet.DigiVPet.Widget-DigiVPetRefreshSpike) ...]
```

A `Remote` on a watch-only app never resolves, so the slot draws empty and the
widget stays `on no host`. **This is the one remaining unknown**: which JSON key
marks a slot as native/Apricot rather than Remote. The likely lead is chronod's
`nativeContainerBundleIdentifier` / `nativeCBI` field, which it logs migrating
(`com.digivpet.DigiVPet.Widget:DigiVPetRefreshSpike` → `com.digivpet.DigiVPet`)
and which has no counterpart in the face JSON yet. Compare against a system
widget's own slot encoding.

Progression of the four attempts, in case the error strings help someone:
1. descriptor as a bare string → `missing value for key 'extension'`
2. added `extension` → parsed, slot empty (widget had no `accessoryCorner` yet)
3. added `accessoryCorner` → `-[__NSCFString objectForKeyedSubscript:]` — the
   descriptor must be a **dictionary**, not a string
4. descriptor as a dict with `identifier`+`kind` → `Tombstone of Remote`;
   adding `displayName`+`supportedFamilies` promoted it to `Remote`. Stopped here.

### The readout, once it is on a host, should be logs not screenshots

chronod archives each delivered timeline and logs it with an entry count and a date
range, under subsystem `com.apple.chrono`, categories `timeline` and `archiving`:

```bash
xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "com.apple.chrono"'
```

The archives themselves are `.chrono-timeline` files under the extension's
`Containers/Data/PluginKitPlugin/<UUID>/SystemData/com.apple.chrono/`. Comparing
the entry dates chronod **accepted** against the dates the provider **requested**
measures coalescing directly, with no screenshot timing error and no 29-minute
wall-clock wait. Prefer this to the screenshot plan the spike view was designed
for; keep the view anyway as the confirmation that a coalesced entry is also a
*rendered* entry, which the logs alone do not prove.

---

## What this means for US-049

**US-049 should not be started on the strength of this document.** It has no floor
in it, so there is nothing to design a cadence around, and the whole point of
sequencing this spike first was to stop US-049 committing to a guess.

Two honest ways forward, in preference order:

1. **Measure it on a real Apple Watch.** Add the spike complication to a face by
   hand — thirty seconds of tapping — and read the chronod log. This also gets the
   AOD number, which the Simulator cannot give at any price.
2. **Finish the face-store injection** above by finding the native/Apricot key.
   That yields the non-AOD floor only; the AOD half of the story still needs
   hardware.

If the floor comes back coarser than about two minutes, US-049 is not worth
forcing: a "walk cycle" whose two frames swap every two minutes is not animation,
it is a stale complication with extra steps, and the honest move is to close
US-049 as not-viable rather than ship it degraded.

## Ruled out, permanently

**Sensor-driven (gyroscope/compass) widget frames.** Not attempted here and not to
be attempted later. A widget is not a running process — WidgetKit calls the
provider, renders entries to snapshots, and exits; nothing is alive to receive a
sensor callback when the user is looking at the face. See the design note in
`tasks/prd-vpet-enhancements.md`.
