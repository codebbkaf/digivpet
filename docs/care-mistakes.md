# The five care mistakes

Written for US-101, which added the fifth. Every one of them lands on the same counter,
`GameState.careMistakeCount`, and that counter is read in exactly two places: `Sickness`
(three mistakes make a Digimon ill) and `EvolutionEngine` (an edge's `maxCareMistakes`
closes a line off). Nothing else reads it, so adding a sixth mistake means adding to this
table and to one of the two audits below — never to the things that consume it.

## The table

| # | Mistake | Threshold | Charged | Marker that caps it | Where |
|---|---|---|---|---|---|
| 1 | Left starving | 8 h at `HungerClock.maximumHunger` (4) | **As a rate** — 24 h starving is 3 | `starvationMistakesCharged` (count so far this spell) | `CareMistakes.chargeStarvationMistakes` |
| 2 | Screen left filthy | 6 h at `PoopClock.maximumPoops` (4) | Once per spell, however long it runs | `poopMistakesCharged` (0 or 1, reset by `clean()`) | `CareMistakes.chargeUncleanedPoopMistakes` |
| 3 | No health data | One whole local day with nothing recorded | One per missed day; **today is never charged** | `healthDataLastSeen`, moved forward by the days actually charged | `CareMistakes.chargeMissingHealthDataDays` |
| 4 | Overfeeding | 3 refusals (`refusalsPerMistake`) in one local day | Once per local day | `refusalMistakeDay` (the refusals themselves are counted by `refusalCount` / `refusalDay`) | `GameState.recordRefusal` |
| 4b | Waking it early | Any action attempted inside the sleep window | Once per local day, however many prods | `wakeMistakeDay` | `GameState.recordWakingEarly` |
| 5 | Light left on | Lit (`.on` **or** `.semi`) at bedtime + 30 min (`LightsOutRule.mistakeGrace`) | Once per night | `lightAuditedNight` (the bedtime that started the night) | `LightsOutRule.shouldChargeMistake` → `GameState.recordLightsLeftOn` |

Five kinds of neglect, six rows: the PRD counts overfeeding and waking early as one
"handling" mistake, and they are charged by two different call sites, so both are listed.

`Sickness.careMistakesUntilSick` is **3**. A cure (30 energy in a day) resets
`careMistakeCount` to zero — the only thing in the game that ever lowers it — and the
per-rule markers above are deliberately NOT reset with it, so a cure forgives the count
without re-arming a spell that is still running.

## Who charges what, and when

Two audits, both run from `MainScreenModel.refresh()`, one after the other, after energy is
credited and before `updateSickness` / `evolveIfReady`:

- `GameState.auditCareMistakes(now:health:)` — mistakes 1, 2 and 3. Everything it needs is
  on the saved game.
- `MainScreenModel.auditLights(_:)` — mistake 5. Separate only because it needs the sleep
  window, which is derived from HealthKit and belongs to the model, not to the save.

Mistakes 4 and 4b have a moment rather than a duration, so they are charged where they
happen (a refused feed, a blocked action) rather than by an audit.

## The invariant every one of them has to hold

**48 hours with the app shut must land exactly where 48 hours with it open does**
(`ClosedAppRecomputeTests`). Each rule pays for this differently:

- Starvation and the silent days are derived from a frozen timestamp, so elapsed time gives
  the same answer either way.
- The mess is charged **once per spell rather than as a rate**, because poop is paused by
  sleep and only a running refresh can observe the pause — as a rate the same 48 hours
  scored 2 mistakes open against 6 shut.
- The light is charged **per night, walking back over every unaudited one**, because nothing
  about it is observation-dependent: each night's verdict is `lightStateChangedAt` compared
  with that night's deadline, recoverable days later. Charging only the night the refresh
  woke up in would have made a weekend cost 1 shut and 2 open.

## What is NOT a care mistake

Losing a battle (US-031), changing the light (US-099), and a battle refused because the
day's allowance is gone (US-032). All three are tested for explicitly — they are the
mistakes a "fair punishment" instinct keeps trying to add.
