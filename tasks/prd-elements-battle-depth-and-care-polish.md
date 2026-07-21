# PRD: Elements, Battle Depth and Care Polish

## Introduction

The V-Pet raises, evolves and fights, but four things read as unfinished on the wrist:

1. **The energy bars are labelled in Chinese** (力 活 心 耐) with nothing saying where the numbers
   come from. A user cannot tell that 力 is their step count.
2. **A battle is over before it can be watched.** The two Digimon stand 8pt apart, the projectile
   crosses a 56pt gap in a straight line, and the outcome is decided entirely by a power number the
   user cannot influence in the moment. There is no matchup, no skill, and no reason to care which
   Digimon is on the other side.
3. **Actions freeze the Digimon.** Feeding swaps in a two-frame chew loop and cleaning holds a
   single happy frame, and in both cases `isWandering` goes false so the sprite stands dead still.
   The thing that makes a V-Pet feel alive — that it *moves* when you do something to it — is missing.
4. **There is no light switch.** A real V-Pet makes lights-out part of the care loop: leave the
   light on over a sleeping pet and that is neglect. The game has a sleep window and a care-mistake
   counter and nothing joining them.

This PRD closes all four, and adds the one thing that gives battles a reason to exist: **every
Digimon has an element and an attribute**, and a fight is decided by the matchup, the stage, the
training you did in the last thirty seconds, and the raising you did over the last week — in that
order of surprise, and in the opposite order of weight.

## Reference

- Canonical attributes (Vaccine / Data / Virus / Free) come from the Digimon Reference Book, mirrored
  at <https://wikimon.net>. Where a Digimon has a canonical attribute, use it.
- Elements are **this application's own axis**, not canon. Digimon canon has "families" and
  "types" but no consistent elemental chart, so D-2 below designs one. Canon is a source of
  *flavour* (Agumon breathes fire, so it is Fire), never a source of *rules*.

## Goals

- Every bar on the main screen says, in English, what real-world data feeds it.
- A battle takes long enough to watch, with enough space between the combatants to see a projectile
  cross it.
- A battle's outcome depends on four legible things — stage, trained stats, the pre-fight minigame,
  and the elemental matchup — and the user can see each one's contribution on the result screen.
- Every one of the 88 curated Digimon has a hand-authored element and attribute; no Dex entry ever
  shows a blank type row.
- A Digimon **moves** during every action that happens to it: eating, refusing, being cleaned up
  after, and landing a training blow.
- Lights-out is a real care obligation with a real cost, derivable after the app has been closed all
  night.

## Architectural decisions

Made up front because several stories depend on each, and re-litigating them mid-implementation
would be expensive.

### D-1: elements are a new bundled file, not a field on `evolutions.json`

`Resources/evolutions.json` is the curated playable graph and `Resources/roster.json` is the
1,022-entry catalog. A **new `Resources/elements.json`** holds the type assignments and the counter
chart, for the same reason `moves.json` is its own file: it is authored data with its own validator,
it must cover ids from *both* other files, and adding a required field to `EvolutionNode` would fail
the whole graph load (`fatalError` at launch) the first time an id was missed.

Lookup mirrors `MoveCatalog` exactly — by `id`, then by `line`, then a keyword rule, then `neutral` —
so there is one lookup idiom in the codebase rather than two.

### D-2: two axes, and the element axis is the one that matters

Every Digimon carries **both**:

- an **attribute**: `vaccine` | `data` | `virus` | `free` — canon, and a small triangle;
- an **element**: `fire` | `water` | `plant` | `electric` | `ice` | `wind` | `earth` | `steel` |
  `light` | `dark` | `machine` | `neutral` — this app's invention, and the headline.

They are separate fields rather than one merged enum because a Digimon is genuinely both (Agumon is
a Vaccine *and* a Fire type), and merging them would force a choice that throws away canon.

**The element counter chart** (each row lists what that element beats):

| Element | Beats | Therefore weak to |
|---|---|---|
| fire | plant, ice, steel | water, earth |
| water | fire, earth, machine | plant, electric |
| plant | water, earth | fire, ice, wind, steel, machine |
| electric | water, machine, steel | earth |
| ice | plant, wind | fire, steel, machine |
| wind | earth, plant | ice |
| earth | fire, electric | water, plant, wind |
| steel | ice, plant | fire, electric |
| light | dark | dark |
| dark | light | light |
| machine | plant, ice | water, electric |
| neutral | — | — |

Two properties are deliberate and must be pinned by tests:

- **`neutral` is inert** — it neither beats nor is beaten. It is the last-resort fallback for a
  roster-only Digimon nobody has authored, and a fallback must never hand out an advantage.
- **light and dark beat each other.** That is not a bug in the table: the multipliers are applied to
  both sides, so a mutual advantage multiplies out to no advantage at all (1.25 × 0.8 = 1.0). It is
  how "eternal rivals" is expressed in a ratio-based engine.

**The attribute triangle:** vaccine → virus → data → vaccine. `free` is inert, like `neutral`.

### D-3: the pre-battle training round is free and battle-only

Tapping Battle opens this Digimon's assigned minigame (`MinigameAssignment`, US-082) *before* the
fight. That round:

- costs **no energy**,
- does **not** raise `strengthStat`,
- does **not** increment `stageTrainingSessions`.

All three are load-bearing. `care.trainingSessions` is an evolution-gating metric (US-084) and the
Digital Monster Color bands punish *over*training as hard as undertraining — so if a battle counted
a session, battling would silently push a player out of a band they were aiming for. The pre-battle
round buys exactly one thing: a multiplier on *this* fight.

The daily battle allowance (`BattleLimits.perDay`) is spent when the minigame **opens**, not when the
fight resolves, for the same reason `TrainAction.begin` charges before the round appears: walking out
of a fight you are about to lose must not be free.

### D-4: modifiers multiply `BattlePower`; they do not replace it

`BattlePower.power(stage:strengthStat:lifetimeEnergy:)` stays exactly as it is and stays the base.
A new pure `BattleModifiers` produces an **effective power** for each side:

```
effective = max(1, round(BattlePower.power(...) × element × attribute × training))

element   = 1.25 if mine beats theirs, × 0.8 if theirs beats mine   (both may apply → 1.0)
attribute = 1.1  if mine beats theirs, × 0.9 if theirs beats mine   (both may apply → 1.0)
training  = 0.8 / 1.0 / 1.15 / 1.3 for miss / good / great / perfect — PLAYER SIDE ONLY
```

Stage stays dominant: a rung is 8 points of base power and the modifiers together span roughly
±40% of it, so a perfectly-played, well-matched underdog can beat one rung up and cannot beat three.
`BattleEngine.resolve` is unchanged — it already takes two powers and does not care where they came
from.

### D-5: action motion is a pure function of elapsed time, like `MovementModel`

The Digimon already has a walk (`MovementModel`) that is a pure function of a seed and a `Date`.
Action motion is the same shape and deliberately *separate*: a new `ActionMotion` maps
(kind, elapsed seconds) to a point offset, with no state, no timer and no randomness. The walk is
suspended during an action exactly as it is today; what changes is that the sprite is no longer
motionless while suspended — it is being driven by a scripted track instead of a wandering one.

This is what makes "the Digimon hops twice when you clean up" assertable in a unit test instead of
only in a screenshot.

### D-6: the lights rule is derived from saved markers, never ticked

Like `HungerClock` and `CareMistakes`, the lights-out mistake must be correct after the app has been
shut all night. Three fields go on `GameState`:

- `lightState` — `on` | `semi` | `off`
- `lightStateChangedAt` — when it was last set
- `lightAuditedNight` — the start of the last sleep window already charged (one charge per night)

The rule then asks a question that saved data can answer: *was the light off, from early enough in
this night's window?* A user who set it to `off` at 21:00 and closed the app is clean at 08:00
without the app ever having run in between.

## User Stories

Priority order is dependency order. Each is one focused session.

---

### US-085: English energy-bar labels naming their health source
**Description:** As a user, I want each energy bar to say in English which real-world activity feeds
it, so I know that walking more fills the first bar.

**Acceptance Criteria:**
- [ ] `EnergyType.symbol` is renamed `shortName` and returns the SOURCE in short English:
      `strength` → `STEP`, `vitality` → `KCAL`, `spirit` → `SLEEP`, `stamina` → `EXER`
- [ ] No CJK glyph remains anywhere in `Sources/` (`grep -rn '[力活心耐]' Sources/` returns nothing)
- [ ] `EnergyBarRow`'s name column widens from 11pt to fit `SLEEP` at font size 8 without truncation;
      the value column and the 4pt bar keep working, and the bar is never narrower than 18pt
- [ ] `ComplicationSnapshot.dominantEnergySymbol` carries the new short name; the complication's
      corner and rectangular families render it without clipping
- [ ] `Tests/EnergyBarsTests.swift` and `Tests/ComplicationTests.swift` assert the new strings
- [ ] VoiceOver still reads the full `displayName` ("Strength"), not the abbreviation
- [ ] Verified by `simctl` screenshot on Apple Watch Series 11 (42mm) — the narrowest supported
      screen — showing all four labelled bars unclipped, plus one on 46mm
- [ ] Typecheck passes (`xcodebuild build` succeeds) and `xcodebuild test` succeeds

---

### US-086: Element and attribute vocabulary with a counter chart
**Description:** As a developer, I need elements, attributes and their counter relations as pure,
tested Swift before anything renders or resolves a battle with them.

**Acceptance Criteria:**
- [ ] `DigimonElement: String, Codable, CaseIterable` with the twelve cases in D-2
- [ ] `DigimonAttribute: String, Codable, CaseIterable` with `vaccine`, `data`, `virus`, `free`
- [ ] Each has `displayName`, a short `badgeText` (≤5 chars), an SF Symbol name, and a `Color`
      (the colour lives in a SwiftUI extension, not in the pure type — the pattern `MoveTint` uses)
- [ ] `DigimonElement.beats: Set<DigimonElement>` implements D-2's table exactly
- [ ] `Effectiveness` enum — `advantage` | `disadvantage` | `even` — with
      `DigimonElement.effectiveness(against:)` and the same on `DigimonAttribute`
- [ ] Mutual advantage (light vs dark) reports `advantage` for BOTH sides; the cancelling-out is
      US-092's arithmetic, not this type's
- [ ] Tests pin: no element beats itself; `neutral` and `free` neither beat nor are beaten by
      anything; every other case beats at least one and is beaten by at least one (so no element is
      strictly best or strictly worst); `effectiveness` is consistent with `beats` in both directions
- [ ] `docs/elements.md` documents both axes, the full chart, and why `neutral` is inert
- [ ] Add new files to `project.yml` and re-run `xcodegen generate`
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-087: Author `elements.json` for every curated Digimon
**Description:** As a player, I want every Digimon I can actually raise or fight to have a real,
sensible element and attribute, so the matchup means something.

**Acceptance Criteria:**
- [ ] `Resources/elements.json` with three sections mirroring `MoveCatalog`: `types` (by id),
      `lineDefaults` (by evolution line), `keywordRules` (ordered substring → element/attribute)
- [ ] All **88** nodes in `evolutions.json` have an explicit `types` entry — a test enumerates the
      graph and fails naming any id that is missing, so this cannot silently regress
- [ ] Attributes use canon where canon exists (Agumon Vaccine, Greymon Vaccine, Numemon Virus,
      Gabumon Data, Devimon Virus, Angemon Vaccine, …); the authoring session records in the file's
      `_comment` which ids were judgement calls rather than looked up
- [ ] Elements are flavour-consistent within a line's theme but need not be identical across it
      (Agumon fire → Greymon fire → MetalGreymon machine is correct, not a bug)
- [ ] `ElementCatalog.type(forId:line:)` resolves id → line → keyword rules → `(.neutral, .free)`,
      pure and unit-tested at every tier
- [ ] Keyword rules cover at least: Agu/Mera/Flame→fire, Gomamon/Seadra/Aqua→water, Palmon/Woodmon/
      Floramon→plant, Thunder/Raidra/Kabuterimon→electric, Yuki/Ice/Frigi→ice, Piyo/Birdra/Aquila→
      wind, Gotsu/Golem/Ankylo→earth, Metal/Andro/Guardro/Machine→machine, Angel/Holy/Seraphi→light,
      Devi/Dark/Black/Skull/Vamde→dark
- [ ] Every one of the 1,022 roster ids resolves to something (a test walks the whole roster and
      asserts no throw and no crash); how many land on `neutral` is REPORTED in the story's notes,
      not asserted — an honest number beats a padded keyword table
- [ ] A malformed `elements.json` fails the decode at load, like `MoveCatalog.bundled`
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-088: Element and attribute badges on the Dex detail view
**Description:** As a player, I want to see a Digimon's element and attribute when I open it in the
Dex, so I can plan a matchup before I fight.

**Acceptance Criteria:**
- [ ] `DexDetailView` shows a badge row under the name: element badge (symbol + short name, tinted)
      and attribute badge, side by side
- [ ] Shown for **discovered** entries; an undiscovered entry shows neither (the type is part of
      what discovery reveals)
- [ ] A Digimon resolving to `neutral`/`free` shows those badges rather than an empty row
- [ ] The badge row costs no more than 16pt of height, and the candidate tiles below it are still
      above the fold on a 41mm screen (this is what US-064 fought for — do not spend it)
- [ ] Tapping the element badge is NOT a navigation (no counter-chart screen in this story)
- [ ] Verified by `simctl` screenshot on 42mm and 46mm: one discovered Digimon showing both badges,
      one undiscovered showing neither
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-089: Projectile and signature move on the Dex detail view
**Description:** As a player, I want to see what a Digimon throws once I have owned it, so the Dex
records what I learned by raising it.

**Acceptance Criteria:**
- [ ] For a **discovered** entry, `DexDetailView` shows an attack row: the `projectileSymbol` glyph
      in its `MoveTint` colour, and the `signatureName` beside it
- [ ] For an **undiscovered** entry the row is absent entirely — not a greyed-out placeholder, which
      would leak that a signature exists and how long its name is
- [ ] "Discovered" is the existing `DexRow.isDiscovered` — no new ownership concept is introduced
- [ ] The move comes from `MoveCatalog.bundled` through the existing `move(for:in:roster:)` lookup
- [ ] A test asserts the row's presence is exactly `row.isDiscovered`, and that the symbol and name
      shown are the ones the catalog returns for that id
- [ ] Verified by `simctl` screenshot: a discovered Digimon showing its glyph and signature name
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-090: Push the combatants to opposite sides of the arena
**Description:** As a player, I want the two Digimon standing at opposite ends of the screen, so
there is room to see a projectile cross the gap.

**Acceptance Criteria:**
- [ ] `BattleView.arena` lays the player against the leading edge and the opponent against the
      trailing edge (`HStack { player; Spacer(minLength: 0); opponent }`), each inset 4pt from the
      bezel — not `HStack(spacing: 8)` centred
- [ ] They still face each other: player mirrored, opponent unmirrored (`faces(_:)` unchanged)
- [ ] The gap between the two sprites' inner edges is at least 60pt on a 42mm (176pt) screen; a test
      asserts the arithmetic against both supported screen widths
- [ ] `projectileSpan` is DERIVED from the measured arena width rather than the current 56pt literal,
      so the flight actually starts at the attacker and ends at the defender on both screen sizes
- [ ] The HP readout and the opponent's name keep their places and are not overlapped by either sprite
- [ ] Verified by `simctl` screenshot on 42mm and 46mm using `-battleTurnDemo`, showing both sprites
      at the edges with the projectile visible between them
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-091: Slow, eased projectile flight
**Description:** As a player, I want to actually see the projectile travel, so an exchange reads as
an attack rather than as a flicker.

**Acceptance Criteria:**
- [ ] The projectile animates with `.easeInOut` over its whole flight — not `.linear`
- [ ] Flight duration is `1.1s` and `turnDuration` rises from `0.7s` to `1.4s`, so the projectile
      lands and the defender's hurt loop is legible before the next exchange starts
- [ ] `introDuration` rises to `1.2s`
- [ ] Both remain injectable properties, so every existing test still drives a whole battle in
      milliseconds and `Tests/BattleTests.swift` needs no waiting
- [ ] A test asserts the flight duration is strictly less than `turnDuration` — impact must land
      inside the turn that threw it, not during the next one
- [ ] A whole battle of the median length (4–6 exchanges) completes in under 12 seconds; the story's
      notes record the measured wall-clock time of a real Simulator battle
- [ ] Verified by two `simctl` screenshots of the same `-battleTurnDemo` launch taken ~0.4s apart,
      showing the projectile at visibly different positions along its arc
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-092: `BattleModifiers` — effective power from matchup and training
**Description:** As a developer, I need one pure function turning stage/stat power plus the matchup
plus the training grade into the two numbers `BattleEngine.resolve` fights with.

**Acceptance Criteria:**
- [ ] New `BattleModifiers` implementing D-4's formula exactly, with every multiplier a named
      `static let` (`elementAdvantage = 1.25`, `elementDisadvantage = 0.8`, `attributeAdvantage = 1.1`,
      `attributeDisadvantage = 0.9`) and the training multipliers on `TrainingResult`
- [ ] `TrainingResult.battleMultiplier`: miss 0.8, good 1.0, great 1.15, perfect 1.3
- [ ] Returns a struct carrying BOTH sides' effective powers AND the individual factors that
      produced them, so US-094 can show the breakdown without recomputing it
- [ ] Pure: no clock, no store, no randomness — same inputs, same output, always
- [ ] Effective power is floored at 1, so a ratio is always safe to take
- [ ] `BattleEngine.resolve` is UNCHANGED; it receives effective powers as its two arguments
- [ ] Tests pin: a light-vs-dark mutual matchup nets 1.0; an even matchup with a `good` grade equals
      raw `BattlePower` unchanged; a `perfect` grade with element advantage beats an opponent one
      stage higher; a `miss` with element disadvantage loses to an equal-stage opponent; the
      training multiplier is NEVER applied to the opponent
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-093: Train before you fight
**Description:** As a player, I want to play my Digimon's training game right before a battle, so my
performance in the moment decides how hard it hits.

**Acceptance Criteria:**
- [ ] Tapping Battle opens `MinigameAssignment.game(for:)`'s game for the current Digimon, full
      screen, exactly as `train()` does — the battle does not begin until the round is graded
- [ ] The round costs **no energy**, does **not** raise `strengthStat`, and does **not** increment
      `stageTrainingSessions` — each asserted separately against the saved state
- [ ] The daily battle allowance is spent and SAVED when the minigame opens, so a force-quit
      mid-round still costs the battle (mirrors `TrainAction.begin`)
- [ ] Backgrounding mid-round grades `.miss` and the battle proceeds with the miss multiplier — the
      fight is not cancelled and the allowance is not refunded
- [ ] The grade is carried into `BattleModifiers` and the resolved `BattleReport` is built from the
      effective powers
- [ ] Battle is still blocked while asleep, dead, or out of allowance, with the same messages, and a
      blocked battle opens NO minigame
- [ ] The Digimon cannot be in a training round and a battle round at once — a test asserts Train
      during a pending battle round is a no-op and vice versa
- [ ] Verified by `simctl` screenshot: the minigame on screen after a Battle tap, then the arena
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-094: Show the matchup and what decided the fight
**Description:** As a player, I want to see why I won or lost, so the element chart and the training
game feel like things I can play rather than dice.

**Acceptance Criteria:**
- [ ] The battle intro beat shows both combatants' element badges and an effectiveness caption:
      "Super effective", "Not very effective", or nothing when even
- [ ] The result screen lists the three contributions to the player's effective power as signed
      percentages, e.g. `Perfect +30% · Fire vs Plant +25% · Vaccine vs Virus +10%`, followed by
      `PWR 41 → 73`
- [ ] Every number shown comes from the `BattleModifiers` result the fight was actually resolved
      from — nothing is recomputed for display, so the caption and the outcome cannot disagree
- [ ] An even matchup with a `good` grade shows `PWR 41` and no percentage row at all, rather than a
      row of `+0%`
- [ ] The breakdown fits a 42mm screen at font size 9 with `minimumScaleFactor(0.7)` and does not
      push the Done button off screen
- [ ] Verified by `simctl` screenshots of `-battleResultDemo` for a win with advantage and a loss
      with disadvantage
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-095: `ActionMotion` — scripted sprite motion
**Description:** As a developer, I need a pure motion track for action poses before any action can
use one.

**Acceptance Criteria:**
- [ ] `ActionMotion` with a `Kind` per motion — `chew`, `hop`, `lunge`, `shake`, `recoil` — and
      `static func offset(for:elapsed:) -> CGPoint`, pure and total
- [ ] Every motion returns `.zero` at `elapsed == 0` and at `elapsed >= duration`, so a sprite always
      starts and ends where it stood — a motion can never strand the Digimon off centre
- [ ] Amplitudes are named constants in sprite PIXELS, scaled by the view's `scale` at draw time, so
      a hop is the same visual height on a 2x and a 5x sprite
- [ ] `DigimonSpriteView` gains a vertical offset alongside its existing horizontal one; both are
      applied in one `.offset`, and `.interpolation(.none)` still sits ahead of the mirror
- [ ] `WanderingSpriteView` takes an optional motion (kind + start date) and, when present, adds its
      offset to the walk position — the walk is still suspended by `isMoving: false`, so the two can
      never fight over the sprite
- [ ] Tests pin each motion's start/end zero, its peak amplitude and its sign (a hop goes UP, i.e.
      negative y), driven by elapsed times a test chooses — no real waiting
- [ ] Add new files to `project.yml` and re-run `xcodegen generate`
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-096: The Digimon moves while it eats and while it refuses
**Description:** As a player, I want my Digimon to visibly react when I feed it, so feeding feels
like something that happened to a creature.

**Acceptance Criteria:**
- [ ] A successful feed plays `.eat` frames AND the `chew` motion — a small vertical bob, two cycles
      over `actionDuration`
- [ ] A refusal plays the refuse frame AND the `shake` motion — a horizontal head-shake, so "not
      hungry" is legible without reading the caption
- [ ] A BLOCKED feed (asleep, dead) still plays no animation and no motion — nothing happened to the
      Digimon, and motion would read as the action having half-worked
- [ ] The motion ends when the pose does; the Digimon resumes wandering from exactly where it stood
- [ ] `MainScreenModel` publishes the motion alongside `animation`, so the two are set and cleared by
      the same `show(_:message:)` call and cannot get out of step
- [ ] A test asserts the motion published for each of fed / refused / blocked
- [ ] Verified by two `simctl` screenshots of one `-feedDemo` launch ~0.3s apart showing the sprite at
      different heights, plus one `-feedRefuseDemo` and one `-feedAsleepDemo` (which must show no
      motion at all)
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-097: The Digimon celebrates a clean screen and lunges on a landed blow
**Description:** As a player, I want cleaning up and training to visibly do something, so the two
actions with no loop of their own stop looking broken.

**Acceptance Criteria:**
- [ ] `clean()` plays the happy frame AND the `hop` motion — two hops over `actionDuration`
- [ ] The poop pile animates OUT rather than vanishing between frames: scale to 0.6 and fade to 0
      over 0.35s, driven by the count going to zero
- [ ] A training round that bought a stat plays the attack frame AND the `lunge` motion — forward in
      the direction the sprite faces, then back
- [ ] A `.miss` plays the angry frame AND the `recoil` motion, so a missed round is distinguishable
      from a landed one without reading the caption
- [ ] Cleaning with nothing to clean stays a no-op — no pose, no motion, no animation on the pile
- [ ] Tests assert the motion for clean, for a paid round and for a miss
- [ ] Verified by `simctl` screenshots: mid-hop and mid-fade on `-poopCleanDemo`, and mid-lunge on
      `-trainResultDemo`
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-098: Light state and the lights-out rule
**Description:** As a developer, I need the light's three states persisted and the neglect rule
written as a pure function before anything renders or notifies.

**Acceptance Criteria:**
- [ ] `LightState: String, Codable, CaseIterable` — `on`, `semi`, `off` — with `displayName`, an SF
      Symbol per state, and `dimOpacity` (0, 0.5, 0.85)
- [ ] `GameState` gains `lightState` (default `.on`), `lightStateChangedAt`, `lightAuditedNight`,
      `lightNotifiedNight` — all with defaults, so an existing store opens cleanly (the lightweight
      migration `EnergyLedger` proved safe; see US-015's warning about non-optional attributes)
- [ ] `LightsOutRule` — PURE, taking `now`, the `SleepSchedule`, the light state and its timestamp:
      - `windowStart(containing:)` — the start `Date` of the sleep window `now` falls in, or nil when
        awake; correct across midnight and for a night-shift non-wrapping window
      - `shouldNotify(...)` — true once the window has been open `notifyGrace` (10 min) with the
        light not `.off`, and not already notified this night
      - `shouldChargeMistake(...)` — true once the window has been open `mistakeGrace` (30 min) with
        the light not `.off`, and not already charged this night
- [ ] Setting the light to `.off` at any point before `windowStart + mistakeGrace` is clean, EVEN IF
      the app never ran during the window — the rule reads `lightStateChangedAt`, not observations
- [ ] `semi` does NOT satisfy lights-out: a test asserts `semi` held all night charges the mistake
- [ ] `GameState.recordLightsLeftOn(now:)` increments `careMistakeCount` at most once per night, in
      the manner of `recordWakingEarly`
- [ ] A Digimon that is awake is never charged, whatever the light is doing
- [ ] Tests use an injected clock throughout and never wait real time
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-099: The light button and the dimmed screen
**Description:** As a player, I want a light switch on the main screen so I can put my Digimon to bed
properly.

**Acceptance Criteria:**
- [ ] A lamp button on the main screen cycles `on → semi → off → on`, with a distinct SF Symbol per
      state (`lightbulb.fill` / `lightbulb.led.fill` / `lightbulb.slash`)
- [ ] It is placed as an overlay in the sprite region's top-LEADING corner, so it costs zero layout
      height — the action row stays five 30pt circles and the sprite scale on a 42mm screen is
      UNCHANGED (a test on `SpriteScale.fitting` pins this)
- [ ] `semi` and `off` draw a black scrim at `dimOpacity` over the whole screen; the light button
      itself is drawn ABOVE the scrim and stays fully legible and tappable, or the user is locked in
      the dark
- [ ] The scrim never covers the battle, training, ceremony or memorial overlays
- [ ] The state persists across app launches
- [ ] Changing the light is not a care mistake in itself and never blocks Feed, Train, Clean or Battle
- [ ] Verified by `simctl` screenshots of all three states on 42mm, plus one showing the action row
      and sprite unchanged in size versus the pre-story build
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-100: Alert the user to turn the light off
**Description:** As a player, I want a nudge when I have left the light on over my sleeping Digimon,
so the mistake is avoidable rather than a surprise the next morning.

**Acceptance Criteria:**
- [ ] New `NotificationKind.lights` with title "Lights out", a body naming the Digimon, its own
      toggle in `NotificationSettingsView`, and `firesWhileAsleep == true` — WITHOUT this the
      dispatcher's sleep gate would suppress the one notice that only makes sense while asleep
- [ ] Sent at most once per night, guarded by `lightNotifiedNight`
- [ ] Sent immediately when a refresh (foreground or background wake) lands inside the window past
      `notifyGrace` with the light not `.off`
- [ ] ALSO scheduled ahead: `PetNotificationDelivering` gains a delivery at a `Date`, and a refresh
      that happens before tonight's bedtime with the light not `.off` schedules one for
      `bedtime + notifyGrace` — otherwise a user whose app is closed all evening is never told
- [ ] Setting the light to `.off` cancels both the pending and the delivered notice, exactly as
      `clean()` withdraws the mess notice
- [ ] A test with a spy deliverer asserts: sent once and only once per night; suppressed when the
      toggle is off; cancelled on lights-out; and NOT sent when the light is already `.off`
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

### US-101: Charge a care mistake for a night under the light
**Description:** As a player, I want leaving the light on over my sleeping Digimon to actually cost
something, so lights-out is part of caring for it.

**Acceptance Criteria:**
- [ ] `refresh()` runs `LightsOutRule.shouldChargeMistake` and charges through
      `recordLightsLeftOn(now:)`, alongside the existing `auditCareMistakes` call
- [ ] At most one mistake per night, however many times the app is opened; `lightAuditedNight` is the
      guard and it is SAVED
- [ ] A night the app never ran is charged on the next launch — a test closes the store at 21:00 with
      the light on, reopens it at 08:00, and asserts exactly one mistake
- [ ] Two consecutive neglected nights charge exactly two
- [ ] `semi` all night charges the mistake; `off` set at any time before `bedtime + 30min` charges
      nothing
- [ ] The mistake feeds `careMistakeCount` like every other, so it gates `maxCareMistakes` edges and
      counts toward sickness (US-028) with no new plumbing
- [ ] Losing a battle still costs nothing — this story adds no path from battling to a care mistake
- [ ] `docs/` gains a note listing all five care mistakes and their thresholds in one table
- [ ] Typecheck passes and `xcodebuild test` succeeds

---

## Functional Requirements

- **FR-1:** Energy bars must be labelled `STEP`, `KCAL`, `SLEEP`, `EXER`; no CJK glyph may appear in
  the UI.
- **FR-2:** Every Digimon must resolve to exactly one `DigimonElement` and one `DigimonAttribute`.
- **FR-3:** The element counter chart must match D-2's table; `neutral` and `free` must be inert.
- **FR-4:** All 88 curated Digimon must have hand-authored types; a missing one must fail a test.
- **FR-5:** The Dex detail view must show element and attribute badges for discovered Digimon only.
- **FR-6:** The Dex detail view must show the projectile glyph and signature name for discovered
  Digimon only.
- **FR-7:** Battle combatants must stand at opposite edges of the arena with ≥60pt of clear gap on
  the narrowest supported screen.
- **FR-8:** The projectile must ease in and out over 1.1s within a 1.4s exchange.
- **FR-9:** Tapping Battle must open the Digimon's assigned minigame before the fight resolves.
- **FR-10:** The pre-battle round must cost no energy, raise no `strengthStat`, and count no
  training session.
- **FR-11:** The daily battle allowance must be spent when the pre-battle round opens.
- **FR-12:** Effective battle power must be `BattlePower` × element × attribute × training grade,
  floored at 1, with the training multiplier applied to the player only.
- **FR-13:** The result screen must show each modifier's contribution, taken from the values the
  fight was resolved with.
- **FR-14:** Feeding, refusing, cleaning and training payouts must each move the sprite.
- **FR-15:** A motion must return the sprite to exactly where it started.
- **FR-16:** The light must have three states, persist, and dim the screen in `semi` and `off`.
- **FR-17:** The light button must remain visible and tappable at any dim level.
- **FR-18:** Leaving the light non-`off` for 10 minutes into the sleep window must notify once per
  night; 30 minutes must charge one care mistake per night.
- **FR-19:** The lights-out rule must be derivable from saved state after the app has been closed
  all night.
- **FR-20:** Adding the light button must not shrink the sprite or the action row on a 42mm screen.

## Non-Goals

- **No PvP.** Opponents remain AI, chosen by `BattleMatchmaker` from the curated graph.
- **No element-based matchmaking.** The opponent is still picked by stage; drawing a bad matchup is
  part of the game.
- **No type-effectiveness chart screen.** The badges show what a Digimon *is*; learning the chart is
  the player's job. (Listed in Open Questions.)
- **No new sprite art.** Every motion is built from the twelve frames already in each sheet.
- **No real screen-brightness control.** watchOS gives an app no such API; the light is an in-app
  scrim and a game rule.
- **No auto-lights-out.** A light that turns itself off is not a care obligation.
- **No change to `BattleEngine.resolve`, `BattlePower`, or the energy model.** Modifiers multiply the
  existing power; the four energy types and their sources are untouched.
- **No new HealthKit authorization.**
- **No element on the main screen.** The badges live in the Dex and the battle; the main screen is
  already at its layout limit.

## Design Considerations

- **The main screen has no room left.** Measured: five 30pt action buttons plus 4pt gaps come to
  166pt against a 176pt screen, and `SpriteScale` already floors at 2x. This is why US-099 puts the
  light button in the sprite region's spare corner (the pile owns bottom-trailing, the sick badge
  owns top-centre, top-leading is free) instead of adding a sixth circle.
- **Colour is never the only signal.** The element badge carries a symbol and text as well as a tint,
  matching `EnergyBarRow`'s existing use of weight alongside colour.
- **Battle pacing is a budget.** At 1.4s per exchange and a median 4–6 exchanges, a fight is 7–10
  seconds after the pre-battle minigame. If playtesting finds the whole flow too long, cut the
  minigame's round length, not the projectile — the projectile is the thing this PRD exists to make
  visible.

## Technical Considerations

- **`elements.json` follows `moves.json` exactly** — same lookup tiers, same `bundled` trap on a bad
  decode, same "authoring is a JSON edit, never a code change" rule. Add it to `project.yml` as a
  bundled resource and re-run `xcodegen generate`.
- **`GameState` migration:** all four new fields need defaults. An added *non-optional attribute* on
  an existing `@Model` is not a lightweight migration — give every one a default value in the
  property declaration, as US-015's note warns.
- **The dispatcher's sleep gate is a trap for US-100.** `NotificationDispatcher.send` drops anything
  whose kind is not `firesWhileAsleep` while the Digimon sleeps. The lights notice fires *only*
  during sleep, so it must opt in or it will silently never send — and a test that asserts "sent"
  through a spy while `isAsleep: false` would pass anyway.
- **Timed delivery is new.** `UserNotificationDeliverer` currently uses a nil trigger for everything.
  US-100 needs a `UNCalendarNotificationTrigger`; keep the immediate path unchanged for the other
  four kinds.
- **Background refresh is not a schedule.** `BackgroundRefreshSchedule.interval` is a 30-minute
  *request*. The lights mistake must therefore be derived at the next refresh whenever it happens
  (D-6), not charged by a timer.
- **`.interpolation(.none)` survives every change.** US-095 adds a vertical offset to
  `DigimonSpriteView`; the modifier must stay on the `Image`, ahead of the mirror, or motion will
  ship blurred pixel art.
- **Tests must not wait.** Every new duration — motion length, projectile flight, notify and mistake
  graces — is an injected property or takes an injected clock.

## Success Metrics

- A user can name the real-world source of all four bars without opening the Dex.
- Zero of the 88 curated Digimon fall back to `neutral`.
- A projectile is visible in two screenshots taken 0.4s apart during the same exchange.
- A `perfect` pre-battle round flips at least one matchup that a `miss` loses, against the same
  seeded opponent — demonstrated in a test, not asserted by feel.
- Feeding, cleaning and training each produce visible sprite displacement between two screenshots.
- One neglected night charges exactly one care mistake, whether the app was open for it or not.

## Open Questions

- Should the element badge open a counter-chart reference screen? It is the only way a player learns
  the table without trial and error, but it is a whole new screen and the Dex is already three deep.
- Should the pre-battle minigame's difficulty scale with the opponent's stage, so fighting up is
  harder in the hands as well as on paper?
- Should a `perfect` pre-battle round grant anything on a LOSS — a consolation the record remembers —
  or is a loss costing nothing already reassurance enough?
- Should `semi` have a mechanical use of its own (e.g. halving poop accrual overnight), or is it
  purely a comfort setting the rules ignore?
- Is 30 minutes the right grace before a lights-on mistake? It is a guess; the eight- and six-hour
  thresholds in `CareMistakes` were guesses too, and are documented as such.
