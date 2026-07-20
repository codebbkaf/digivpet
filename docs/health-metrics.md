# Which HealthKit identifiers are actually readable on watchOS 26.4

US-055 spike. Produced by `Sources/HealthMetricProbe.swift` (DEBUG only, ships no feature).
US-061 must not author an evolution criterion on an identifier this doc does not mark **usable**.

Probed 2026-07-20, Xcode 26.4.1, watchOS 26.4 Simulator (Apple Watch Series 11 46mm).
Reproduce with:

```bash
xcrun simctl launch --console-pty <UDID> com.digivpet.DigiVPet -probeHealthMetrics
xcrun simctl spawn <UDID> log show --last 2m --predicate 'category == "HealthProbe"' --style compact
```

## Headline

**All 27 identifiers plus `HKWorkoutType.workoutType()` are valid, readable types on
watchOS 26.4. Not one is unavailable on the platform.** The constraint on US-061 is therefore
not *which types exist* — it is *which types need a new authorization prompt* (23 of 27 do)
and *which types actually carry data on a real wrist* (this spike cannot answer that; see
[Limits](#limits-what-this-spike-could-not-establish)).

## How each of the three facts was established

| Fact | Method | Result |
|---|---|---|
| Compiles on watchOS 26.4 | `xcodebuild build` with all 27 identifiers referenced | **BUILD SUCCEEDED** — every one compiles |
| Appears in the authorization sheet | `requestAuthorization(toShare:read:)` with all 27 at once | Sheet displayed, **no throw**. HealthKit rejects the *entire* request with `errorInvalidArgument` if *any* member is not readable on the platform, so a clean display proves all 27 are requestable. Per-type: `getRequestStatusForAuthorization` returned `shouldRequest` / `unnecessary` for all 27 — never an error |
| Returns samples or noData, not an error | `HKSampleQuery`, limit 1, 30-day window | The 4 already-granted types returned `ok(samples=0)` — **noData, not an error**. The other 23 returned `authorizationNotDetermined(5)`, which is a *grant* failure, not a *type* failure |

The distinction that carries this spike: HealthKit reports `errorInvalidArgument(3)` for a type
that does not exist on the platform, and `errorAuthorizationNotDetermined(5)` for a real type
nobody has answered for yet. **Zero of the 27 returned code 3.** That is the finding.

## Quantity types

| Identifier | Compiles | In sheet | Read result | Needs NEW prompt | Verdict |
|---|---|---|---|---|---|
| `.stepCount` | yes | yes | `ok(samples=0)` | **no — already granted** | usable |
| `.distanceWalkingRunning` | yes | yes | `notDetermined(5)` | yes | usable |
| `.flightsClimbed` | yes | yes | `notDetermined(5)` | yes | usable |
| `.appleExerciseTime` | yes | yes | `ok(samples=0)` | **no — already granted** | usable |
| `.appleStandTime` | yes | yes | `notDetermined(5)` | yes | usable |
| `.activeEnergyBurned` | yes | yes | `ok(samples=0)` | **no — already granted** | usable |
| `.basalEnergyBurned` | yes | yes | `notDetermined(5)` | yes | usable |
| `.vo2Max` | yes | yes | `notDetermined(5)` | yes | usable |
| `.restingHeartRate` | yes | yes | `notDetermined(5)` | yes | usable |
| `.heartRateVariabilitySDNN` | yes | yes | `notDetermined(5)` | yes | usable |
| `.respiratoryRate` | yes | yes | `notDetermined(5)` | yes | usable |
| `.oxygenSaturation` | yes | yes | `notDetermined(5)` | yes | usable |
| `.distanceSwimming` | yes | yes | `notDetermined(5)` | yes | usable |
| `.distanceCycling` | yes | yes | `notDetermined(5)` | yes | usable |
| `.dietaryWater` | yes | yes | `notDetermined(5)` | yes | usable |
| `.timeInDaylight` | yes | yes | `notDetermined(5)` | yes | usable |
| `.physicalEffort` | yes | yes | `notDetermined(5)` | yes | usable |
| `.environmentalAudioExposure` | yes | yes | `notDetermined(5)` | yes | usable |

## Category types

| Identifier | Compiles | In sheet | Read result | Needs NEW prompt | Verdict |
|---|---|---|---|---|---|
| `.handwashingEvent` | yes | yes | `notDetermined(5)` | yes | usable |
| `.mindfulSession` | yes | yes | `notDetermined(5)` | yes | usable |
| `.appleStandHour` | yes | yes | `notDetermined(5)` | yes | usable |
| `.toothbrushingEvent` | yes | yes | `notDetermined(5)` | yes | usable |
| `.sleepAnalysis` | yes | yes | `ok(samples=0)` | **no — already granted** | usable |
| `.highHeartRateEvent` | yes | yes | `notDetermined(5)` | yes | usable |
| `.lowCardioFitnessEvent` | yes | yes | `notDetermined(5)` | yes | usable |
| `.appleWalkingSteadinessEvent` | yes | yes | `notDetermined(5)` | yes | usable |

## Workouts

| Identifier | Compiles | In sheet | Read result | Needs NEW prompt | Verdict |
|---|---|---|---|---|---|
| `HKWorkoutType.workoutType()` | yes | yes | `notDetermined(5)` | yes | usable |

Workout **counts by activity type** are therefore reachable: read `HKWorkoutType.workoutType()`
and bucket the returned `HKWorkout` samples by `workoutActivityType`. A single read grant covers
every activity type — there is no per-activity authorization. Not separately verified against real
workout samples, because the Simulator has none.

## Authorization: what is already granted vs what needs a new prompt

Already granted, via `HealthAuthorization.swift` (`HealthMetric` enum, four cases):

- `.stepCount` · `.activeEnergyBurned` · `.appleExerciseTime` · `.sleepAnalysis`

Confirmed by the probe: these four alone reported `status=unnecessary` and read without error.
**All 23 other identifiers reported `status=shouldRequest` and need a new authorization prompt.**

This matters for US-059. On watchOS, re-requesting an expanded read set shows the sheet again but
**does not revoke the existing grant** — the four already-answered types come back as
`unnecessary`. US-059 should widen the `HealthMetric` enum rather than build a second store.

Note also: `Info.plist` already carries `NSHealthShareUsageDescription`; no new usage-description
key is needed for additional *read* types.

## Limits: what this spike could NOT establish

Recorded plainly rather than guessed, because US-061 will build on this.

1. **No identifier is certified as "has data".** The Simulator's health database is empty — even
   the four *granted* types returned `samples=0`. So the third verdict value, *"compiles but never
   has data"*, could not be assigned to anything, and equally **could not be ruled out for
   anything**. Types whose data is typically iPhone- or feature-sourced rather than watch-sourced
   (`.toothbrushingEvent`, `.handwashingEvent`, `.dietaryWater`, `.timeInDaylight`,
   `.environmentalAudioExposure`, `.lowCardioFitnessEvent`, `.appleWalkingSteadinessEvent`) are the
   plausible risks here, but that is *reasoning, not measurement* — none of it was observed.
2. **The sheet's per-row contents were not read visually.** `simctl` cannot synthesise a tap, and
   the watchOS sheet opens on an intro screen behind a "Review" button. The per-type evidence is
   the API's own `shouldRequest` / no-`invalidArgument` result, which is stronger than a screenshot
   anyway.
3. **The Simulator cannot grant health access.** `simctl privacy` has no `health` service on
   Xcode 26.4.1, so the read path for the 23 new types is unexercised end-to-end.

**Recommendation for US-061:** anchor the primary evolution criteria on the four already-granted
metrics plus the watch-native movement types (`.distanceWalkingRunning`, `.flightsClimbed`,
`.appleStandTime`, `.appleStandHour`, `.basalEnergyBurned`, workouts), which the watch generates
itself. Treat anything in the risk list above as a *bonus* branch that must degrade gracefully to
"criterion never met" rather than gating a mainline evolution — because if it turns out to be
empty on real hardware, a Digimon depending on it becomes unreachable.
