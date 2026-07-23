# PRD: Per-Map Eggs, the Sleep Screen, and a Staggered Action Grid

## Introduction

This PRD is a batch of main-screen and map reworks that follow the US-193…US-205 polish pass.
It does five things:

1. **Fixes a real bug** — a map's Digitama conditions read as *already unlocked* the moment you
   enter a new map, because they are evaluated against **global** counters. Progress toward a map's
   egg must be scoped to *that map*.
2. **Changes how eggs are found** — winning a battle *inside a map* now becomes the moment the map
   checks its egg condition and, if met, gives a **chance** at the egg. The condition line stays
   drawn under the egg art **even after the egg is in hand**.
3. **Unifies the action buttons** — every progress reading becomes a segmented ring around the
   button it belongs to (Feed/meat and Map/steps join Train/Battle/Clean), the Clean and Battle
   glyphs go back to their earlier icons, and the map name + Party button come off the strip and
   into the grid. The grid itself becomes an Apple-Watch-list-style **staggered, scrollable** grid.
4. **Adds a Sleep screen** — a new bed/sleep button (with the Zz reading as its ring) opens a Sleep
   Time view that shows the active Digimon's total sleep and its per-Digimon sleep / wake / nap
   schedule.
5. **Two small polish items** — the Settings screen shows the data-collection (HealthKit) status,
   and the wandering Digimon walks at one steady pace edge-to-edge instead of occasionally
   sprinting across the screen.

**These stories are additive.** Do not touch or re-open the already-failing stories US-168, US-169,
US-201, US-202, US-203, US-204, US-205 — leave their `passes: false` as they are.

## Goals

- A map's egg conditions measure progress made **on that map**, so a fresh map starts locked.
- Winning a battle is the moment a map may award its egg, with a ~50% chance when the condition is
  met; the condition line is always visible under the egg, held or not.
- Every spendable/earned reading is a ring of **10 segments** around its own button — Feed (meat),
  Train, Clean, Battle, and Map (steps) — with the ring divider spacing consistent across all five.
- The Clean and Battle buttons show their pre-US-197 glyphs again.
- The map name label and the Party button leave the area under the sprite; both live in the grid.
- The action grid reads like a watchOS list: staggered rows (5 / 4 / …), sized like list rows, and
  scrollable so more buttons can be added without crowding.
- A Sleep button opens a Sleep Time view with a per-Digimon, deterministic sleep schedule.
- Settings reflects the real data-collection authorization state.
- The wandering sprite never teleports or sprints; it paces at one constant speed, wall to wall.

## User Stories

### US-206: A map's Digitama conditions measure progress *on that map*, not globally
**Description:** As a player, I want each map's egg to start locked when I arrive, so that finding an egg reflects what I have done *in that map* rather than everything I have ever done.

**Context:** `DigitamaDrop.eligibleSlots` (`Sources/DigitamaDrop.swift`) tests each slot with
`ConditionReveal.allMet(slot.conditions, in: context)`, and the same `ConditionContext` is what the
Dex and `MapDetailView` read. Today that context is built from **global** lifetime counters (total
steps, `care.battleCount`, etc.), so a slot gated on e.g. `care.battleCount stage atLeast 1` or
`health.steps day atLeast 2000` can read as already-met the instant a new map is selected.

**Acceptance Criteria:**
- [ ] Map-scoped counters exist and persist per map: at minimum steps-walked-in-this-map and
      battles-won-in-this-map are tracked separately for each map id (survive relaunch via `GameState`).
- [ ] Selecting a **new** map (one with no prior progress) shows its Digitama conditions as **not met**
      in `MapDetailView` — no "Ready to find" mark appears purely because of global history.
- [ ] Switching back to a map where progress was earned restores that map's own progress (counters do
      not leak between maps).
- [ ] `DigitamaDrop.eligibleSlots` / the condition context it uses reads the **selected map's** scoped
      counters for map-scoped conditions, not the global lifetime totals.
- [ ] Clock stays injectable; any time-based condition is tested against the injected clock, not real time.
- [ ] A regression test proves: enter map A, meet its condition; enter fresh map B → B's matching
      condition is NOT met; return to A → A's condition is still met.
- [ ] Build green; existing tests pass.

### US-207: Win a battle to (maybe) find the egg — and the condition stays shown after you have it
**Description:** As a player, I want winning a battle in a map to be the moment the map might give me its egg, and I want to keep seeing the egg's condition under its picture even after I own it, so I always understand what that egg is about.

**Context:** `DigitamaDrop.award(in:context:held:)` currently runs after train / battle / step.
This story makes the **battle win** the primary award moment and gates the actual drop on a chance
roll. `MapDetailView`'s `DigitamaSlotDetail` withholds a slot's `conditions` once the egg is held
(see the note at `Sources/MapDetailView.swift`), which is exactly what must change.

**Acceptance Criteria:**
- [ ] When a battle is **won** inside a map and that map has an egg slot whose (now map-scoped, US-206)
      condition is met and whose egg is not yet held, the game rolls a **~50%** chance to award the egg.
- [ ] The chance uses an injectable/seedable RNG so a test can force both the win-drop and the win-no-drop
      outcomes deterministically.
- [ ] A losing battle never awards an egg.
- [ ] When the condition is met but the egg is NOT dropped this time, the game does not consume or reset
      the condition — the next qualifying win rolls again.
- [ ] Under a Digitama slot's image, the condition line(s) are drawn **whether or not the egg is already
      held** (remove the "hide conditions once held" behavior).
- [ ] For a held egg the condition line reads as satisfied/complete (e.g. a checkmark or "Found"), not as
      an outstanding task, but it is still visible.
- [ ] The existing found-an-egg banner (`DigitamaDropBanner`) still shows on a real drop.
- [ ] Tests: forced-hit roll on a qualifying win drops the egg; forced-miss roll does not; a loss never
      drops; a held egg still renders its condition line.
- [ ] Build green. Verify the map detail in the simulator: a held egg shows art + its condition line.

### US-208: The Feed button wears a meat ring like the others
**Description:** As a player, I want the Feed button to show a ring of how much meat is in the larder, so it matches Train, Clean and Battle instead of being a lone bar.

**Context:** `Sources/ContentView.swift` still draws meat as a standalone `DashBar`
(`DashBar(filled: model.meat, total: model.meatCap, tint: .orange, dashHeight: 5)`), while the other
three currencies became `DashRing` overlays on their buttons in US-199. The Feed button
(`Sources/ActionControls.swift`, `fork.knife`, `.orange`) has no ring.

**Acceptance Criteria:**
- [ ] The Feed button carries a `DashRing` overlay driven by `model.meat` / `model.meatCap`, orange,
      exactly like Train/Clean/Battle carry theirs.
- [ ] The standalone meat `DashBar` row is removed from `ContentView` (meat now reads only as the ring).
- [ ] The ring updates when meat is spent by feeding and refilled, same as before.
- [ ] Feed's accessibility value announces the meat amount (matching the `chargeValue` pattern).
- [ ] Build green. Verify in the simulator with a screenshot that the Feed button shows a filled ring.

### US-209: Clean and Battle go back to their previous glyphs
**Description:** As a player, I want the Clean and Battle buttons to use the icons they had before, because I preferred the earlier ones.

**Context:** US-197 changed Clean to a `.waste` coil glyph and Battle to `figure.martial.arts`
(`Sources/ActionControls.swift`). This reverts both to the glyphs used before that change.

**Acceptance Criteria:**
- [ ] The Clean button uses its pre-US-197 icon again (the earlier sparkle/clean glyph, not the waste coil).
- [ ] The Battle button uses its pre-US-197 icon again (the earlier battle glyph, e.g. the bolt, not
      `figure.martial.arts`).
- [ ] Both buttons keep their existing rings, disabled states, tints, and accessibility labels.
- [ ] The exact previous glyph names are recorded in a code comment so the revert is auditable.
- [ ] Build green. Verify both glyphs in the simulator with a screenshot.

### US-210: The map name and Party button move off the sprite area into the grid
**Description:** As a player, I want the map name label and the two-people Party button removed from under the Digimon's play area, because those belong with the other buttons, not floating under the sprite.

**Context:** `Sources/ContentView.swift` draws `MapStripView(strip:...)` and passes `mapName` into
`MainReadingBars` under the sprite. The Party navigation already exists inside `ActionControls`
(`person.2.fill`, `.teal`) via `partyDestination`.

**Acceptance Criteria:**
- [ ] The map-name text is no longer drawn under the sprite / above the action grid (remove the
      `MapStripView` name label and the `mapName:` reading from that area).
- [ ] The Party button (two-people icon) no longer appears under the sprite; it appears only as a grid
      button.
- [ ] Selecting a map is still reachable — via the grid's Map button — so no navigation is lost.
- [ ] The Party grid button still opens `PartyView` with the same activate/fuse wiring.
- [ ] Nothing that used the removed label is left dangling (no dead `mapName` plumbing).
- [ ] Build green. Verify in the simulator: no map name and no party icon under the sprite.

### US-211: The action grid becomes a staggered, scrollable, list-style grid
**Description:** As a player, I want the buttons laid out like an Apple Watch app list — sized like list rows and staggered — and scrollable, so the grid can grow without feeling cramped.

**Context:** `Sources/ActionControls.swift` currently lays out two flush `HStack` rows of four.
Keeping the current button order and appending the new Sleep button (US-213), the grid becomes:
Row 1 (5): **Feed, Train, Clean, Battle, Map**. Row 2 (4): **Party, Light, Dex, Sleep**.

**Acceptance Criteria:**
- [ ] Row 1 holds 5 buttons and Row 2 holds 4 buttons, and Row 2 is **staggered** — horizontally
      offset by about half a cell so its buttons sit between Row 1's, watchOS-list style.
- [ ] Button/icon sizing reads like a watchOS list row (document the diameter constant chosen).
- [ ] The grid is wrapped so it **scrolls** vertically when it is taller than the available area,
      leaving room for a future third row of up to 5 buttons without a layout change.
- [ ] Button order is preserved from the current grid, with the new Sleep button appended (Feed, Train,
      Clean, Battle, Map / Party, Light, Dex, Sleep).
- [ ] All existing per-button rings, disabled states, actions, and accessibility labels still work.
- [ ] No horizontal clipping on the narrowest supported watch (42mm) or the 46mm.
- [ ] Build green. Verify in the simulator with screenshots on both watch sizes.

### US-212: Map steps become a ring around the Map button; every ring is 10 segments
**Description:** As a player, I want the map's step progress drawn as a ring around the Map button like the other buttons, and I want all the rings to use the same 10-segment spacing, so the whole grid reads consistently.

**Context:** Map-step progress is drawn today as a `DashBar` inside `MainReadingBars`
(`Sources/ContentView.swift`), reading `strip.recordedSteps` / `strip.totalSteps`. The Map button
lives in `ActionControls`. `DashRing` (`Sources/DashBar.swift`) draws the segmented ring.

**Acceptance Criteria:**
- [ ] The Map button carries a `DashRing` overlay driven by the map's recorded / total steps
      (green tint, matching the Map glyph).
- [ ] The map-step `DashBar` reading is removed from `MainReadingBars` (steps now read only as the ring).
- [ ] Every progress ring — Feed (meat), Train, Clean, Battle, and Map — is drawn as **10 segments**
      with the **same divider spacing** between segments (define one shared segment count / spacing
      constant; "10 space" = 10 segments per ring).
- [ ] A ring with a partial value fills the correct number of the 10 segments (rounding rule documented).
- [ ] Map accessibility value announces the step progress.
- [ ] Build green. Verify in the simulator that all five rings share the same 10-segment look.

### US-213: A Sleep button, ringed with the Zz reading, opens the Sleep Time view
**Description:** As a player, I want a bed/sleep button whose ring is the sleep (Zz) progress, and tapping it opens a screen about my Digimon's sleep, so sleep has a home like the other actions.

**Context:** Sleep hours read as the "Zz" `DashBar` in `MainReadingBars` today
(`model.sleepHours` / `model.sleepHoursCap`, `Sources/ContentView.swift`). This makes it a ringed
grid button and adds the navigation target built in US-214.

**Acceptance Criteria:**
- [ ] A new grid button uses a bed/sleep SF Symbol (e.g. `bed.double.fill`), appended per US-211.
- [ ] The button carries a `DashRing` overlay driven by `model.sleepHours` / `model.sleepHoursCap`
      (10 segments, US-212), so the Zz reading now lives on this button.
- [ ] The sleep `DashBar` (Zz) reading is removed from `MainReadingBars` — sleep reads only as the ring.
- [ ] Tapping the Sleep button navigates to the Sleep Time view (US-214) via a `NavigationLink`,
      consistent with Map/Party/Dex.
- [ ] Accessibility: labelled "Sleep", value announces slept vs. goal hours.
- [ ] Build green. Verify in the simulator: the Sleep button shows the Zz ring and pushes the Sleep view.

### US-214: The Sleep Time view — total sleep and a per-Digimon sleep / wake / nap schedule
**Description:** As a player, I want a screen that shows how much my Digimon has slept and the times it sleeps, wakes, and naps, so its rest feels personal to each Digimon.

**Context:** New view. The schedule is **derived per Digimon** (deterministic from the Digimon id) so
every Digimon has stable, distinct times without authoring data for 200+ entries.

**Acceptance Criteria:**
- [ ] The view shows the active Digimon's **total sleep time** (from `model.sleepHours` / the sleep
      accounting already on the model).
- [ ] The view shows a **bedtime** and a **wake time** and at least one **nap** window for the active
      Digimon.
- [ ] The schedule is a pure, deterministic function of the Digimon id: the same Digimon always shows
      the same times, and two different Digimon show different times (no real-clock randomness).
- [ ] The nap window is included in a sensible way (e.g. total = night sleep + nap, or clearly labelled).
- [ ] A pure function computes the schedule from an id and is unit-tested: determinism (same id → same
      times) and distinctness (a couple of known ids differ) are both asserted.
- [ ] Times are formatted for the watch (e.g. `22:30` / `07:00`) and the layout scrolls on the 42mm watch.
- [ ] Build green. Verify the Sleep view in the simulator with a screenshot (add a demo flag if needed).

### US-215: Settings shows the data-collection status
**Description:** As a player, I want the Settings screen to tell me whether the app is collecting my health data, so I know the current data-collection state.

**Context:** US-198 put a settings gear in the top-right holding notification settings. HealthKit
authorization state lives in `Sources/HealthAuthorization.swift` (`StubHealthAuthorizer.Outcome`,
launch flags `-healthAnswered` / `-healthDenied` / `-healthUnavailable`).

**Acceptance Criteria:**
- [ ] The Settings screen shows a data-collection status row reflecting the real authorization state
      (e.g. "Collecting health data" / "Not collecting" / "Unavailable").
- [ ] The status is read from the same authorization source the app uses, not hard-coded.
- [ ] The three stub outcomes (`-healthAnswered`, `-healthDenied`, `-healthUnavailable`) each produce the
      correct status text.
- [ ] Wording is clear that data never leaves the watch, consistent with the existing HealthKit intro copy.
- [ ] Build green. Verify each status in the simulator via the three launch flags with screenshots.

### US-216: The Digimon paces at one steady speed, wall to wall — no sprinting
**Description:** As a player, I want the Digimon to walk at a constant speed all the way to the right edge and back to the left, without suddenly sprinting or jumping across the screen.

**Context:** `Sources/Movement.swift` `MovementModel` catches up skipped time by applying many 0.25s
steps at once (`advance(to:)` up to `maximumCatchUp`), which reads as a sprint when the view
re-appears; and `decide()` randomly rests/reverses mid-screen, so the walk is jittery rather than a
clean edge-to-edge pace. `SpriteWanderer` (`Sources/WanderingSpriteView.swift`) drives it.

**Acceptance Criteria:**
- [ ] The sprite moves at one constant per-step distance and never covers a large distance in a single
      visible jump: on re-appearing after being hidden/backgrounded, it does NOT teleport or sprint —
      catch-up is capped so at most a small, unnoticeable number of steps apply (or it resumes in place).
- [ ] The walk is a deterministic ping-pong: from wherever it is, it walks to one edge, reverses at the
      wall, walks to the other edge, and repeats — no random mid-screen direction changes that read as
      "flying around".
- [ ] The pace still reads as alive (it keeps walking) but calm; document the chosen behavior for
      resting, if any, in a comment.
- [ ] Bound handling still turns exactly at the edge (keep the `>=` wall behavior).
- [ ] `isMoving: false` (asleep / eating / battle) still holds the sprite in place and resumes without a
      catch-up burst.
- [ ] Tests: a long elapsed gap applied via `advance(to:)` does not move the sprite more than the capped
      amount; a run of steps produces a monotonic edge-to-edge pace (no direction change before a wall).
- [ ] Build green. Verify in the simulator (`-wanderDemo`) that the walk is smooth and edge-to-edge.

## Functional Requirements

- FR-1: Track per-map progress counters (at least steps and battles-won) in `GameState`, keyed by map id,
  persisted across relaunch.
- FR-2: Build the Digitama condition context for a map from that map's scoped counters, so a fresh map
  reads as not-yet-met.
- FR-3: On a battle **win** in a map with a met, unheld egg condition, roll a ~50% seedable chance to award
  the egg; a loss never awards; a miss leaves the condition intact for the next win.
- FR-4: Always render a Digitama slot's condition line(s) under its art, held or not; a held egg shows the
  condition as satisfied but still visible.
- FR-5: Draw meat as a `DashRing` on the Feed button and remove the standalone meat `DashBar`.
- FR-6: Restore the Clean and Battle button glyphs to their pre-US-197 icons.
- FR-7: Remove the map-name label and Party button from under the sprite; Party stays only as a grid button.
- FR-8: Lay out the action grid as staggered rows (Row 1 = 5, Row 2 = 4, offset), list-row sized, wrapped in
  a vertical scroll, with headroom for a third 5-button row.
- FR-9: Draw map-step progress as a `DashRing` on the Map button and remove the map-step `DashBar`.
- FR-10: Every progress ring uses one shared 10-segment spec (10 segments, identical divider spacing).
- FR-11: Add a bed/sleep grid button whose ring is the sleep (Zz) reading; remove the sleep `DashBar`.
- FR-12: Add a Sleep Time view showing total sleep plus a deterministic per-Digimon bedtime, wake time, and
  nap window, computed purely from the Digimon id.
- FR-13: Show the real data-collection authorization status in Settings.
- FR-14: Make the wander a constant-speed, capped-catch-up, edge-to-edge ping-pong with no mid-screen
  random dashes.

## Non-Goals (Out of Scope)

- No changes to the already-failing stories US-168, US-169, US-201–US-205 (leave `passes: false`).
- No new Digimon, sprites, evolution edges, or authored sleep-schedule data files.
- No change to how HealthKit data is gathered — US-215 only *displays* the existing status.
- No editing of egg **drop odds per slot** beyond the single ~50% win roll (no per-map rarity tables).
- No change to the battle engine's outcome logic; US-207 only hooks the award onto the win result.
- No animation of the sleep schedule (no live clock hands); a static schedule readout is enough.

## Design Considerations

- Reuse `DashRing` / `DashRingSegment` (`Sources/DashBar.swift`) for every button ring; centralize the
  10-segment count and spacing so all five rings are provably identical.
- Reuse `ActionButtonFace` (`Sources/ActionControls.swift`) for the new Sleep button so it matches.
- The staggered grid should follow the watchOS app-grid feel: circular faces, list-row sizing, Row 2
  nudged half a cell so it interlocks with Row 1.
- The Sleep Time view should match existing pushed screens (`PartyView`, `MapListView`, `DexView`) in
  navigation and typography.

## Technical Considerations

- Keep the clock injectable everywhere time is read (per-map time conditions, sleep schedule if it ever
  reads "now"); tests must never wait real time.
- The egg-drop chance must take a `RandomNumberGenerator` so both branches are testable, matching the
  seedable style already used in `DigitamaDrop.award`.
- Per-map counters are a `GameState` schema addition — remember the three-line contract noted in
  `progress.txt` (property + `Freeze.shiftTimeline` line + the one lifecycle write site).
- Watch out for the stale-DerivedData and HealthKit-intro gotchas documented in `progress.txt` when
  screenshotting (build/install from an explicit `-derivedDataPath`; launch with `-healthAnswered`).

## Success Metrics

- Entering a brand-new map never shows a "Ready to find" egg from global history.
- A player can win battles in a map and occasionally receive that map's egg, and always read the egg's
  condition on the map screen.
- The main screen reads as one consistent grid of ringed buttons with no floating bars, name label, or
  stray party icon.
- The wandering Digimon never visibly teleports or sprints during a normal session.

## Open Questions

- Exact per-Digimon schedule formula (hash → times) — any constraints on plausible bedtime/nap ranges?
- Should the Map ring's "total steps" be the map's full length or the current segment? (Default: mirror
  whatever `strip.totalSteps` means today.)
- Should a held egg's condition line show the *original* condition text or a generic "Found on <map>"?
  (Default: original text, marked satisfied.)
