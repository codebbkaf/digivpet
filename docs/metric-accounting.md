# Metric accounting: today's delta, credited once

Written for US-204. The one rule this whole document defends:

> **Steps, calories, exercise minutes and sleep are credited by the DELTA against a stored
> baseline — never by the raw total — so the same activity is never paid for twice, no matter
> how many times the app is opened.**

The health metrics HealthKit hands us are **cumulative daily totals**: "steps today" is 4,000 at
noon and still those same 4,000 at 18:00. An app that credited the reading itself would pay for the
same steps at every refresh. Every crediting path below reads today's total, subtracts what it has
already banked for today, and credits only the positive difference.

## The two ledgers

There are two persisted ledgers, one per accounting dimension. They read the same daily totals but
answer to different caps and lifetimes, so they hold separate baselines.

| Ledger | File | What it de-duplicates | Cap |
|---|---|---|---|
| `EnergyLedger` | `Sources/EnergyLedger.swift` | The four **energy currencies** a reading buys (`EnergyType`). | `EnergyRates.dailyCapPerEnergyType` per type. |
| `MetricLedger` | `Sources/MetricLedger.swift` | The raw **metric totals** (`ConditionMetric`) a `health.*` evolution condition, a map, or a charge reads. | None — raw measurements. |

Both are `@Model` types (they must survive a cold launch — "reopening never double-credits" is a
statement about a fresh process, and an in-memory baseline would be zero again on every one). Both
key on a `day` (local midnight) and reset the baseline at a day rollover. Neither lives on
`GameState`: `resetGame` is a total wipe, and a ledger there would hand a reborn Digimon today's
full readings a second time out of the same day's activity.

Two ledgers reading one metric is **not** double counting: a step becomes one unit of Strength
*energy* (a spendable currency) and is separately tallied as one *step* toward a map. Those are
different quantities in different units; each is credited once within its own ledger.

## The delta rule, in code

Both ledgers do the same three things — roll the day if midnight has passed, take
`max(0, todayTotal − alreadyCredited)`, then add that delta to the baseline:

- `EnergyLedger` — inline in `EnergyCreditor.credit` (`Sources/EnergyLedger.swift`). The reading is
  first converted to capped points by `EnergyRates.cappedDailyPoints`, then the delta of *points*
  is taken against `creditedToday[type]`.
- `MetricLedger.claim(_:dayTotal:now:)` — **the single place the metric de-duplication rule lives.**
  Every consumer of a metric (the stage/lifetime totals `MetricCreditor` keeps, the per-map step
  accrual, the train and clean charges) spends the delta `claim` hands back rather than computing
  its own from a private baseline. Two baselines over one reading is exactly how "walking 1,000
  steps credited the map 2,000" would happen.

`max(0, …)` means a **shrinking** reading — data deleted in the Health app, or a source revising a
sample down — credits zero and takes nothing back. Progress is never un-earned.

## The one refresh, one claim wiring

`MainScreenModel.refresh()` (`Sources/MainScreenModel.swift`, ~line 1309) reads the day **once**
into `HealthDayReadings`, then:

1. `EnergyCreditor.credit` banks the four energy currencies off `EnergyLedger`.
2. `MetricCreditor.credit` banks the raw metric totals off `MetricLedger`, returning the deltas it
   claimed.
3. The map, train and clean charges **spend those returned deltas** — they never `claim` a second
   time. So a step is de-duplicated once and shared:
   - `creditMapSteps(creditedMetrics[.healthSteps])` — US-118 map progress.
   - `creditTrainCharges(creditedMetrics[.healthActiveEnergy])` — US-177 training charges.
   - `creditCleanCharges(creditedMetrics[.healthHandwashing])` — US-178 cleaning charges.
   - `state.creditSleep(minutes: creditedMetrics[.healthSleep])` — US-181 accumulated sleep.

Nothing reads HealthKit twice in one refresh: the three daily quantities and last night's sleep are
seeded from the single read the energy path already made (`HealthEnergySource.dayReadings`).

The widget cannot open a second store on the same file for the same reason — two stores mean two
in-memory ledgers crediting the same steps twice. It only ever *reads* the `ComplicationSnapshot`
the app publishes (see `Sources/ComplicationSnapshot.swift:101`).

## How each of the four avoids double counting

| Activity | Metric | Energy (via `EnergyLedger`) | Metric total (via `MetricLedger`) |
|---|---|---|---|
| Steps | `.healthSteps` | Strength, capped | Map steps (US-118), stage/lifetime step totals |
| Active calories | `.healthActiveEnergy` | Vitality, capped | Train charges (US-177), stage/lifetime totals |
| Exercise minutes | `.healthExerciseMinutes` | Stamina, capped | Stage/lifetime totals |
| Sleep | `.healthSleep` | Spirit, capped (last-night window) | Accumulated per-Digimon sleep (US-181) |

Each cell credits the delta of *today's* reading against *its own* stored baseline. A day rollover
re-baselines both ledgers to zero (yesterday's readings restarted at midnight too), so today is
credited on its own merits and yesterday is never back-credited.

## The tests that prove it

No gap was found while writing this — the code already enforces the guarantee, and these tests pin
it (`Tests/`):

**Energy path (`EnergyCreditingTests.swift`):**

- `testReadingTwiceWithNoNewHealthDataCreditsZeroTheSecondTime` — same day, unchanged reading →
  second credit is 0 (AC2).
- `testOnlyTheNewPartOfARisingDayIsCredited` / `testCreditingRepeatedlyIsWorthTheSameAsCreditingOnce`
  — a rising day credits only the increase (AC1, AC3).
- `testAShrinkingReadingNeverTakesEnergyBack` — a shrinking reading credits nothing.
- `testANewDayCreditsAgainstAFreshBaselineAndAFreshCap` / `testTheDayRollsOverAtLocalMidnight` — a
  rollover re-baselines without back-crediting yesterday (AC3).
- `testReopeningTheAppDoesNotCreditTheSameDayAgain` / `testAReopenedStoreStillCreditsGenuinelyNewActivity`
  — the persisted baseline survives a cold relaunch (AC2).
- `testResettingTheGameDoesNotRefundTheDaysCap` — a game reset does not re-credit the day.

**Metric path (`MetricTotalsTests.swift`):**

- `testRefreshingTwiceInADayDoesNotDoubleCount` — same steps, twice, banked once (AC2).
- `testOnlyTheDeltaIsCreditedWhenADayGrows` — a grown day credits only the delta (AC1, AC3).
- `testAShrinkingReadingNeverSubtracts` — a shrinking reading credits nothing.
- `testTheBaselineResetsAtLocalMidnight` — a new local day starts over at zero (AC3).
- `testEvolvingMidDayDoesNotRebankTheMorning` — a stage reset mid-day does not re-bank the morning's
  already-credited steps.
- `testTheLedgerBaselineSurvivesARelaunch` — the metric baseline survives a cold relaunch (AC2).

**Wired end-to-end (`MetricWiringTests.swift`):**

- `testRefreshingTwiceInADayCreditsTheMetricOnce` — a full `refresh()` twice in one day credits the
  metric once.
