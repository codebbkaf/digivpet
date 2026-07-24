# PRD: Egg stillness, a shorter play area, a smaller Digimon, and a smooth walk

## Introduction

Five main-screen defects, all about what the player sees in the room where the Digimon lives.

1. **A Digitama behaves like a hatched Digimon.** The egg walks back and forth across the floor, and
   Feed, Train and Battle all work on it. An egg has no legs, no mouth and no fists — its sprite
   sheet is 48×16 (idle, wobble, hatch) with no eat, attack or refuse frame at all — so every one of
   those actions draws a pose the art does not have and tells a story the game does not mean.
2. **The play area is too tall.** The Digimon's slot is the one flexible row on the screen and it
   claims every point the fixed rows leave, so the map background and the walking floor dominate the
   display. The player wants that band cut to **80% of its current height** (a 20% trim).
3. **The Digimon itself is too big.** Even inside a shorter band, the sprite dominates. It should be
   drawn at roughly **80% of its current size**.
4. **An egg can take forever to hatch.** Hatching is gated on 50 total energy, which comes entirely
   from HealthKit — and HealthKit has no data in the Simulator by default, so a test save's egg never
   hatches at all. The egg should also hatch on **5 minutes elapsed** or **500 steps walked**,
   whichever comes first.
5. **The walk still is not smooth.** US-216 made the pace constant, but the model is integrated in
   whole 0.25s steps and drawn straight, so the sprite teleports 7.5pt four times a second. Constant
   speed, visibly discrete motion.

## Goals

- A Digitama stands perfectly still and cannot be fed, trained or sent to battle; it can still be
  cleaned up after, still has its light switched, and still accumulates energy.
- Every refused egg action explains itself in one short line and costs the player nothing — no
  energy, no charge, no care mistake.
- An egg hatches promptly: on 50 total energy **or** 5 minutes **or** 500 steps, whichever lands
  first, including while the app was closed.
- The sprite slot and the map background painted behind it are drawn at 80% of the height they get
  today; the reclaimed 20% is left as empty margin.
- The Digimon is drawn at 80% of the height it gets in that band, taking it one further step down the
  whole-number scale ladder.
- The walk reads as continuous motion at the same speed it has now, with no change to the movement
  model's step, cadence or path.

## User Stories

### US-217: A Digitama does not walk

**Description:** As a player, I want my unhatched egg to sit still instead of pacing the floor, so
that it reads as an egg rather than as a Digimon that lost its legs.

**Acceptance Criteria:**
- [ ] While `state.stage == .digitama`, `MainScreenModel.isWandering` is `false`, so
      `WanderingSpriteView` is passed `isMoving: false` and the egg holds one position.
- [ ] The egg holds the position it was created at (centre), not wherever a previous Digimon stood.
- [ ] The suspension goes through `MovementModel.hold(at:)` — the existing `isMoving: false` path —
      so the walk's clock keeps up and the Digimon does **not** lurch across the floor on the first
      frame after it hatches.
- [ ] The instant the egg hatches into Baby I, walking resumes with no jump: the newly hatched
      Digimon starts walking from where the egg sat.
- [ ] Every other reason `isWandering` is already false (asleep, eating, sick, dead, overlay up)
      still turns it off — this is an added condition, not a replacement.
- [ ] Tests: a model at `.digitama` reports `isWandering == false`; the same model at `.babyI`
      reports `true`; a `MovementModel` given only `hold(at:)` calls over a long span has offset 0.
- [ ] Typecheck passes (`xcodebuild build`).
- [ ] Verify on the watchOS Simulator: two screenshots of a fresh save ≥2s apart show the egg in the
      same place. **Pace screenshots at least 2s apart** — a burst starves the `TimelineView` and
      makes any sprite look frozen (see progress.txt, US-216 learnings).

---

### US-218: Feed, Train and Battle are refused while it is still an egg

**Description:** As a player, I want the Feed, Train and Battle buttons to be visibly unavailable
while my Digimon is an egg, so that I am not spending meat, charges and energy on something that
cannot eat, train or fight.

**Acceptance Criteria:**
- [ ] `ActionControls` receives a new flag (e.g. `isEgg`) and applies `.disabled(true)` to the Feed,
      Train and Battle buttons when it is set. The disabled circles grey out through the existing
      `ActionButtonFace` `@Environment(\.isEnabled)` path — **no second source of truth for the
      enabled state.**
- [ ] Clean, Light, Map, Party, Dex and Sleep stay enabled and unchanged while the egg is unhatched.
- [ ] The grid still draws all nine circles — nothing is removed or re-laid-out, so
      `ActionGridLayout.rowCounts(forButtons: 9) == [5, 4]` is unchanged.
- [ ] `MainScreenModel.feed()`, `train()` and `battle()` each guard on `.digitama` and return the
      blocked outcome with a short reason shown in the existing orange `actionMessage` line
      (e.g. `"It is still an egg."`). Wording may differ per action but must fit the 9pt one-line
      name row.
- [ ] **The egg guard runs FIRST — before `wakeIfAsleep()` and before each action's existing rule.**
      A blocked egg action therefore charges **no care mistake**, spends **no meat, energy or
      charge**, opens **no minigame**, and plays **no pose and no motion** (same treatment as any
      other `.blocked` outcome).
- [ ] Tests: at `.digitama`, `feed()` returns `.blocked`, `train()` returns `.blocked`, and
      `battle()` returns `nil` with a message set; the profile's meat, the state's train/battle
      charges, its energy totals and its care-mistake counters are all **unchanged** across all
      three; `pendingTraining` and `pendingBattleRound` stay nil. The same three calls at `.babyI`
      behave exactly as they do today.
- [ ] Typecheck passes; full suite green.
- [ ] Verify on the watchOS Simulator: a screenshot of a fresh (unhatched) save shows Feed, Train
      and Battle greyed and Clean/Light/Map/Party/Dex/Sleep in colour, plus a screenshot of the
      message after tapping Feed.

---

### US-219: The play area and the map behind it are 80% of their old height

**Description:** As a player, I want the Digimon's band and its map backdrop to take less of the
screen, so that the display is less dominated by scenery.

**Acceptance Criteria:**
- [ ] A new named constant carries the fraction (e.g. `MainScreenLayout.playAreaHeightFraction =
      0.8`), free-standing and non-generic so a test can read it without building a view graph —
      the same pattern as `SpriteScale`, `MapBackgroundLayout` and `MainScreenLayout`.
- [ ] The sprite's flexible row is given a height of `floor(available * 0.8)`; the remaining 20% is
      **left empty**. Nothing else on the screen grows into it — the action grid, the stats strip
      and the name row keep the heights and positions they have today.
- [ ] The shortened band stays vertically **centred** in the flexible row, so the reclaimed margin
      splits above and below rather than pushing the Digimon to one end.
- [ ] `SpriteSlotBoundsKey`'s `anchorPreference` is attached to the **shortened** band, so the map
      background, the light scrim and the poop pile — all of which are placed off that anchor —
      shrink with it automatically and stay exactly co-located. There must be no second piece of
      arithmetic computing the same rect.
- [ ] The map background still `.scaledToFill()`s and is still `.clipped()` to the (now shorter)
      slot — no letterboxing bands appear inside the band.
- [ ] The sprite is still sized by `SpriteScale.fitting` against the shortened slot, so it never
      overflows the band it is drawn in.
- [ ] **Re-measure and update the pinned slot heights.** `MainScreenLayoutTests` currently pins
      41.5pt (41mm) and 56.0pt (46mm) as *measured evidence*, with the comment that a later layout
      change must re-measure them. Take fresh Simulator measurements at both sizes, update those
      assertions, and record the numbers in progress.txt. Expect the 46mm sprite to drop from
      scale 3 to scale 2 — that is the accepted cost of the trim, not a bug.
- [ ] The sprite never goes below `SpriteScale.minimum` (2) at either screen size; if the trim would
      push it there, say so in the notes rather than lowering the floor.
- [ ] Typecheck passes; full suite green.
- [ ] Verify on the watchOS Simulator at **both** 42mm and 46mm, with a map selected: screenshots
      show a visibly shorter map band with clear margin above and below it, the Digimon inside that
      band, and every action circle still on screen and untouched.

---

### US-220: The walk is drawn continuously between simulation steps

**Description:** As a player, I want the Digimon to glide across the floor instead of hopping, so
that the pace US-216 made constant also *looks* constant.

**Acceptance Criteria:**
- [ ] **`MovementModel` is not changed at all.** Its `step`, `pointsPerSecond`, `stepDistance`,
      `maximumCatchUpSteps` and ping-pong path stay exactly as US-216 left them; this is a rendering
      change in `WanderingSpriteView` only.
- [ ] The drawn horizontal offset is tweened between steps with a **linear** animation whose
      duration equals `MovementModel.step`, so each hop finishes exactly as the next begins and the
      on-screen velocity is continuous and constant — no ease-in/ease-out, which would re-introduce a
      visible pulse at every step.
- [ ] The tween duration is a named constant (e.g. `WalkTween.duration`) derived from
      `MovementModel.step` rather than a literal `0.25`, and a test asserts the two are equal — so
      changing the model's step can never leave the tween out of sync.
- [ ] **The animation is scoped to the walk offset only.** `flipped` must NOT animate: a tweened
      mirror reads as the sprite squashing flat and inflating again at every wall. The sprite frame
      index (walk1/walk2) must not animate either.
- [ ] While a `motion` is playing (chew, shake), the walk tween is off — the motion already ticks at
      `ActionMotion.tick` and the walk is held at a fixed offset for the motion's whole length, so a
      tween on top would fight it.
- [ ] Turning at a wall still looks like a turn: the sprite tweens into the bound and back out, with
      no overshoot past `bound` and no visible pause at the edge.
- [ ] A held sprite (`isMoving: false` — asleep, eating, an egg per US-217, an overlay up) does not
      drift: with the offset constant there is nothing to tween.
- [ ] Coming back from the background does not produce one long slide: the existing
      `maximumCatchUpSteps` cap means at most 15pt is ever tweened at once.
- [ ] Typecheck passes; full suite green (all 2746 existing tests still pass).
- [ ] Verify on the watchOS Simulator with `-wanderDemo`: a sequence of screenshots ≥2s apart shows
      the sprite at intermediate positions that are **not** multiples of `stepDistance` from where it
      started — evidence the drawn position is being interpolated rather than snapped.

### US-221: The Digimon is drawn at 80% of its size, one step further down the ladder

**Description:** As a player, I want the Digimon sprite itself to be smaller, so that it does not
dominate the watch face.

**Acceptance Criteria:**
- [ ] A new named constant carries the fraction (e.g. `SpriteScale.sizeFraction = 0.8`), separate
      from US-219's `playAreaHeightFraction` so the two can be tuned independently.
- [ ] The fraction is applied to the height **handed to** `SpriteScale.fitting`, i.e.
      `SpriteScale.fitting(SickBadgeLayout.spriteHeight(in: slotHeight, isSick:) * sizeFraction)`.
      It must **not** be applied by lowering `SpriteScale.maximum` — the ceiling does not bind on
      either supported screen, so that would change nothing.
- [ ] `SpriteScale.minimum` drops from **2 to 1**. This is required, not incidental: the floor only
      binds below 32pt, so without lowering it the 41mm sprite cannot shrink at all.
- [ ] `SpriteScale.fitting` still returns whole numbers only, for every input — the existing
      `testTheScaleIsAlwaysAWholeNumber` must still pass untouched. Fractional scales resample 16×16
      art onto a grid it does not line up with, which `.interpolation(.none)` renders as uneven pixel
      widths rather than hiding as blur.
- [ ] The sprite still never exceeds the band it is drawn in at either screen size — it is drawn with
      `.offset`, so an overflow does not clip, it lands on top of the rows above and below.
- [ ] `SpriteScale.minimum`'s doc comment is rewritten. It currently states 2 as a hard readability
      floor ("32pt is still a recognisable Digimon — the complication draws one no larger"); that
      reasoning is being overridden by an explicit product decision and the comment must say so
      rather than contradict the code.
- [ ] `MainScreenLayoutTests` is updated for the new floor, and the measured slot/scale pairs are
      **re-measured on the Simulator** at both sizes rather than predicted, with the numbers recorded
      in progress.txt.
- [ ] The complication is unaffected — `ComplicationViews` has its own sizing and must not inherit
      this fraction.
- [ ] Typecheck passes; full suite green.
- [ ] Verify on the watchOS Simulator at **both** 42mm and 46mm: screenshots show a visibly smaller
      Digimon, still walking the floor, with no part of it overlapping the stats strip, the name row
      or the action grid.

**Expected arithmetic (verify, do not assume).** Compounded on top of US-219's shorter band:

| | slot today | after US-219 (×0.8) | sprite height (×0.8) | scale | sprite |
|---|---|---|---|---|---|
| 41mm | 41.5pt | ~33.2pt | ~26.6pt | 1 | 32pt → **16pt** |
| 46mm | 56.0pt | ~44.8pt | ~35.8pt | 2 | 48pt → **32pt** |

Both fit their band with margin (16 < 33.2, 32 < 44.8), so the two fractions compounding does not
cause an overflow. **These are predictions from the currently pinned measurements — re-measure.**

---

### US-222: The egg hatches after 5 minutes or 500 steps

**Description:** As a player, I want my Digitama to hatch reasonably soon after I start, so that I am
not staring at an egg that may never crack — especially in the Simulator, where there is no health
data to earn the 50 energy with.

**Acceptance Criteria:**
- [ ] `EggHatcher.hatchTarget` gains an **OR** of three paths, and hatches when **any** is met:
      - total stage energy ≥ the hatch edge's `minEnergy` (the existing 50, still read from the
        graph data and not duplicated here);
      - `now - stageEnteredDate >= EggHatcher.maximumEggDuration` (a new constant, 5 × 60 seconds);
      - `state.stageMetricTotals[.healthSteps] >= EggHatcher.stepsToHatch` (a new constant, 500).
- [ ] Both new thresholds are named constants on `EggHatcher`, next to each other, in the spirit of
      `EvolutionTiming` ("retuning the pacing is editing these numbers, not hunting through the
      engine").
- [ ] The comparisons are `>=`, matching the existing energy threshold: an egg at exactly 5 minutes
      or exactly 500 steps hatches.
- [ ] `EggHatcher.hatchTarget` stays a **pure function** with the clock passed in as `now: Date` —
      never `Date()` inside. Tests must not wait real time.
- [ ] Steps are read from `stageMetricTotals`, which `enterStage(at:)` already clears, so the 500 is
      counted **since this egg appeared** and a second egg starts again from zero.
- [ ] Steps go through the subscript (absent metric reads as 0), **not** `known(_:)` — an
      un-credited step total means the egg simply has not met that path yet, and 0 is the right
      answer for a `>=` gate here.
- [ ] The five minutes is **wall-clock** against `stageEnteredDate`: an app closed on an egg and
      reopened six minutes later finds a hatched Baby I, and `BackgroundRefresh` can hatch it
      without a foreground.
- [ ] A **frozen** egg in the box does not age toward the hatch. `Freeze.shiftTimeline` already
      moves `stageEnteredDate`, so this should hold for free — add a test that proves it, since it is
      now load-bearing in a way it was not before.
- [ ] Every existing hatch guard is unchanged: a dead egg does not hatch, an inactive (boxed) record
      does not hatch, and hatching still bypasses the illness pause and the evolution time gate
      (`EvolutionTiming.minimumStageDuration(for: .digitama)` stays nil — this must **not** become an
      evolution).
- [ ] `state.hatchedDate` is still stamped at the hatch, so US-200's age counter is right whichever
      of the three paths fired.
- [ ] The hatch still goes through the graph's `isDefault` hatch edge and `EvolutionCeremonyView`
      still plays — a time-triggered hatch is the same event as an energy-triggered one, not a quiet
      swap.
- [ ] Tests: an egg at 0 energy and 0 steps hatches when handed a `now` 5 minutes past
      `stageEnteredDate` and does **not** at 4m59s; an egg at 0 energy and 500 steps hatches with
      `now == stageEnteredDate`; an egg at 50 energy still hatches immediately as it does today; a
      non-Digitama node still returns nil on all three paths.
- [ ] Typecheck passes; full suite green.
- [ ] Verify on the watchOS Simulator: a fresh save's egg hatches within ~5 minutes with no health
      data present, showing the ceremony.

---

## Functional Requirements

- **FR-1:** While the active Digimon's stage is `.digitama`, `MainScreenModel.isWandering` must be
  `false`.
- **FR-2:** Movement suspension for an egg must use `MovementModel.hold(at:)`, never a skipped
  `advance(to:)`, so no catch-up burst fires when the egg hatches.
- **FR-3:** While the active Digimon's stage is `.digitama`, the Feed, Train and Battle buttons must
  be disabled via SwiftUI's `.disabled` modifier on the button, read back through
  `ActionButtonFace`'s `@Environment(\.isEnabled)`.
- **FR-4:** `feed()`, `train()` and `battle()` must each check for `.digitama` **before** calling
  `wakeIfAsleep()` and before any existing eligibility rule, and must return a blocked result with a
  reason.
- **FR-5:** A blocked egg action must not modify any persisted state: no meat spent, no train or
  battle charge spent, no energy spent, no care mistake charged, no map care credited, no minigame
  opened.
- **FR-6:** A blocked egg action must show its reason in the existing `actionMessage` line, with no
  pose change and no `ActionMotion`.
- **FR-7:** Clean, Light, Map, Party, Dex and Sleep must remain fully functional while the Digimon is
  an egg.
- **FR-8:** The sprite slot must be laid out at `floor(availableHeight * 0.8)`, centred vertically in
  the row it used to fill, with the remaining height left empty.
- **FR-9:** The 0.8 fraction must be a single named constant that a unit test can read.
- **FR-10:** `SpriteSlotBoundsKey` must report the shortened band, so the map background, the light
  scrim and the poop pile track it without any separate arithmetic.
- **FR-11:** The drawn sprite offset must be interpolated with `.linear(duration:)` where the
  duration equals `MovementModel.step`, applied to the offset value alone.
- **FR-12:** `MovementModel` must be unchanged by US-220.
- **FR-13:** `MainScreenLayoutTests`'s pinned slot-height measurements (41.5pt / 56.0pt) must be
  re-measured on the Simulator and updated, with the new numbers recorded in progress.txt.
- **FR-14:** The height handed to `SpriteScale.fitting` must be multiplied by a second named
  fraction (0.8), independent of FR-8's play-area fraction.
- **FR-15:** `SpriteScale.minimum` must be 1, and `SpriteScale.fitting` must still return only whole
  numbers.
- **FR-16:** A Digitama must hatch when **any** of: total stage energy ≥ the hatch edge's
  `minEnergy`; 5 minutes have elapsed since `stageEnteredDate`; or 500 steps have accumulated in
  `stageMetricTotals[.healthSteps]`.
- **FR-17:** The 5-minute and 500-step thresholds must be named constants on `EggHatcher`.
- **FR-18:** `EggHatcher.hatchTarget` must remain a pure function taking `now: Date` as a parameter.
- **FR-19:** The existing dead / inactive / ceremony / `hatchedDate` behaviour of the hatch must be
  unchanged regardless of which of the three paths fired.

## Non-Goals (Out of Scope)

- **The horizontal walk bound is unchanged.** The Digimon still paces the full width of the screen
  wall to wall; only the *vertical* band and the map behind it shrink. (See Open Questions.)
- The 50-total-energy hatch rule is **kept**, not replaced — US-222 adds two more ways to hatch, it
  does not remove the existing one, and the graph's `minEnergy` data and its validator rule stay
  meaningful.
- No time or step shortcut for any evolution above the egg. Baby I's 24-hour gate and everything
  above it are untouched; only hatching gains new paths.
- No change to `SpriteScale.maximum` (stays 5) and no fractional scales.
- No change to `MovementModel`'s speed, step, catch-up cap or path.
- No new egg-specific animation. The Digitama's wobble/idle frames are drawn as they are today; a
  wobble-on-a-timer is a separate story.
- No change to the walk-cycle frame rate (walk1/walk2 flipping) — this PRD smooths *position* only.
- No change to the sprite scale ladder itself (`SpriteScale.minimum`/`maximum` stay 2 and 5); the
  scale drop at 46mm is a consequence of the shorter slot, not a re-tuning.
- Egg restrictions apply to the main screen's actions only — the Dex, Party and Map screens are
  untouched.

## Design Considerations

- **The shorter band costs the Digimon a scale step at 46mm on its own.** 56pt × 0.8 ≈ 44.8pt, and
  `SpriteScale.fitting` *floors* `height / 16`, so 46mm falls from scale 3 (48pt) to scale 2 (32pt).
  41mm is already at scale 2 and stays there (41.5 × 0.8 ≈ 33.2pt, still ≥ 32). US-221's separate
  fraction is what then takes both screens one step further.
- **The scale ladder is coarse, and 80% does not land on a rung.** Scales are whole numbers because
  fractional ones resample 16×16 art unevenly, so the reachable sizes are 5·4·3·2·1 → 80/64/48/32/16
  points. There is no 80%-of-48 (38.4pt) rung; the achievable move is a full step down. The end
  state is therefore ~67% at 46mm and ~50% at 41mm rather than a literal 80%, and 41mm lands at
  **scale 1 — a raw 16×16 sprite at 1:1**, which is smaller than the watch complication draws one.
  I flagged that as a readability risk and it was chosen deliberately; it is recorded here so a later
  reader does not file it as a regression. If it turns out too small on-wrist, the cheapest revert is
  raising `SpriteScale.sizeFraction` back to 1.0 and leaving the floor at 1.
- **The hatch shortcut is real gameplay, not a debug flag.** Five minutes is a very short egg stage —
  it was chosen knowingly. The 50-energy rule remains, so a player who is walking still hatches on
  energy first, and the graph's hatch-edge data keeps its meaning.
- **Steps come from the ledger, not a fresh HealthKit query.** `stageMetricTotals` is already
  credited from `health.steps` by `MetricLedger` and already cleared by `enterStage(at:)`. Reading
  the ledger keeps `EggHatcher` a pure function and keeps the "no live queries in tests" rule from
  CLAUDE.md intact.
- **Disabled buttons over hidden ones.** Feed/Train/Battle grey out rather than disappear, so the
  grid does not re-flow the moment the egg hatches and the player can see what is coming. This
  matches how Battle already behaves when the player cannot afford it (`canAffordBattle`).
- **Reuse the existing block path.** `FeedOutcome.blocked(reason:)` and
  `TrainingStart.blocked(reason:)` already exist and already route to the orange message line with no
  pose. The egg case is one more reason string, not a new mechanism.
- **One anchor, one rect.** The map, the light scrim and the poop pile are all placed off
  `SpriteSlotBoundsKey`. Attaching the anchor to the shortened frame is what makes them shrink
  together by construction rather than by three sets of arithmetic agreeing.

## Technical Considerations

- `MainScreenModel.isWandering` (Sources/MainScreenModel.swift:2073) is the single place US-217
  changes.
- `feed()` (:2131), `train()` (:2185) and `battle()` (:2418) each need the guard placed above their
  `wakeIfAsleep()` call — the ordering is load-bearing for "no care mistake".
- `ActionControls` is generic over four destination types, so any constant a test needs must live in
  a free-standing enum (`ActionButtonFace`, `ActionGridLayout`, `ActionSymbol` all exist for exactly
  this reason).
- The sprite row is `GeometryReader { … }.frame(maxHeight: .infinity)` at
  Sources/ContentView.swift:582–620, with `.anchorPreference(SpriteSlotBoundsKey)` on it. The height
  cap and the anchor must land on the same frame.
- `.padding(.bottom, MainScreenLayout.actionRowBottomInset)` inside `.ignoresSafeArea(.bottom)`
  (:805) means the flexible row already absorbs every layout change; US-219's cap sits inside that
  same row.
- `EggHatcher.hatchTarget` has exactly one caller, `MainScreenModel` (Sources/MainScreenModel.swift:3079),
  which already has an injectable `now()` and already holds `state.stageEnteredDate` and
  `state.stageMetricTotals` — so US-222 needs no new plumbing, only new parameters.
- `Freeze.shiftTimeline` (Sources/Freeze.swift:115) moves `stageEnteredDate` with everything else,
  which is why a frozen egg cannot bank hatch time. That file's own comment calls itself "the single
  line a new time-derived field has to be added to" — US-222 adds no field, but it does make an
  existing one load-bearing for a new rule, so the test is worth having.
- `ConditionMetric.healthSteps` has raw value `"health.steps"` and is already in the read set; no new
  HealthKit authorization is involved.
- A `TimelineView` re-evaluating its body is what drives the tween in US-220 — the animation must be
  attached so SwiftUI sees a changed offset on a stable view identity, or it will snap as it does
  now.
- **Screenshot discipline:** never judge motion from a burst of `simctl io screenshot` calls. Bursts
  starve the app's `TimelineView` and a walking sprite looks frozen. Idle ≥2s between captures.

## Success Metrics

- A fresh save's egg is in the identical position across two screenshots 2s apart.
- Tapping Feed, Train or Battle on an egg leaves every counter in `GameState` and `PlayerProfile`
  byte-for-byte unchanged.
- The map band on 46mm measures ~80% of its pre-change height in a screenshot, with visible empty
  margin above and below it.
- The sprite measures one whole scale step smaller than today at both screen sizes, and still fits
  inside its band with margin.
- A fresh save in the Simulator, with no HealthKit data at all, hatches into a Baby I within five
  minutes of first launch.
- Screenshots of the walk show positions that are not whole multiples of `stepDistance`.
- Full suite green (2746 tests today), build green at both simulator sizes.

## Open Questions

- "Move area" was read as the vertical play band. Should the **horizontal** walk bound also shrink to
  80% (the Digimon turning around well short of each bezel), or does it keep pacing the full width?
  This PRD assumes the full width is kept.
- Should the egg's *wobble* frame play on a slow timer now that it no longer walks, so it still reads
  as alive? Out of scope here; worth a follow-up story.
- Should the 20% reclaimed margin eventually go to the action grid (breathing room, a taller scroll
  cap) rather than staying empty? Left empty by decision for now.
- Is scale 1 (a 16pt sprite) readable on a 41mm wrist? It cannot be judged from a Simulator
  screenshot alone. If not, `SpriteScale.sizeFraction` is the single knob to back off.
- Five minutes is short enough that a player may never see the egg at all if they open the app,
  browse the Dex, and come back. Is that intended, or should the egg stage be long enough to be
  noticed (e.g. 15–30 minutes)?
- With a 5-minute hatch, the 50-energy path will almost never be the one that fires. Should the egg's
  energy threshold be retuned, or is it now effectively vestigial?
