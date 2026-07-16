# PRD: Digimon Health V-Pet (watchOS)

## Introduction

A standalone Apple Watch app that turns your real-world health data into food for a Digimon.

The app reads HealthKit metrics — steps, active calories, sleep, exercise minutes — and converts each into a distinct **energy type**. That energy hatches a Digitama (egg), grows it through the classic evolution stages (Baby I → Baby II → Child → Adult → Perfect → Ultimate), and determines *which* Digimon it becomes. Walk a lot and your Digimon evolves down a strength line; sleep well and it evolves down a spirit line.

The problem it solves: fitness apps show you numbers you forget. A creature that visibly depends on your behavior — and that can get sick and die if you neglect it — creates a stake that a step counter does not.

The project already contains a sprite library in the classic 16×16 LCD V-Pet style, organized by evolution stage: **865 fully-animated Digimon** (12-frame sheets), plus 157 that exist only as a single idle frame. (The raw file count is ~2,270 PNGs, but that double-counts black-and-white and idle-frame duplicates of the same Digimon — see Key Asset Facts.)

---

## Goals

- Read steps, active energy, sleep, and exercise minutes from HealthKit on watchOS, with no iPhone app required.
- Convert each metric into one of four energy types, displayed clearly to the user.
- Grow a Digimon through 7 evolution stages, where the **dominant energy type** decides the evolution branch.
- Support the full sprite roster via a data-driven evolution graph that requires no code change to extend.
- Implement the full classic V-Pet loop: feeding, training, battles, sickness, death, and rebirth.
- Animate Digimon using the existing 12-frame sprite sheets at true pixel fidelity (no smoothing).
- Run entirely on-device with all health data staying on the watch.

---

## Key Asset Facts (verified — read this before writing any sprite code)

These were confirmed by inspecting the actual files. Do not re-derive them.

### Sprite sheet layout

Every stage sprite is a **48×64 PNG** = a **3-wide × 4-tall grid of 16×16 frames** = **12 frames**, in row-major order:

| Index | Row, Col | Frame | Used for |
|---|---|---|---|
| 0 | 0,0 | Walk 1 | Idle/walk animation |
| 1 | 0,1 | Walk 2 | Idle/walk animation |
| 2 | 0,2 | Eat 1 | Feeding |
| 3 | 1,0 | Eat 2 | Feeding |
| 4 | 1,1 | Sleep 1 | Sleeping (real sleep data) |
| 5 | 1,2 | Sleep 2 | Sleeping |
| 6 | 2,0 | Refuse | Rejecting food when full |
| 7 | 2,1 | Happy | Praise, goal met, evolution |
| 8 | 2,2 | Angry | Neglect, care mistake |
| 9 | 3,0 | Hurt 1 | Taking damage in battle |
| 10 | 3,1 | Hurt 2 | Taking damage in battle |
| 11 | 3,2 | Attack | Battle attack |

Frame index → source rect: `x = (index % 3) * 16`, `y = (index / 3) * 16`, size `16×16`.

**This layout is confirmed by pixel content, not just the xlsx.** The frames were cut and inspected: `eat1` has an open mouth, `sleep1`/`sleep2` have closed eyes, `happy` is a closed-eye cheerful pose, `angry` has an angry brow. The labels match the art.

### Frames are sliced at runtime — do NOT ship cut frames (benchmarked)

The app bundles the **865 original sheets** and crops frames at runtime with `CGImage.cropping(to:)`. Pre-cutting frames into individual PNGs was measured and rejected:

| | Runtime slicing | Pre-cut PNGs |
|---|---|---|
| Load 216 frames (decode only) | **1.26 ms** | 18.87 ms |
| Load 216 frames (pixels realized) | **4.41 ms** | 27.48 ms |
| File opens for 18 Digimon | **18** | 216 |
| Full roster on disk | **1.2 MB / 865 files** | 4.6 MB / 10,380 files |

**Why:** PNG decode cost is dominated by a *fixed* per-file overhead (file open, header parse, zlib stream init) that dwarfs the pixels in a 16×16 image — twelve tiny decodes pay it twelve times, one 48×64 decode pays it once. And `cropping(to:)` references the sheet's existing backing buffer instead of copying pixels, so the twelve crops are near-free. Pre-cutting is slower, 4× the bytes, 12× the files, and slower to build.

**Implementation rule:** decode each sheet **once**, crop to 12 `CGImage`s at load, cache the array. Never re-crop per animation tick; never re-decode per frame.

`scripts/cut_sprites.swift` remains as a **dev tool only** — it exports frames to `sprites_cut/` (gitignored, never bundled) for visual inspection. It earned its keep: cutting the frames is what confirmed the xlsx frame order matches the actual art, and revealed that Digitama frame 3 is the hatch.

- **Digitama (eggs)** are **48×16** = 3 frames of 16×16: `idle`, `wobble`, `hatch`. **Frame 3 is the egg cracking open with the Digimon emerging** — a ready-made hatch animation (verified by cutting it).
- **`Idle Frame Only/`** (842 files) are single **16×16** PNGs — use for the Dex list, pickers, and complications.

### Real roster size (verified — the raw file count is misleading)

The ~2,270 PNG count double-counts the same Digimon across the B&W and idle-frame folders. The counts that actually matter:

| Measure | Count | Meaning |
|---|---|---|
| Animated 12-frame sheets across all stage folders | **865** | Playable Digimon — this is the real roster |
| Idle-only sprites with **no** animated sheet | **157** | Dex-only; cannot animate, cannot be playable |
| Unique Digimon overall | **~1,022** | 865 + 157 |

**Consequence:** the full-roster graph is ~865 nodes to author, not 2,270 — meaningfully smaller than it first appears. The 157 idle-only Digimon (including `Poyomon`, `Ankylomon`, `Aquilamon`, and the Ancient/Arkadimon lines) must be marked `dexOnly` and excluded from evolution edges, or the app will try to animate a sprite sheet that does not exist.
- **`Black and White Sprites/`** are 1-bit versions — a possible "classic LCD" display mode (see Non-Goals; not v1).

### Roster by stage

| Folder | Count | Stage |
|---|---|---|
| `Digitama/` | 58 | Egg (48×16) |
| `Baby I/` | 43 | Stage 1 |
| `Baby II/` | 47 | Stage 2 |
| `Child/` | 120 | Stage 3 ("Rookie") |
| `Adult/` | 192 | Stage 4 ("Champion") |
| `Perfect/` | 169 | Stage 5 ("Ultimate") |
| `Ultimate-Super Ultimate/` | 221 | Stage 6 (final) |
| `Armor-Hybrid/` | 16 | Special branch |

### Naming conventions

Filenames are the Digimon name, with variant suffixes: `_X` (X-Antibody), `_Black`, `_Blue`, `_Virus`, `_2006`, `_2010`, `_YnK`. Stage-disambiguating suffixes appear where a name spans stages: `Algomon_Child.png`, `Algomon_Adult.png`. Digitama use a short prefix: `Agu_Digitama.png`.

### What does NOT exist

- **There is no evolution graph in this project.** `LCD Checklist.xlsx` is a checklist of *which physical V-Pet device each sprite came from* (sheets: Digimon Mini, Digimon Twin, Pendulum Ver. 20th, Digivice iC, Pendulum Cycle, Color Devices, Video Games, …). It contains no parent→child evolution data.
- The only evolution hint in the project is `Digitama/_How this works.txt`, which states the author assigned a unique Digitama and specific Baby I/II forms to **each Child-level Digimon**. This implies a Digitama→Baby I→Baby II→Child mapping can be partly recovered from filename prefixes, but Child→Adult→Perfect→Ultimate must be authored.

**Consequence:** the evolution graph is authored data and is the critical path for full-roster support. See US-004 and Technical Considerations.

---

## Energy Type Model

Four energy types, one per HealthKit metric:

| Energy | Symbol | HealthKit source | Identifier |
|---|---|---|---|
| **Strength** | 力 | Steps today | `HKQuantityTypeIdentifier.stepCount` |
| **Vitality** | 活 | Active calories burned today | `.activeEnergyBurned` |
| **Spirit** | 心 | Sleep last night | `HKCategoryTypeIdentifier.sleepAnalysis` |
| **Stamina** | 耐 | Exercise minutes today | `.appleExerciseTime` |

**Conversion (v1 baseline rates, tunable in one constants file):**

- Strength: 1 point per 100 steps
- Vitality: 1 point per 20 active kcal
- Spirit: 1 point per 15 min asleep (`asleepCore`/`asleepDeep`/`asleepREM`/`asleepUnspecified`; `inBed` and `awake` excluded)
- Stamina: 1 point per 2 exercise minutes

**Dominant energy** = the energy type with the highest accumulated total since the current stage began. It decides which evolution branch is taken when the stage's evolution conditions are met.

Energy accrues to a per-stage running total AND a lifetime total. The per-stage total resets on evolution; the lifetime total persists for the Dex.

---

## User Stories

> **Verification note:** the `/prd` skill's default UI acceptance criterion is "verify in browser using dev-browser skill." That does not apply here — this is a native watchOS app. The equivalent criterion used throughout is **"Verify in watchOS Simulator (or on device)."** HealthKit stories additionally require a real device or simulator with seeded Health data, since the Simulator has no health data by default.

### Phase 1 — Foundation

#### US-001: Xcode project + asset pipeline
**Description:** As a developer, I need a standalone watchOS SwiftUI project with sprites bundled, so the app can build and load art.

**Acceptance Criteria:**
- [ ] Standalone watchOS app target created (SwiftUI lifecycle, no iOS companion target)
- [ ] Minimum deployment target set to watchOS 10.0 or later
- [ ] Sprite PNGs copied into the target as a folder reference (preserving stage subfolders), NOT an asset catalog — filenames must remain addressable at runtime
- [ ] A `SpriteLoader.load(name:stage:)` returns a non-nil image for `Child/Agumon.png`
- [ ] Project builds with zero warnings
- [ ] Typecheck/build passes

#### US-002: Sprite sheet slicing and animation view
**Description:** As a developer, I need to slice a 48×64 sheet into its 12 named frames and animate them, so every Digimon can be displayed and animated from one component.

**Acceptance Criteria:**
- [ ] `SpriteFrame` enum with all 12 cases (`.walk1`, `.walk2`, `.eat1`, `.eat2`, `.sleep1`, `.sleep2`, `.refuse`, `.happy`, `.angry`, `.hurt1`, `.hurt2`, `.attack`) mapping to indices 0–11 per the table above
- [ ] Slicing uses `x = (index % 3) * 16`, `y = (index / 3) * 16`, `16×16`
- [ ] `DigimonSpriteView` renders a given frame, scaled with `.interpolation(.none)` so pixels stay sharp
- [ ] Supports animation loops: idle (walk1↔walk2), eat (eat1↔eat2), sleep (sleep1↔sleep2), hurt (hurt1↔hurt2)
- [ ] Handles 48×16 Digitama sheets (3 frames) without crashing
- [ ] Returns a placeholder, not a crash, when a sprite file is missing
- [ ] Typecheck passes
- [ ] Verify in watchOS Simulator

#### US-003: Persistence layer
**Description:** As a developer, I need game state saved on-device, so the Digimon survives app restarts.

**Acceptance Criteria:**
- [ ] SwiftData model (or Codable + file) storing: current Digimon id, stage, per-stage energy totals (4), lifetime energy totals (4), birth date, stage-entered date, care-mistake count, hunger, strength, health status, battle W/L
- [ ] State survives force-quit and relaunch
- [ ] A `resetGame()` path exists for testing
- [ ] Typecheck passes

#### US-004: Evolution graph data format + seed data
**Description:** As a developer, I need the evolution tree stored as external data, so the full roster can be extended without code changes.

**Acceptance Criteria:**
- [ ] `evolutions.json` schema defined and documented, with per-node: `id`, `displayName`, `stage`, `spriteFile`, and `evolutions[]` — each edge carrying `to`, `requiredEnergy` (which type must be dominant), `minEnergy`, `maxCareMistakes`, and optional `minBattleWins`
- [ ] Schema supports multiple edges per node (branching) and multiple parents per node (converging lines)
- [ ] Decoded into typed Swift models at launch
- [ ] Seeded with **at least 3 complete lines** (e.g. Agumon→Greymon→MetalGreymon→WarGreymon; Gabumon→Garurumon→WereGarurumon→MetalGarurumon; Patamon→Angemon→HolyAngemon→Seraphimon), each with its Digitama and Baby I/II forms
- [ ] A validation function reports: edges pointing at unknown ids, nodes whose `spriteFile` does not exist on disk, and stage transitions that skip a stage
- [ ] Validation runs as a unit test and fails the build on a broken graph
- [ ] Typecheck passes

#### US-005: Roster import tooling
**Description:** As a developer, I need a script that generates roster entries from the sprite folders, so I don't hand-type 2,270 nodes.

**Acceptance Criteria:**
- [ ] Script walks the sprite folders and emits a JSON node per sprite with `id`, `displayName`, `stage`, and `spriteFile` pre-filled
- [ ] Parses variant suffixes (`_X`, `_Black`, `_Virus`, `_2006`, `_2010`, `_Blue`, `_YnK`) into a `variant` field
- [ ] Strips stage-disambiguating suffixes (`_Child`, `_Adult`) from `displayName`
- [ ] Matches Digitama prefixes (`Agu_Digitama`) to their Child form where derivable, and reports those it cannot match
- [ ] Output merges with hand-authored `evolutions[]` edges without clobbering them (re-runnable)
- [ ] Script is documented in the repo README

### Phase 2 — Health data → energy

#### US-006: HealthKit authorization
**Description:** As a user, I want to grant health access on first launch so the app can feed my Digimon.

**Acceptance Criteria:**
- [ ] Requests read-only authorization for step count, active energy, sleep analysis, exercise time
- [ ] `NSHealthShareUsageDescription` present in Info.plist with a clear reason string
- [ ] Onboarding screen explains what is read and that data never leaves the watch, before the system prompt appears
- [ ] Denial shows an explanatory state with a link to Settings — the app does not crash or hang
- [ ] Partial authorization (e.g. steps granted, sleep denied) works, and unavailable energy types read zero
- [ ] Verify on device or Simulator with seeded Health data

#### US-007: Read today's metrics
**Description:** As a developer, I need current health values so they can be converted into energy.

**Acceptance Criteria:**
- [ ] Steps, active energy, and exercise time queried for **today** (from local-timezone midnight)
- [ ] Sleep queried for **last night**, defined as the longest asleep block in the window 18:00 previous day → 12:00 today
- [ ] Sleep sums only `asleepCore`/`asleepDeep`/`asleepREM`/`asleepUnspecified`; `inBed` and `awake` excluded
- [ ] Overlapping sleep samples from multiple sources are de-duplicated (no double-count)
- [ ] Values expose a "no data" state distinct from a real zero
- [ ] Unit tests cover the sleep-window and de-duplication logic with fixture samples
- [ ] Typecheck passes

#### US-008: Convert metrics to energy
**Description:** As a user, I want my activity to become energy so my Digimon grows from what I actually did.

**Acceptance Criteria:**
- [ ] All four conversion rates live in one constants file
- [ ] Energy is credited **only for the delta** since the last read — reopening the app never double-credits
- [ ] Daily caps prevent a single day from dominating (v1: 100 points per energy type per day)
- [ ] Energy accrues to both the per-stage total and the lifetime total
- [ ] Dominant energy = highest per-stage total; ties broken by most recently incremented
- [ ] Unit tests cover: delta crediting, cap enforcement, tie-breaking
- [ ] Typecheck passes

#### US-009: Main screen
**Description:** As a user, I want to open the app and see my Digimon with its energy, so I know how it's doing at a glance.

**Acceptance Criteria:**
- [ ] Digimon renders center-screen, idle-animating, scaled up crisply from 16×16
- [ ] Four energy bars/pips visible with the type symbol (力/活/心/耐), each showing progress toward the next evolution's requirement
- [ ] Dominant energy type is visually distinguished
- [ ] Stage name and Digimon name shown
- [ ] Layout correct on both 41mm and 49mm without clipping
- [ ] Refreshes on `scenePhase` becoming active
- [ ] Typecheck passes
- [ ] Verify in watchOS Simulator at 41mm and 49mm

### Phase 3 — Growth and evolution

#### US-010: Hatching
**Description:** As a new user, I want to start with an egg that hatches from my activity, so my first Digimon feels earned.

**Acceptance Criteria:**
- [ ] New game starts at a randomly selected Digitama, animating its 3 frames
- [ ] Hatches when total energy across all types reaches the threshold (v1: 50)
- [ ] Hatch plays an animation and lands on the Baby I form linked to that Digitama in the graph
- [ ] Hatched Digimon is written to persistence and to the Dex
- [ ] Verify in watchOS Simulator

#### US-011: Evolution engine
**Description:** As a user, I want my Digimon to evolve based on which energy I earned most, so my real habits shape the outcome.

**Acceptance Criteria:**
- [ ] On each energy update, the engine evaluates the current node's outgoing edges
- [ ] An edge qualifies only if: dominant energy matches `requiredEnergy`, per-stage total ≥ `minEnergy`, care mistakes ≤ `maxCareMistakes`, and battle wins ≥ `minBattleWins` (when set)
- [ ] Minimum time-in-stage is enforced so a stage cannot be skipped in one session (v1: 24h for Baby I/II, 72h for Child+)
- [ ] When multiple edges qualify, the one matching dominant energy with the highest `minEnergy` wins (most specific)
- [ ] When **no** edge qualifies at the time gate, it falls back to the node's designated default edge — a Digimon is never stuck forever
- [ ] Evolution resets per-stage energy totals, preserves lifetime totals, and increments the Dex
- [ ] Unit tests cover: branch selection per dominant type, time gating, care-mistake blocking, fallback
- [ ] Typecheck passes

#### US-012: Evolution animation
**Description:** As a user, I want a moment of ceremony when my Digimon evolves, so the payoff feels real.

**Acceptance Criteria:**
- [ ] Full-screen animation plays: old sprite → flash/silhouette → new sprite
- [ ] Haptic fires (`.success`) at the reveal
- [ ] New name announced on screen
- [ ] Triggers when the app opens if evolution conditions were met while it was closed
- [ ] Verify in watchOS Simulator

#### US-013: Digimon Dex
**Description:** As a user, I want to see every Digimon I've raised, so I have a reason to try different habits.

**Acceptance Criteria:**
- [ ] Scrollable grid of all discovered Digimon using `Idle Frame Only/` 16×16 sprites
- [ ] Undiscovered entries show a silhouette or `?` placeholder
- [ ] Tapping an entry shows name, stage, and the date first obtained
- [ ] Shows a discovered/total count
- [ ] Performs smoothly when the graph holds the full roster (lazy loading — do not decode 2,270 images eagerly)
- [ ] Typecheck passes
- [ ] Verify in watchOS Simulator

### Phase 4 — Care mechanics

#### US-014: Sleep state mirrors real sleep
**Description:** As a user, I want my Digimon asleep when I'm asleep, so it mirrors my life.

**Acceptance Criteria:**
- [ ] Digimon shows sleep frames (4/5) during the user's typical sleep window inferred from HealthKit sleep history
- [ ] Falls back to a fixed 22:00–07:00 window when sleep history is unavailable
- [ ] Sleeping Digimon does not idle-animate and cannot be fed or trained
- [ ] Waking it early (opening the app and tapping) counts as a care mistake
- [ ] Verify in watchOS Simulator

#### US-015: Feeding
**Description:** As a user, I want to spend earned energy feeding my Digimon, so my activity has a direct use.

**Acceptance Criteria:**
- [ ] Feed action costs Vitality energy and reduces hunger by one unit
- [ ] Plays the eat animation (frames 2↔3) with a light haptic
- [ ] Feeding at full hunger plays the **refuse** frame (6) and consumes nothing
- [ ] Overfeeding (3+ refusals in a day) counts as a care mistake
- [ ] Hunger increases over real time (v1: one unit per 4h)
- [ ] Typecheck passes
- [ ] Verify in watchOS Simulator

#### US-016: Training
**Description:** As a user, I want to train my Digimon so I can steer it toward stronger evolutions.

**Acceptance Criteria:**
- [ ] Train action costs Strength or Stamina energy and raises the strength stat
- [ ] Plays the attack animation (frame 11) with a haptic
- [ ] Training is blocked while asleep or sick, with a reason shown
- [ ] Strength stat feeds battle power (US-018)
- [ ] Typecheck passes
- [ ] Verify in watchOS Simulator

#### US-017: Sickness, care mistakes, death, rebirth
**Description:** As a user, I want real stakes — if I neglect my Digimon it should suffer and eventually die.

**Acceptance Criteria:**
- [ ] Care mistake recorded for: no health data for a full day, hunger at max for 8h+, overfeeding, waking it early
- [ ] 3 accumulated care mistakes → sick state: angry frame (8), no idle animation, evolution paused
- [ ] Sickness cures when the user hits a daily activity goal (v1: ≥ 30 energy in a day)
- [ ] Sick and untreated for 72h → death
- [ ] Death shows a memorial screen with the Digimon's name, lifespan, and final stats, then returns to a new Digitama
- [ ] Lifetime totals and the Dex survive death — progress is never wiped
- [ ] Care mistakes gate evolution branches per US-011 (neglect → weaker/virus lines)
- [ ] All time thresholds live in one constants file
- [ ] Unit tests cover mistake accrual, sickness onset, cure, and death with an injectable clock
- [ ] Typecheck passes

### Phase 5 — Battles

#### US-018: Battle system
**Description:** As a user, I want to battle AI opponents using stats built from my real activity, so my fitness translates into power.

**Acceptance Criteria:**
- [ ] Battle power derived from stage, strength stat, and lifetime energy totals
- [ ] Opponent selected near the player's stage from the roster
- [ ] Turn-based resolution: attack frame (11) on the attacker, hurt frames (9↔10) on the defender
- [ ] Win/loss shown with the happy (7) or hurt frame, plus a haptic
- [ ] Win/loss record persisted and usable as an evolution requirement (`minBattleWins`)
- [ ] Battles limited per day (v1: 5) so they can't be farmed
- [ ] Losing does not cause death or a care mistake
- [ ] Unit tests cover power calculation and battle resolution with a seeded RNG
- [ ] Typecheck passes
- [ ] Verify in watchOS Simulator

### Phase 6 — Platform polish

#### US-019: Background refresh
**Description:** As a user, I want energy to accrue without opening the app, so the Digimon feels alive.

**Acceptance Criteria:**
- [ ] `WKApplicationRefreshBackgroundTask` scheduled to update energy and evaluate evolution/sickness
- [ ] Uses `HKObserverQuery` with background delivery for step and energy updates
- [ ] Time-based state (hunger, care mistakes, sickness, death) is computed from elapsed real time on next launch — never dependent on the app having been open
- [ ] Verify by backgrounding the app, seeding health data, and reopening

#### US-020: Complication
**Description:** As a user, I want my Digimon on my watch face so I see it all day.

**Acceptance Criteria:**
- [ ] WidgetKit complication shows the current Digimon's 16×16 idle sprite
- [ ] Supports `.accessoryCircular` and `.accessoryRectangular`
- [ ] Rectangular shows sprite + dominant energy progress
- [ ] Tapping opens the app
- [ ] Updates within one timeline refresh of an evolution
- [ ] Verify in watchOS Simulator

#### US-021: Notifications
**Description:** As a user, I want to be told when something important happens, so I don't miss an evolution or lose my Digimon to neglect.

**Acceptance Criteria:**
- [ ] Local notification on evolution
- [ ] Local notification on sickness onset, and a final warning 24h before death
- [ ] All notification types individually toggleable in settings, default on
- [ ] No notification fires while the Digimon is asleep except the death warning
- [ ] Verify in watchOS Simulator

---

## Functional Requirements

**Health data**
- FR-1: Request read-only HealthKit authorization for `stepCount`, `activeEnergyBurned`, `sleepAnalysis`, `appleExerciseTime`.
- FR-2: Query steps, active energy, and exercise time for the current day from local midnight.
- FR-3: Query sleep as the longest asleep block between 18:00 the previous day and 12:00 today, counting only asleep categories.
- FR-4: Operate correctly under partial authorization; unavailable metrics read zero.
- FR-5: Never transmit health data off-device. No network calls in v1.

**Energy**
- FR-6: Map steps→Strength, active calories→Vitality, sleep→Spirit, exercise minutes→Stamina.
- FR-7: Convert at the rates in the Energy Type Model, with all rates in a single constants file.
- FR-8: Credit only the delta since the last read; never double-credit.
- FR-9: Cap each energy type at 100 points per day.
- FR-10: Track per-stage totals (reset on evolution) and lifetime totals (persist through death).
- FR-11: Dominant energy = highest per-stage total, ties broken by most recent increment.

**Evolution**
- FR-12: Load the evolution graph from `evolutions.json`; adding Digimon must require no code change.
- FR-13: Validate the graph at build time; unknown ids, missing sprite files, or skipped stages fail the test suite.
- FR-14: Start each new game at a random Digitama; hatch at 50 total energy into that egg's linked Baby I form.
- FR-15: Evolve when dominant energy matches an edge's `requiredEnergy` and all its thresholds are met.
- FR-16: Enforce minimum time-in-stage: 24h for Baby I/II, 72h for Child and above.
- FR-17: Prefer the most specific qualifying edge; fall back to the node's default edge if none qualifies at the time gate.
- FR-18: Play an evolution animation with haptic, including on app open if the change happened in the background.

**Sprites**
- FR-19: Slice 48×64 sheets into 12 frames at `x=(i%3)*16, y=(i/3)*16`, per the frame table.
- FR-20: Handle 48×16 Digitama sheets as 3 frames.
- FR-21: Render with `.interpolation(.none)` — never smooth pixel art.
- FR-22: Use `Idle Frame Only/` 16×16 sprites for Dex, pickers, and complications.
- FR-23: Show a placeholder for a missing sprite; never crash.

**Care**
- FR-24: Show sleep frames during the user's inferred sleep window; block feed/train while asleep.
- FR-25: Feed costs Vitality, lowers hunger, plays eat frames; refuses at full hunger.
- FR-26: Train costs Strength or Stamina, raises the strength stat, plays the attack frame.
- FR-27: Increase hunger one unit per 4h of real time.
- FR-28: Record care mistakes for: a day with no health data, hunger maxed 8h+, 3+ refusals in a day, waking early.
- FR-29: 3 care mistakes → sick; cure by earning ≥30 energy in a day; 72h sick → death.
- FR-30: On death, show a memorial, then restart at a new Digitama, preserving lifetime totals and the Dex.

**Battle**
- FR-31: Derive battle power from stage, strength stat, and lifetime energy.
- FR-32: Resolve turn-based battles with attack and hurt frames; persist the W/L record.
- FR-33: Limit to 5 battles/day. Losing never kills or causes a care mistake.

**Platform**
- FR-34: Update energy and evaluate state via background refresh and `HKObserverQuery`.
- FR-35: Compute all time-based state from elapsed real time, correct after long closure.
- FR-36: Provide circular and rectangular complications that open the app on tap.
- FR-37: Notify on evolution, sickness, and 24h-before-death; each toggleable.

---

## Non-Goals (Out of Scope)

- **No iPhone companion app.** Standalone watchOS only. No WatchConnectivity.
- **No accounts, cloud sync, or backend.** All state is on-watch. A dead watch means a dead Digimon.
- **No multiplayer or PvP.** Battles are against AI only. No Bluetooth/NFC trading.
- **No dietary calorie intake.** "Calories" means active energy *burned*. Food logging is out.
- **No writing to HealthKit.** Read-only.
- **No monetization**, ads, or IAP.
- **No custom art.** Only the existing sprite library; nothing new is drawn.
- **No B&W "classic LCD" mode** in v1, though `Black and White Sprites/` makes it a natural v2.
- **No Armor/Hybrid branch** in v1 (16 sprites, needs bespoke rules — defer).
- **No localization.** English only in v1 (note: sprite names use Japanese-canon naming, e.g. Perfect vs Ultimate).
- **No Apple Watch Ultra Action Button** or other hardware-specific integrations.

---

## Design Considerations

- **Pixel fidelity is the whole aesthetic.** 16×16 art scaled to a ~180pt watch face is a ~11× upscale; it must be nearest-neighbor. Any smoothing kills the look.
- **Round-rect screen.** Sprites go center-screen with generous margins; test 41mm and 49mm — the small watch is the constraint.
- **Glanceable first.** The primary screen answers "how's my Digimon and what does it need" in under two seconds. Battles and the Dex live behind navigation.
- **Honor the source material.** Two-frame animation at ~500ms per frame is what the original V-Pets did; resist making it smooth.
- **Dark background.** Sprites are designed on light LCD backgrounds — verify contrast on OLED black and add a subtle backing panel if they float oddly.
- **Haptics carry the emotion.** Evolution, death, and battle results should be felt without looking.

---

## Technical Considerations

- **watchOS 10+**, SwiftUI, SwiftData for persistence. Standalone target.
- **The evolution graph is the critical path and the main risk.** The full roster is **865 animated Digimon** (not 2,270 — see Real Roster Size), and the folder contains **no evolution data at all** — every edge must be authored by hand. At an optimistic 30 seconds per node, the full graph is still on the order of 7–10 hours of pure data entry, and it is not code, so it cannot be shortcut by better engineering. The PRD is structured so this does not block the build: US-004 defines the format, US-005 generates the boilerplate from filenames, and the app ships behaving correctly on the seeded lines while the graph fills in. **Recommendation: implement and validate the whole loop on 3–4 lines first, then expand the data.** An external community dataset (e.g. the Digimon API or wikimon) could seed the edges, but licensing and name-matching against these filenames need checking first — see Open Questions.
- **Name matching is fiddly.** Variant suffixes (`_X`, `_Black`, `_Virus`, `_2006`) mean one Digimon has many sprites. Decide early whether variants are separate graph nodes (more collectible, more data) or display skins of one node (simpler). The PRD assumes **separate nodes**.
- **Sleep data is unreliable.** Users without Sleep Focus or a sleep tracker produce no sleep samples. Spirit energy would then be permanently zero and its evolution branches unreachable. US-006's partial-authorization path and US-007's "no data" state exist for this; consider a fallback so Spirit lines aren't dead for those users.
- **Do not use an asset catalog for sprites.** 2,270 images in a catalog bloats build time and loses the folder structure that encodes stage. Use a folder reference and load by path.
- **Memory.** Never decode the full roster at once. The Dex must lazily load and cache; a 16×16 PNG is tiny but 2,270 decoded `UIImage`s are not.
- **The clock must be injectable.** Sickness, death, hunger, and time-gating all depend on elapsed time; without a mockable clock these are untestable and you will be waiting 72 real hours to test death.
- **Guard against clock manipulation** at least minimally — a user setting their watch forward should not instantly evolve a Digimon.
- **Background execution on watchOS is stingy.** Do not assume background refresh runs on schedule; recompute from elapsed time on launch (FR-35). Background refresh is an optimization, not the source of truth.
- **HealthKit needs a real device or seeded Simulator data.** Plan for a seeding script or test fixtures.

---

## Success Metrics

- A user's first Digimon hatches within one day of normal activity (~5,000 steps).
- Evolution branches are legibly driven by behavior: a walking-heavy week and a sleep-heavy week reach visibly different Digimon from the same egg.
- Energy is never double-credited across app relaunches (verified by test).
- The main screen renders and refreshes in under 200ms on an Apple Watch Series 7.
- The Dex scrolls at 60fps with the full roster loaded.
- The evolution graph validator passes with zero broken edges or missing sprites.
- A neglected Digimon reliably progresses sick → dead on schedule, and a cared-for one never does.

---

## Open Questions

1. **Evolution data sourcing.** Is hand-authoring the full graph acceptable, or should we evaluate an external dataset (Digimon API / wikimon) to seed edges? This is the single biggest schedule driver. Licensing and name-matching against these specific filenames both need verification.
2. **Variants as nodes or skins?** Should `Agumon`, `Agumon_X`, and `Agumon_Black` be three collectible Digimon or one with skins? PRD currently assumes three.
3. **Sprite licensing.** The sprites are a community collection by "Tortoiseshel," many heavily edited, and Digimon is Bandai IP. Fine for personal/portfolio use; **blocking for App Store distribution.** What's the intent here?
4. **Spirit energy fallback.** What should happen for users with no sleep tracking at all — should Spirit lines be unreachable, or should there be an alternate path?
5. **Stage cadence.** Is 24h/72h per stage the right pace? Real V-Pets hit Ultimate in about a week; a health app might want a slower, months-long arc.
6. **Should the user pick the starting Digitama** or is random better for replay value? Currently random.
7. **Multiple Digimon at once,** or strictly one at a time? Currently one.
8. **Armor/Hybrid branch** — worth designing rules for later, or cut permanently?
9. **Naming convention** — the sprites use Japanese canon (Perfect/Ultimate, Dukemon). Keep that, or map to English dub names (Ultimate/Mega, Gallantmon)?
