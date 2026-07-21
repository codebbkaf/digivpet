# PRD: Battle cost, waking the sleeper, and screen clarity

## Introduction

Five changes, three of which reverse a decision the code currently argues for in a comment. Where
that happens this PRD says so and says why, because a story that silently contradicts a written
rationale is how the next iteration ends up reinstating it.

1. **The daily battle cap is the wrong brake.** `BattleLimits.perDay = 5` (`Battle.swift:227`) is
   the *only* thing gating a battle — a battle costs no energy at all. Training costs 5 points of
   Strength or Stamina (`TrainAction.swift:36`). So the two actions are gated by two unrelated
   mechanisms, and the one on battles runs out even when the Digimon is fit and willing. Battles
   should cost energy exactly as training does, and the cap should go.

2. **Prodding a sleeping Digimon does nothing but punish you.** `MainScreenModel` already charges
   the care mistake (`noteWakingEarly()` at `:977`, `:1032`, `:1227`, capped at one per day by
   `recordWakingEarly` — `CareMistakes.swift:210`), but the action is *blocked*. The user pays for
   a disturbance that never happened. The Digimon should actually wake and the action should
   actually run.

3. **The Dex's evolution hints are flattened across every branch**, so tapping the "?" you care
   about tells you nothing specific. `DexView.swift:261-268` argues for this deliberately.

4. **The room light dims the whole screen**, including the button row and the Dex toolbar icon —
   the latter by an explicit `.opacity(1 - model.lightState.dimOpacity)` at `ContentView.swift:288`.
   The light is a lamp in the Digimon's room, not a screen brightness control.

5. **"SLEEP" is the one 5-character energy label** among STEP / KCAL / EXER
   (`GameState.swift:39`), and `EnergyBarLayout.nameWidth` is sized for it
   (`EnergyBarsView.swift:146`), costing every other bar width on a 41mm screen.

## Goals

- A battle is limited by the Digimon's energy, not by a counter that resets at midnight.
- Feeding, training or battling a sleeping Digimon **wakes it and works**, at the cost of one care
  mistake — the cost the game already charges for a disturbance that currently does not occur.
- Tapping an evolution candidate in the Dex reveals **that branch's** conditions.
- The room light dims **the Digimon's room** and nothing else.
- The sleep energy bar's label fits in the space the other three use.

## Decisions already made

Answered by the product owner before this PRD was written. Do not re-litigate these:

| # | Decision |
|---|---|
| 1 | Battle costs **5 points of Strength or Stamina, whichever is richer** — the same rule and the same number as training. The daily cap is deleted. |
| 2 | **All three** actions (Feed, Train, Battle) wake a sleeping Digimon. One consistent rule. |
| 3 | Waking is temporary: the Digimon is awake for the action and for a short grace period, then returns to the sleep loop. The care mistake stays capped at one per day. |
| 4 | Dex: tap a candidate to filter the hint list to that branch; tap again to deselect and return to today's flat all-branches list. |
| 5 | The light scrim covers **only the sprite slot**. Energy bars, name line, action button row and the Dex toolbar icon all stay at full brightness in every light state. |
| 6 | `"SLEEP"` becomes **`"Zz"`** — two characters. |

**Already true, no work needed:** the light button is *already* top-leading in the sprite slot —
`LightLayer` is a `ZStack(alignment: .topLeading)` at `LightButtonLayout.inset = 2`
(`LightSwitchView.swift:23`, `:71`). Nothing moves.

## User Stories

---

### US-108: A battle costs energy, and the daily cap is gone

**Description:** As a user, I want to battle as often as my Digimon has the energy for, so the
limit is something I can act on by moving rather than a counter I wait out.

**What the cap was for, and what replaces it.** `BattleLimits`' comment states its purpose: *"a
win/loss record cannot be farmed into an evolution edge's `minBattleWins` in an afternoon of
tapping."* That concern is real and must not simply be dropped. **The energy cost is the
replacement brake, and it is a stronger one:** energy is credited from HealthKit steps and
exercise minutes (`EnergyRates`), so 20 battles now costs 100 points of Strength/Stamina — real
walking — where 20 taps used to cost nothing but time. The rationale changes; the protection does
not disappear. Say this in the comment that replaces `BattleLimits`.

**One payment rule, not two.** `TrainAction.begin` already implements "charge the richest of
`payableWith`, ties to Strength, spend from `stageEnergy` only, never from `lifetimeEnergy`"
(`TrainAction.swift:82-93`). Battle must not grow a second copy of that. Extract it once and call
it from both.

**Acceptance Criteria:**
- [ ] `BattleLimits` is deleted, along with `GameState.battlesRemaining(now:calendar:)` and `MainScreenModel.battlesRemainingToday` / `battleLimitReason`
- [ ] `GameState.battlesFought(now:calendar:)` is **kept** — `ConditionEvaluator` reads it for `.day`-window battle conditions (`ConditionEvaluator.swift:173`) and those still work
- [ ] A battle costs 5 points, from Strength or Stamina, whichever the Digimon holds more of, ties to Strength — identical to `TrainAction.energyCostPerTraining` and `payableWith`
- [ ] The "charge the richest payable energy" rule exists in **exactly one** implementation, called by both training and battling; `grep` finds no second copy
- [ ] The cost is spent from `stageEnergy` only and never credited back — a battle dismissed halfway has still been paid for, exactly as `TrainAction.begin` documents
- [ ] `lifetimeEnergy` is untouched by a battle
- [ ] A battle with insufficient energy is blocked with a message naming what to do, in the register of `TrainAction`'s "Not enough Strength or Stamina. Move to earn more."
- [ ] Guard order in `MainScreenModel.battle()` is dead → asleep → funds → matchmaking, so a broke Digimon is reported as broke and a sleeping one is handled by US-110
- [ ] A blocked battle opens no minigame and spends nothing
- [ ] `recordBattle` is still untouched by this story: **losing still costs nothing** — no care mistake, no health change (`Battle.swift:234-240`)
- [ ] The `-battleLimitDemo` launch argument (`MainScreenModel.swift:559`, `:576`, `:613`) is removed or replaced with one that empties Strength and Stamina, so the blocked state stays screenshottable
- [ ] Test: six consecutive battles in one local day all succeed given enough energy — the case the old cap forbade
- [ ] Test: a battle with 4 points in both payable energies is blocked and spends nothing
- [ ] Test: a battle with 7 Strength and 6 Stamina charges Strength; with 6 Strength and 7 Stamina charges Stamina; with equal amounts charges Strength
- [ ] Test: `stageEnergy` drops by exactly 5 and `lifetimeEnergy` is unchanged
- [ ] `BattleLimitTests` is deleted or rewritten against the energy rule — not left asserting a cap that no longer exists
- [ ] Typecheck passes (`xcodebuild build`), tests pass

---

### US-109: The Battle button says what it is waiting for

**Description:** As a user, I want the Battle button to tell me why I cannot battle, so "no
battles left today" is not replaced by a button that is simply dead.

`ActionControls` currently disables Battle on `battlesLeft == 0` (`:65`), captions it
`"\(battlesLeft) left today"` below the cap (`:76`), and tints it orange at zero (`:124`). All
three read a counter that US-108 deletes.

**Acceptance Criteria:**
- [ ] `ActionControls.battlesLeft` is gone; the view takes whatever US-108's rule actually needs (e.g. whether the Digimon can afford a battle)
- [ ] Battle is disabled when the Digimon cannot afford the cost, and enabled otherwise
- [ ] The disabled caption names energy, not a daily allowance
- [ ] No caption is shown when a battle **is** affordable — today's "N left today" only appeared below the cap, and a permanent cost label on one of five buttons is noise on a 41mm screen
- [ ] The orange "you have run out" tint applies to the unaffordable state, so the existing visual language is kept rather than a new one invented
- [ ] The Train button's affordance is unchanged — it already gates on the same energy, and the two buttons must now read consistently
- [ ] Test: `isBattleDisabled` is true with 4 points in both payable energies and false with 5
- [ ] Test: the caption is absent when affordable and present when not
- [ ] `ActionControlsTests` updated, not deleted
- [ ] Verify on the simulator: screenshots of the action row affordable and unaffordable, on 41mm, with all five buttons still fitting the row
- [ ] Typecheck passes, tests pass

---

### US-110: Feeding, training or battling wakes a sleeping Digimon

**Description:** As a user, I want prodding my sleeping Digimon to actually wake it and do the
thing, so the care mistake I am charged is for a disturbance that really happened.

**Today the mistake is charged for nothing.** `train()` and `battle()` call `noteWakingEarly()`
and then `return nil`; `feed()` reaches `FeedAction.feed`'s own `guard !isAsleep` and gets
`.blocked`. The user pays and gets no action.

**Where the wake decision goes.** The model wakes the Digimon *first* — records the mistake, sets
the awake marker — and *then* calls the pure action with `isAsleep: false`. This keeps the wake
policy in the one place that has the clock and the store, and leaves `FeedAction.feed` and
`TrainAction.begin` pure and unchanged. Their `guard !isAsleep` arms stay as the contract for any
caller that has not woken the Digimon; update their doc comments to say who calls them and when,
so the arms do not read as dead code to the next iteration.

**The grace period.** 5 minutes awake, then back to the sleep loop — a chosen balance number, not
a derived one, so name it and comment it as such. It must survive a relaunch (a user who force-
quits mid-grace must not find the Digimon asleep again), so it is persisted state on `GameState`,
not a `@Published` field on the model. `updateSleepState()` runs on every `refresh()` and
re-derives `isAsleep` from the sleep window — it must respect the awake marker or it will undo the
wake on the next foreground.

**Acceptance Criteria:**
- [ ] Feeding, training and battling a Digimon inside its sleep window all **proceed** — the meal is eaten, the training round opens, the battle round opens
- [ ] Each of the three records the disturbance via the existing `recordWakingEarly(now:calendar:)` — `stageSleepDisturbances` increments on **every** disturbance, `careMistakeCount` at most **once per local day** (`CareMistakes.swift:210-219`). Neither cap nor counter changes in this story
- [ ] `GameState` gains a persisted awake marker (e.g. `awakeUntil: Date?`) set to `now + wakeGracePeriod` when a sleeping Digimon is woken
- [ ] `wakeGracePeriod` is a named constant of 5 minutes with a comment saying it is a balance number
- [ ] While the marker is live, `isAsleep` is false: the Digimon shows the walk loop, wanders (`isWandering`), and further actions run without a second wake
- [ ] When the marker expires **and** the sleep window still holds, the Digimon returns to the sleep loop with no user action required
- [ ] A later action within the same night wakes it again and increments `stageSleepDisturbances` again, but charges **no** second care mistake that day
- [ ] `updateSleepState()` respects the marker, so a `refresh()` during the grace period does not put the Digimon back to sleep
- [ ] The marker is cleared or ignored once the sleep window has passed, so it cannot leak into the next day
- [ ] A **dead** Digimon still cannot be fed, trained or battled — the death guard sits before the wake, and waking a corpse is not a thing
- [ ] A **sick** Digimon's existing blocks are unchanged
- [ ] Doc comments claiming these actions are blocked while asleep are corrected: `MainScreenModel.swift:1204-1206`, `FeedAction`'s and `TrainAction.begin`'s sleep guards (`TrainAction.swift:61-63`, `:77-79`), and `noteWakingEarly`'s own comment at `:1375-1381`, which currently describes matching a *block*
- [ ] Tests use the **injected clock** and wait for no real time — the grace period is sampled at chosen dates, per `CLAUDE.md`
- [ ] Test: feeding at 02:00 inside the window feeds, charges one mistake, and increments disturbances
- [ ] Test: feed then train then battle in one night → 3 disturbances, exactly 1 care mistake
- [ ] Test: two disturbances on two consecutive nights → 2 care mistakes
- [ ] Test: `isAsleep` is false at wake + 4m59s and true again at wake + 5m01s, given the window still holds
- [ ] Test: a Digimon woken at 06:58 with a window ending 07:00 is simply awake at 07:01 — the marker expiring outside the window changes nothing
- [ ] Test: reloading the model mid-grace (fresh store read) still reports the Digimon awake
- [ ] Test: three disturbed nights reach `Sickness.careMistakesUntilSick` and the Digimon falls ill — the mistakes are real mistakes
- [ ] `SleepStateTests` / `SleepQueryTests` / `CareMistakeTests` updated where they assert the old blocked behaviour
- [ ] Verify on the simulator: screenshot a Digimon inside its sleep window before and after a Feed tap — the second shows the walk loop, not the sleep loop
- [ ] Typecheck passes, tests pass

---

### US-111: Tapping an evolution candidate shows that branch's conditions

**Description:** As a user, I want to tap a "?" in the Dex and be told what *that* one needs, so
the hint list answers the question I asked rather than the union of every question.

**This reverses a documented decision, deliberately.** `DexView.swift:261-268` argues the flat
list is right because a per-branch list "would tell the player exactly how many criteria stand
between them and each unnamed thing." That reasoning stands for the **default** view and is why
decision 4 keeps the flat list as the default. What changes is that the player may now *ask*, one
branch at a time, by tapping. Rewrite that comment to say this — do not leave it contradicting the
code, and do not delete the reasoning, because it is why the default is what it is.

**Acceptance Criteria:**
- [ ] `DexCandidateCell` is tappable, for discovered and undiscovered ("?") candidates alike — the undiscovered case is the whole point
- [ ] Tapping a candidate selects it and the "It wants" list shows **only** that candidate's conditions, in authored order
- [ ] The section heading changes while a branch is selected, so the list is not silently narrower than it looks (e.g. "It wants" → "To become this")
- [ ] Tapping the selected candidate again deselects it and the list returns to the flat all-branches view
- [ ] Tapping a different candidate moves the selection directly, with no intermediate deselect
- [ ] The selected cell is visibly marked, and that marking does **not** reuse the green earned outline or the discovered/undiscovered brightness — those two channels already carry meanings (`DexCandidateCell` doc comment) and a third meaning on either would make an earned-but-unselected cell indistinguishable from a selected one
- [ ] Nothing about the candidate's **name or sprite** is revealed by selecting it — an undiscovered candidate stays a "?" while selected. The Dex still makes you go and find it
- [ ] Selecting a candidate whose edge is unconditional shows a plain line saying it needs nothing, not an empty section
- [ ] Selection resets when the sheet is dismissed and reopened
- [ ] Deduplication across branches applies only to the flat list; a selected branch shows its own conditions untouched
- [ ] `ConditionReveal` and `ConditionHintRow` are unchanged — this story changes which conditions are listed, never how one is worded or how warm it reads
- [ ] Test: with two branches sharing one criterion, the flat list shows it once and each selected branch shows its own
- [ ] Test: selecting, re-selecting and cross-selecting produce the expected condition lists, as a pure function of (selection, candidates) with no view
- [ ] Test: a selected undiscovered candidate's `displayName` appears nowhere in the rendered text
- [ ] Verify on the simulator: screenshots on 41mm of the flat list, a selected branch, and the same branch deselected — with the hint list still reachable below the fold via the existing `-dexTreeDemo`-style debug hook
- [ ] Typecheck passes, tests pass

---

### US-112: The light dims the Digimon's room, not the whole screen

**Description:** As a user, I want turning the light down to darken where the Digimon is, so the
buttons and the Dex stay readable at night.

Two changes. The scrim in `LightLayer` covers the whole screen; confine it to the sprite slot it
already receives as `spriteSlot: Anchor<CGRect>` — the anchor is already there, already resolved
by the drawing `GeometryProxy`, and already used to place the button. And `ContentView.swift:288`
dims the Dex toolbar button explicitly; that line and its comment go.

**Acceptance Criteria:**
- [ ] The scrim is confined to the sprite slot's resolved rect
- [ ] The action button row, the energy bars, the name/message line and the poop pile are at **full brightness** in `semi` and `off`
- [ ] The Dex toolbar button is at full brightness in every light state; `.opacity(1 - model.lightState.dimOpacity)` and the comment above it are removed from `ContentView.swift:282-288`
- [ ] The light button itself is still drawn **above** the scrim and is still legible and tappable at `off` — the ordering `LightLayer`'s doc comment calls "the feature"
- [ ] The light button has **not** moved: still top-leading of the sprite slot at `LightButtonLayout.inset`
- [ ] The scrim still `allowsHitTesting(false)`, so Feed / Train / Clean / Battle / the bell stay tappable through it
- [ ] `LightState.dimOpacity` values are unchanged (`on` 0, `semi` 0.5, `off` per `Light.swift:60`) — this story changes the scrim's *extent*, not its darkness
- [ ] The `dimDuration` fade still applies, and the scrim is still faded rather than removed, so it can animate
- [ ] Before the first layout pass (`spriteSlot == nil`) the scrim draws nothing rather than covering the screen — a nil anchor must not fall back to full-screen
- [ ] The battle, training, ceremony and memorial overlays are still never dimmed — they are applied to the `NavigationStack` and painted above this
- [ ] The lights-out **rule** is untouched: `LightsOutRule` and US-101's care mistake still turn on `LightState`, which this story does not change
- [ ] `LightTests` still pass; add one asserting the scrim's extent is the sprite slot and not the screen
- [ ] Verify on the simulator: screenshots at `on`, `semi` and `off` on 41mm — in all three the five action buttons and the Dex icon are equally bright, and only the Digimon's area darkens
- [ ] Typecheck passes, tests pass

---

### US-113: The sleep bar's label is "Zz"

**Description:** As a user, I want the sleep bar's label to take no more room than the other
three, so the bars get the width instead.

`EnergyType.shortName` returns `"SLEEP"` for `.spirit` (`GameState.swift:39`). It is not
persisted — `rawValue` is, and the comment at `:29` says `shortName` is free to change.

**Acceptance Criteria:**
- [ ] `EnergyType.spirit.shortName` is `"Zz"`
- [ ] `strength` / `vitality` / `stamina` are unchanged: `"STEP"`, `"KCAL"`, `"EXER"`
- [ ] `EnergyBarLayout.nameWidth` is re-sized for the new longest label (4 characters, not 5) and its comment no longer says "wide enough for SLEEP"
- [ ] The width reclaimed goes to the bar, not to padding — the point of the change
- [ ] No label truncates and all four columns still line up at `nameFontSize`
- [ ] VoiceOver is unaffected: the accessibility label is `goal.type.displayName` (`EnergyBarsView.swift:231`), which still says "Spirit". A screen reader must not be handed "Zz"
- [ ] `EnergyBarLayout`'s "two of these fit the narrowest screen" arithmetic still holds and its test still passes
- [ ] The complication is checked: if any complication view draws `shortName`, it is screenshotted too
- [ ] Test: `shortName` for all four cases, asserting the new value and that the other three did not drift
- [ ] Test: the longest `shortName` fits `nameWidth` at `nameFontSize`
- [ ] `EnergyBarsTests` / `DominantEnergyTests` updated where they assert "SLEEP"
- [ ] Verify on the simulator: screenshot the energy bars on **41mm** (the narrow case the width exists for) and on 46mm
- [ ] Typecheck passes, tests pass

---

## Functional Requirements

- **FR-1:** A battle must cost 5 points of energy, charged from Strength or Stamina, whichever the Digimon holds more of, ties to Strength.
- **FR-2:** The cost must be spent from `stageEnergy` only, never from `lifetimeEnergy`, and must never be refunded.
- **FR-3:** There must be no limit on the number of battles per day.
- **FR-4:** The "charge the richest payable energy" rule must have exactly one implementation, shared by training and battling.
- **FR-5:** Losing a battle must continue to cost nothing — no care mistake, no health change.
- **FR-6:** Feeding, training or battling a Digimon inside its sleep window must wake it and perform the action.
- **FR-7:** Waking must increment `stageSleepDisturbances` every time and `careMistakeCount` at most once per local day.
- **FR-8:** A woken Digimon must stay awake for a 5-minute grace period, then return to the sleep loop if the window still holds.
- **FR-9:** The awake marker must be persisted, so it survives a relaunch, and must be respected by `updateSleepState()`.
- **FR-10:** A dead Digimon must not be woken, fed, trained or battled.
- **FR-11:** Tapping a Dex evolution candidate must filter the condition list to that candidate's edge; tapping it again must restore the flat list.
- **FR-12:** Selecting a candidate must not reveal an undiscovered candidate's name or sprite.
- **FR-13:** The light scrim must cover only the sprite slot; the action row, energy bars, name line and Dex toolbar icon must be at full brightness in every light state.
- **FR-14:** The light button must remain drawn above the scrim, legible and tappable at `off`, in the top-leading corner of the sprite slot.
- **FR-15:** `EnergyType.spirit.shortName` must be `"Zz"`, and `EnergyBarLayout.nameWidth` must be re-sized to the new longest label.
- **FR-16:** VoiceOver must continue to announce the full `displayName` ("Spirit"), never the short label.

## Non-Goals (Out of Scope)

- **No change to how energy is earned.** `EnergyRates`, `EnergyLedger` and the HealthKit read set are untouched. This PRD changes what energy is *spent* on.
- **No change to battle resolution or matchmaking.** `BattleEngine`, `BattleMatchmaker`, `BattlePower` and `BattleModifiers` are untouched.
- **No re-balancing of evolution edges.** `minBattleWins` thresholds stay as authored. Whether they need re-tuning now that the cap is gone is an Open Question, not this PRD's work.
- **No change to the lights-out rule.** `LightsOutRule` and US-101's nightly care mistake are unaffected — US-112 changes where the scrim is painted, nothing about what the light *means*.
- **No change to the sleep schedule inference.** `SleepSchedule`, `SleepQuery` and the 22:00–07:00 fallback are untouched. US-110 adds a temporary override of `isAsleep`, not a new way to decide the window.
- **No change to `ConditionReveal`'s wording or warmth levels.** US-111 changes which conditions are listed, never how one reads.
- **No moving the light button.** It is already top-leading.
- **No renaming `EnergyType.displayName`.** Only the short bar label changes.
- **No new sprite art, and no change to any animation.** That is the sibling PRD, `prd-live-animation-and-battle-impact.md`.

## Design Considerations

- **The two "you cannot act" registers already exist and should be reused**: `TrainAction`'s "Not enough Strength or Stamina. Move to earn more." names the remedy, and `ActionControls`' orange tint means "you have run out". US-109 should extend both to Battle rather than invent a third.
- **Waking is a cost the user chooses to pay.** After US-110 the message changes from a refusal to a consequence. Whether the UI *says* anything when it wakes ("Woken early.") is left to the implementer's judgement — but if it does, it must not read as a block, because the action succeeded.
- **The Dex's selection marker needs a third visual channel.** Brightness means discovered-or-not and the green outline means earned-or-not (`DexCandidateCell` doc comment). A background fill, a scale bump, or a border in a non-green colour are all available; a second use of either existing channel is not.
- **A scrim confined to a rect has a hard edge.** Whether it wants a corner radius matching the sprite slot, or a short gradient at its boundary, is a judgement call to settle with a screenshot on 41mm, not with arithmetic.

## Technical Considerations

- **The clock must be injectable**, per `CLAUDE.md`. US-110's grace period is the story where this matters most — no test may wait five real minutes, or five real seconds.
- **`updateSleepState()` runs on every `refresh()`** and re-derives `isAsleep` from the inferred window. The awake marker has to be consulted there or every foreground undoes the wake. This is the single most likely way US-110 ships broken.
- **Seeded fixtures are sensitive to elapsed time.** `progress.txt` records four test files that had to seed the light correctly once US-098 made a new game start lit, because any fixture spanning nights started earning mistakes. US-110 adds another way a fixture spanning a sleep window can earn one. Expect to fix fixtures, and comment each seed that changes with the reason — as those four were.
- **`GameState` is SwiftData.** Adding `awakeUntil` is a schema change; check what the project does about migration (`GameStore`) before assuming a new optional is free.
- **A model-level test must keep the model alive while reading `model.state`** — `progress.txt` records a whole test class crashing on this. Helpers must return the model, not the state.
- **`ConditionEvaluator.battlesToday` survives US-108.** `GameState.battlesFought(now:calendar:)` is what feeds it and is explicitly kept; only `battlesRemaining` goes.
- **Check whether any complication view draws `shortName`** before assuming US-113 is app-only.
- **Verification commands** are in `CLAUDE.md`. Export `DEVELOPER_DIR=/Applications/Xcode_26_4_1.app/Contents/Developer` before any `xcodebuild`.

## Success Metrics

- Six or more battles can be fought in one local day given enough energy; today the seventh is impossible at any energy level.
- Feeding a sleeping Digimon changes the sprite from the sleep loop to the walk loop. Today it changes nothing but the mistake counter.
- Tapping an undiscovered candidate in the Dex changes the condition list, and the candidate's name still does not appear anywhere on screen.
- Screenshots at `off` show the five action buttons and the Dex icon at the same brightness as at `on`.
- The sleep bar's label occupies the same width as "STEP", and the bars are measurably wider on 41mm.
- The full suite stays green and the test count goes up.

## Open Questions

1. **Do `minBattleWins` evolution thresholds need re-tuning now that the cap is gone?** The energy cost is the new brake and it is arguably a stronger one, but no edge was authored against it. Out of scope here; worth a look once US-108 has shipped and the real cost of a battle is visible.
2. **Should the wake grace period be longer than the 2-second action pose?** 5 minutes is a chosen number. If it turns out that a Digimon woken to feed visibly snaps back to sleep before the user has finished looking at it, this is the constant to move.
3. **Should waking say something?** See Design Considerations. Left to implementation, but if two implementers answer it differently across US-110's three actions the result will be inconsistent — decide once.
4. **Should the Dex remember the last selected branch** across sheet dismissals? US-111 says no, on the grounds that a sheet reopening in a filtered state looks like a bug. If it turns out to be tedious in use, that is the line to revisit.
5. **Does the scrim want a corner radius?** Screenshot question, not an arithmetic one.
