# PRD: Adventure Maps, Multi-Digimon Party, Jogress, and Full Roster Wiring

## Introduction

Four bodies of work, deliberately in one PRD because they interlock:

1. **Adventure maps.** Sixteen map backgrounds already sit in `Resources/Assets.xcassets`
   (`01_grassland` … `16_iceland`) and nothing draws them. A map becomes the place you play:
   it accrues your steps, supplies your battle opponents, and holds the Digitama you can find.
2. **Owning several Digimon.** Today `GameStore.loadOrCreate` fetches `.first` — there is exactly
   one saved game. Maps hand out eggs, so there has to be somewhere to put them.
3. **Jogress.** Two owned Digimon fuse into one higher form, returning one of their two Digitama.
4. **Roster wiring.** 868 playable Digimon exist on disk; **88** are reachable through
   `Resources/evolutions.json`. **780 are orphans** — in the Dex, never obtainable. Maps that
   promise Digimon need Digimon to promise.

Plus one layout fix that unblocks the rest: the room light button currently sits *inside* the
sprite's play area and the Digimon walks under it.

## Current state (measured, not assumed)

| Fact | Value | Source |
|---|---|---|
| Roster entries total | 1025 | `roster.generated.json` |
| Playable (animated sheet) | 868 | `dexOnly == false` |
| Dex-only (idle frame only) | 157 | `dexOnly == true` |
| **Nodes in `evolutions.json`** | **88** | 6 lines: agumon, gabumon, palmon, patamon, piyomon, gazimon |
| **Playable orphans (no in-edge, no out-edge)** | **780** | see Appendix A |
| Digitama sprites | 57 | 6 wired, **51 orphaned** |
| Map background assets | 16 | `Resources/Assets.xcassets/NN_*.imageset` |
| Device evolution trees available locally | 11 | `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md` |

Orphan counts by stage: Digitama 51 · Baby I 38 · Baby II 42 · Child 109 · Adult 168 ·
Perfect 153 · Ultimate 203 · Armor-Hybrid 16.

## Goals

- Draw a chosen map behind the Digimon at 30–50% opacity, never brighter.
- Accrue real HealthKit steps to the selected map only; show `recorded / total` per map.
- Unlock maps in a fixed chain; mark a map finished when recorded ≥ total.
- Scale battle opponents to the selected map's pool and the player's progress within it.
- Let a player own many Digimon, one active and the rest frozen (no hunger, no ageing, no evolution).
- Award Digitama from maps by authored, hinted conditions — never silently at random.
- Never let a player hold two of the same Digitama, even after it has hatched.
- Fuse two owned Digimon into one via Jogress and return one parent's Digitama.
- Never let a player be stuck with nothing: an empty box after total wipeout grants Agu Digitama.
- Move the light button out of the play area into the toolbar.
- Wire every one of the 780 orphaned Digimon into the evolution graph.

---

## User Stories

Numbering continues from the existing `prd.json`, whose last story is US-113.

### Phase A — Screen layout

#### US-114: Move the light button to the top-left toolbar
**Description:** As a player, I want the light switch out of the room so it never covers my Digimon.

**Acceptance Criteria:**
- [ ] The light button is a `ToolbarItem(placement: .topBarLeading)`, mirroring the Dex book at
      `.topBarTrailing` (`ContentView.swift:275`).
- [ ] `LightButton` is removed from `LightLayer`; `LightLayer` now draws the scrim only.
- [ ] The scrim still covers the sprite slot and nothing beyond it (US-112 behaviour is unchanged).
- [ ] The toolbar light button is **never dimmed** by the scrim, like the Dex button.
- [ ] The button's icon still reflects and cycles `LightState` on tap; `model.cycleLight()` is the
      action.
- [ ] `LightButtonLayout.inset` is no longer applied to the sprite slot; the sprite's usable
      rect grows by that inset. Verified by screenshot comparison on 41mm and 46mm: the sprite's
      reachable area is wider than before and no button overlaps it at any walk position.
- [ ] Existing `LightSwitchView` / light tests still pass, updated for the new placement.
- [ ] Build green, tests green.

#### US-115: Draw the selected map behind the Digimon
**Description:** As a player, I want to see where my Digimon is adventuring.

**Acceptance Criteria:**
- [ ] A new `MapBackgroundView` draws the selected map's asset image behind the sprite slot only —
      not behind the energy bars, action row, or toolbar.
- [ ] Opacity is a named constant in the range 0.30–0.50 (default **0.35**), asserted by a test
      that fails if it leaves that band.
- [ ] The image is `.scaledToFill()` and clipped to the sprite slot; it never causes horizontal
      or vertical layout growth.
- [ ] Under `LightState` dim/off, the scrim covers the map background as well as the sprite —
      the background is inside the scrimmed region, not above it.
- [ ] The Digimon sprite remains legible over every one of the 16 backgrounds. Verified by
      screenshot on 46mm for at least the 3 brightest assets (`01_grassland`, `14_farmland`,
      `16_iceland`).
- [ ] With no map selected (fresh save), the background is absent and layout is unchanged.
- [ ] Build green, tests green.

### Phase B — The map system

#### US-116: Map catalog data file and model
**Description:** As a developer, I need maps as shipped data so tuning a map needs no code change.

**Acceptance Criteria:**
- [ ] New `Resources/maps.json`, bundled via the existing `Resources` folder in `project.yml`
      (no `project.yml` change should be needed — confirm the file is copied into the built app).
- [ ] New `Sources/MapCatalog.swift` with `AdventureMap` (`id`, `displayName`, `assetName`,
      `tier`, `totalSteps`, `unlockedBy`, `opponentPool: [String]`, `digitamaSlots: [DigitamaSlot]`)
      and `MapCatalog` loading it, in the same shape and with the same fatalError-on-bad-data
      contract as `Roster` / `EvolutionGraph`.
- [ ] All **16** maps present, exactly matching the asset names on disk (verified with `ls`), with
      the tiers and step totals in the FR-6 table.
- [ ] `unlockedBy` forms a single linear chain: map 1 has none, every other names its predecessor.
- [ ] Test: `MapCatalog.bundled` decodes and holds exactly 16 maps, and every `assetName` resolves
      to a non-nil image at runtime.
- [ ] Build green, tests green.

#### US-117: Map catalog validator
**Description:** As a developer, I need bad map data to fail loudly in a test rather than quietly at
runtime, the way `EvolutionGraphValidator` already does for the evolution graph.

**Acceptance Criteria:**
- [ ] New `Sources/MapCatalogValidator.swift`, in the same shape as `EvolutionGraphValidator` —
      returns findings, does not throw.
- [ ] Rejects: an `assetName` with no imageset; an `opponentPool` id absent from the roster; an
      `opponentPool` id marked `dexOnly` (no animated sheet, so it can never be an opponent); a
      `digitamaSlots` id that is not a `Stage.digitama` roster entry; an `unlockedBy` naming no
      map; any cycle in the unlock chain; a `DigitamaSlot` condition with a blank hint.
- [ ] A test runs the validator over the shipped `maps.json` and asserts **zero** findings.
- [ ] A test proves each rejection rule fires on a hand-built bad fixture.
- [ ] Build green, tests green.

#### US-118: Per-map step accrual
**Description:** As a player, I want the steps I walk to count toward the map I chose.

**Acceptance Criteria:**
- [ ] New persisted `MapProgress` (map id → recorded steps, finishedAt) on the player profile
      (US-123) or its own `@Model`, whichever US-123 lands first.
- [ ] Only steps read from HealthKit **while that map is selected** accrue to it. Steps banked
      while a different map was selected never move.
- [ ] Accrual reuses the existing step read path (`HealthMetricReader` / `MetricLedger`) and is
      credited from the same already-deduplicated deltas — walking 1000 steps credits the map
      1000, not 2000, even if two reads overlap. Proved by a test with a fixture reader.
- [ ] Switching maps mid-day does not retroactively move already-credited steps.
- [ ] A map whose recorded steps reach `totalSteps` is marked finished, once, with a timestamp.
      Passing the total again does not re-fire.
- [ ] Recorded steps are **not** capped at the total — the counter keeps climbing past a finish.
- [ ] Clock and reader are injected; no test waits real time.
- [ ] Build green, tests green.

#### US-119: Map list screen
**Description:** As a player, I want to see every map, my progress on it, and which are locked.

**Acceptance Criteria:**
- [ ] New `MapListView`, pushed onto the existing `NavigationStack`.
- [ ] One row per map in tier order, showing name, its background as a small thumbnail, and
      `recorded / total` rendered exactly as `1222 / 25000` (space-slash-space, no abbreviation).
- [ ] A finished map shows a distinct finished mark; the currently selected map shows a distinct
      selected mark; the two are visually different.
- [ ] A locked map shows a lock, hides its Digitama and opponent pool, and states its unlock
      condition in one line: "Finish <previous map name>".
- [ ] A locked map cannot be selected — tapping it does not change the selection.
- [ ] Verified by screenshot on 41mm and 46mm: no truncation of the `n / m` progress text at the
      largest realistic values (map 16 finished, 6 digits).
- [ ] Build green, tests green.

#### US-120: Map strip button on the main screen, and map switching
**Description:** As a player, I want to reach maps in one tap and see where I am without leaving
the main screen.

**Acceptance Criteria:**
- [ ] A single thin row sits directly above the energy bars holding two controls:
      a wide leading `NavigationLink` to `MapListView` labelled with the selected map's name and
      `recorded / total`, and a trailing icon button that opens the party screen (US-126).
- [ ] The row costs at most one line of height and does not shrink the sprite slot below what a
      41mm screen showed before this PRD (measured against a US-114 screenshot).
- [ ] Selecting a map from `MapListView` persists the selection, updates the background (US-115)
      and the strip, and pops back to the main screen.
- [ ] With no map selected, the strip shows the first map as a prompt to choose, and the game is
      fully playable — nothing is gated on having selected a map.
- [ ] Verified by screenshot on 41mm and 46mm: strip readable, nothing truncated, both controls
      tappable.
- [ ] Build green, tests green.

#### US-121: Map detail — opponents and Digitama slots with hints
**Description:** As a player, I want to know what lives in a map and what I must do to find its eggs.

**Acceptance Criteria:**
- [ ] Tapping a map row opens a detail view listing its opponent pool grouped by stage, and its
      Digitama slots.
- [ ] A Digitama the player has never owned draws as **"?"**, exactly as `DexCell` does for an
      undiscovered Digimon (`DexView.swift:191`) — a "?", not a silhouette.
- [ ] Each "?" slot lists its conditions using the SAME progressive reveal the Dex evolution
      hints use (`ConditionReveal.line(for:in:)`), so a far-off condition is vague and a nearly-met
      one is specific.
- [ ] A Digitama the player owns or has owned draws its real sprite and name, with no hint rows.
- [ ] A slot whose conditions are currently all met but which has not dropped yet is marked as
      ready.
- [ ] Verified by screenshot: a locked map's detail is unreachable, an unlocked map shows a mix of
      "?" and revealed slots.
- [ ] Build green, tests green.

#### US-122: Opponents come from the map, scaled by progress
**Description:** As a player, I want tougher opponents as I explore a map further.

**Acceptance Criteria:**
- [ ] `OpponentPicker` (`Battle.swift:191`) picks from the **selected map's** `opponentPool`
      rather than the whole roster.
- [ ] The stage band it picks from is chosen by progress ratio `p = recorded / total`, clamped to
      the map's own tier band: `p < 0.25` → the pool's lowest band; `< 0.50` → second; `< 0.75` →
      third; `>= 0.75` → the pool's highest band. A finished map (`p >= 1`) still picks from the
      highest band and never above it.
- [ ] The picker is seeded by an injected `RandomNumberGenerator`, as today, so the band is
      testable without flakiness.
- [ ] A map whose pool has no member in the computed band falls back to the nearest populated
      band rather than returning nil.
- [ ] With no map selected, behaviour is exactly today's roster-wide pick — no regression.
- [ ] Existing battle tests pass, plus new tests for each of the four bands and the fallback.
- [ ] Build green, tests green.

### Phase C — Owning several Digimon

#### US-123: PlayerProfile, and migrating the existing save
**Description:** As a developer, I need somewhere for map progress and lifetime energy to live that
is not tied to one Digimon. **This is the riskiest story in the wave** — a migration that loses a
live player's pet is not recoverable.

**Acceptance Criteria:**
- [ ] A new `@Model PlayerProfile` holds what is global rather than per-Digimon: carried
      `lifetimeEnergy`, selected map id, per-map recorded steps and `finishedAt`, and the set of
      Digitama ids ever owned.
- [ ] `PlayerProfile` is added to `GameStore.schema` — a `@Model` missing from it is silently never
      saved.
- [ ] `lifetimeEnergy` moves off `GameState` onto the profile; every read of it goes through the
      profile.
- [ ] `GameStore.loadOrCreateProfile()` is the only way in, like `loadOrCreate`.
- [ ] **Migration:** a store written by the CURRENT build opens with its `GameState` intact and its
      `lifetimeEnergy` copied onto a newly created `PlayerProfile` — stage, energy, care mistakes,
      poop, battle record, light state and sickness all survive.
- [ ] Proved by a test that writes a store in the **pre-migration** shape and reopens it through the
      new `GameStore`. A test that constructs the new shape directly does not satisfy this.
- [ ] `EnergyLedger` and `MetricLedger` stay single global records and are not touched.
- [ ] Build green, tests green.

#### US-124: The store can hold many Digimon, one of them active
**Description:** As a developer, I need more than one saved Digimon. `GameStore.loadOrCreate`
fetches `.first` today, so there is exactly one.

**Acceptance Criteria:**
- [ ] `GameState` gains `isActive: Bool` and the store may hold many records.
- [ ] `GameStore` gains `activeState()`, `allStates()` and `activate(_:)`; `savedState()` returns
      the **active** record.
- [ ] The US-123 migration sets `isActive = true` on the single existing record.
- [ ] `activate(_:)` freezes the previously active record and activates the new one in **one** saved
      transaction — a crash part-way can never leave zero active or two active.
- [ ] Invariant asserted directly by a test: at most one `GameState` has `isActive == true`, after a
      fresh start, after an activate, and after a failed activate.
- [ ] `resetGame` and `rebirth` still work, and still operate on the active record.
- [ ] Every existing caller of `savedState()` still compiles and still sees the Digimon it saw.
- [ ] Build green, tests green.

#### US-125: Frozen Digimon do not hunger, age, or evolve
**Description:** As a player, I want the Digimon I put away to be exactly as I left them.

**Acceptance Criteria:**
- [ ] An inactive `GameState` accrues no hunger, no care mistakes, no sickness, no ageing toward
      death, and is never evaluated for evolution.
- [ ] Freezing records `frozenSince`; activating adds the frozen span to a stored
      `frozenDuration` and shifts every time-derived reading by it, so a Digimon frozen for three
      days is exactly as hungry on thaw as it was on freeze. Proved by a test using the injected
      clock, advancing days between freeze and thaw.
- [ ] Poop does not accumulate while frozen.
- [ ] Background refresh (`BackgroundRefresh`) and the health observers process the **active**
      Digimon only.
- [ ] The complication snapshot publishes the active Digimon.
- [ ] Notifications are never sent about a frozen Digimon.
- [ ] Build green, tests green.

#### US-126: Party screen and activating a Digimon
**Description:** As a player, I want to choose which of my Digimon is out.

**Acceptance Criteria:**
- [ ] New `PartyView`, reachable from the strip's trailing button (US-120), listing every owned
      Digimon and every unhatched Digitama the player holds.
- [ ] Each row shows sprite, name, stage, and status (active / frozen / dead).
- [ ] Tapping a frozen Digimon activates it and freezes the previously active one, in one saved
      transaction — a crash mid-switch can never leave zero or two active.
- [ ] The active Digimon's row is marked and tapping it is a no-op.
- [ ] A dead Digimon is shown but cannot be activated.
- [ ] Tapping an unhatched Digitama activates it, which is what starts hatching it.
- [ ] Verified by screenshot on 41mm and 46mm with at least 4 owned entries, including one dead.
- [ ] Build green, tests green.

#### US-127: One of each Digitama, ever — until it dies
**Description:** As a player, I want each egg to mean something, so I cannot farm duplicates.

**Acceptance Criteria:**
- [ ] `PlayerProfile` tracks every Digitama id currently *held*, where held means: an unhatched
      egg in the box, **or** any living Digimon that hatched from it.
- [ ] A held Digitama id is never offered as a map drop.
- [ ] When a Digimon dies, its origin Digitama id stops being held and becomes droppable again.
- [ ] Every `GameState` records the `originDigitamaId` it hatched from and carries it through
      every evolution, so the rule survives a Digimon evolving six times. Migration (US-123) sets
      it for the existing save from its starting id.
- [ ] Tests cover: drop → hatch → evolve → still blocked; drop → death → droppable again.
- [ ] Build green, tests green.

#### US-128: Digitama drops from maps
**Description:** As a player, I want to find new eggs by meeting a map's stated conditions.

**Acceptance Criteria:**
- [ ] A `DigitamaSlot` carries `digitamaId` plus a `[EvolutionCondition]` list, reusing the
      existing `ConditionMetric` vocabulary — including the health category metrics the user
      asked for (`health.handwashing`, `health.toothbrushing`, `health.mindfulMinutes`) and the
      care counters (`care.trainingSessions`, `care.battleCount`, `care.battleWinRatio`).
- [ ] Each condition has a non-empty `hint`, enforced by the US-116 validator.
- [ ] A drop is checked after a train, after a battle, and after a step accrual tick — not on a
      timer.
- [ ] On a check, the engine computes the set of slots in the **selected** map whose conditions
      are ALL met and whose Digitama is not held (US-127), and awards **one at random** from that
      set using an injected generator. An empty set awards nothing.
- [ ] At most one Digitama is awarded per check.
- [ ] A drop is announced to the player and records the Digitama in the Dex, like any discovery.
- [ ] A condition gated on a metric that is empty on real hardware is never the ONLY condition on
      a slot — same rule `EvolutionCondition` already states for edges, enforced by the validator.
- [ ] Tests: conditions unmet → nothing; one eligible → that one; three eligible → one of the
      three, deterministic under a seeded generator; all held → nothing.
- [ ] Build green, tests green.

#### US-129: Never stranded — the Agumon failsafe
**Description:** As a player who lost everything, I want to be able to start again immediately.

**Acceptance Criteria:**
- [ ] When every owned Digimon is dead AND the box holds no unhatched Digitama, the player is
      granted `agu_digitama` immediately, without any condition or map requirement.
- [ ] The grant fires even if `agu_digitama` was previously held by a Digimon that has since died.
- [ ] The grant is idempotent: it fires once per wipeout, not once per app launch while wiped out.
- [ ] The check runs on launch, after a death, and after a Jogress — the three ways the box can
      empty.
- [ ] `lifetimeEnergy` on `PlayerProfile` survives the failsafe, as it does across a rebirth today.
- [ ] Tests cover the wipeout path and the idempotence.
- [ ] Build green, tests green.

### Phase D — Jogress

#### US-130: Jogress data file, model, and validator
**Description:** As a developer, I need Jogress recipes as shipped data.

**Acceptance Criteria:**
- [ ] New `Resources/jogress.json` and `Sources/JogressCatalog.swift` with
      `JogressRecipe(parentA, parentB, result, conditions: [EvolutionCondition])`.
- [ ] Recipes are **unordered** in the parents: A+B and B+A resolve to the same recipe, and the
      validator rejects a file that lists both.
- [ ] Validator rejects: a parent or result absent from the roster, a parent or result marked
      `dexOnly`, `parentA == parentB`, a result at a lower `Stage.ladderIndex` than either parent,
      and a duplicate parent pair.
- [ ] A test runs the validator over the shipped file and asserts zero findings.
- [ ] Build green, tests green.

#### US-131: Author the Jogress recipes
**Description:** As a player, I want the real Jogress fusions from the Color devices.

**Acceptance Criteria:**
- [ ] Every recipe is sourced from `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`
      or a named external reference, and **every** participant is verified present and non-`dexOnly`
      with `ls` before being written.
- [ ] The four Jogress pairs the local document states verbatim are present:
      BlitzGreymon + CresGarurumon → Omegamon Alter-S; Darkdramon + BanchoLeomon → Chaosmon;
      Mugendramon + Darkdramon → Chaosdramon; WarGreymon + MetalGarurumon → Omegamon.
- [ ] Additional Pendulum Color recipes are added only where the pairing can be confirmed;
      **an unconfirmed pairing is left out and named in `notes`, not guessed.** Note for the
      implementer: a `WebFetch` of `https://humulos.com/digimon/penc` during PRD research returned
      self-referential nonsense (e.g. "Cthyllamon + Houou = Cthyllamon"). Do not trust a summarised
      fetch of that page — read the underlying data or use a second source.
- [ ] Known-unusable: **Stingmon is `dexOnly`**, so XV-mon + Stingmon → Paildramon cannot ship.
      Any recipe blocked this way is listed in `notes`.
- [ ] Every result already exists as a playable sprite — verified: Omegamon, Omegamon Alter-S,
      Chaosmon, Chaosdramon, Mastemon, GranKuwagamon, Fenriloogamon, Hydramon, Cernumon,
      Brigadramon, Aegisdramon, Mitamamon, Cthyllamon, VoltoBautamon, Diarbbitmon, Amphimon.
- [ ] The US-130 validator passes over the authored file.
- [ ] Build green, tests green.

#### US-132: Perform a Jogress
**Description:** As a player, I want to fuse two of my Digimon into something stronger.

**Acceptance Criteria:**
- [ ] A Jogress entry point in `PartyView` offers only pairs the player **actually owns**, both
      alive, that match a recipe and whose conditions are all met.
- [ ] When no such pair exists, the entry point states why in one line rather than being absent.
- [ ] Performing a Jogress: removes both parents from the box, creates the result as a new owned
      Digimon, and makes it the active one.
- [ ] Both parents' origin Digitama ids stop being held (US-127), and **one of the two, chosen at
      random with an injected generator, is granted back to the box immediately** as an unhatched
      Digitama.
- [ ] The result is recorded in the Dex.
- [ ] The whole thing is one saved transaction — a failure part-way leaves the box exactly as it
      was, with both parents intact.
- [ ] The Jogress plays the existing evolution ceremony (`EvolutionCeremonyView`) rather than a
      new animation.
- [ ] The US-129 failsafe check runs afterwards.
- [ ] Tests cover: eligible pair fuses; the returned egg is one of the two parents' and is seeded
      deterministically; an ineligible pair is refused; a failure rolls back.
- [ ] Verified by screenshot: the Jogress entry point and the ceremony.
- [ ] Build green, tests green.

### Phase E — Wiring the 780 orphans

Rules that apply to **every** story in this phase:

- Source the tree from `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md` first.
  Where it is silent, use a named external reference and record which one in `notes`.
- `ls` every sprite before naming it. **Never invent a name or a path.**
- Never place a `dexOnly` Digimon on an edge.
- Every new node needs a `line`, or `EvolutionGraph.bundled` fails to decode and traps at launch.
- Every edge needs at least one condition with a non-empty `hint`.
- `EvolutionGraphValidator` must report zero findings over the whole file before the story passes.
- Each story states in `notes` how many orphans it removed, so the count is auditable.

#### US-133 … US-143: One story per device version (11 stories)

| Story | Tree | Section in the local md |
|---|---|---|
| US-133 | Digital Monster Color Version 1 | line 9 |
| US-134 | Digital Monster Color Version 2 | line 26 |
| US-135 | Digital Monster Color Version 3 | line 43 |
| US-136 | Digital Monster Color Version 4 | line 58 |
| US-137 | Digital Monster Color Version 5 | line 75 |
| US-138 | Pendulum Color V1 Nature Spirits | line 96 |
| US-139 | Pendulum Color V2 Deep Savers | line 110 |
| US-140 | Pendulum Color V3 Nightmare Soldiers | line 124 |
| US-141 | Pendulum Color V4 Wind Guardians | line 138 |
| US-142 | Pendulum Color V5 Metal Empire | line 152 |
| US-143 | Pendulum Color V0 Virus Busters / ZERO | line 166 |

**Acceptance Criteria (each):**
- [ ] Every Digimon named in that tree section that exists as a playable sprite is a node in
      `evolutions.json`, on the correct `Stage`, in a `line` named for that device version.
- [ ] Every arrow in that section is an edge with conditions and hints.
- [ ] Any name in the section with **no** playable sprite is listed in `notes` with the name it
      was searched for — an absent sprite is a finding, not a silent skip.
- [ ] The tree is reachable from a Digitama, so the whole line is playable end to end.
- [ ] `EvolutionGraphValidator` reports zero findings over the whole file.
- [ ] The orphan count drops by the number claimed in `notes`, verified by re-running the count.
- [ ] Build green, tests green.

#### US-144 … US-169: Orphan sweeps (26 stories)

Run **after** the device trees, over whatever orphans they left behind. A stage is not one story:
168 orphaned Adults is not one iteration's work, so the big stages are cut into alphabetical ranges
by `displayName`. Ranges are deterministic, so a story's scope is checkable rather than a judgement
call, and the counts below are the *current* orphan counts — the device trees will have reduced
them.

| Story | Scope | Orphans today |
|---|---|---|
| US-144 | Digitama, A–K | ~27 |
| US-145 | Digitama, L–Z | ~24 |
| US-146 | Baby I, all | 38 |
| US-147 | Baby II, all | 42 |
| US-148 | Child, A–F | ~28 |
| US-149 | Child, G–L | ~39 |
| US-150 | Child, M–Z | ~42 |
| US-151 | Adult, A–D | ~34 |
| US-152 | Adult, E–G | ~27 |
| US-153 | Adult, H–L | ~25 |
| US-154 | Adult, M–R | ~33 |
| US-155 | Adult, S–T | ~30 |
| US-156 | Adult, U–Z | ~19 |
| US-157 | Perfect, A–C | ~32 |
| US-158 | Perfect, D–G | ~21 |
| US-159 | Perfect, H–L | ~18 |
| US-160 | Perfect, M | ~31 |
| US-161 | Perfect, N–R | ~25 |
| US-162 | Perfect, S–Z | ~26 |
| US-163 | Ultimate, A–B | ~40 |
| US-164 | Ultimate, C–D | ~36 |
| US-165 | Ultimate, E–H | ~25 |
| US-166 | Ultimate, I–M | ~33 |
| US-167 | Ultimate, N–R | ~36 |
| US-168 | Ultimate, S–Z | ~33 |
| US-169 | Armor-Hybrid, all | 16 |

**Acceptance Criteria (each):**
- [ ] Every remaining playable orphan in that range has at least one in-edge (something evolves
      into it) and, unless it is a terminal Ultimate, at least one out-edge.
- [ ] Lines are grouped coherently — a sweep must not produce dozens of one-node lines. Related
      variants (X-Antibody, Black, 2006, Virus) hang off their base form's line.
- [ ] Every edge has at least one condition with a non-empty hint; no edge is unconditional.
- [ ] `ls` every sprite before naming it; no `dexOnly` Digimon appears on any edge.
- [ ] Every new node has a `line`, or `EvolutionGraph.bundled` traps at launch.
- [ ] `EvolutionGraphValidator` reports **zero** findings over the whole of `evolutions.json`.
- [ ] `notes` records the orphan count for that stage **before and after**, counted with the script
      in Appendix B.
- [ ] Build green, tests green.

---

## Functional Requirements

**Layout**
- FR-1: The light button moves to `.topBarLeading` in the toolbar and is never dimmed.
- FR-2: The sprite's play area reclaims the space the light button occupied.
- FR-3: The selected map's asset draws behind the sprite slot at 0.30–0.50 opacity (default 0.35),
  inside the light scrim.

**Maps**
- FR-4: 16 maps ship in `Resources/maps.json`, one per `NN_*` imageset.
- FR-5: Maps unlock in a linear chain; map 1 is unlocked from the start; a map unlocks when its
  predecessor is finished.
- FR-6: Map tiers, order and step totals are:

  | # | Map | Tier | Stage band of opponents | Total steps |
  |---|---|---|---|---|
  | 1 | 01_grassland | 1 | Baby II – Child | 3,000 |
  | 2 | 14_farmland | 1 | Baby II – Child | 5,000 |
  | 3 | 02_river | 2 | Child – Adult | 8,000 |
  | 4 | 08_jungle | 2 | Child – Adult | 10,000 |
  | 5 | 09_lake | 2 | Child – Adult | 12,000 |
  | 6 | 04_desert | 3 | Adult – Perfect | 16,000 |
  | 7 | 07_mountains | 3 | Adult – Perfect | 18,000 |
  | 8 | 16_iceland | 3 | Adult – Perfect | 20,000 |
  | 9 | 03_ocean | 3 | Adult – Perfect | 22,000 |
  | 10 | 05_wasteland | 4 | Perfect – Ultimate | 26,000 |
  | 11 | 06_industrial | 4 | Perfect – Ultimate | 28,000 |
  | 12 | 13_factory_town | 4 | Perfect – Ultimate | 30,000 |
  | 13 | 10_city_dusk | 4 | Perfect – Ultimate | 32,000 |
  | 14 | 15_dungeon | 5 | Ultimate | 38,000 |
  | 15 | 11_city_night | 5 | Ultimate | 42,000 |
  | 16 | 12_cyberpunk | 5 | Ultimate | 50,000 |

- FR-7: Only HealthKit steps earned while a map is selected accrue to that map.
- FR-8: A map is finished when recorded ≥ total; the counter keeps climbing past the total.
- FR-9: Progress renders as `recorded / total`, e.g. `1222 / 25000`.
- FR-10: Opponents are drawn from the selected map's pool, banded by `recorded / total`
  (<0.25 / <0.50 / <0.75 / ≥0.75), clamped to the map's tier band.
- FR-11: Each map lists its Digitama; unowned ones draw as "?" with progressive condition hints.

**Digitama distribution**
- FR-12: All 57 Digitama sprites are distributed across the 16 maps, each appearing in exactly one
  map, thematically. Suggested assignment (the implementing story may adjust, but must place all 57
  and must not place one twice):

  | Map | Digitama |
  |---|---|
  | 01_grassland | Agu, Pata, Pal |
  | 14_farmland | Piyo, Flora, Mush, Worm, Heriss |
  | 02_river | Goma, Kame, Beta |
  | 08_jungle | Lala, Tento, Kune, Morpho |
  | 09_lake | Swim, Kuda, Bluco |
  | 04_desert | Zuba, Sunariza, Commandra |
  | 07_mountains | Gabu, Lioll, Bear, Gao |
  | 16_iceland | Hyoko, Angora, Espi |
  | 03_ocean | Vorvo, Kuda2006, Baku |
  | 05_wasteland | Gazi, GabuBlack, BlackGuil |
  | 06_industrial | Elec, Pulse, Funbee |
  | 13_factory_town | PawnChessWhite, PawnChessBlack, Koe |
  | 10_city_dusk | Plot, Rena, Terrier, Lop |
  | 15_dungeon | Ghost, PicoDevi, Imp, Kera, Cand |
  | 11_city_night | Guil, Monodra, Phasco |
  | 12_cyberpunk | V, Luce, Ludo, Meicoo, Agu2006 |

- FR-13: A Digitama slot's conditions use the existing `ConditionMetric` vocabulary. Higher-tier
  maps carry harder conditions. Examples of the intended shape:
  - `01_grassland` / Agu: `care.trainingSessions atLeast 1` — "Train once".
  - `06_industrial` / Pulse: `health.handwashing atLeast 5` (window `day`) — "Wash your hands 5 times today".
  - `15_dungeon` / Ghost: `care.battleCount atLeast 20` + `care.battleWinRatio atLeast 0.6`.
- FR-14: A drop check runs after a train, a battle, and a step accrual tick; it awards at most one
  Digitama, chosen at random from the currently-eligible, not-held set.

**Party**
- FR-15: The player may own any number of Digimon; exactly one is active.
- FR-16: A frozen Digimon accrues no hunger, care mistakes, sickness, ageing, poop, or evolution.
- FR-17: A Digitama id is *held* while an unhatched egg or any living descendant of it exists; a
  held id never drops.
- FR-18: A Digimon's death releases its origin Digitama id.
- FR-19: A wipeout (all dead, no eggs) grants `agu_digitama` immediately, once.
- FR-20: The existing single save migrates into the active slot with nothing lost.

**Jogress**
- FR-21: `Resources/jogress.json` holds unordered parent pairs → result, with conditions.
- FR-22: A Jogress consumes both parents, creates and activates the result, and grants back one of
  the two parents' Digitama at random.
- FR-23: Both parents must be owned and alive; `dexOnly` Digimon are never parents or results.

**Roster**
- FR-24: All 780 orphaned playable Digimon gain evolution edges (Phase E).
- FR-25: `EvolutionGraphValidator` reports zero findings after every Phase E story.
- FR-26: No sprite path or Digimon name is ever written without an `ls` confirming it.

---

## Non-Goals

- The watch app never loads a web page. `humulos.com` is a research source for the *author*, not a
  runtime dependency.
- The 157 `dexOnly` Digimon stay Dex-only. They are never playable, never opponents, never on an
  edge, never a Jogress parent, never a map drop.
- No trading, no multiplayer, no cloud sync.
- No new map art. The 16 shipped assets are the complete set.
- No per-map weather, time of day, or events beyond opponent banding and Digitama drops.
- No releasing or deleting a Digimon by hand — the box only shrinks through death and Jogress.
- No animated map transitions.
- Jogress does not chain: a Jogress result cannot immediately be a parent in the same session
  unless a recipe genuinely names it.

---

## Design Considerations

- **The map background must stay quiet.** 0.35 opacity is the default for a reason: the Digimon is
  16×16 pixels drawn with `.interpolation(.none)` and a busy background at 0.6 makes it
  unreadable. Any change to that constant needs a screenshot against `01_grassland` and
  `16_iceland`, the two brightest assets.
- **Reuse, do not reinvent, the reveal system.** Map Digitama hints must go through
  `ConditionReveal` and `ConditionHints` so a map hint and an evolution hint read identically. The
  user asked for exactly this ("like the digimon detail view's evolution hint").
- **"?" not silhouette**, matching `DexCell`'s existing reasoning at `DexView.swift:191`.
- **Toolbar has two slots.** Light takes leading, Dex keeps trailing. Map and Party therefore go on
  the strip above the energy bars, not in the toolbar, and not as two more circles in
  `ActionControls` — a sixth and seventh circle does not fit 41mm.
- **Screen budget.** The strip costs one row. US-114 gives one back by freeing the light inset.
  Any story that makes the sprite slot smaller than it was at US-114 has regressed and fails.

## Technical Considerations

- `GameStore.schema` must list `PlayerProfile`; a `@Model` missing from it is silently never saved.
- Migration is the risk in this PRD. US-123 must be written so that opening a store written by the
  *current* build produces a playable active Digimon, and there must be a test that does exactly
  that rather than one that constructs the new shape directly.
- Freezing is implemented as a clock offset, not as a paused timer — every hunger, sickness and
  ageing reading in `GameState` is derived from stored `Date`s, so the offset is the only approach
  that does not require touching each of them.
- HealthKit is empty in the Simulator. Map step accrual, drop conditions and opponent banding are
  all tested against injected fixture samples, never live queries (CLAUDE.md).
- `maps.json` and `jogress.json` ride along in the existing `Resources` folder reference; confirm
  they land in the built bundle rather than assuming it.
- `roster.generated.json` is regenerated by `python3 scripts/build_roster.py`; Phase E edits
  `Resources/evolutions.json` by hand, never the generated roster.
- Phase E is 37 stories of data authoring (11 device trees + 26 sweeps). Expect several Ralph iterations per device version;
  a partial tree with an honest `notes` is the correct outcome when one does not fit.

## Success Metrics

- Orphan count falls from **780 → 0**, measurable by re-running the count in Appendix B.
- All 57 Digitama are obtainable; all 16 maps are reachable through the unlock chain.
- A player can hold ≥ 5 Digimon simultaneously with exactly one active.
- A Digimon frozen for 7 simulated days thaws with unchanged hunger and age.
- No screenshot on 41mm shows the Digimon overlapped by any button at any walk position.
- `EvolutionGraphValidator`, `MapCatalogValidator` and the Jogress validator all report zero
  findings on the shipped data.

## Open Questions

1. Should a finished map keep accruing steps toward nothing, or should selecting a finished map
   warn the player they are no longer progressing? (Currently specced: it keeps counting silently.)
2. Should frozen Digimon still count toward the Dex's "raised" statistics? (Assumed yes.)
3. Should a Jogress require both parents to be at Ultimate, or does the recipe alone decide?
   (Currently specced: the recipe alone, with the validator only enforcing that the result is not
   *below* either parent.)
4. When the box is empty and US-129 grants Agu Digitama, should map progress reset? (Assumed no —
   map progress lives on `PlayerProfile` and outlives every Digimon, like `lifetimeEnergy`.)

---

## Appendix A — The 780 unimplemented Digimon

Every playable Digimon with no in-edge and no out-edge in `Resources/evolutions.json`, as of this
PRD. Regenerate with the script in Appendix B.

### Digitama (51)
Agu2006, Angora, Baku, Bear, Beta, BlackGuil, Bluco, Cand, Commandra, Elec, Espi, Flora, Funbee,
GabuBlack, Gao, Ghost, Goma, Guil, Heriss, Hyoko, Imp, Kame, Kera, Koe, Kuda, Kuda2006, Kune, Lala,
Lioll, Lop, Luce, Ludo, Meicoo, Monodra, Morpho, Mush, PawnChessBlack, PawnChessWhite, Phasco,
PicoDevi, Plot, Pulse, Rena, Sunariza, Swim, Tento, Terrier, V, Vorvo, Worm, Zuba
*(each suffixed `_Digitama` on disk)*

### Baby I (38)
Algomon, Bombmon, Bommon, Bubbmon, Chibickmon, Chicomon, Choromon, Cocomon, Cotsucomon, Curimon,
Dodomon, Dokimon, Fufumon, Fukamon, Jyarimon, Ketomon, Kiimon, Kuramon, Leafmon, Mokumon, Nyokimon,
Pafumon, Paomon, Petitmon, Pipimon, Pitchmon, Popomon, Pupumon, Pururumon, Pusumon, Puyomon,
Pyonmon, Relemon, Sunamon, Tomorimon, Tsubumon, YukimiBotamon, Zerimon

### Baby II (42)
Algomon, Arkadimon, Babydmon, Bibimon, Budmon, Caprimon, Chibimon, Chicchimon, Chocomon, Cupimon,
Dorimon, Gigimon, Goromon, Gummymon, Hiyarimon, Kakkinmon, Kozenimon, Kyokyomon, MeicooBaby,
Minomon, Mochimon, Mococomon, Monimon, Moonmon, Nyaromon, Onibimon, PetiMeramon, Pickmon, Pokomon,
Poromon, Pukamon, Puroromon, Pusurimon, Pyocomon, Sunmon, Tokomon X, TorikaraBallmon, Tsumemon,
Upamon, Wanyamon, Xiaomon, Yaamon

### Child (109)
Agumon 2006, Agumon Black, Agumon Black X, Agumon X, Algomon, Alraumon, Angoramon, Arkadimon,
Armadimon, Bakumon, Bearmon, BlackGuilmon, Blucomon, Candmon, ClearAgumon, Commandramon, Coronamon,
DORUmon, Dokunemon, Dracomon, Dracomon X, Dracumon, Ekakimon, Elecmon, Elecmon Violet, Floramon,
Fujamon, Funbeemon, Gabumon Black, Gabumon X, Gammamon, Ganimon, Gaomon, Gaossmon, Gasamon,
Gazimon X, Ghostmon, Gomamon, Gomamon X, Gotsumon, Guilmon, Guilmon X, Gumdramon, Hackmon,
Hagurumon, Hanimon, Herissmon, Impmon, Impmon X, Jazamon, Jellymon, Junkmon, Kakamon, Keramon,
Keramon X, Koemon, Kokabuterimon, Kokuwamon, Kokuwamon X, Kunemon, Labramon, Lalamon, Lopmon,
Lopmon X, Lucemon, Ludomon, Lunamon, MeicooChild, Monodramon, Morphomon, Mushmon, Otamamon,
Otamamon Red, Otamamon Red Ver2, Otamamon X, Palmon X, Penmon, PetitMamon, Phascomon, PicoDevimon,
Plotmon, Plotmon X, Pteromon, Pulsemon, Renamon, Renamon X, Ryudamon, Sangomon, Shakomon,
Shakomon X, Shoutmon, Sistermon Blanc, Solarmon, Starmon 2010, Sunarizamon, Swimmon, Takinmon,
Tentomon, Terriermon, Terriermon X, Tinkermon, ToyAgumon, ToyAgumon Black, V-mon, Vorvomon,
Wankomon, Wormmon, YukiAgumon, Zenimon

### Adult (168)
Airdramon, Akatorimon, Algomon, Allomon X, Angemon, Arresterdramon, Baboongamon, BetelGammamon,
Birdramon, BlackGalgomon, BlackGaogamon, BlackGrowmon, BlackTailmon, Burgermon Mama,
Burgermon Papa, Chamblemon, Clockmon, Cockatrimon, Coredramon Blue, Coredramon Green, DORUgamon,
Damemon, DarkLizamon, DarkTyranomon X, Death-X-DORUgamon, Deckerdramon, Devimon, Diginorimon,
Dinohumon, Dobermon, Dogmon, Dokugumon, Dorulumon, Drimogemon, Ebidramon, Filmon, Firamon,
FlareLizamon, Fugamon, Galemon, Galgomon, Gaogamon, Garurumon Black, Gawappamon, Gekomon,
GeoGreymon, Gesomon, Ginkakumon, Ginryumon, Gokimon, Greymon 2010, Greymon Blue, Greymon X,
Growmon, Growmon Orange, Growmon X, Gryzmon, Guardromon, Guardromon Gold, GulusGammamon,
Gururumon, Hakubamon, Hanumon, Hi-Commandramon, Hookmon, Hyougamon, IceDevimon, Icemon, Igamon,
Ikkakumon, Jazardmon, JungleMojyamon, Kabuterimon, KausGammamon, Kinkakumon, Kiwimon, Kokeshimon,
Kougamon, Kuwagamon X, Kyubimon, Kyubimon Silver, Lavorvomon, Lekismon, Leomon X, Lianpumon,
Loogarmon, MadLeomon, Manekimon, Mantaraymon X, Mechanorimon, Meicoomon, Meramon X, Mikemon,
Mimicmon, Minotaurmon, Monochromon X, MoriShellmon, Musyamon, Nefertimon X, NiseDrimogemon,
Numemon X, Octmon, Ogremon X, Omekamon, Paledramon, Parasaurmon, Peckmon, Pegasmon X, Pidmon,
PlatinumScumon, Porcupamon, Pteranomon X, Raptordramon, RedV-dramon, RedVegimon, Reppamon,
Revolmon, Rhinomon X, Rukamon, Saberdramon, SandYanmamon, Sangloupmon, Seadramon, Seadramon X,
Shellmon, ShimaUnimon, Shoutmon King, Siesamon, Siesamon X, Sorcerymon, Soulmon, Starmon,
Sunflowmon, SymbareAngoramon, Tailmon, Tailmon X, Tankmon, Targetmon, Tenkomon, TeslaJellymon,
Thunderballmon, TiaLudomon, Tobiumon, Tobucatmon, Togemon X, Tortamon, Troopmon, Tsuchidarumon,
Turuiemon, Tylomon X, Tyrannomon, Tyrannomon X, V-dramon, V-dramon Black, Vegimon, Waspmon,
WezenGammamon, Witchmon, Wizarmon, Wizarmon X, Woodmon, XV-mon, XV-mon Black, Xiquemon, Yanmamon,
Youkomon, Yukidarumon, Zassoumon

### Perfect (153)
AeroV-dramon, Andiramon Data, Andiramon Virus, Angewomon, Angewomon X, Anomalocarimon,
Anomalocarimon X, Archnemon, Astamon, Asuramon, AtlurKabuterimon Blue, AtlurKabuterimon Red,
Baalmon, BigMamemon, BlackMachGaogamon, BlackMegaloGrowmon, BlackRapidmon, Blossomon, BlueMeramon,
Boutmon, Cannonbeemon, Canoweissmon, Cargodramon, CatchMamemon, Caturamon, Cerberumon X,
Chimairamon, ChoHakkaimon, Crescemon, CrysPaledramon, Cyberdramon, Cyberdramon X, DORUguremon,
Dagomon, DarkKnightmon, DarkSuperstarmon, Darumamon, DeathMeramon, Delumon, Duramon, Entmon,
Ex-Tyranomon, Fantomon, Flaremon, Garudamon, Garudamon X, Gigadramon, Gogmamon, Gokuwmon,
Grademon, GrandGalemon, Grappleomon, Gusokumon, Hangyomon, Hisyaryumon, HolyAngemon, Huankunmon,
Insekimon, Jazarichmon, Jyureimon, Karakurumon, Karatenmon, Knightmon, LadyDevimon, LadyDevimon X,
Lamortmon, Lavogaritamon, Lilamon, Lilimon X, Locomon, Lucemon Falldown, MachGaogamon, Mamemon,
Mamemon X, Mametyramon, Mammon, Mammon X, Manticoremon, MarinBullmon, MarinChimairamon,
MarinDevimon, MegaSeadramon, MegaSeadramon X, MegaloGrowmon, MegaloGrowmon Orange, MegaloGrowmon X,
Meicrackmon, Meicrackmon Vicious, Mephismon, Mephismon X, Mermaimon, MetalGreymon Virus,
MetalGreymon Virus X, MetalGreymon X, MetalMamemon, MetalMamemon X, MetalPhantomon,
MetalTyranomon V2, MetalTyranomon X, Monzaemon, Monzaemon X, Mummymon, NeoDevimon, Oboromon,
Okuwamon, Okuwamon X, OmegaShoutmon, OmegaShoutmon X, Orochimon, Paildramon, Pandamon, Panjyamon,
Panjyamon X, Phantomon, Piranimon, Pumpmon, RaijiLudomon, Rapidmon, Rebellimon, Regulusmon,
RizeGreymon, RizeGreymon X, Sagomon, Sanzomon, SaviorHackmon, Scorpiomon, Sekkamon, Shawujinmon,
Shishimamon, Shootmon, Sirenmon, SkullBaluchimon, SkullGreymon, Soloogarmon, Stiffilmon,
Superstarmon, Tekkamon, Thetismon, TonosamaGekomon, Triceramon, Triceramon X, Vamdemon, Vamdemon X,
Vermillimon, WaruMonzaemon, WaruSeadramon, WereGarurumon Black, WereGarurumon X, Whamon,
Xingtianmon, Yatagaramon, Yatagaramon 2006, Zudomon

### Ultimate–Super Ultimate (203)
Aegisdramon, Agumon YnK, Algomon, Alphamon, Alphamon Ouryuken, Amaterasumon, Amphimon,
AncientBeatmon, AncientMegatheriumon, AncientMermaimon, AncientSphinxmon, AncientVolcamon,
Anubimon, Apocalymon, Apollomon, Arcturusmon, Ariemon, Armagemon, Armamon, Bagramon, BanchoLilimon,
BanchoMamemon, Barbamon, Barbamon X, BeelStarmon X, Beelzebumon, Beelzebumon Blast, Beelzebumon X,
BelialVamdemon, Belphemon Rage, Belphemon X, BlackSaintGalgomon, BlackSeraphimon, BlackWarGreymon,
BlackWarGreymon X, Blastmon, BlitzGreymon, Breakdramon, Brigadramon, Bryweludramon, Callismon,
Cernumon, ChaosDukemon, ChaosDukemon Core, Chaosdramon, Chaosdramon V2, Chaosdramon X, Chaosmon,
Cherubimon Vice, Cherubimon Vice X, Cherubimon Virtue, Cherubimon Virtue X, Craniummon,
Craniummon X, CresGarurumon, Cthyllamon, DORUgoramon, DarkKnightmon X, DarknessBagramon, Deathmon,
Deathmon Black, Demon, Demon X, Diablomon, Diablomon X, Dianamon, Diarbbitmon, Dijiangmon,
Dinorexmon, Dinotigermon, Dominimon, Duftmon, Duftmon X, Dukemon, Dukemon X, Dynasmon X, Ebemon X,
ElDoradimon, Enmamon, Erlangmon, Examon X, Fenriloogamon, Gankoomon X, GigaSeadramon, Goddramon X,
GraceNovamon, GranKuwagamon, GrandDracumon, GrandLocomon, GrandisKuwagamon, Griffomon, Gundramon,
HerakleKabuterimon, Hexeblaumon, Hi-Andromon, HolyDigitamamon, Holydramon, Holydramon X, Hououmon,
Hououmon X, Hydramon, Imperialdramon Fighter, Imperialdramon Fighter Black, Imperialdramon Paladin,
Jesmon, Jesmon GX, Jesmon X, Jougamon, JumboGamemon, Justimon X, Kaguyamon, Kazuchimon, Kuzuhamon,
Leviamon, Leviamon X, Lilithmon, Lilithmon X, LordKnightmon X, Lotusmon, Lucemon Satan, Lucemon X,
Magnamon X, MarinAngemon, Mastemon, Megidramon, Megidramon X, MetalGarurumon Black,
MetalGarurumon X, MetalPiranimon, MetalSeadramon, Metallicdramon, Millenniumon, Minervamon X,
Mitamamon, Nezhamon, NoblePumpmon, Ogudomon, Ogudomon X, Omegamon, Omegamon Alter-S, Omegamon X,
Omegamon Zwart, Ophanimon, Ophanimon Core, Ophanimon Falldown X, Ophanimon X, Ordinemon, Ouryumon,
Piemon, Pinochimon, Plesiomon, Plesiomon X, PrinceMamemon, PrinceMamemon X, Pukumon, Quantumon,
Rafflesimon, RagnaLordmon, Ragnamon, Raguelmon, Rapidmon X, Rasenmon, Rasenmon Fury, Rasielmon,
Ravmon, Regalecusmon, Rosemon Burst, Rosemon X, RustTyrannomon, Ryugumon, SaberLeomon,
SaintGalgomon, Sakuyamon, Sakuyamon X, SeitenGokuwmon, Seraphimon, Shagaramon, Shakamon, Siriusmon,
SkullMammon, SkullMammon X, SlashAngemon, Sleipmon X, Susanoomon, Takutoumon, Tengumon,
TigerVespamon, Titamon, Tlalocmon, UlforceV-dramon, UlforceV-dramon X, UltimateBrachimon,
Valdurmon, VenomVamdemon, Vikemon, Volcanicdramon, VoltoBautamon, WarGreymon X, Xiangpengmon,
Yukinamon, Zanbamon, ZekeGreymon, Zephagamon

### Armor-Hybrid (16)
All 16 entries in `16x16 Digimon Sprites/Armor-Hybrid/` are orphaned. No Armor or Hybrid evolution
exists in the graph at all.

---

## Appendix B — Regenerating the orphan count

```python
import json, collections
r = json.load(open('roster.generated.json'))['nodes']
inc = collections.Counter()
for n in r:
    for e in n.get('evolutions', []):
        inc[e['to']] += 1
conn = {n['id'] for n in r if n.get('evolutions')} | set(inc)
orph = [n for n in r if not n.get('dexOnly') and n['id'] not in conn]
print(len(orph), collections.Counter(n['stage'] for n in orph))
```

`roster.generated.json` is produced by `python3 scripts/build_roster.py` and mirrors
`Resources/evolutions.json`; regenerate it before counting after a Phase E story.
