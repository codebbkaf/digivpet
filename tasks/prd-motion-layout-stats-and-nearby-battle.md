# PRD: Wandering Motion, Screen Layout, Stat Visibility, and Nearby (Watch-to-Watch) Battle

## Introduction

Five loosely-related improvements to the Digimon Health V-Pet, gathered because they were requested together:

1. **Wandering motion** — the Digimon should pace in discrete, randomised steps (not a fixed
   wall-to-wall ping-pong), sometimes turning back partway across the floor, and should occasionally
   break its walk with a brief expression (anger, happiness, etc.).
2. **Bars and button rings** — the map-progress and sleep (Zz) readings, which currently ride on
   dash-rings around the Map and Sleep buttons, move back to flat 2px dash bars drawn under the map
   background; the ring borders come off those two buttons.
3. **Action grid + scroll** — the action buttons are re-chunked into rows of **4 / 3 / 4**, the whole
   main screen scrolls so buttons are easier to tap, and the Light button leaves the grid for the
   top-left toolbar, styled to match the top-right Settings gear.
4. **Stat visibility** — the Party screen rows show each Digimon's **current** HP/ATK/AGI as dash
   bars; the Dex detail sheet's stat block gains **numeric values** and shows the **maximum** each
   stat can reach (`base + trainingCap`) alongside the current value.
5. **Nearby battle** — two Apple Watches battle each other with **no backend**: they discover and
   connect over the local network (Bonjour / Network.framework), exchange their Digimon's battle
   stats, and both run the existing deterministic battle resolution locally so each shows the same
   replay.

## Goals

- Make the wander read as a living creature pacing, not a metronome — discrete steps, unpredictable
  turns, occasional expression, with no change to the injectable-clock testability the codebase
  relies on.
- Restore the map-step and sleep readings as thin (2px) bars under the map, and de-clutter the Map
  and Sleep buttons by removing their rings.
- Improve tap ergonomics: 4/3/4 button rows, a scrollable main screen, and a toolbar Light control.
- Let the player actually read a Digimon's HP/ATK/AGI — current values everywhere, and the trainable
  ceiling in the Dex detail.
- Ship a peer-to-peer battle between two nearby watches that needs no server, reusing the existing
  battle engine so the fight is deterministic and identical on both wrists.

## User Stories

### US-301: Wandering motion advances in discrete steps with randomised reversals
**Description:** As a player, I want my Digimon to wander in step-by-step moves that don't always go
wall-to-wall — sometimes it walks a few steps toward the middle and turns back — so it feels alive
rather than mechanical.

**Acceptance Criteria:**
- [ ] `MovementModel` no longer turns *only* at `±bound`: it may choose a reversal at an interior
      position, producing runs of a few steps in one direction then a few in the other.
- [ ] Reversal decisions are driven only by the injected `seed` (deterministic): the same seed +
      the same sequence of `advance(to:)` dates produces the exact same path, so tests never wait
      real time. No `Date()`, no `.random` inside `advance`.
- [ ] Movement is still integrated in whole `MovementModel.step` (0.25s) units, and
      `maximumCatchUpSteps` catch-up behaviour is preserved (a long gap is still forgiven, not paid
      back as a sprint).
- [ ] `offset` is still clamped to `-bound...bound` at all times; the Digimon can never walk off
      screen and a shrink of `bound` still pulls it back in.
- [ ] The step is still constant speed on screen (`pointsPerSecond`), so a view redrawing at any
      cadence walks the same path — two 0.5s advances land where four 0.25s advances do.
- [ ] New/updated tests in `Tests/` assert: (a) a known seed produces at least one interior
      reversal within N steps, and (b) two different seeds produce different paths, and (c) the
      determinism property above.
- [ ] Build green: `xcodebuild build -project DigiVPet.xcodeproj -scheme DigiVPet -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'`.
- [ ] `xcodebuild test ...` passes.

### US-302: The Digimon breaks its walk with brief expressions
**Description:** As a player, I want my walking Digimon to occasionally show a mood — anger, happiness
— so it has personality beyond pacing.

**Acceptance Criteria:**
- [ ] While wandering, the sprite occasionally plays a short non-walk animation (at minimum `angry`;
      may include `happy`) for a brief beat, then returns to walking.
- [ ] The expression uses the existing sprite frames only (grid indices from `CLAUDE.md`: `happy`=7,
      `angry`=8, `hurt`=9/10). It is drawn with `.interpolation(.none)` like all sprite art.
- [ ] The choice of when/which expression is deterministic given the injected seed/clock — a test can
      reproduce it without waiting real time; no wall-clock randomness in the model layer.
- [ ] Expressions never fire while the Digimon is sleeping, eating, sick, dead, an unhatched egg, or
      behind an overlay (they ride only on the ordinary wandering state, `isWandering == true`).
- [ ] The expression does not move the sprite's position — the walk resumes from where it stood.
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass, and a `-*Demo` launch flag (following the existing DEBUG-demo pattern in
      `ContentView`) can stage the expression so it is screenshottable in the watchOS Simulator.
- [ ] Verify in watchOS Simulator with a screenshot showing the expression frame mid-wander.

### US-303: Map-step and Zz bars return as 2px dash bars under the map
**Description:** As a player, I want the map-progress and sleep readings shown as thin bars under the
map background again, so I can read them without decoding a ring around a button.

**Acceptance Criteria:**
- [ ] Two `DashBar`s are drawn under the map background inside the play-area band: one for
      map-progress (`recordedSteps` / `totalSteps` from `MapStrip`) and one for sleep
      (`sleepHours` / `sleepHoursCap`), matching the tints they had on their rings (green / indigo).
- [ ] Each bar's height is **2 points** (`dashHeight: 2`).
- [ ] The bars sit beneath the map background layer visually (under the Digimon's play area), not in
      the action grid.
- [ ] Bars are hidden/degrade gracefully when there is no map selected (0 of 0 draws nothing, as the
      ring did) and before the first layout pass.
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass.
- [ ] Verify in watchOS Simulator with a screenshot showing both 2px bars under the map.

### US-304: Remove the dash-ring border from the Map and Sleep buttons
**Description:** As a player, I want the Map and Sleep buttons to be plain circles like the others,
since their readings now live under the map.

**Acceptance Criteria:**
- [ ] The `DashRing` around the Map button and the `DashRing` around the Sleep button are removed in
      `ActionControls`; both render as plain `ActionButtonFace` circles.
- [ ] No other button loses or gains a ring (Feed/Train/Battle/Clean rings, if present, are
      untouched).
- [ ] The map-step and sleep values are no longer passed into the ring for these two buttons (dead
      parameters cleaned up or left only where still used by US-303's bars).
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass.
- [ ] Verify in watchOS Simulator with a screenshot showing plain Map and Sleep buttons.

### US-305: Action buttons re-chunk into rows of 4 / 3 / 4
**Description:** As a player, I want the action buttons laid out in rows of 4, then 3, then 4, so the
grid is balanced and easy to scan.

**Acceptance Criteria:**
- [ ] `ActionGridLayout` (or its replacement) lays the buttons out as row 1 = 4 buttons, row 2 = 3
      buttons, row 3 = 4 buttons (11 slots total after Light leaves the grid in US-307 — confirm the
      exact count against the current button set and document it; if the count differs, the PRD's
      4/3/4 intent stands and the final row absorbs the remainder).
- [ ] Buttons remain within `ActionButtonFace.diameter` sizing rules and do not clip on the narrowest
      supported screen (176pt wide, Apple Watch 41mm).
- [ ] A pure layout test asserts the row split (4/3/4) and that every button is present exactly once.
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass.
- [ ] Verify in watchOS Simulator with a screenshot showing the 4/3/4 rows.

### US-306: The main screen scrolls
**Description:** As a player, I want to scroll the whole main screen so the action buttons come up
into easy reach for tapping.

**Acceptance Criteria:**
- [ ] The main `digimon` content (`ContentView`) is wrapped so the play area + stats + action rows
      can scroll vertically when they don't all fit, bringing the buttons closer to the thumb.
- [ ] Scrolling does not break the map background / scrim / poop anchoring (`SpriteSlotBoundsKey`) —
      the map, dim scrim and mess still align to the play-area band after layout.
- [ ] Overlays (ceremony, battle, wild encounter, memorial, training) still cover the full screen and
      are not affected by the scroll.
- [ ] The Digimon's play area still gets a sensible size (it does not collapse to nothing inside the
      scroll view).
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass.
- [ ] Verify in watchOS Simulator with a screenshot showing the scrolled-down state with buttons in
      reach.

### US-307: Light button moves to the top-left toolbar, styled like the gear
**Description:** As a player, I want the room-light control in the top-left corner, matching the
Settings gear in the top-right, so both utility controls sit in the toolbar.

**Acceptance Criteria:**
- [ ] The Light control is removed from the action grid and added as a `ToolbarItem` at
      `.topBarLeading` in `ContentView`.
- [ ] Its icon style matches the Settings gear (plain SF Symbol `Image`, same weight/treatment — no
      filled circle background), e.g. a `lightbulb`/`lightbulb.fill` symbol reflecting the current
      `lightState`.
- [ ] Tapping it still cycles the light exactly as `model.cycleLight()` did from the grid button.
- [ ] It carries an accessibility label ("Light" or the current state) like the gear's "Settings".
- [ ] The action grid no longer contains a Light button (accounted for in US-305's count).
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass.
- [ ] Verify in watchOS Simulator with a screenshot showing the top-left Light and top-right gear.

### US-308: Party rows show current HP / ATK / AGI as dash bars
**Description:** As a player, I want to see each Digimon's current battle stats in the Party list, so
I can compare my roster at a glance.

**Acceptance Criteria:**
- [ ] Each `PartyRow` carries its current HP/ATK/AGI values (current = `effectiveStat`, i.e.
      `base + trained bonus`), resolved without a view (in `PartyRow.rows(...)`), so it is testable.
- [ ] The party row view draws three compact dash bars (HP red, ATK orange, AGI green) using the
      existing `BattleStat` symbols/tints, showing the **current** value only (no max in the list).
- [ ] Rows for a Digitama or a `dexOnly`/statless record draw no stat bars (gracefully absent, as the
      Dex block does when stats are nil).
- [ ] The bars fit the existing narrow party row without clipping the name/stage/status already
      there.
- [ ] A test asserts the current-stat values resolved onto a `PartyRow` for a fixture Digimon
      (including a trained one, so the bonus shows).
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass.
- [ ] Verify in watchOS Simulator with a screenshot of party rows showing the stat bars (reuse the
      `-partyDemo` launch flag).

### US-309: Dex detail shows numeric HP/ATK/AGI values and the trainable maximum
**Description:** As a player, I want the Dex detail stat bars to show actual numbers and how high each
stat can go, so I know a Digimon's ceiling and not just an unlabelled bar.

**Acceptance Criteria:**
- [ ] `StatBarsRow` shows, per stat: the **current** value as a number, and the **maximum** the
      Digimon can reach (`base + trainingCap`) — both readable, e.g. "current / max" text and a bar
      whose filled portion is current out of a total of max.
- [ ] The bar total is `base + trainingCap` (the ceiling) and the filled portion is the current
      value, so an untrained Digimon reads as partially filled toward its cap rather than full.
- [ ] Icons (heart/burst/hare) and per-stat tints are kept; VoiceOver still reads
      "Health: X of Y" style labels reflecting current and max.
- [ ] `DexStatBars` (the no-view resolver) exposes both current and max so the numbers are testable
      without a screen; a test asserts current and max for a fixture stage (with and without training
      bonus if the Dex reflects it, otherwise base vs base+cap).
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass.
- [ ] Verify in watchOS Simulator with a screenshot of the Dex detail stat block showing numbers and
      the max.

### US-310: Nearby-battle transport — discover and connect two watches over the local network
**Description:** As a developer, I need a peer-to-peer transport so two nearby watches can find each
other and open a reliable connection without any backend server.

**Acceptance Criteria:**
- [ ] A transport type (e.g. `NearbyBattleLink`) uses `Network.framework`
      (`NWListener` + `NWBrowser` + `NWConnection`) with a Bonjour service type to advertise, browse,
      and connect one watch to another.
- [ ] Roles: one watch **hosts** (advertises + listens), the other **joins** (browses + connects);
      the API exposes discovered peers and a connect action.
- [ ] Connection state is observable (searching / connecting / connected / failed / disconnected) so
      the UI can reflect it, and a failure or timeout surfaces a readable error rather than hanging.
- [ ] The required `Info.plist`/entitlement keys for local networking + Bonjour are added via
      `project.yml` (NOT by hand-editing `.xcodeproj`); `xcodegen generate` regenerates cleanly.
- [ ] Message framing is defined so a complete stat payload (US-311) is delivered whole (length-
      prefixed or a documented delimiter), not assumed to arrive in one read.
- [ ] The transport is isolated from resolution logic so it can be unit-tested with a fake/in-memory
      channel (no two real radios needed in a test).
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass for the framing/serialization and the observable state transitions over a fake
      channel.

### US-311: Deterministic stat exchange and shared bout resolution
**Description:** As a player, when two connected watches battle, I want both to compute the same fight
locally from each other's Digimon, so the result is fair and identical on both wrists with no server
deciding it.

**Acceptance Criteria:**
- [ ] Each side serializes its combatant (stage, HP/ATK/AGI or `strengthStat`/lifetime energy as the
      existing engine needs, element, display name, sprite ids) into a small `Codable` payload sent
      over the link (US-310).
- [ ] A shared random **seed** is agreed deterministically (e.g. host sends it, or it is derived from
      both payloads) so both devices feed the *same* seed into the existing battle resolution.
- [ ] Both devices run the existing deterministic battle engine (the same code path `pendingBattle` /
      `BattleView` already uses) on `(myCombatant, theirCombatant, seed)` and produce the **identical**
      `BattleBout`/report — a test asserts both sides' reports are equal for the same inputs.
- [ ] The existing `BattleView` replay is reused unchanged to show the fight.
- [ ] No network round-trip is needed *during* the replay — once both payloads + seed are exchanged,
      each device plays out the bout on its own.
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass, including the "both sides identical" determinism test.

### US-312: Nearby-battle entry UI and connection flow
**Description:** As a player, I want a screen to host or join a nearby battle, see the other player,
connect, and drop into the fight.

**Acceptance Criteria:**
- [ ] A new entry point (reached from the Battle button or a dedicated control) offers **Host** and
      **Join**; Join lists discovered nearby peers with their Digimon's name.
- [ ] Selecting a peer / accepting a host connects (US-310), exchanges combatants + seed (US-311),
      then presents the shared `BattleView` replay over the game like the existing battle overlay.
- [ ] Connection status and errors are shown to the player (searching, connecting, failed/timeout,
      opponent left) with a way to cancel/back out cleanly.
- [ ] The nearby battle honours the same gates as a local battle where sensible (e.g. refused while
      the Digimon is an unhatched egg — `isEgg`).
- [ ] The flow tears the link down when the battle ends or the screen is dismissed (no lingering
      advertiser/connection).
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass for the view-model driving the flow (using the fake channel from US-310).
- [ ] Verify in watchOS Simulator with a screenshot of the host/join entry screen (use a DEBUG demo
      flag, since `simctl` cannot pair two real watches or tap).

### US-313: Record the outcome of a nearby battle
**Description:** As a player, I want my wins and losses from nearby battles counted like any other
battle, so my record reflects them.

**Acceptance Criteria:**
- [ ] When a nearby bout ends, the active Digimon's `battleWins`/`battleLosses` are updated exactly as
      a local battle updates them (same `finishBattle` bookkeeping path or an equivalent that writes
      the same records).
- [ ] A draw/disconnect mid-battle is handled by a documented rule (e.g. no record written on an
      aborted connection) and does not corrupt the save.
- [ ] The energy/charge cost of a nearby battle is consistent with the local battle's cost rules (or
      explicitly documented as free — pick one and state it in `notes`).
- [ ] A test asserts the win/loss record is written for a resolved nearby bout and NOT written for an
      aborted one.
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass.

### US-314: The egg hatches after 5 minutes only
**Description:** As a player, I want my Digitama to hatch on a simple, predictable timer — five
minutes — so hatching isn't sped up by walking or energy and I always know when it will happen.

**Acceptance Criteria:**
- [ ] `EggHatcher` hatches a Digitama on the **5-minute wall-clock condition alone**
      (`maximumEggDuration`): the 500-step condition (`stepsToHatch` / `walkedIt`) is removed, and
      the total-energy condition (`earnedIt`, the `>= edge.minEnergy` check) is removed too.
- [ ] `EggHatcher.stepsToHatch` and any now-dead energy/step plumbing in `hatchTarget(...)` are
      deleted (or the signature is trimmed) — no unused parameter is left silently present.
- [ ] The hatch is still evaluated inside `refresh()` / `BackgroundRefresh`, so an app closed on an
      egg and reopened six minutes later still finds a hatched Baby I, and a frozen egg still does not
      age toward the timer (`Freeze.shiftTimeline` behaviour unchanged).
- [ ] The 5-minute check remains `>=` against `stageEnteredAt` with the clock injected — no `Date()`
      inside `hatchTarget`, so tests never wait real time.
- [ ] `EggHatcherTests` (and any suite that previously earned a hatch via energy or steps) is updated
      to the time-only rule: assert an egg does NOT hatch on energy or steps, and DOES hatch at
      exactly 5 minutes. Fix, don't skip — note in the story if any test was genuinely about a removed
      path.
- [ ] Build green (`xcodebuild build ...`).
- [ ] `xcodebuild test ...` passes.

### US-315: A wild encounter during the egg stage auto-flees silently
**Description:** As a player, while I'm still raising an egg, I don't want a BATTLE/FLEE dialog I can't
act on — the egg should just avoid the fight and lose the map steps, with no sad animation it can't
play.

**Acceptance Criteria:**
- [ ] When the active Digimon is an egg (`isEgg == true`), `checkForWildEncounter` does NOT present
      the `pendingWildEncounter` dialog; instead the encounter is auto-fled.
- [ ] The auto-flee applies the same map-step penalty a normal flee does
      (`reduceRecorded(steps: wildEncounterStepInterval, forMap:)` and moves the encounter marker
      forward), and saves — so the counter behaves exactly as a manual flee would.
- [ ] No sad/refuse/recoil animation or "Fled!" pose is shown (an egg has no such frames): the
      `show(.pose(.refuse), motion: .recoil, ...)` call is skipped in the egg path.
- [ ] The wild Digimon is still recorded as met on the map if the existing non-egg flow would record
      it at surface — OR, if simpler and consistent, the egg encounter is skipped before a meeting is
      recorded; pick one and state it in `notes`.
- [ ] A non-egg Digimon's wild-encounter dialog behaviour is unchanged (still BATTLE/FLEE).
- [ ] A test asserts that with an egg active, a due encounter results in the step penalty + marker
      move and NO `pendingWildEncounter` and NO refuse pose, and that a non-egg still gets the dialog.
- [ ] Build green (`xcodebuild build ...`).
- [ ] `xcodebuild test ...` passes.

### US-316: A "Zz" sleep indicator animates in the top-right while sleeping
**Description:** As a player, I want a clear "Zz" sign near the top-right of the screen while my
Digimon is asleep, so I can tell at a glance it's sleeping.

**Acceptance Criteria:**
- [ ] While `model.isAsleep == true`, a "Zz" indicator (emoji 💤 or drawn "Zz") is shown in the
      **top-right** of the main screen with padding from the edges.
- [ ] It is animated (e.g. a gentle pulse/rise/fade loop), reading as active rather than a static
      glyph.
- [ ] It appears only while asleep — it is absent when awake — and does not overlap or fight the
      top-right Settings gear (offset/padded so both are legible, or placed clear of the toolbar).
- [ ] It does not shift the layout of the sprite, stats strip, or action rows (drawn as an overlay,
      like the sick badge).
- [ ] It does not appear over full-screen overlays (ceremony, battle, memorial, training) — those
      still cover it, consistent with how the scrim/badges are layered.
- [ ] Build green (`xcodebuild build ...`).
- [ ] Tests pass, and a `-sleepDemo`-style launch flag can stage the asleep state so it is
      screenshottable in the Simulator.
- [ ] Verify in watchOS Simulator with a screenshot showing the animated top-right Zz while asleep.

## Functional Requirements

- FR-1: `MovementModel.advance(to:)` must produce discrete-step motion with seed-deterministic
  interior reversals (not only wall reversals), preserving constant on-screen speed, whole-step
  integration, catch-up clamping, and `±bound` clamping.
- FR-2: While `isWandering`, the sprite must occasionally play a short seed-deterministic expression
  (at least `angry`) using existing frames, without moving the sprite, and never during
  sleep/eat/sick/dead/egg/overlay states.
- FR-3: Draw a 2px map-progress `DashBar` and a 2px sleep `DashBar` under the map background in the
  play-area band, using their existing green/indigo tints and value sources.
- FR-4: Remove the `DashRing` from the Map and Sleep buttons in `ActionControls`; both become plain
  circles.
- FR-5: Lay the action buttons out in rows of 4 / 3 / 4.
- FR-6: Make the main screen (`ContentView.digimon`) scrollable without breaking play-area anchoring
  or full-screen overlays.
- FR-7: Move the Light control to a `.topBarLeading` toolbar item styled like the Settings gear
  (plain symbol, no circle), still cycling `model.cycleLight()`.
- FR-8: `PartyRow` must carry current HP/ATK/AGI (`effectiveStat`) and the party row view must draw
  three current-value dash bars; statless records draw none.
- FR-9: `StatBarsRow` / `DexStatBars` must show numeric current values and the trainable maximum
  (`base + trainingCap`) per stat, with the bar filled = current out of total = max.
- FR-10: Provide a Bonjour/`Network.framework` transport (`NWListener`/`NWBrowser`/`NWConnection`)
  with host/join roles, observable connection state, framed messaging, and an injectable fake channel
  for tests; declare the local-network + Bonjour keys via `project.yml`.
- FR-11: Exchange `Codable` combatant payloads + a shared seed, and run the existing battle engine on
  both devices to produce identical `BattleBout` reports, reusing `BattleView` for the replay.
- FR-12: Provide a host/join entry UI and connection flow that presents the shared replay and tears
  down the link on completion/dismissal, honouring the egg gate.
- FR-13: Record nearby-battle wins/losses via the same bookkeeping as local battles; define and apply
  a rule for aborted connections and for battle cost.
- FR-14: `EggHatcher` must hatch a Digitama on the 5-minute wall-clock condition **only**; the
  500-step and 50-energy conditions are removed, with the clock still injectable.
- FR-15: When the active Digimon is an egg, a due wild encounter must auto-flee (apply the map-step
  penalty + marker move, save) with no dialog and no refuse/recoil animation.
- FR-16: While `isAsleep`, draw an animated "Zz" indicator in the top-right with padding, as an
  overlay that doesn't shift layout, clear of the Settings gear and beneath full-screen overlays.

## Non-Goals (Out of Scope)

- No backend, cloud, or matchmaking server of any kind (nearby battle is local-network only).
- No cross-internet / not-nearby play, no Game Center (a possible future alternative, explicitly not
  this PRD).
- No live turn-by-turn interactive battle — the fight is a deterministic replay from exchanged stats.
- No phone companion app or WatchConnectivity (this is watch-to-watch, not watch-to-phone).
- No new stat *mechanics* — HP/ATK/AGI and their training caps already exist; this only surfaces them.
- No change to what training does, only to how the resulting stats are displayed.
- No new sprite art — expressions reuse existing sheet frames, and the egg auto-flee plays no
  animation at all.
- No new egg hatch mechanics beyond the timer — energy and steps no longer hatch (US-314); this does
  not change how energy or steps are earned or spent elsewhere.
- The egg auto-flee (US-315) does not add an egg-specific battle — an egg never fights; it only
  avoids the encounter.

## Design Considerations

- Reuse `DashBar` (US-303, US-308) and `BattleStat` symbols/tints (US-308, US-309) so the new stat
  displays match the app's existing visual language.
- The Light toolbar item must visually match the existing gear `ToolbarItem` in `ContentView` (same
  plain-symbol treatment) — the two utility controls should read as a matched pair top-left/top-right.
- Party stat bars are compact (single current value) to fit the existing 41mm row; the Dex detail has
  room for numbers + max.
- Follow the existing DEBUG `-*Demo` launch-flag pattern in `ContentView` for anything that needs a
  Simulator screenshot but can't be reached by `simctl` taps (expressions, party stats, nearby-battle
  entry screen).

## Technical Considerations

- **Testability / clocks:** all motion and expression randomness must be seed/clock-deterministic —
  the codebase forbids tests that wait real time. No `Date()` or `.random` inside model layers.
- **watchOS local networking:** `Network.framework` is the supported path; `NWListener`/`NWBrowser`
  with a Bonjour `NWParameters` service type. Requires `NSLocalNetworkUsageDescription` and
  `NSBonjourServices` in the built `Info.plist` — set via `project.yml`, then `xcodegen generate`;
  never hand-edit `.xcodeproj`.
- **Two-radio problem:** the transport must be behind a protocol so resolution and view-models test
  against an in-memory fake; only manual/dual-device runs exercise real radios.
- **Determinism:** reuse the exact existing battle resolution so a nearby bout and a local bout share
  one code path; the only new inputs are the opponent payload and the agreed seed.
- **Layout regressions:** US-306's scroll and US-305's re-chunk interact with the `SpriteSlotBoundsKey`
  anchoring that positions the map, scrim and poop — verify those still align after the change.

## Success Metrics

- The wander shows visibly varied, non-metronomic paths and occasional expressions in the Simulator,
  with green tests proving determinism.
- Map and sleep readings are visible as 2px bars; Map/Sleep buttons are plain; buttons sit in 4/3/4
  rows; the screen scrolls; Light is top-left.
- A player can read current HP/ATK/AGI in the Party list and current + max in the Dex detail.
- Two watches on a shared local network can discover, connect, and each play out the identical
  battle, with the outcome recorded — no server involved.

## Open Questions

- Exact final button count/order for the 4/3/4 rows once Light leaves the grid (confirm against the
  live button set during US-305).
- Should a nearby battle cost energy/charges like a local one, or be free? (US-313 must pick one and
  record it in `notes`.)
- Which expressions beyond `angry` to include in US-302 (e.g. `happy`), and their relative frequency.
- Should Join list peers by player name, Digimon name, or both (US-312)?
