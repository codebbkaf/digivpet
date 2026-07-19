# PRD: V-Pet Enhancements — Movement, Compact Controls, Evolution Tree, New Lines, Widget Poses, Poop

## Introduction

The Digimon Health V-Pet is feature-complete against its original PRD (all 35 stories in `prd.json` pass). This PRD covers the second wave of work: making the pet feel alive and the screen feel like a real V-Pet rather than a settings form.

Six changes, in the user's words:

1. The Digimon stands dead centre and never moves — it should walk left and right.
2. The Feed / Train / Battle / Notifications controls are large stacked blocks, forcing the user to scroll away from the sprite to tap anything. They should be small circular buttons that fit on screen with the Digimon still visible.
3. The Dex is a flat grid of cells. It should be an evolution **tree map**, so a user can see how many branches a line has and where their Digimon sits on it.
4. Only three evolution lines are playable. Add three more.
5. The widget/complication shows one fixed sprite. Its pose should reflect what the pet is actually doing.
6. There is no poop. A real V-Pet poops, you clean it, and it nags you if you don't.

## Goals

- Digimon moves horizontally with a walk animation and faces its direction of travel.
- All primary actions reachable without scrolling, with the sprite visible while tapping.
- Dex presents each evolution line as a stage-by-stage tree, undiscovered nodes still masked with `?`.
- Playable roster grows from 3 lines (22 nodes) to 6 lines.
- Widget sprite pose reflects live state (eating, sleeping, sick, poop present, dead).
- Poop accumulates on a clock, is cleanable, charges care mistakes, and can cause sickness.

## Context the implementer must not re-derive

These were verified against the repo while writing this PRD. Trust them.

- **Current playable lines** (`Resources/evolutions.json`, 22 nodes): Agumon, Gabumon, Palmon — Adventure-style, *not* the Color/Pendulum trees.
- **`Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md` already exists** and holds the extracted Color V1–V5 and Pendulum V0–V5 trees. Use it. Do **not** re-parse the PDFs or fetch `humulos.com` — the extraction is already done.
- **Sprite availability was checked** for every node named in this PRD (see US-043). The exceptions are called out explicitly; do not assume a sprite exists because the tree names it.
- **There is no poop sprite in the asset pack.** Confirmed by search. It must be drawn in SwiftUI. Do not invent a `spriteFile` path for it.
- watchOS widgets render from a static timeline. **Frame-by-frame widget animation is not possible** — hence FR-5 is pose selection, not animation.

## User Stories

Numbering continues from the existing `prd.json` (US-001…US-035).

---

### Feature 1 — Horizontal movement

### US-036: Add a movement model for horizontal wandering
**Description:** As a developer, I need a testable model that decides where the Digimon is and which way it faces, so movement is not tangled up in view code.

**Acceptance Criteria:**
- [ ] New `Sources/Movement.swift` with a `MovementModel` exposing horizontal offset (points from centre) and facing direction (`.left` / `.right`)
- [ ] Position advances via an **injectable clock**, never a real timer — tests advance time by hand and assert position
- [ ] Movement is bounded: the sprite never leaves the visible width; on reaching a bound it reverses and flips facing
- [ ] Direction changes are deterministic given a seed, so a test can assert an exact path
- [ ] `Tests/MovementTests.swift` covers: advancing time moves position, hitting a bound reverses, facing matches direction of travel
- [ ] Build passes, tests pass

### US-037: Render movement in the main screen
**Description:** As a user, I want my Digimon to walk around so it feels alive instead of frozen.

**Acceptance Criteria:**
- [ ] `DigimonSpriteView` accepts a horizontal offset and a `flipped` flag; flipping uses `.scaleEffect(x: -1)` and does **not** break `.interpolation(.none)`
- [ ] `ContentView` drives the sprite from `MovementModel`
- [ ] Movement is **suspended** (sprite returns to centre-ish and holds) while: sleeping, eating, sick, dead, or a battle/ceremony overlay is up
- [ ] Movement resumes when those states clear
- [ ] The walk loop (`walk1`/`walk2`) continues to animate while moving
- [ ] Verify in Simulator on Series 11 (46mm): screenshot shows the sprite off-centre
- [ ] Build passes

---

### Feature 2 — Compact circular controls

### US-038: Replace the action controls with circular icon buttons
**Description:** As a user, I want small round buttons so tapping an action doesn't hide my Digimon.

**Acceptance Criteria:**
- [ ] `FeedControls`, `TrainControls`, `BattleControls` are replaced by a single row of circular icon-only buttons (fork.knife / dumbbell / bolt.fill), plus a bell for Notifications
- [ ] Each button is circular, no larger than 32×32 points, and has an accessibility label naming the action
- [ ] Battle button still disables at the daily limit and still surfaces `MainScreenModel.battleLimitReason`
- [ ] Tapping a button triggers exactly the same model call as before (`model.feed()`, `model.train()`, `model.battle()`)
- [ ] Build passes, existing ContentView tests still pass

### US-039: Fit the main screen without scrolling
**Description:** As a user, I want everything on one screen so I never scroll away from my Digimon to act.

**Acceptance Criteria:**
- [ ] Stats become a compact single strip above the sprite: hunger pips, STR, PWR, W/L — no longer stacked blocks
- [ ] Main screen renders **without a `ScrollView`** on the playing path, or the scroll view never actually scrolls at 41mm
- [ ] Sprite remains visible at the same time as all four buttons on both Series 11 (42mm) and Series 11 (46mm)
- [ ] The `-feedScrollDemo` / `-trainScrollDemo` / `-battleScrollDemo` / `-settingsScrollDemo` debug scroll flags are removed or made no-ops, since there is nothing left to scroll to
- [ ] Verify in Simulator on **both** 42mm and 46mm: screenshot shows sprite + all buttons together, nothing clipped
- [ ] Build passes

---

### Feature 3 — Evolution tree Dex

### US-040: Add line and stage-column metadata to the evolution graph
**Description:** As a developer, I need each node to know which line it belongs to, so the Dex can group nodes into trees.

**Acceptance Criteria:**
- [ ] `evolutions.json` schema gains a `line` field (e.g. `"agumon"`, `"patamon"`) on every node; `docs/evolutions-schema.md` updated to match
- [ ] Swift model decodes `line`; decoding a node without `line` fails loudly rather than defaulting
- [ ] All 22 existing nodes are tagged with their line, no behaviour change to evolution logic
- [ ] `EvolutionGraphValidator` gains a check that every node has a non-empty `line`
- [ ] Existing evolution tests still pass
- [ ] Build passes, tests pass

### US-041: Build the evolution tree layout view
**Description:** As a user, I want to see a line drawn as a tree so I can tell how many branches it has.

**Acceptance Criteria:**
- [ ] New `Sources/EvolutionTreeView.swift` renders one line as columns ordered by stage: Digitama → Baby I → Baby II → Child → Adult → Perfect → Ultimate
- [ ] Nodes at the same stage stack vertically within their column
- [ ] Edges between nodes are drawn as visible connecting lines
- [ ] Discovered nodes show their idle sprite; **undiscovered nodes still show `?`**, exactly as the current grid does
- [ ] The tree scrolls horizontally when wider than the screen
- [ ] Tapping a discovered node opens the existing `DexDetailView`; undiscovered nodes stay non-tappable
- [ ] Verify in Simulator: screenshot shows a branching tree with connectors
- [ ] Build passes

### US-042: Replace the Dex grid with the tree
**Description:** As a user, I want the record book to *be* the tree map, not a flat grid.

**Acceptance Criteria:**
- [ ] `DexView` no longer renders `LazyVGrid`; it presents a list of lines, each opening its `EvolutionTreeView`
- [ ] The `discovered/total` count in the navigation title is preserved
- [ ] Only nodes belonging to a line appear in trees; `dexOnly` Digimon (157 idle-frame-only entries) remain reachable in a separate flat "Others" section so the count still reconciles
- [ ] Lazy rendering is preserved — opening the Dex must not decode all 865 sprites
- [ ] `-dexDemo` and `-dexDetailDemo` debug paths still work
- [ ] Verify in Simulator: screenshot of the line list and of one opened tree
- [ ] Build passes, existing Dex tests pass

---

### Feature 4 — Three new evolution lines

Target lines, chosen for sprite coverage: **Color V3 (Patamon)**, **Color V4 (Piyomon)**, **Color V5 (Gazimon)**.

### US-043: Verify and record sprite availability for the new lines
**Description:** As a developer, I need a checked list of which nodes have animated sheets before seeding data, so no story references art that doesn't exist.

**Acceptance Criteria:**
- [ ] A script under `scripts/` reports, for a list of names, whether each has an animated sheet, is `Idle Frame Only` (dexOnly), or is missing entirely
- [ ] Output committed to `docs/` recording the result for all three target lines
- [ ] The following **known exceptions** are confirmed and documented — these must NOT be seeded as playable:
  - `Poyomon` — idle-frame-only, so V3's canonical Baby I is unavailable
  - `Nanimon` — idle-frame-only (V4 branch)
  - `Flymon` — idle-frame-only (V5 branch)
  - `Kokatorimon` — **absent from the asset pack entirely** (V4 branch)
- [ ] Build passes

### US-044: Seed the V3 Patamon line
**Description:** As a user, I want a third line to raise.

**Acceptance Criteria:**
- [ ] Line seeded: `Pata_Digitama` → Baby I substitute → `Tokomon` → `Patamon` → Adult branches → Perfect → Ultimate
- [ ] Because `Poyomon` is dexOnly, an **animated** Baby I substitute is used and the divergence from the source tree is recorded in a comment in `evolutions.json` and in `notes`
- [ ] Adult/Perfect/Ultimate nodes drawn from the verified-available set (`Unimon`, `Centalmon`, `Ogremon`, `Bakemon`, `Shellmon`, `Drimogemon`, `Scumon`, `Andromon`, `Giromon`, `Etemon`, `HiAndromon`, `Gokumon`, `BanchoLeomon`)
- [ ] Every `spriteFile` verified to exist on disk before commit
- [ ] `EvolutionGraphValidator` passes on the extended graph
- [ ] Build passes, tests pass

### US-045: Seed the V4 Piyomon line
**Description:** As a user, I want a fourth line to raise.

**Acceptance Criteria:**
- [ ] Line seeded from `Piyo_Digitama` → `Yuramon` → `Tanemon` → `Piyomon` → Adult → Perfect → Ultimate
- [ ] `Kokatorimon` and `Nanimon` branches **omitted** (missing / dexOnly per US-043), and the omission noted
- [ ] Uses verified-available nodes (`Monochromon`, `Leomon`, `Kuwagamon`, `Coelamon`, `Mojyamon`, `Megadramon`, `Piccolomon`, `Digitamamon`, `Darkdramon`, `BloomLordmon`, `Gankoomon`)
- [ ] Does not collide with the existing Palmon line, which already uses `Yuramon`/`Tanemon` — either share those nodes or give this line distinct Baby stages, and state which was chosen
- [ ] Every `spriteFile` verified to exist on disk
- [ ] Validator passes, build passes, tests pass

### US-046: Seed the V5 Gazimon line
**Description:** As a user, I want a fifth and sixth branch-rich line to raise.

**Acceptance Criteria:**
- [ ] Line seeded from `Gazi_Digitama` → `Zurumon` → `Pagumon` → `Gazimon` → Adult → Perfect → Ultimate
- [ ] `Flymon` branch **omitted** (dexOnly per US-043), omission noted
- [ ] Uses verified-available nodes (`Gizamon`, `DarkTyranomon`, `Cyclomon`, `Devidramon`, `Tuskmon`, `Raremon`, `Deltamon`, `MetalTyranomon`, `Ex-Tyranomon`, `Nanomon`, `Mugendramon`, `Gaioumon`, `Raidenmon`)
- [ ] Every `spriteFile` verified to exist on disk
- [ ] Validator passes, build passes, tests pass
- [ ] Egg selection at rebirth can reach all six lines

---

### Feature 5 — Widget poses and batched-timeline motion

**Design note — how this landed.** Three approaches were considered:

- *Sensor-driven frames* (gyroscope / compass): **ruled out.** A widget is not a running process. WidgetKit calls the provider, renders entries to snapshots, and exits; the view is not live when the user sees it. Sensor APIs need delegate callbacks over time, and there is no process alive to receive them. Do not attempt this.
- *Pre-baked timeline entries*: **adopted.** One provider call returns many entries, each drawing a different frame. Entries batched into a single timeline are **not** billed per entry against the reload budget — one timeline is one charge — so this is the cheap path.
- *In-app motion*: viable but out of scope this wave.

The constraint on the adopted approach is **render granularity, not budget**: entry dates are hints, and the system coalesces fine-grained ones rather than honoring them. Sub-second frame swapping will not render. The real floor on watchOS 10 is unmeasured — which is why US-048 measures it before US-049 commits to a cadence.

### US-047: Complication sprite pose reflects live state
**Description:** As a user, I want a glance at my watch face to tell me what my Digimon is doing.

**Acceptance Criteria:**
- [ ] `ComplicationSnapshot` carries a pose derived from state
- [ ] Pose mapping is explicit and total: sleeping → sleep frame, sick → hurt frame, poop present → angry frame, dead → a distinct held frame, otherwise → idle walk1
- [ ] Complication views render the mapped frame with `.interpolation(.none)`
- [ ] Snapshot is republished when the underlying state changes, so the pose is not stale
- [ ] Tests cover the pose mapping for every state, including precedence when two apply at once (e.g. sick *and* poop present)
- [ ] Verify via `-complicationDemo`: screenshot shows a non-idle pose
- [ ] Build passes, tests pass

### US-048: Spike — measure the real timeline refresh granularity
**Description:** As a developer, I need to know the actual floor on entry granularity before designing an animation cadence around a guess.

**Acceptance Criteria:**
- [ ] A throwaway `TimelineProvider` returns entries at 1s, 5s, 30s, 60s and 5min spacing, each rendering a visibly distinct frame or number
- [ ] Observed on a real watchOS 10 target, recording which spacings actually repaint and which are coalesced
- [ ] Behaviour in **Always-On Display** recorded separately — AOD throttles repaints and is expected to differ
- [ ] Findings written to `docs/widget-refresh-granularity.md`: the measured floor, the AOD floor, and the date and OS version measured on
- [ ] The spike code is removed or left clearly marked as non-shipping
- [ ] **This story ships a measurement, not a feature.** If the floor turns out coarser than ~2 minutes, say so plainly in the doc and note that US-049 should be reconsidered rather than forced
- [ ] Build passes

### US-049: Batched-timeline frame alternation
**Description:** As a user, I want the sprite on my watch face to move a little, so it feels alive rather than frozen.

**Acceptance Criteria:**
- [ ] **Blocked on US-048** — the entry cadence must be the measured floor from `docs/widget-refresh-granularity.md`, not an assumed value
- [ ] The provider returns a batch of entries alternating `walk1` / `walk2` at that cadence, in a single timeline
- [ ] The batch covers a defined horizon, with a documented plan for what happens when it runs out
- [ ] Alternation is suppressed for states where a held pose is correct — sleeping, sick, and dead must not appear to walk
- [ ] SwiftUI entry transitions are applied so the frame change reads as motion rather than a jump
- [ ] Tests assert the generated timeline: correct entry count, correct spacing, correct frame sequence, and suppression in held-pose states
- [ ] Verify via `-complicationDemo`: two screenshots at different entry dates showing different frames
- [ ] Build passes, tests pass

### US-050: Interactive Clean button on the complication
**Description:** As a user, I want to clean up after my Digimon straight from the watch face, without opening the app.

**Acceptance Criteria:**
- [ ] An `AppIntent`-backed `Button` in the complication performs the clean action (watchOS 10 supports interactive widgets; the project targets 10.0)
- [ ] The button appears only when there is poop to clean
- [ ] Tapping it zeroes the poop count through the **same** model path as the in-app Clean button — no duplicated logic
- [ ] The timeline reloads after the intent runs, so the pose and button state update
- [ ] Pending poop notifications are cancelled, exactly as in-app cleaning does
- [ ] Tests cover the intent invoking the shared clean path and the button's visibility rule
- [ ] **Depends on US-053** (the poop model) — sequence accordingly
- [ ] Build passes, tests pass

**Explicit non-goal:** no sensor-driven and no per-frame animation in the widget. Batched entry alternation at the measured floor is the ceiling of what the platform allows.

---

### Feature 6 — Poop

### US-051: Add the poop model
**Description:** As a developer, I need poop to accumulate on a clock so the rest of the feature has something to read.

**Acceptance Criteria:**
- [ ] New `Sources/Poop.swift` with poop count and the timestamps behind it
- [ ] Poop accumulates on an **injectable clock** — tests never wait real time
- [ ] A ceiling on simultaneous poops is defined and enforced
- [ ] Poop generation is tied to feeding and/or elapsed time, with the chosen rule documented
- [ ] Poop does **not** accumulate while the Digimon is asleep or dead
- [ ] Count persists across launches via the existing SwiftData model
- [ ] `Tests/PoopTests.swift` covers accumulation, the ceiling, the sleep pause, and persistence
- [ ] Build passes, tests pass

### US-052: Show poop and add the clean action
**Description:** As a user, I want to see the mess and clean it up.

**Acceptance Criteria:**
- [ ] Poops render on screen beside the Digimon, one shape per poop, **drawn in SwiftUI** — no invented sprite path, since no poop art exists in the pack
- [ ] A circular Clean button joins the action row from US-038, matching its size and style
- [ ] Tapping Clean sets poop count to zero and shows a confirmation message in the existing caption slot
- [ ] The Clean button is disabled when there is no poop
- [ ] Verify in Simulator: screenshot with poop visible, and one after cleaning with it gone
- [ ] Build passes

### US-053: Uncleaned poop charges care mistakes and causes sickness
**Description:** As a user, I want neglect to have consequences, so cleaning matters.

**Acceptance Criteria:**
- [ ] Poop left uncleaned past a defined threshold charges a care mistake, using the existing `CareMistakes` machinery
- [ ] A care mistake is charged **at most once** per threshold crossing — no repeated charging on every refresh tick
- [ ] Reaching the poop ceiling can trigger sickness through the existing `Sickness` path (`careMistakesUntilSick`)
- [ ] Cleaning stops further charging
- [ ] Tests drive the injected clock across the threshold and assert exactly one mistake charged, and assert the sickness path fires at the ceiling
- [ ] Build passes, tests pass

### US-054: Notify when poop needs cleaning
**Description:** As a user, I want to be told there's a mess so I can deal with it before my Digimon gets sick.

**Acceptance Criteria:**
- [ ] A local notification fires when poop reaches the notify threshold, via the existing `Notifications` layer
- [ ] A toggle for it is added to `NotificationSettingsView`, defaulting on, persisted like the existing toggles
- [ ] With the toggle off, no poop notification is scheduled
- [ ] Notifications are not repeated for the same uncleaned mess — one per threshold crossing
- [ ] Cleaning cancels any pending poop notification
- [ ] Tests cover: scheduled at threshold, suppressed when toggled off, cancelled on clean, not duplicated
- [ ] Verify via `-settingsDemo`: screenshot shows the new toggle
- [ ] Build passes, tests pass

## Functional Requirements

- FR-1: The Digimon must move horizontally within screen bounds and face its direction of travel.
- FR-2: Movement must derive from an injectable clock and be suspended while sleeping, eating, sick, dead, or overlaid.
- FR-3: Feed, Train, Battle, Clean and Notifications must be circular icon buttons no larger than 32×32 points.
- FR-4: The main screen must present sprite, stats and all action buttons without scrolling at 42mm and 46mm.
- FR-5: The Dex must render each evolution line as a stage-column tree with drawn connectors.
- FR-6: Undiscovered Digimon must continue to render as `?` in the tree.
- FR-7: Every node must declare a `line`, enforced by the graph validator.
- FR-8: Three new lines (Color V3 Patamon, V4 Piyomon, V5 Gazimon) must be playable.
- FR-9: Every `spriteFile` must be verified present on disk; dexOnly and missing Digimon must never be seeded as playable.
- FR-10: The complication sprite pose must be a total function of live state, with defined precedence.
- FR-10a: The complication must alternate walk frames via batched timeline entries, at a cadence measured empirically rather than assumed, suppressed in held-pose states.
- FR-10b: The complication must offer an `AppIntent`-backed Clean button when poop is present, routed through the same clean path as the in-app button.
- FR-11: Poop must accumulate on an injectable clock, up to a defined ceiling, pausing during sleep and death.
- FR-12: Poop must be cleanable, and cleaning must zero the count and cancel pending poop notifications.
- FR-13: Uncleaned poop past a threshold must charge exactly one care mistake per crossing and can lead to sickness.
- FR-14: A poop notification must fire at threshold, be toggleable, and never duplicate for the same mess.

## Non-Goals

- No vertical movement, jumping, or pathfinding — horizontal only.
- No sensor-driven widget animation (gyroscope, compass, motion) — the widget execution model makes it impossible, not merely difficult.
- No per-frame widget animation at the app's 0.5s sprite cadence; batched entry alternation at the measured floor is the ceiling.
- No in-app gyroscope/tilt response this wave — viable, but deferred.
- No new poop *sprite art* — drawn in SwiftUI, not added to the asset pack.
- No Jogress/Ultra evolutions, even where the source trees describe them.
- No Pendulum Color lines this wave — Color V3/V4/V5 only.
- No re-parsing of the source PDFs or fetching humulos.com; the extracted markdown is the source of truth.
- No redesign of the energy, hunger, battle, or HealthKit systems.
- No making the 157 `dexOnly` Digimon playable.

## Technical Considerations

- **Sprite flipping:** `.scaleEffect(x: -1)` must not reintroduce smoothing — `.interpolation(.none)` stays mandatory.
- **Clock injection:** movement and poop both join the existing injectable-clock convention used by hunger, sickness and death. Tests must never sleep.
- **Sprite caching:** the tree view can put many sprites on screen. Keep `SpriteSheetCache` decode-once semantics and lazy rendering; do not re-crop per tick.
- **Line collision:** the existing Palmon line already uses `Yuramon`/`Tanemon`, which the V4 tree also names. US-045 must resolve this deliberately, not accidentally.
- **`project.yml` only** — never hand-edit `.xcodeproj`; re-run `xcodegen generate`.
- **Care-mistake idempotence:** US-050's "once per crossing" is the subtle part. `chargeStarvationMistakes` in `CareMistakes.swift` is the existing precedent for a clock-driven, non-repeating charge — follow it.

## Success Metrics

- Zero scrolling required to perform any primary action on a 42mm watch.
- Playable lines grow 3 → 6; total playable nodes roughly double.
- Every seeded `spriteFile` resolves to a real file — validator green, no runtime `?` placeholders on playable nodes.
- A user can see, for any line they've started, how many branches remain undiscovered.

## Open Questions

1. **V3's Baby I substitute** — `Poyomon` is idle-frame-only. Which animated Baby I stands in? `Puyomon` is the closest name-and-shape match, but this is a deliberate divergence from the source tree and needs a call.
2. **Poop trigger rule** — purely time-based, or tied to feeding? Feeding-tied is more faithful to real V-Pets but means a neglected pet never poops, which weakens the notification.
3. **Poop thresholds** — how many poops before a care mistake, and how many before sickness? US-050 assumes the ceiling triggers sickness; the exact numbers are unset.
4. **V4 Baby-stage collision** — share `Yuramon`/`Tanemon` with the existing Palmon line, or give V4 distinct Baby stages? Sharing merges two trees in the Dex view, which may or may not be desirable.
5. **Widget refresh floor is unmeasured** — US-048 exists precisely because this is unknown. If the floor lands coarser than ~2 minutes, US-049's alternation may not be worth shipping, and the complication should fall back to US-047's state-driven pose alone. Decide after the spike, not before.
6. **Timeline horizon** — how far ahead to batch entries, and what happens when the batch is exhausted before the system next asks for a timeline. US-049 requires a documented plan; the plan itself is unset.
7. **Tree view on a 41mm screen** — a seven-stage tree with branches is wide. Horizontal scroll is specified, but a stage-at-a-time pager may read better; worth a look once US-041 is on screen.
