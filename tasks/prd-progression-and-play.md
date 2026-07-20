# PRD: Progression and Play — branching evolution, a full Dex, real battles, real training

## Introduction

The V-Pet is complete as a care simulator and thin as a *game*. Evolution branches on one axis
(which of four energy types is dominant), the Dex is a text list of six lines, a battle is two
sprites twitching at each other, and training is a single tap that always gives `+1`.

This PRD adds the play. Five threads, in dependency order:

1. **Branching evolution driven by real health behaviour.** An edge can require things like "1,000
   steps in this stage", "washed your hands eight times", "stood in twelve separate hours". Miss
   them and you get the junk evolution — an Agumon that never walked becomes Numemon, not Greymon.
2. **A full-roster Dex** — all 1,022 Digimon as a flat grid, owned ones filled in, unowned as a
   disabled `?`. Tapping an owned one opens the existing detail view, which now lists its one-to-
   three possible evolutions with a *subtle hint* at what each one takes.
3. **Visible sickness** — an animated sick pose and a pulsing medical-bandage icon.
4. **Battles with projectiles and signature moves** — each Digimon throws something characteristic,
   and the winner's finishing blow is its named signature move.
5. **Six training minigames** — Timing Bar, Button Masher, Power Meter and three more, with
   different Digimon training in different games, and performance scaling the stat gained.

The through-line is *anticipation*: you should want to raise a new Digimon to find out what it
throws, how it trains, and what it might become.

## Reference

Evolution mechanics are modelled on the Digital Monster Color, documented at
<https://humulos.com/digimon/dmc/>. What was taken from it, and what was not, is in D-3.

## Goals

- Evolution branches on **behaviour**, not just on an energy total — at least eight distinct
  condition types across the shipped lines, drawn from both the `health.*` and `care.*` families.
- Every non-terminal Digimon has a **junk evolution** reachable by doing nothing, so the good
  branches feel earned.
- A player can look at any owned Digimon and **infer, without being told a number**, what to do to
  reach each of its possible evolutions.
- All 1,022 Digimon are browsable; the ~950 that are art-only degrade gracefully rather than
  showing an empty screen.
- A battle is **legible as a fight**: you can see who threw what, and the finishing blow is named.
- Training has a **skill ceiling** — playing well beats playing badly, and six distinct games mean
  a new Digimon brings a new game.

## Architectural decisions

Four decisions made up front, because several stories depend on them and re-litigating them
mid-implementation would be expensive.

### D-1: `roster.json` is new and separate from `evolutions.json`

`Resources/evolutions.json` stays exactly what it is — the **curated playable graph**, 69 nodes
across six lines, every node carrying a required `line` and real `evolutions[]`.

A new bundled `Resources/roster.json` is the **Dex catalog**: all 1,022 entries, no `line`, no
edges. It is generated from `roster.generated.json`, which `scripts/import_roster.py` already
produces.

They are not merged, for a specific reason: `EvolutionNode.line` is `decode`, not
`decodeIfPresent`, and a missing `line` fails the *entire* graph load — which `fatalError`s at
launch. Pouring ~950 line-less nodes into `evolutions.json` would either break the load or force
`line` to become optional, which would silently drop nodes out of the tree. A separate, lighter
`RosterEntry` type keeps the playable graph's invariants intact.

The Dex reads `roster.json` for its cells and cross-references `EvolutionGraph.bundled` for the
detail view's evolution section. An entry absent from the graph shows "No evolutions recorded."

### D-2: conditions extend the edge, they do not replace it

`requiredEnergy` / `minEnergy` / `maxCareMistakes` / `minBattleWins` all stay and keep working
unchanged. A new optional `conditions: [EvolutionCondition]` array is **additive** — every existing
edge decodes and behaves exactly as it does today, and all existing evolution tests stay valid.

An edge qualifies only if the old gates pass **and** every condition passes.

### D-3: borrow DMC's ideas, add them alongside what exists

Source: the Digital Monster Color mechanics at <https://humulos.com/digimon/dmc/>.

The real device branches on five things: care mistakes, **training session count**, overfeeds,
sleep disturbances, and **battle win ratio** over a minimum number of battles. Three of those are
genuinely good ideas this app lacks. **Nothing here replaces an existing mechanism** — the four
energy types, `requiredEnergy`, `minEnergy`, `maxCareMistakes` and `minBattleWins` all stay exactly
as they are and keep gating exactly as they do.

So `metric` spans two families:

- `health.*` — HealthKit-backed, limited to identifiers US-055 marked usable.
- `care.*` — only counters **nothing today can express**: `trainingSessions`, `overfeeds`,
  `sleepDisturbances`, `battleCount`, `battleWinRatio`.

`careMistakes` is deliberately **not** among them: `maxCareMistakes` already gates on it, and two
ways to say one thing is how a later iteration talks itself into deleting the older one. Likewise
`minBattleWins` stays and keeps working — `battleWinRatio` *adds* ratio gating it cannot express,
and an edge may use either or both.

Two consequences that are easy to miss:

**Criteria are bands, not floors.** The signature DMC shape is *training 8–31 earns the good
branch, while both 0–7 and 32+ fall to the junk one* — overtraining is punished exactly as much as
undertraining. A band is two conditions on one edge (`atLeast` + `atMost`). A design with only
floors cannot express this, and it is most of what makes the real device interesting.

**Battle gating can be a ratio.** DMC wants "15+ battles at 80%+ wins", which absolute
`minBattleWins` cannot say. `care.battleCount atLeast 15` plus `care.battleWinRatio atLeast 0.8`
can — as an additional option, not a replacement.

Three of the counters this needs do not usefully exist yet, which is why US-084 exists:
`refusalCount` resets **daily** and so cannot express a stage-long "3+ overfeeds"; only
`wakeMistakeDay` exists for sleep, and it is a day marker rather than a count; and there is no
training-session counter at all.

**`strengthStat` is not that counter, and must not become it.** `TrainAction` currently comments
that the stat "reads as sessions trained" — one session, one point. US-075's graded gain (0–3)
breaks that identity, so *sessions trained* needs its own counter, incremented once per session
**regardless of grade**. DMC is explicit that training counts whether it succeeded or not.

*Not adopted:* DMC's stage durations (10 min / 12 h / 24 h / 36 h / 48 h) are much shorter than
this project's shipped `EvolutionTiming` (24 h baby, 72 h mature). Retuning that is out of scope —
it is balanced against this app's health-data pacing, not a 1998 pedometer's.

### D-4: verification is a Simulator screenshot behind a launch flag

This project has no browser. The established convention (`-dexLineDemo`, `-dexDetailDemo`,
`-complicationDemo`, `-wanderDemo`) is a `#if DEBUG` launch argument that pushes the screen
directly, because `simctl` cannot synthesise a tap. Every UI story below follows it.

**Do not uninstall the app to reset game state** — `progress.txt` records that this wipes the
HealthKit grant and costs ~15 minutes to repair via `healthdb.sqlite`. Add a demo flag instead.

---

## User Stories

### Epic 1 — Health-driven evolution conditions

### US-055: Spike — which HealthKit types are actually readable on watchOS 26.4
**Description:** As a developer, I need to know which health identifiers exist, are readable on the
watch, and return data, before designing criteria around ones that do not.

**Acceptance Criteria:**
- [ ] For each candidate identifier below, record: compiles on watchOS 26.4, appears in the
      authorization sheet, and returns samples or `noData` (not an error) in the Simulator.
- [ ] Quantity candidates: `.stepCount`, `.distanceWalkingRunning`, `.flightsClimbed`,
      `.appleExerciseTime`, `.appleStandTime`, `.activeEnergyBurned`, `.basalEnergyBurned`,
      `.vo2Max`, `.restingHeartRate`, `.heartRateVariabilitySDNN`, `.respiratoryRate`,
      `.oxygenSaturation`, `.distanceSwimming`, `.distanceCycling`, `.dietaryWater`,
      `.timeInDaylight`, `.physicalEffort`, `.environmentalAudioExposure`
- [ ] Category candidates: `.handwashingEvent`, `.mindfulSession`, `.appleStandHour`,
      `.toothbrushingEvent`, `.sleepAnalysis`, `.highHeartRateEvent`, `.lowCardioFitnessEvent`,
      `.appleWalkingSteadinessEvent`
- [ ] `HKWorkoutType.workoutType()` — whether workout counts by activity type are readable
- [ ] Write findings to `docs/health-metrics.md`, one row per identifier with a verdict of
      `usable` / `unavailable on watchOS` / `compiles but never has data`
- [ ] Explicitly record which ones need a **new authorization prompt** vs. which are covered by the
      four already granted
- [ ] Build passes

**Note:** this is a spike. It writes a doc and may write throwaway probe code under `#if DEBUG`;
it ships no feature. Leave `passes: true` only when `docs/health-metrics.md` exists and every
identifier above has a verdict.

### US-056: Add `EvolutionCondition` to the edge schema
**Description:** As a developer, I need conditions to be data in `evolutions.json` so criteria can
be authored without editing Swift.

**Acceptance Criteria:**
- [ ] New `EvolutionCondition` struct: `metric` (string enum), `window` (`stage` | `day` |
      `lifetime`), `comparison` (`atLeast` | `atMost`), `value` (Double), `hint` (string)
- [ ] `metric` spans both families per D-3: `health.*` (only identifiers US-055 marked `usable`)
      and `care.*` (`trainingSessions`, `careMistakes`, `overfeeds`, `sleepDisturbances`,
      `battleCount`, `battleWinRatio`)
- [ ] A **band** is two conditions on one edge (`atLeast` X + `atMost` Y) — the DMC shape where a
      middle training range earns the good branch and both extremes fall to the junk one
- [ ] `battleWinRatio` is a 0.0–1.0 fraction, so "15+ battles at 80%+ wins" is expressible
- [ ] `EvolutionEdge` gains `conditions: [EvolutionCondition]`, hand-decoded to default `[]` when
      the key is absent — matching how `isDefault` and `dexOnly` already default
- [ ] Every existing edge in `evolutions.json` decodes unchanged, with `conditions == []`
- [ ] `EvolutionGraphValidator` rejects: an unknown `metric`, a negative `value`, an empty `hint`,
      and a `battleWinRatio` outside 0.0–1.0
- [ ] `docs/evolutions-schema.md` gains a Condition section documenting every field and window
- [ ] Existing `EvolutionGraphTests` and `EvolutionGraphValidatorTests` still pass
- [ ] Build passes

### US-057: Read an arbitrary health metric over a window
**Description:** As a developer, I need one reader that can total any usable metric — quantity or
category — over a date interval, so conditions are not limited to the four energy metrics.

**Acceptance Criteria:**
- [ ] `HealthMetricReader` totals a quantity metric over an injected `DateInterval`
- [ ] It counts a category metric's **events** (e.g. handwashing events, stood stand-hours) rather
      than summing values, since `HKCategoryValueNotApplicable` has no meaningful magnitude
- [ ] `.appleStandHour` counts only samples whose value is `HKCategoryValueAppleStandHour.stood`
- [ ] Behind a protocol so tests inject fixture samples — the Simulator has no health data, and a
      test against a live query proves nothing (CLAUDE.md)
- [ ] A failing or unauthorized read returns `.unavailable`, never a thrown error, matching
      `TodayHealthReader.read`
- [ ] Unit tests cover: a quantity total, a category event count, a stand-hour filtered count,
      an empty window returning `noData`, and a failing fetch returning `.unavailable`
- [ ] Build passes, tests pass

### US-058: Accumulate per-stage metric totals
**Description:** As a developer, I need running totals per metric since the Digimon entered its
current stage, so a `window: "stage"` condition has something to compare against.

**Acceptance Criteria:**
- [ ] `GameState` gains stage-scoped metric totals, keyed by metric
- [ ] Crediting is **idempotent** — refreshing twice in one day does not double-count, following
      the `EnergyLedger` pattern already in the codebase
- [ ] Totals **reset on evolution**, when `stageEnteredDate` moves
- [ ] Lifetime totals accumulate separately and never reset
- [ ] `window: "day"` resolves to the best single local day, not the current one — so one good
      Tuesday still counts on Friday
- [ ] Persists across app launches
- [ ] Tests drive an injected clock; no test waits real time (CLAUDE.md)
- [ ] Tests cover: accumulation, double-refresh idempotency, reset on evolution, lifetime survival
      across a reset, and best-day selection
- [ ] Build passes, tests pass

### US-084: Stage-scoped care counters for evolution gating
**Description:** As a developer, I need the counters the Digital Monster Color branches on —
training sessions, overfeeds, sleep disturbances — tracked per stage, since none of them exists in
a usable form today.

**Acceptance Criteria:**
- [ ] `GameState` gains stage-scoped `trainingSessions`, `overfeeds` and `sleepDisturbances`,
      all persisted
- [ ] `trainingSessions` increments once per session **regardless of grade** — DMC counts training
      whether it succeeded or not, and US-075's graded gain must not be what evolution reads
- [ ] `overfeeds` counts cumulative refusals within the stage — distinct from the existing
      `refusalCount`, which resets **daily** and so cannot express a stage-long "3+ overfeeds" gate
- [ ] `sleepDisturbances` counts waking the Digimon during its sleep window — a new counter; only
      `wakeMistakeDay` exists today, and it is a day marker rather than a count
- [ ] All three reset on evolution, alongside the US-058 metric totals
- [ ] `care.battleWinRatio` derives from existing `battleWins`/`battleLosses`, and is 0.0 with no
      battles fought — never a divide by zero
- [ ] Existing `refusalCount`, `wakeMistakeDay` and care-mistake behaviour are **unchanged** —
      this story adds counters and rewires nothing
- [ ] Tests use an injectable clock and cover each counter incrementing, reset on evolution, the
      zero-battle ratio, and `trainingSessions` incrementing on a `miss`
- [ ] Build passes, tests pass

### US-059: Expand HealthKit authorization without breaking the existing grant
**Description:** As a user who already granted the four original types, I want the new ones
requested without losing what I already approved.

**Acceptance Criteria:**
- [ ] The read set includes every metric named by a condition in `evolutions.json`, derived from
      the graph rather than hardcoded — so authoring a new condition cannot forget the grant
- [ ] A user with the original four grants is re-prompted only for the new types
- [ ] A **denied** new type makes its conditions unsatisfiable but leaves every other edge working;
      it never blocks evolution entirely and never charges a care mistake
- [ ] `HealthAuthorizationView` copy explains what the new types are for
- [ ] The existing `-healthDenied` / `-healthUnavailable` / `-healthAnswered` launch flags still work
- [ ] Build passes, tests pass

### US-060: `EvolutionEngine` evaluates conditions
**Description:** As a player, I want my behaviour to decide which branch I get.

**Acceptance Criteria:**
- [ ] `EvolutionEngine.qualifies` returns false unless **every** condition on the edge passes
- [ ] Existing gates (`requiredEnergy`, `minEnergy`, `maxCareMistakes`, `minBattleWins`) are
      unchanged and still evaluated
- [ ] An edge with `conditions: []` behaves **exactly** as it does today — every existing test in
      `EvolutionTests` passes untouched
- [ ] A metric whose reading is `.unavailable` fails its condition rather than passing it — an
      unreadable metric must not hand out a branch the player did not earn
- [ ] A band (`atLeast` + `atMost` on the same metric) evaluates as a closed interval — a value
      outside it fails, so an **over**trained Digimon falls to the junk branch as on the real device
- [ ] `care.*` conditions read the US-084 counters; `health.*` conditions read the US-058 totals
- [ ] The `isDefault` fallback still fires when nothing qualifies, so no Digimon is ever stuck
- [ ] Tests cover: a condition met, unmet, `atMost` inverted, multiple conditions where one fails,
      an unavailable metric, and the fallback firing when all conditioned edges fail
- [ ] Build passes, tests pass

### US-061: Author branching criteria and junk evolutions
**Description:** As a player, I want each of my Digimon to have a real choice with a real
consequence for neglect.

**Acceptance Criteria:**
- [ ] Every non-terminal Child and Adult across the six lines has **two to three** outgoing edges
- [ ] Every such node's `isDefault` edge is a **junk evolution** reachable by inaction. `Numemon`
      (`Adult/Numemon.png`) and `Scumon` (`Adult/Scumon.png`) both exist on disk and are verified
      present before being referenced
- [ ] At least one node uses the **band** shape — a middle training range earns the good branch
      while both too-little and too-much fall to the junk one
- [ ] At least one Perfect-or-later edge is gated on battle performance as a **ratio**
      (`care.battleCount atLeast 15` + `care.battleWinRatio atLeast 0.8`), following the real device
- [ ] At least **eight distinct** condition metrics are used, drawn from **both** families
- [ ] Every `to` names a node that exists; every `spriteFile` is verified with `ls` before use
- [ ] No `dexOnly` node is named by any edge (CLAUDE.md)
- [ ] `EvolutionGraphValidator` passes on the whole file
- [ ] Every condition carries a `hint` that does **not** contain a digit — see US-065
- [ ] Build passes, tests pass

---

### Epic 2 — Full-roster Dex and evolution hints

### US-062: Bundle the full 1,022-entry roster
**Description:** As a developer, I need the whole roster available at runtime so the Dex can show
every Digimon.

**Acceptance Criteria:**
- [ ] `Resources/roster.json` is bundled and contains all 1,022 entries
- [ ] New `RosterEntry` type: `id`, `displayName`, `stage`, `spriteFile`, `variant`, `dexOnly` —
      **no `line`, no `evolutions`** (decision D-1)
- [ ] Entries that `roster.generated.json` emits with `"stage": null` are resolved to a real stage
      before bundling; the loader rejects a null stage rather than defaulting one
- [ ] Every `spriteFile` is verified to exist on disk by a test, not by inspection
- [ ] `evolutions.json` is **unmodified** by this story
- [ ] `scripts/` regenerates `roster.json` reproducibly; README documents the command
- [ ] Build passes, tests pass

### US-063: Replace the Dex line list with a flat item grid
**Description:** As a user, I want to see every Digimon in one grid so I can tell at a glance how
much of the roster I have met.

**Acceptance Criteria:**
- [ ] The Dex root is a `LazyVGrid` over all 1,022 roster entries — **not** the line list
- [ ] Owned entries show the idle sprite; unowned show `?`, are visibly dimmed, and are `.disabled`
- [ ] Only on-screen cells decode art — scrolling the full grid must not decode 1,022 sprites
- [ ] Header still reads `discovered/total` against the full roster
- [ ] Tapping an owned cell opens `DexDetailView`; tapping an unowned one does nothing
- [ ] Fits the 41mm screen without horizontal clipping
- [ ] Scrolling the full grid stays responsive (no visible stutter) on Series 11 (46mm)
- [ ] **Verify in Simulator** via a `#if DEBUG` launch flag, screenshot attached to the notes (D-4)
- [ ] Build passes, tests pass

### US-064: Detail view lists possible evolutions
**Description:** As a user, I want to see what my Digimon can become so I have something to aim at.

**Acceptance Criteria:**
- [ ] `DexDetailView` gains an "Evolves into" section listing every outgoing edge's target
- [ ] Each candidate shows its sprite and name if **already discovered**; a `?` and the name
      withheld if not — meeting it should still be a surprise
- [ ] An entry with no edges, or absent from `EvolutionGraph.bundled`, shows
      "No evolutions recorded." rather than an empty section (decision D-1)
- [ ] One to three candidates render without scrolling on 41mm; more than three scrolls
- [ ] **Verify in Simulator** via `-dexDetailDemo`, screenshot attached (D-4)
- [ ] Build passes, tests pass

### US-065: Hint vocabulary for every condition metric
**Description:** As a player, I want to be nudged toward what a branch needs without being handed a
checklist.

**Acceptance Criteria:**
- [ ] Every `HealthConditionMetric` has default flavour text, e.g. steps → "Restless. It wants to
      see the horizon."; handwashing → "It flinches from grime."; mindful → "It listens for
      stillness."; stand hours → "It cannot bear sitting still."; daylight → "It turns toward
      the sun."
- [ ] An edge's authored `hint` overrides the default
- [ ] A test asserts **no hint string contains a digit** — the hint must never leak the threshold
- [ ] Hint text is pure and testable without a view
- [ ] Build passes, tests pass

### US-066: Render hints with progress-based reveal
**Description:** As a player, I want the hint to warm up as I get closer, so I can tell I am on the
right track.

**Acceptance Criteria:**
- [ ] Three reveal levels, chosen by progress toward the condition:
      **far** (< 50%) shows flavour text alone; **close** (>= 50%) shows flavour plus a warmer
      qualifier; **met** shows a checkmark
- [ ] No exact number, threshold, or percentage is ever displayed
- [ ] A candidate whose conditions are all met is visually distinguished from one that is not
- [ ] The reveal-level function is pure and unit-tested at each boundary
- [ ] **Verify in Simulator** via a demo flag seeding a part-met condition, screenshot attached (D-4)
- [ ] Build passes, tests pass

### US-067: Keep the evolution tree reachable from the flat Dex
**Description:** As a user, I want the flat grid as my way in without losing the line tree, so the
at-a-glance roster and the shape of a line are both available.

**Acceptance Criteria:**
- [ ] `EvolutionTreeView` is **kept, not deleted** — US-041/US-042 built it, and it shows a line's
      branching shape, which a flat grid cannot
- [ ] The flat grid from US-063 stays the Dex root, per the request that the line map was too
      complicated as an *entry point*
- [ ] `DexDetailView` gains a way through to the owning line's tree, for any Digimon in a line
- [ ] A Digimon in no line (the ~950 roster-only entries) shows no tree affordance rather than an
      empty tree
- [ ] The `-dexLineDemo` launch flag still works
- [ ] `EvolutionTreeTests` and `DexScreenTests` both still pass
- [ ] **Verify in Simulator** that grid → detail → tree works, screenshot attached (D-4)
- [ ] Build passes, tests pass

**Note:** deliberately a *merge*, not a retirement. An earlier draft offered deleting the tree;
that discards working, tested UI to satisfy a navigation change. The grid answers "what do I own",
the tree answers "what shape is this line".

---

### Epic 3 — Visible sickness

### US-068: Animate the sick Digimon
**Description:** As a user, I want a sick Digimon to look sick, so I notice without opening a menu.

**Acceptance Criteria:**
- [ ] A sick Digimon plays a distinct animation — the hurt loop (frames 9 ↔ 10) at a slower cadence
      than the battle hurt loop, so it reads as ailing rather than as being struck
- [ ] Wandering movement is suppressed or slowed while sick
- [ ] A healthy Digimon is visually unchanged
- [ ] Rendering still uses `.interpolation(.none)` (CLAUDE.md)
- [ ] The animation choice is a pure function of `healthStatus`, unit-tested without a view
- [ ] **Verify in Simulator** via a demo flag forcing the sick state — **not** by uninstalling to
      reset the save (D-4, and `progress.txt`'s HealthKit-grant trap). Screenshot attached
- [ ] Build passes, tests pass

### US-069: Pulsing medical-bandage icon
**Description:** As a user, I want an unambiguous sick indicator, since a slow hurt loop alone is
easy to miss.

**Acceptance Criteria:**
- [ ] A `bandage.fill` SF Symbol overlays the main screen while `healthStatus == .sick`
- [ ] It pulses — opacity or scale, continuously, not a one-shot
- [ ] It is absent when healthy and absent when dead
- [ ] It does not overlap the sprite's body or the action buttons on 41mm
- [ ] The main screen still fits without scrolling (US-039 is not regressed)
- [ ] **Verify in Simulator** via the same demo flag, screenshot attached (D-4)
- [ ] Build passes, tests pass

---

### Epic 4 — Battles with projectiles and signature moves

### US-070: Move catalog
**Description:** As a developer, I need per-Digimon attack identity as data, so authoring a move is
not a code change.

**Acceptance Criteria:**
- [ ] `Resources/moves.json` maps a Digimon `id` to: `projectileSymbol`, `tint`,
      `signatureName`, `signatureSymbol`
- [ ] Symbols are SF Symbols (`flame.fill`, `bolt.fill`, `drop.fill`, `hand.raised.fill`,
      `snowflake`, `leaf.fill`, `moon.fill`, `sparkles`, …) — no new image assets
- [ ] Every symbol name is verified to render; an unknown symbol fails a test rather than shipping
      as a blank square
- [ ] A Digimon absent from the file falls back by `line`, then by `stage` — so all 1,022 have
      *something*, and battle never renders an empty projectile
- [ ] `MoveCatalog` lookup is pure and unit-tested, including both fallback tiers
- [ ] Build passes, tests pass

### US-071: Face-to-face arena
**Description:** As a user, I want the two Digimon facing each other, not both facing right.

**Acceptance Criteria:**
- [ ] Player on the left facing right; opponent on the right **horizontally mirrored** to face left
- [ ] Mirroring does not soften the pixels — `.interpolation(.none)` survives the transform
- [ ] Hit points and the opponent's name remain visible, and the arena fits 41mm
- [ ] **Verify in Simulator** via a battle demo flag, screenshot attached (D-4)
- [ ] Build passes, tests pass

### US-072: Projectiles fly on each exchange
**Description:** As a user, I want to see the attack travel, so an exchange reads as a hit.

**Acceptance Criteria:**
- [ ] On each `BattleTurn`, the attacker's projectile animates from attacker toward defender
- [ ] It travels in the correct direction for whichever side is attacking
- [ ] It is tinted with the attacker's catalog tint
- [ ] Impact coincides with the defender entering its hurt loop — the existing frame assignment
      (attacker holds frame 11, defender plays 9 ↔ 10) is preserved
- [ ] Timing is driven by the existing injectable `turnDuration`, so tests still run a whole battle
      in milliseconds
- [ ] `BattleEngine` is **not** touched — resolution stays pure and every existing `BattleTests`
      and `BattlePowerTests` assertion holds
- [ ] **Verify in Simulator**, screenshot attached (D-4)
- [ ] Build passes, tests pass

### US-073: Signature move on the finishing blow
**Description:** As a user, I want the killing blow to be special and named, so a win feels like a
win.

**Acceptance Criteria:**
- [ ] The turn where `isKnockout` is true renders the winner's `signatureSymbol` instead of the
      ordinary projectile
- [ ] It is visibly larger than an ordinary projectile
- [ ] The `signatureName` is shown as a banner during that turn
- [ ] It fires whether the **player or the opponent** lands the finish
- [ ] The result screen still shows the existing win/loss frames and its haptic
- [ ] The knockout-turn detection is pure and unit-tested against a seeded report
- [ ] **Verify in Simulator**, screenshot of a signature move attached (D-4)
- [ ] Build passes, tests pass

### US-074: Author moves for all 69 curated Digimon
**Description:** As a player, I want each Digimon's attack to suit it, so owning a new one is worth
looking forward to.

**Acceptance Criteria:**
- [ ] All 69 nodes in `evolutions.json` have an explicit `moves.json` entry
- [ ] Attacks suit the Digimon — e.g. Agumon throws orange flame with a larger flame signature;
      Gabumon throws **blue** flame; a plant line throws leaves; an electric line throws bolts
- [ ] No two Digimon in the same line share an identical `projectileSymbol` + `tint` pair
- [ ] At least **eight distinct** symbols are used across the file
- [ ] Signature names are authored, not generated from a template
- [ ] A test asserts full coverage of the 69 and the uniqueness rule
- [ ] Build passes, tests pass

---

### Epic 5 — Training minigames

### US-075: Minigame foundation and graded gain
**Description:** As a developer, I need one shape every minigame conforms to, so adding a seventh is
adding a file.

**Acceptance Criteria:**
- [ ] A `TrainingMinigame` protocol/enum with a uniform `TrainingResult`:
      `miss` | `good` | `great` | `perfect`
- [ ] `TrainAction` maps the result to `strengthStat` gain: `miss` = 0, `good` = 1, `great` = 2,
      `perfect` = 3
- [ ] The session increments `trainingSessions` (US-084) exactly once **regardless of grade**,
      including on a `miss` — evolution branches on sessions trained, not on how well they went
- [ ] Energy cost is charged **once**, on entering the game, and is **not** refunded on `miss` —
      otherwise a miss is free and the game is optional
- [ ] Existing eligibility rules are unchanged: asleep blocks, sick blocks, insufficient energy
      blocks, all with their current messages
- [ ] Every existing `TrainingTests` assertion about cost and blocking still passes
- [ ] Grading is pure and unit-tested at every boundary
- [ ] Build passes, tests pass

### US-076: Timing Bar
**Description:** As a user, I want to stop a moving marker in a target zone.

**Acceptance Criteria:**
- [ ] A marker sweeps a bar; tapping stops it; the zone hit decides the grade
- [ ] A centre sub-zone yields `perfect`; missing the zone entirely yields `miss`
- [ ] Sweep speed and zone width are injectable so tests do not wait real time
- [ ] Grade-from-position is pure and unit-tested at each boundary
- [ ] **Verify in Simulator** via a demo flag, screenshot attached (D-4)
- [ ] Build passes, tests pass

### US-077: Button Masher
**Description:** As a user, I want to tap as fast as I can against a timer.

**Acceptance Criteria:**
- [ ] Counts taps within a fixed window; thresholds map the count to a grade
- [ ] The window duration is injectable
- [ ] A live tap count is visible during play
- [ ] Grade-from-count is pure and unit-tested at each threshold
- [ ] **Verify in Simulator**, screenshot attached (D-4)
- [ ] Build passes, tests pass

### US-078: Power Meter
**Description:** As a user, I want to hold to charge and release before it overloads.

**Acceptance Criteria:**
- [ ] Holding fills a meter; releasing in the target band grades highest
- [ ] Overfilling past the band yields `miss` — there is a real cost to greed
- [ ] Fill rate and band bounds are injectable
- [ ] Grade-from-fill is pure and unit-tested, including the overload case
- [ ] **Verify in Simulator**, screenshot attached (D-4)
- [ ] Build passes, tests pass

### US-079: Crown Sprint
**Description:** As a user, I want to spin the Digital Crown to fill a gauge.

**Acceptance Criteria:**
- [ ] Crown rotation accumulates toward a target within a time window
- [ ] Uses `digitalCrownRotation`; the gauge responds to real crown input on the Simulator
- [ ] Rotation total and window are injectable
- [ ] Grade-from-rotation is pure and unit-tested
- [ ] **Verify in Simulator**, screenshot attached (D-4)
- [ ] Build passes, tests pass

### US-080: Reflex Strike
**Description:** As a user, I want to tap the instant the signal appears.

**Acceptance Criteria:**
- [ ] After a randomised delay a signal appears; reaction time decides the grade
- [ ] Tapping **before** the signal is a false start and yields `miss`
- [ ] The delay uses the project's `SeededGenerator`, so a test can pin it
- [ ] Grade-from-latency is pure and unit-tested, including the false start
- [ ] **Verify in Simulator**, screenshot attached (D-4)
- [ ] Build passes, tests pass

### US-081: Sequence Recall
**Description:** As a user, I want to repeat a pattern back from memory.

**Acceptance Criteria:**
- [ ] A short sequence is shown, then reproduced by the user; correct count decides the grade
- [ ] A fully correct sequence yields `perfect`; the first wrong entry ends the round
- [ ] Sequence length and playback speed are injectable; generation uses `SeededGenerator`
- [ ] Grade-from-correct-count is pure and unit-tested
- [ ] **Verify in Simulator**, screenshot attached (D-4)
- [ ] Build passes, tests pass

### US-082: Assign a minigame per Digimon
**Description:** As a player, I want a new Digimon to bring a new game, so raising one is worth it.

**Acceptance Criteria:**
- [ ] Each of the six shipped lines maps to a different one of the six games
- [ ] A Digimon outside the six lines falls back deterministically by stage — never to "no game"
- [ ] The same Digimon **always** gets the same game; assignment is not random per session
- [ ] Assignment is pure and unit-tested, including the fallback
- [ ] Build passes, tests pass

### US-083: Train opens the assigned minigame
**Description:** As a user, I want tapping Train to start my Digimon's game rather than silently
adding a point.

**Acceptance Criteria:**
- [ ] Train presents the assigned game as an overlay, in the manner of `BattleView` and
      `EvolutionCeremonyView` — the buttons underneath are not tappable through it
- [ ] The result applies the graded gain and shows what was earned
- [ ] Blocked cases (asleep / sick / insufficient energy) show their message and **never** open a game
- [ ] Dismissing or backgrounding mid-game grades as `miss` and does not refund — it must not be an
      escape hatch from a bad round
- [ ] **Verify in Simulator** end to end: open, play, see the gain, screenshot attached (D-4)
- [ ] Build passes, tests pass

---

## Functional Requirements

**Evolution conditions**
- FR-1: An edge may carry zero or more conditions; an edge with none behaves exactly as today.
- FR-2: A condition names a metric, a window (`stage` / `day` / `lifetime`), a comparison
  (`atLeast` / `atMost`), a numeric threshold, and a hint string.
- FR-2a: A metric belongs to `health.*` (HealthKit) or `care.*` (game counters).
- FR-2b: A band is two conditions on one edge and evaluates as a closed interval, so a value above
  the band fails exactly as one below it does.
- FR-2c: `care.battleWinRatio` is a 0.0–1.0 fraction and is 0.0 when no battle has been fought.
- FR-3: An edge qualifies only if its existing gates pass **and** every condition passes.
- FR-4: A metric reading of `.unavailable` fails its condition.
- FR-5: Per-stage metric totals reset when the Digimon evolves; lifetime totals never reset.
- FR-5a: `trainingSessions`, `overfeeds` and `sleepDisturbances` are stage-scoped and reset with them.
- FR-5b: `trainingSessions` increments once per training session regardless of the grade earned.
- FR-6: Metric crediting is idempotent within a local day.
- FR-7: The authorization read set is derived from the metrics named in `evolutions.json`.
- FR-8: Every non-terminal Child and Adult has an `isDefault` junk evolution reachable by inaction.
- FR-9: At least eight distinct condition metrics are used across the shipped graph.

**Dex**
- FR-10: The Dex root is a flat grid over all 1,022 roster entries.
- FR-11: Unowned entries render as a disabled, dimmed `?`.
- FR-12: Only on-screen cells decode sprite art.
- FR-13: The detail view lists every outgoing edge of the selected Digimon.
- FR-14: An undiscovered candidate's sprite and name are withheld.
- FR-15: An entry absent from the evolution graph shows "No evolutions recorded."
- FR-16: Each candidate shows a hint per unmet condition, revealed at one of three levels.
- FR-17: No hint ever displays a number, threshold, or percentage.

**Sickness**
- FR-18: A sick Digimon plays the hurt loop at a slowed cadence.
- FR-19: A pulsing `bandage.fill` overlays the main screen while sick, and only while sick.

**Battle**
- FR-20: The opponent is horizontally mirrored to face the player.
- FR-21: Each exchange animates the attacker's projectile toward the defender.
- FR-22: Projectiles are SF Symbols tinted per Digimon; no new image assets.
- FR-23: The knockout blow renders the winner's signature symbol, enlarged, with its name.
- FR-24: Every Digimon resolves to a move via explicit entry, then line, then stage.
- FR-25: `BattleEngine` resolution stays pure and untouched by presentation.

**Training**
- FR-26: Train opens the Digimon's assigned minigame.
- FR-27: Six minigames ship: Timing Bar, Button Masher, Power Meter, Crown Sprint, Reflex Strike,
  Sequence Recall.
- FR-28: Every game grades to `miss` | `good` | `great` | `perfect`.
- FR-29: Grades map to a `strengthStat` gain of 0 / 1 / 2 / 3.
- FR-30: Energy is charged on entry and never refunded, including on abandonment.
- FR-31: Assignment is deterministic per Digimon.
- FR-32: Existing blocking rules are preserved and never open a game.

## Non-Goals

- **Nothing existing is removed.** DMC is a source of *ideas*, not a spec to conform to. Every
  shipped mechanic — the four energy types, dominant-energy branching, `requiredEnergy`,
  `minEnergy`, `maxCareMistakes`, `minBattleWins`, `EvolutionTiming`, `refusalCount`, the evolution
  tree — survives this PRD intact. New mechanics sit **beside** them. Any story that finds itself
  deleting a working feature to make room should stop and leave `passes: false` with a note.
- **No PvP.** `BattleSide` stays a two-case enum; nothing here makes it a list of combatants.
- **No new sprite assets.** Projectiles are SF Symbols; pixel-art projectiles
  are a possible later swap, not this PRD.
- **No writing to HealthKit.** Read-only, as today.
- **No new evolution lines.** The six shipped lines get richer criteria, not new members.
- **No rebalancing of the four energy types.** `EnergyRates` is untouched.
- **Losing a battle still costs nothing** but the record — `recordBattle`'s deliberate "nothing
  else" is preserved.
- **No minigame leaderboards, streaks, or currency.**
- **No iPhone companion app.**

## Technical Considerations

- **The HealthKit grant is fragile.** `progress.txt` documents that uninstalling to reset state
  wipes the grant and strands the app on an untappable system sheet. Every state-reset need in this
  PRD must be met with a `#if DEBUG` launch flag.
- **`EvolutionGraph.bundled` traps on a decode failure**, and the app is the `TEST_HOST` — a JSON
  typo kills the whole test run with an error naming neither the file nor the graph. Grep for
  "Could not load the evolution graph". US-056 and US-061 both touch this file and are the two most
  likely places to hit it.
- **Sprite rendering must stay `.interpolation(.none)`** — including through the mirroring transform
  in US-071.
- **Sheets are decoded once and cropped to 12 `CGImage`s at load** (`IdleSpriteCache`,
  `SpriteLoader`). The 1,022-cell Dex grid must not break that: lazy cells, no eager decode.
- **1,022 grid cells is the main performance risk** in this PRD. `LazyVGrid` inside a `ScrollView` is
  the existing pattern in `DexGridView` and should carry over directly.
- **`.timeInDaylight`, `.physicalEffort` and `.toothbrushingEvent` are the most likely of the
  candidates to be unavailable or empty on watchOS** — US-055 exists to find out before US-061
  authors criteria around them.
- **Every new randomised element uses `SeededGenerator`**, so minigame and reflex timing stay
  reproducible in tests, matching how battles already work.
- **`project.yml` is the only place to add resources** — `roster.json` and `moves.json` both go
  through it, then `xcodegen generate`. Never hand-edit `.xcodeproj`.

## Success Metrics

- Two Agumon raised over the same period with different step counts reach **different** Adults.
- A player who never opens the app past hatching lands on a junk evolution, every time.
- At least eight distinct condition metrics and eight distinct projectile symbols ship.
- Every one of the 1,022 roster entries is reachable in the Dex.
- A player can name what a branch wants from its hint alone, without a wiki.
- Training the same Digimon well versus badly differs by 3x in `strengthStat` gained.
- Full test suite green; build green on Series 11 (46mm).

## Open Questions

- **Should conditions be visible for a Digimon you have *not* yet owned?** Currently US-064
  withholds the candidate's identity but still shows hints. Showing the hint for an unmet Digimon
  may spoil less than showing its sprite — worth a look during US-066.
- **Does the `day` window mean "best single day" or "any qualifying day"?** US-058 specifies best
  single day; confirm that plays well with `atMost` conditions, where "best" inverts.
- **Should a junk evolution be escapable?** Real V-Pets let a Numemon still evolve onward. The
  shipped graph currently makes Adults terminal-ish; decide during US-061 whether junk Adults get
  their own (poor) Perfect edges.
- **Does the complication need a sick indicator too?** US-047 made the complication pose reflect
  live state; the bandage may belong there as well, but it is not in scope here.
- **AOD repaint rate is still unmeasured** (carried from US-048/US-049, needs real hardware). None
  of this PRD depends on it.
