# PRD: Sleep, the Consumption Loop, Battle Stats, and Screen Polish

## Introduction

This PRD closes the loop the game has been circling. Today four HealthKit metrics feed four energy
bars, but the *play* loop and the *evolution* loop use those metrics inconsistently, and one whole
data pipeline (the metric ledger behind every `health.*` evolution condition) is wired in tests and
nowhere else. The stories here make the metric→game conversion a single tunable config, turn the
care actions into a coherent economy, give sleep a first-class role in evolution, give every Digimon
real battle stats, and fix the layout so the Digimon has room to live.

**The intended cycle, stated once so every story can point at it:**

1. **Sleep** to push the active Digimon toward its per-Digimon *sleep-hours* evolution requirement.
2. **Walk** — steps become **battle charges** (300 steps = 1 charge, capped at 10, stored per
   Digimon).
3. **Battle** — spending a charge; wins drop **meat** randomly. Meat is the one **global** currency,
   shared across the whole box of Digimon.
4. **Feed** the Digimon with meat.
5. **Exercise** — active calories become **train charges** (50 kcal = 1 train), which you spend to
   raise stats toward a Digimon's *training* evolution requirement.
6. **Clean** the poop, which costs **handwash** time (accumulates to at most 2, global).

Every one of these values is shown on screen as a **dash bar** — one dash per unit, solid for
earned/filled and outline-only (border, no fill) for the remainder — with **no numbers**. The dash
bar is the single visual language for progress in this app, chosen so the wrist reads state in under
two seconds without parsing digits.

## Ownership rule (verified against the code, do not re-derive)

`GameState` is per-Digimon (`Sources/GameState.swift:175`); `PlayerProfile` is what outlives a
Digimon (US-123). Therefore:

| Value | Stored on | Why |
|---|---|---|
| Meat | `PlayerProfile` (global) | Shared across the box; the only global currency |
| Handwash charges | `PlayerProfile` (global, max 2) | Real-world hygiene isn't per-pet |
| Battle charges | `GameState` (per Digimon, max 10) | "battle time is store in specific digimon" |
| Train charges | `GameState` (per Digimon) | Training is the pet you trained |
| Accumulated sleep hours | `GameState` (per Digimon) | Feeds that pet's sleep evolution gate |
| HP / Attack / Agility trained bonuses | `GameState` (per Digimon) | You trained this pet's body |

When the player switches the active Digimon (US-126), every per-Digimon value above must display
that Digimon's own stored value — a switch must never leak another pet's battle/train/sleep state.

## Current state (measured, not assumed)

| Fact | Value | Source |
|---|---|---|
| Metric→game conversion constants | scattered across files | `EnergyRates`, `FeedAction.swift:22`, `TrainAction.swift:36`, `Battle.swift` `BattleLimits.perDay = 5` |
| `MetricCreditor.credit` calls from `Sources/` | **0** | only tests call it; `grep` over `Sources/` |
| `EnergyCreditor.credit` calls from `Sources/` | 1 (`MainScreenModel.swift:1157`) | the energy path IS wired |
| `ConditionContext.readings` supplied from `Sources/` | never (empty dict at all 5 build points) | `MainScreenModel`, `DexModel.swift:252` |
| Feed currency | Vitality energy (5 pts/feed) | `FeedAction.swift:22` |
| Battle gate | per-day cap of 5, costs no energy | `Battle.swift`, `BattleLimits` |
| Digimon combat stats (HP/Attack/Agility) | none in `Resources/roster.json` | grep found no such fields |
| Elements / attributes | exist | `Resources/elements.json`, `DigimonElement.swift`, `ElementCatalog.swift` |

### The dead health pipeline (the reason the sleep gate can't ship without a fix)

`MetricCreditor.credit(...)` (`Sources/MetricLedger.swift:143`) is the only writer of
`GameState.stageMetricTotals` / `lifetimeMetricTotals` / `stageBestDayMetrics`, and those three
fields are the sole data source for every `health.*` evolution condition
(`ConditionContext.init(state:now:)`, `Sources/ConditionEvaluator.swift`). Because nothing in
`Sources/` ever calls it:

- **Problem 1 — `atLeast` health gates never pass.** `stageMetricTotals` defaults to `[:]`, whose
  subscript returns `0`, so `healthValue(...)` yields `.known(0)`, not `.unknown`. Any
  `atLeast N` health condition is permanently unmet.
- **Problem 2 — `atMost` health gates pass for free (worse).** The same `.known(0)` satisfies
  `0 <= N` for every threshold, silently turning "stay up late to fall to a dark evolution" into a
  freebie: e.g. `agumon → devimon` is now gated on `care.battleCount` alone; sleep is irrelevant.
- **Problem 4 — standing/instantaneous metrics are unanswerable.** `ConditionContext.readings` is
  never supplied, so non-accumulating metrics (resting HR, VO2 max) can only return `.unknown`;
  `HealthMetricReader`'s `averageQuantity` aggregation is dead code today.

Wiring `MetricCreditor` beside `EnergyCreditor` and supplying `readings` from `HealthMetricReader`
is the prerequisite for the sleep evolution gate, and it revives the `health.*` conditions the
orphan-wiring epic already authored.

> **Out of scope here (tracked separately):** the ~20 `maps.json` Digitama slots that authorize a
> metric×window combination `ConditionEvaluator` refuses to answer (e.g. `care.battleCount` with a
> `stage` window). The user is fixing that data in a separate pass. US-183/US-184 below add the
> *validator rule* that would have caught it, but do not re-author the data.

---

## The stories

Grouped by theme; implementation order and priorities are in `prd.json`. Every story ends with
"Tests pass / Typecheck passes" against the build command in `CLAUDE.md`.

### A. Foundation

**Metric→game conversion config.** One shipped `Resources/consumption.json` + `Sources/ConsumptionConfig.swift`
(loaded the way `MapCatalog.bundled` loads, `fatalError` on undecodable data) holds every
conversion constant: `kcalPerTrain` (50), `stepsPerBattleCharge` (300), `maxBattleCharges` (10),
`handwashPerCleanCharge`, `maxCleanCharges` (2), `meatPerBattleWin` range, the hit-rate and
element-damage coefficients, and the per-stage stat/training-cap tables. No conversion constant may
remain hard-coded in an action file once this ships. A validator test asserts the config decodes and
every value is in a sane range.

**Dash-bar component.** One reusable SwiftUI `DashBar(filled:total:)` renders `total` equal-width
dashes, the first `filled` solid and the rest outline-only (stroked border, no fill), no number
anywhere, laid out to fit the watch width and wrap/scale for large `total` (e.g. 16 sleep dashes).
Accessibility label carries "filled of total" for VoiceOver even though the visual has no digits.
Every value bar added by later stories uses this component.

### B. Screen polish

**Bottom-align the action row; grow the play area.** The action button row pins to the screen bottom
with 4pt padding, and the sprite play area + `MapBackgroundView` grow to take the reclaimed vertical
space, so the Digimon has more room to walk and the map reads larger. Measured before/after on 41mm
and 46mm: the play area is taller, the button row bottom-inset is 4pt, nothing overlaps the sprite.

**Bigger widget sprite.** The circular complication's Digimon image is enlarged within its frame so
it reads at a glance, without clipping the round bezel.

### C. The consumption economy

**Meat is the global feed currency.** Replace Vitality-cost feeding (`FeedAction.swift:22`) with a
global `meat` count on `PlayerProfile`; feeding consumes 1 meat and is blocked at 0 with a clear
"no meat — go battle" affordance. Meat displays as a dash bar.

**Battle wins drop meat.** Winning (or completing) a battle grants a random amount of meat from the
config range, credited to the global pool, surfaced in the result screen.

**Battle charges from steps.** Steps convert to per-Digimon battle charges (`stepsPerBattleCharge`
= 300 → 1 charge, capped at `maxBattleCharges` = 10). A battle spends one charge; the old per-day cap
(`BattleLimits.perDay`) is removed. Charges are stored on `GameState` and shown as a dash bar.

**Train charges from calories.** Active calories convert to per-Digimon train charges (`kcalPerTrain`
= 50 → 1 charge). Training spends one charge (replacing the Strength/Stamina energy cost in
`TrainAction.swift`). Shown as a dash bar.

**Cleaning costs handwash.** Cleaning poop spends a global handwash charge (`PlayerProfile`, from
HealthKit handwashing, capped at `maxCleanCharges` = 2). No handwash charge → cleaning is unavailable
and says so. Shown as a dash bar.

### D. Sleep

**Wire the metric ledger.** Call `MetricCreditor.credit(...)` beside `EnergyCreditor.credit`
(`MainScreenModel.swift:1157`) in the health-read flow, and supply `ConditionContext.readings` from
`HealthMetricReader` at every build point. Fixes Problems 1, 2, 4; a test proves a credited
`health.sleep` total reaches an `atLeast`/`atMost` condition.

**Unknown is not zero.** Make "never credited / unauthorized" read as `.unknown`, distinct from a
credited real `0`, so `atMost` health gates stop passing for free. The `GameState` accessor returns
`nil` (→ `.unknown`) when a metric was never credited, matching the `ConditionContext` comment's
stated intent.

**Per-Digimon sleep accumulation.** Accumulated sleep-hours are stored on `GameState` and persist
across active-Digimon switches; switching shows the correct pet's sleep. (Distinct from the nightly
sleep *energy* — this is the lifetime-of-this-Digimon accumulation the evolution gate reads.)

**Zz bar shows the active Digimon's sleep.** The main screen "Zz" bar renders the active Digimon's
accumulated HealthKit sleep as a dash bar.

**Sleep evolution gate + detail dash bar.** Evolution edges may require accumulated sleep hours
(e.g. Agumon needs 16 h). The Digimon detail view shows a per-Digimon sleep dash bar: `required`
dashes total, `earned` solid, the rest outline, no numbers — so the player sees exactly how much
sleep remains. Evolution down that edge is blocked until the sleep requirement is met.

### E. Light-off conditions

**Light-off evolution condition.** A new evolution condition type "light must be off": some Digimon
(dark-side) only evolve while the room light is off (`LightState`, `Light.swift`). Authored into a
handful of edges; validated.

**Light-off map condition.** A map's Digitama slot / opponent set may require the light off — dark
Digimon appear only in the dark. Authored into a few maps; validated by `MapCatalogValidator`.

### F. Battle stats and mechanics

**Base stats HP / Attack / Agility.** Every playable Digimon has base HP, Attack, and Agility, in
`Resources/roster.json` (or a companion stats file), scaling with stage (higher stage → higher base
and higher training caps). Shown in the Digimon detail page as dash bars.

**Dash HP bar in battle.** Battle mode shows each combatant's HP as a dash bar (Agumon 5 HP → 5
dashes). A hit removes dashes; at 0 dashes that Digimon loses.

**Agility dodge with face-turn.** Each incoming attack rolls a hit chance from the two Agility
stats: a reasonable, monotonic, bounded formula (equal Agility → a fixed base chance; the more agile
defender dodges more; clamped to a floor and ceiling so nothing is guaranteed or impossible), with
its coefficients in `consumption.json`. On a dodge the projectile misses and the defender flips to
face the other way at the dodge instant.

**Element advantage in damage.** Real damage scales Attack by the attacker-vs-defender element
matchup (advantage/neutral/disadvantage, from the existing `elements.json`/`ElementCatalog`), with a
minimum of 1 so a hit always dents at least one dash.

**Trainable stats with caps.** Training raises HP/Attack/Agility toward a per-Digimon cap (base +
capped bonus, cap scaling with stage). Bonuses are stored per-Digimon on `GameState`; a test proves
training never exceeds the cap and higher-stage Digimon have larger caps.

**Losing a battle: heal or care mistake, and death.** After a loss the Digimon is either healed or,
if not, charged a care mistake (integrating existing `CareMistakes.swift`); accumulated care
mistakes progress toward death (`Death.swift`) on the existing schedule. Reverses the old "losing
never causes a care mistake" rule (`prd-battle-cost-sleep-and-screen-polish.md`) deliberately — the
new loop makes battles matter.

---

## Non-goals

- No new sprite art; poses come from the existing 12-frame sheets (dodge uses a flipped walk frame).
- No numeric readouts on the care/stat bars — the dash bar replaces numbers, deliberately.
- Not re-authoring the ~20 mis-windowed `maps.json` Digitama slots (separate pass); only adding the
  validator rule that catches the class of bug.
- No defense stat — damage is Attack × element matchup only, to keep the model legible on the wrist.

## Open questions

1. **Sleep-hours unit granularity** — whole hours (16 dashes) as the example implies, or half-hours?
   Assumed whole hours.
2. **Stat units vs dashes** — is 1 HP = 1 dash at every stage, or does a Perfect's larger HP pool
   need grouped dashes? Assume 1:1 until a stage's HP makes the bar too wide, then group in config.
3. **Meat cap** — is the global meat pool capped, or unbounded? Assumed a config cap.
