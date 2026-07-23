# PRD: Screen Polish, Wild Battles, Map Bosses, and the Metric Ledger

## Introduction

This PRD collects a batch of UX polish and gameplay features for the main screen, plus one
urgent crash fix. The main screen is reworked so the room is smaller and the chrome is a two-row
action grid; the three energy bars (STEP / KCAL / EXER) come off the screen now that they are
already converted into train points and battle time, and the map's own step progress takes their
place as a dash bar. Two new encounters are added — a *wild battle* that greets the player when
they have walked far enough since the last one, and a per-map *boss* that gates the next map — and
the map's residents hide behind "?" until you have actually met them. Finally the step/calorie/sleep
accounting is double-checked and documented so metrics are never counted twice.

## Goals

- Ship the urgent fix first: tapping the Dex book must never crash.
- Make the main screen calmer: a shorter room, a two-row action grid, a settings gear, and only the
  two dash-bar readings that still matter (map steps and sleep).
- Turn each spendable resource's progress into a ring drawn around the button that spends it.
- Add a wild-battle encounter and a map-boss encounter that use the player's walked steps.
- Show map residents as "?" until met; reveal art once met.
- Add a visible Digimon age ("1Y") and guarantee step/metric accounting is never doubled.

## User Stories

### US-193: Fix the Dex crash — one shared GameStore, not a second one
**Description:** As a player, I want to open the field guide without the app crashing, so I can browse the Dex.

**Context:** `ContentView.swift:310` builds `DexView(model: DexModel())`, and `DexModel`
(`DexModel.swift:236`) defaults `makeStore` to `{ try GameStore() }` — a *second* `GameStore` on
the same file. `DigiVPetApp.swift:10` documents exactly why this is illegal: a second store opens a
second `ModelContext`, and a `GameState` fetched through one context is invalidated when the other
context is reset, which is the crash: `SwiftData/BackingData.swift:835: This model instance was
destroyed by calling ModelContext.reset`.

**Acceptance Criteria:**
- [ ] Opening the Dex from the top-right toolbar does not crash — verified in the simulator by tapping the book (or launching with `-dexDemo`) and navigating in and back out repeatedly.
- [ ] `DexView`/`DexModel` reuse the single app-wide `GameStore`/`ModelContext` (injected from the same source `MainScreenModel` uses) rather than constructing a fresh `GameStore()`.
- [ ] No code path constructs a second `GameStore` on the live store file at runtime; the `DigiVPetApp.swift:10` single-store invariant is upheld.
- [ ] A regression test proves a `GameState` read through the Dex path stays valid after the main screen's context does its normal work (no use-after-reset).
- [ ] Build green; existing tests pass.

### US-194: Shorter room, and the action row sits 12 from the bottom
**Description:** As a player, I want the Digimon play area a little shorter and the buttons closer to the bottom edge, so the screen feels balanced.

**Acceptance Criteria:**
- [ ] The Digimon play-area (sprite slot) height is reduced by a small, deliberate amount from its current value (document the before/after constant in `ContentView.swift`).
- [ ] The action row's bottom padding is exactly `12`.
- [ ] The Digimon still walks within its slot and the scrim (US-112) still covers only that slot.
- [ ] Build green. Verify layout in the simulator with a screenshot.

### US-195: Dash bars read as one solid bar split by 2pt lines
**Description:** As a player, I want the dash bars to look like one bar divided by thin lines, not a row of spaced-out dashes.

**Context:** `DashBar.swift:45` uses `spacing: 2` between rounded-rect dashes.

**Acceptance Criteria:**
- [ ] Dashes touch — there is no gap between adjacent segments (segment spacing is 0).
- [ ] Adjacent segments are separated by a divider line of width `2` (a 2pt rule/inset between fills), so the boundary is still legible.
- [ ] All existing `DashBar` callers (sleep Zz bar, stat bars, map-step bar) render correctly with the new look.
- [ ] Build green. Verify in the simulator with a screenshot.

### US-196: Energy bars leave the screen; map-step and Zz dash bars stay
**Description:** As a player, I want the main screen to show only the two readings that still matter — my progress in the current map and my sleep — since steps/calories/exercise are already spent into train points and battle time.

**Context:** `EnergyBarsView.swift` renders the STEP/KCAL/EXER rows plus the Zz sleep `DashBar`.
`MapStripView.swift:49` shows a `figure.walk` symbol and a `progressText` step count.

**Acceptance Criteria:**
- [ ] The STEP, KCAL, and EXER energy bars are removed from the main screen.
- [ ] The current map's step progress is shown on the main screen as a `DashBar` (map recorded steps / map total steps).
- [ ] The main screen shows exactly two dash-bar lines above the action area: line 1 = map steps, line 2 = Zz (sleep).
- [ ] The `figure.walk` travelling icon and the step-count wording are removed from the map strip.
- [ ] Build green. Verify in the simulator with a screenshot.

### US-197: A two-row action grid with new icons and a circular Light
**Description:** As a player, I want the actions laid out in two rows with clearer icons.

**Context:** `ActionControls.swift` currently renders one row (feed `fork.knife`, train `dumbbell`,
clean `sparkles`, battle `bolt.fill`). The Light button today lives in the toolbar (US-114).

**Acceptance Criteria:**
- [ ] Row 1: **Feed**, **Train**, **Clean**, **Battle**.
- [ ] Clean uses a "shit"/waste icon (e.g. an SF Symbol reading as droppings) instead of `sparkles`.
- [ ] Battle uses a "fight" icon (e.g. a combat symbol) instead of `bolt.fill`.
- [ ] Row 2: **Map**, **Party**, **Light**, **Book (Dex)**.
- [ ] The Light control is a circular button matching the other action buttons' style (same `ActionButtonFace` treatment), not the old toolbar switch.
- [ ] All eight buttons share one consistent circular look and spacing across the two rows.
- [ ] Build green. Verify in the simulator with a screenshot.

### US-198: A settings gear in the top-right holds notification settings
**Description:** As a player, I want a Settings screen behind a gear in the top-right, and notifications configured there instead of from a button in the action row.

**Context:** `ActionControls.swift:114` and `ContentView.swift:333`/`:654` place a `bell` button that
opens `NotificationSettingsView`.

**Acceptance Criteria:**
- [ ] A gear button (`gearshape`) sits in the top-right toolbar and opens a Settings screen.
- [ ] The Settings screen contains the notification settings (reusing `NotificationSettingsView`) as its only section for now.
- [ ] The old `bell` notifications button is removed from the action row.
- [ ] Notification settings still persist and behave exactly as before, just reached via the gear.
- [ ] Build green. Verify in the simulator with a screenshot.

### US-199: Consumption rings around the button that spends them, handwash goal = 8
**Description:** As a player, I want each spendable resource shown as a ring around its button, so I see how full it is at a glance.

**Context:** Today the red (train) / purple (battle) / blue (handwash-clean) progress reads as dash
bars on the action row. `ConsumptionConfig.swift:85` sets `handwashPerCleanCharge`.

**Acceptance Criteria:**
- [ ] Train progress is a **red** ring around the Train button.
- [ ] Battle-time progress is a **purple** ring around the Battle button.
- [ ] Handwash/clean progress is a **blue** ring around the Clean button.
- [ ] Each ring is segmented (a circular version of the dash bar) and surrounds its own button.
- [ ] The handwash goal is raised to **8**, so the clean ring is drawn as **8 segments**.
- [ ] The old straight dash bars for these three resources are gone from the row.
- [ ] Build green. Verify in the simulator with a screenshot.

### US-200: A Digimon's age shown as "1Y" beside the battle record
**Description:** As a player, I want to see how old my Digimon is, counted as one year per real day since it hatched.

**Acceptance Criteria:**
- [ ] Age = whole real days from the Digitama hatch time to now; each elapsed day is one year.
- [ ] The age is shown as e.g. `1Y` on the top line, immediately after the battle win/loss numbers.
- [ ] Age is computed from the injectable clock (a freshly hatched Digimon reads `0Y`; after one injected day, `1Y`).
- [ ] A test drives the clock forward and asserts the displayed year increments once per day.
- [ ] Build green. Verify in the simulator with a screenshot.

### US-201: A wild battle greets you after 500 more steps
**Description:** As a player, when I open the app having walked at least 500 steps since my last encounter, I want to be challenged to a wild battle I can accept or flee.

**Acceptance Criteria:**
- [ ] On app foreground/open, if `currentMapSteps - lastEncounterSteps >= 500`, a dialog offers **BATTLE** or **FLEE** against a wild (non-`GameState`) Digimon from the current map.
- [ ] The 500-step threshold is measured against the map-step reading recorded at the previous encounter, and the encounter marker is updated whenever an encounter resolves.
- [ ] **FLEE**: the Digimon plays its sad/refuse animation and the current map's recorded steps decrease by 500.
- [ ] **BATTLE** then losing: the current map's recorded steps decrease by 500.
- [ ] **BATTLE** then winning: no step penalty; the wild Digimon counts as *met* for this map (see US-202/US-203).
- [ ] The clock and step source are injectable; tests drive the trigger, flee penalty, and loss penalty without waiting real time.
- [ ] Build green. Verify in the simulator with a screenshot.

### US-202: Map residents are "?" until you meet them
**Description:** As a player, I want a map's Digimon to appear as "?" until I have met them (by wild encounter or 500-step meeting), then show their art.

**Context:** `MapDetailView.swift` already draws a "?" for undiscovered slots.

**Acceptance Criteria:**
- [ ] A map Digimon shows its sprite only once *met*; otherwise it shows "?".
- [ ] "Met" is set both when you fight it (win *or* the encounter simply occurred) and when a 500-step meeting surfaces it — both paths count.
- [ ] Met state persists across launches (stored on the save, not in view state).
- [ ] A test asserts an unmet resident renders "?" and a met one renders art.
- [ ] Build green. Verify in the simulator with a screenshot.

### US-203: Each map has a boss that gates the next map
**Description:** As a player, once I have walked the whole map and met every resident, I want to fight the map's boss to actually finish the map and unlock the next one.

**Acceptance Criteria:**
- [ ] The boss dialog appears the first time the player has (a) reached the map's total steps AND (b) met every resident of the map.
- [ ] The dialog's only action is **BATTLE** (no flee).
- [ ] The boss is the highest-stage Digimon of that map.
- [ ] **Win**: the map is marked truly finished and the next map unlocks.
- [ ] **Lose**: the current map's recorded steps decrease by 1000 (the player must keep walking); the boss can be re-challenged once the conditions hold again.
- [ ] Until the boss is beaten, the map is *not* counted as finished even if step total was reached.
- [ ] The clock/step source are injectable; tests cover the trigger conditions, the win-unlock, and the 1000-step loss penalty.
- [ ] Build green. Verify in the simulator with a screenshot.

### US-204: Step/metric accounting is never doubled, and it is documented
**Description:** As a developer, I want a written, tested guarantee that steps, calories, exercise, and sleep are only ever credited once.

**Context:** `EnergyLedger.swift`, `MetricLedger.swift`, `ComplicationSnapshot.swift:101`, and the
`GameSession` machinery already exist to prevent double-crediting.

**Acceptance Criteria:**
- [ ] The accounting reads *today's* cumulative metric, compares it to the locally stored baseline, and credits only the positive delta — never the raw total.
- [ ] Re-opening the app within the same day with an unchanged metric credits **zero** (proved by a test).
- [ ] A metric that increases credits only the increase; a day rollover re-baselines without back-crediting yesterday.
- [ ] A README section (e.g. `README.md` or `docs/metric-accounting.md`) explains the today's-delta approach and how each of steps/calories/exercise/sleep avoids double counting, pointing at the ledger types that enforce it.
- [ ] Any gap found while double-checking is fixed (or, if none, the note says the code already enforces it and cites the tests).
- [ ] Build green; accounting tests pass.

### US-205: Best-effort background step check that can raise a wild-battle notification
**Description:** As a player, I want the watch to occasionally notice I have walked 500+ steps and nudge me with a notification to battle, even before I open the app.

**Note:** watchOS does not guarantee fixed-interval background execution. This is explicitly
*opportunistic* — a `BGAppRefreshTask`/widget-timeline refresh that fires *when the system allows*,
targeting roughly every 30 minutes, with no timing guarantee. Documented as such.

**Acceptance Criteria:**
- [ ] A background refresh (BGAppRefreshTask and/or widget timeline reload) reads current steps and, if `>= 500` since the last encounter, schedules a local notification inviting the player to battle.
- [ ] The notification does not double-schedule for the same threshold crossing and does not fire while an encounter is already pending.
- [ ] The 30-minute cadence is requested but documented as opportunistic/no-guarantee in code comments and the README.
- [ ] Tapping the notification opens the app to the wild-battle dialog (US-201).
- [ ] Build green. Manual note in `progress.txt` on simulator limitations for background verification.

## Functional Requirements

- FR-1: Dex must share the single app-wide `GameStore`/`ModelContext`; never open a second store on the live file.
- FR-2: Reduce sprite-slot height; set action-row bottom padding to 12.
- FR-3: `DashBar` segments touch with a 2pt divider line, no spacing.
- FR-4: Remove STEP/KCAL/EXER bars; render map-step and Zz as the two main-screen dash bars; remove the map walking icon and step wording.
- FR-5: Two-row action grid — [Feed, Train, Clean(waste icon), Battle] / [Map, Party, Light(circular), Book].
- FR-6: Top-right gear opens a Settings screen containing notification settings; remove the bell action.
- FR-7: Train/Battle/Clean progress render as red/purple/blue segmented rings around their buttons; handwash goal = 8 (8-segment ring).
- FR-8: Show Digimon age as `<n>Y` after the battle record, one year per real day since hatch, off the injectable clock.
- FR-9: On app open, if map steps advanced ≥500 since last encounter, show a wild BATTLE/FLEE dialog; flee → sad anim + map steps −500; battle loss → map steps −500.
- FR-10: Map residents show "?" until met (encounter or 500-step meeting); met state persists.
- FR-11: Per-map boss (highest stage) with a BATTLE-only dialog once steps complete AND all residents met; win unlocks next map; loss → map steps −1000; map not finished until boss beaten.
- FR-12: Credit only today's positive metric delta against a stored baseline; document the anti-double-count approach in a README.
- FR-13: Best-effort background step check (~30 min, opportunistic) that raises a wild-battle local notification; tapping it opens the wild-battle dialog.

## Non-Goals

- No guaranteed background execution interval (watchOS forbids it).
- No redesign of the battle engine itself; wild/boss battles reuse the existing battle flow.
- No new map content beyond wiring bosses to existing map rosters.
- No changes to how metrics are *converted* into train points / battle time — only to how they are *counted* and *displayed*.

## Design Considerations

- Reuse `ActionButtonFace` for all eight action buttons and the circular Light.
- Reuse `DashBar` (as a ring variant) for the consumption rings and the map-step bar.
- Reuse `NotificationSettingsView` inside the new Settings screen.
- Reuse `MapDetailView`'s existing "?" affordance for unmet residents.

## Technical Considerations

- The single-store invariant is the crux of US-193; audit every `GameStore()` construction site.
- Encounter/boss/age logic must take the injectable clock and a fixture step source so tests never wait real time (HealthKit is empty in the simulator).
- Persist last-encounter step marker, per-map met set, and boss-defeated flag on the save models (`MapProgress`/`GameState`), migrating cleanly.

## Success Metrics

- Zero Dex-open crashes.
- Main screen shows exactly two dash bars and a two-row grid; screenshots confirm.
- Wild and boss encounters trigger at the correct step thresholds in tests.
- No metric is ever credited twice (tests + README).

## Open Questions

- Exact SF Symbols for the "waste" (Clean) and "fight" (Battle) icons — pick the closest-reading symbols available in the deployment target.
- Whether the boss should be re-fightable immediately on loss or after re-meeting conditions (spec: after conditions hold again).
