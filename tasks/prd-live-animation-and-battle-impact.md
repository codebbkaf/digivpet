# PRD: Live animation and battle impact

## Introduction

The Digimon does not look alive enough, and one battle effect is plainly broken.

Three problems, all verified against the code:

1. **Poses are single frames that get nudged around.** `SpriteAnimation` only has real
   two-frame loops for `.idle`, `.eat`, `.sleep`, `.hurt` and `.sick`. Everything else is
   `.still(_)` — one drawing, held. `MainScreenModel` shows `.still(.refuse)` when food is
   refused (`MainScreenModel.swift:972`), `.still(.attack)` / `.still(.angry)` after a
   training round (`:1066`), `.still(.happy)` after cleaning (`:1117`), and `BattleView`
   shows `.still(.attack)` for the attacker (`BattleView.swift:389`). `ActionMotion`
   (US-095) then *displaces* that one drawing — a hop, a lunge, a shake. That is the "same
   image moving up and down" complaint, and it is exactly what the code does.

2. **The battle projectile flies backward on impact instead of disappearing.** In
   `BattleView.run()` (`BattleView.swift:422`), `projectileProgress = 0` is assigned on the
   line immediately before `withAnimation(.easeInOut(duration: 0.15)) { beat = .turn(index) }`.
   SwiftUI sweeps that reset into the animated transaction, so the glyph *animates* from the
   defender back to the attacker over 0.15 s at the start of every exchange. Separately, the
   projectile is drawn for the whole `.turn` beat (`turnDuration` = 1.4 s) while the flight is
   `flightDuration` = 1.1 s, so for ~0.3 s it sits parked on top of the defender before doing
   the backward slide. Both halves read as "the shot bounced back".

3. **The defender's hurt loop is not tied to the moment of impact.** `animation(for:during:)`
   returns `.hurt` for the defender for the *entire* turn — it starts flinching 1.1 s before
   the shot arrives.

Separately, the ticking rectangle widget visible on the watch face is
`RefreshGranularitySpike.swift` — the US-048 measurement instrument, `#if DEBUG` only, whose
file header already says *"Once US-049 has landed, DELETE THIS FILE"*. US-049 has landed. Its
seconds tick because of `Text(entry.date, style: .timer)` (`:100`), which is WidgetKit's native
self-updating text, **not** a timeline repaint — it is not evidence that sprites can be redrawn
every second. The real Digimon complication alternates walk1/walk2 at the measured 5 s cadence
(`ComplicationViews.swift:61`), which reads as sluggish.

## Goals

- Every pose the Digimon can strike is a **two-frame loop**, not a held drawing, so motion
  comes from the art changing rather than only from the sprite being pushed around.
- A battle projectile **disappears the instant it reaches the defender** and never travels
  backward under any circumstance.
- The defender's hurt animation **starts on impact**, so the flinch is caused by the hit
  rather than running in parallel with the flight.
- The watch-face complication animates at **1 s**, the finest cadence US-048 observed, with an
  honest, documented degradation when the reload budget is spent.
- The non-shipping US-048 spike widget is **gone** from the bundle.

## Decisions already made

Answered by the product owner before this PRD was written. Do not re-litigate these:

| # | Decision |
|---|---|
| 1 | Delete the US-048 spike **and** speed up the real complication. |
| 2 | Complication cadence goes to **1 s**, accepting the jitter US-048 measured. |
| 3 | Single-frame poses animate as **pose ↔ walk1**, the V-Pet toy convention. |
| 4 | "Sad" maps to **refuse ↔ walk1** — i.e. it is the *same loop* as refuse, not a new one. |
| 5 | Projectile disappears at impact; defender's hurt loop starts **at that instant**. |

**Consequence of 3+4 worth stating plainly:** there is no `sad` case to add. Frame 6 is
`refuse`, "sad" and "refuse" resolve to the identical two-frame loop, and inventing a second
name for one loop would be two ways to say one thing. The refuse loop *is* the sad loop.

## User Stories

---

### US-102: Two-frame loops for the poses that were held still

**Description:** As a developer, I need `SpriteAnimation` to express "this pose is a loop of the
pose frame and walk1", so that every screen gets moving art from the same mechanism the eat and
sleep loops already use.

The sheet has exactly one drawing each for `refuse` (6), `happy` (7), `angry` (8) and `attack`
(11) — there is no second frame to pair them with, which is why they shipped as `.still(_)`.
Pairing each with `walk1` (0) is what the physical V-Pet does and needs no new art.

Add **one** case, not four: `case pose(SpriteFrame)`, whose `stageFrames` is
`[frame, .walk1]`. A per-pose case list would need a new case and a new switch arm for every
frame someone later wants to animate.

`.still(_)` stays, and stays used, for the poses that are genuinely motionless: the dead
Digimon's held `hurt2` (`MainScreenModel.swift:916`) and the battle result screen
(`BattleView.swift:303`). A corpse must not twitch.

**Acceptance Criteria:**
- [ ] `SpriteAnimation` gains `case pose(SpriteFrame)` with `stageFrames == [frame, .walk1]`, in sheet order, pose frame first
- [ ] `pose(_)` reports `frameDuration == SpriteAnimation.frameDuration` (0.5 s), the shared V-Pet beat
- [ ] `pose(_).eggFrames` is `[]` — an egg cannot look happy or attack, and must fall through to the placeholder exactly as `.still` already does
- [ ] `pose(.walk1)` yields `[.walk1, .walk1]` and is therefore harmless rather than a special case needing a guard
- [ ] `.still(_)` is unchanged and still returns a one-element `stageFrames`
- [ ] `SpriteAnimation` remains `Hashable` and usable in `MainScreenModel.restingPoses`
- [ ] Test: for each of `refuse`, `happy`, `angry`, `attack`, `pose(frame).frames(from:)` on a synthetic stage sheet returns 2 distinct `CGImage`s and the first is the pose frame
- [ ] Test: `SpriteAnimation.frameIndex` over a 2-frame `pose(_)` loop alternates 0,1,0,1 across four consecutive 0.5 s samples
- [ ] Typecheck passes (`xcodebuild build`), tests pass

---

### US-103: The Digimon actually moves when it refuses, trains and celebrates

**Description:** As a user, I want the Digimon's drawing to change while it reacts, so a
refusal or a celebration reads as the creature moving rather than as one picture being shoved
about the screen.

Three call sites in `MainScreenModel`, all currently `.still(_)`. The `ActionMotion` displacement
stays exactly as it is — the two layers compose, and that is the point: the eat loop already
does both (`show(.eat, motion: .chew, …)` at `:970`) and is the model to follow.

**Acceptance Criteria:**
- [ ] `MainScreenModel.swift:972` refusal shows `.pose(.refuse)`, still with `motion: .shake` and the "Not hungry." caption
- [ ] `MainScreenModel.swift:1066` training shows `.pose(.attack)` on a gain and `.pose(.angry)` on none, still with `motion: .lunge` / `.recoil`
- [ ] `MainScreenModel.swift:1117` cleaning shows `.pose(.happy)`, still with `motion: .hop` and the "All clean!" caption
- [ ] The dead Digimon at `MainScreenModel.swift:916` is **still** `.still(.hurt2)` and does not animate
- [ ] `restingPoses` still contains every pose `restingAnimation` can return, so a Digimon leaving one of these action poses settles back correctly
- [ ] Comments claiming these are single held frames — `:1069`'s *"Both poses are single held frames"*, and `:966`'s and `:1116`'s reasoning — are corrected, not left contradicting the code
- [ ] Test: after `feed()` on a full Digimon the model's `animation` is `.pose(.refuse)` and yields 2 frames
- [ ] Test: after a training round the model's `animation` is `.pose(.attack)` (gain) / `.pose(.angry)` (no gain)
- [ ] Test: after `clean()` the model's `animation` is `.pose(.happy)`
- [ ] Existing `FeedMotionTests` / `CleanTrainMotionTests` still pass, updated where they assert `.still(_)`
- [ ] Verify on the simulator: screenshot the celebration pose at two instants 0.5 s apart and confirm the sprite tile pixels differ (the technique `archive/2026-07-20-vpet-enhancements/prd.json` used for US-049)
- [ ] Typecheck passes, tests pass

---

### US-104: The projectile vanishes on impact and never flies backward

**Description:** As a user, I want a shot to hit the other Digimon and be gone, so the exchange
reads as a blow landing instead of a glyph bouncing back to where it came from.

**The bug, precisely.** `BattleView.run()`:

```swift
projectileProgress = 0                                          // meant to snap
withAnimation(.easeInOut(duration: 0.15)) { beat = .turn(index) } // sweeps the reset in
withAnimation(Self.flightAnimation(duration: flightDuration)) { projectileProgress = 1 }
```

The reset and the `beat` change land in the same SwiftUI update, so the reset is animated:
the projectile slides from the defender back to the attacker over 0.15 s. Then it flies out
again. Fixing this needs the reset taken out of any animated transaction — a
`withTransaction` with `disablesAnimations = true`, or a reset that happens while the
projectile is not being drawn at all. The second is preferable because it also fixes the
parked-glyph half of the problem.

**The other half.** The projectile is drawn for the whole `.turn(index)` beat. Since
`flightDuration` (1.1 s) is deliberately shorter than `turnDuration` (1.4 s), it sits on the
defender for ~0.3 s. It must be gone the moment progress reaches 1.

**Acceptance Criteria:**
- [ ] A shot is **not drawn at all** once its flight has completed — no parked glyph on the defender, no reverse travel, not for a single frame
- [ ] `projectileProgress` is reset with animations explicitly disabled, so a future reordering of `run()` cannot resurrect the reverse slide
- [ ] The impact instant is a piece of view state (e.g. `@State private var hasLanded: Bool`) set after `flightDuration` elapses within the turn, so US-105 has something to hang the hurt loop on
- [ ] Consecutive turns by the **same** attacker still each start their shot at the attacker — the case where the backward slide was most visible
- [ ] Turns by **alternating** attackers still fly in the correct direction, per `faces(_:)`
- [ ] `flightDuration < turnDuration` is still asserted, and the ~0.3 s tail is now the beat where the defender flinches with nothing else on screen — the comment at `BattleView.swift:111` is updated to say so
- [ ] A pure, view-free predicate answers "is the projectile visible at elapsed *t* of turn *n*", so this is testable without a screenshot — the pattern `isKnockoutTurn` and `projectileOffset` already establish
- [ ] Test: the predicate is true for `0 < t < flightDuration` and false for `t >= flightDuration` and for `t <= 0`
- [ ] Test: driving `run()` at a fast injected pacing through a multi-turn report, the projectile is never visible at a progress value that decreases between two samples
- [ ] Existing `BattleTests` / `BattleArenaTests` still pass
- [ ] Verify on the simulator: screenshots at ~0.5× and ~1.2× `flightDuration` into a turn — the first shows the glyph in the gap, the second shows no glyph anywhere in the arena
- [ ] Typecheck passes, tests pass

---

### US-105: The defender flinches on impact, and the attacker's swing animates

**Description:** As a user, I want the hit to visibly cause the flinch, and I want the
attacker's swing to be a moving drawing rather than one frame held for the whole exchange.

Today `animation(for:during:)` returns `.still(.attack)` for the attacker (one frame, held for
1.4 s) and `.hurt` for the defender (a real loop, but running from the turn's *start* — the
defender begins flinching a full 1.1 s before anything reaches it).

Both are fixed by making the mapping a function of **whether the shot has landed**, using the
`hasLanded` state US-104 introduces.

**Acceptance Criteria:**
- [ ] `BattleView.animation(for:during:)` gains a landed parameter and stays **static and pure**, so the whole mapping is assertable without a view — the reason it is static today (`BattleView.swift:385`)
- [ ] Attacker plays `.pose(.attack)` (US-102's attack ↔ walk1 loop) for the whole turn, both before and after impact
- [ ] Defender plays `.idle` **before** impact and `.hurt` (hurt1 ↔ hurt2) **after** impact
- [ ] The defender's hurt loop is visibly two alternating frames during the post-impact tail, not one frame held
- [ ] `hasLanded` resets to false at the start of every turn, so turn 2's defender does not begin already flinching
- [ ] The result screen is unchanged: `.still(.happy)` on a win and `.still(.hurt1)` on a loss stay **held** — the fight is over and nothing is hitting it (`BattleView.swift:403-409`)
- [ ] The doc comment at `BattleView.swift:76-80` describing "the ATTACKER holds the attack frame (11)" is rewritten to describe the loop, not the held frame
- [ ] Test: `animation(for: .player, during: turnWherePlayerAttacks, landed: false)` is `.pose(.attack)`; the same with `landed: true` is also `.pose(.attack)`
- [ ] Test: the defender's animation is `.idle` at `landed: false` and `.hurt` at `landed: true`, for both `BattleSide` values
- [ ] Test: across a real multi-turn `BattleReport`, every turn's attacker/defender assignment matches `turn.attacker`
- [ ] Verify on the simulator: screenshots of the defender at two instants ~0.5 s apart after impact show differing sprite pixels
- [ ] Typecheck passes, tests pass

---

### US-106: Delete the US-048 measurement spike

**Description:** As a user, I do not want a debug measurement widget offering itself on my watch
face; as a developer, I do not want dead instrument code that a future iteration might mistake
for a feature.

The spike's own header (`RefreshGranularitySpike.swift:5-19`) says it ships no feature, must not
be built on, and should be deleted once US-049 has landed. US-049 has landed. The deliverable
was the doc, and the doc exists.

**Acceptance Criteria:**
- [ ] `Sources/Complication/RefreshGranularitySpike.swift` is deleted
- [ ] The `#if DEBUG RefreshGranularitySpikeWidget()` entry is removed from `DigiVPetComplicationBundle` (`DigiVPetComplication.swift:22-26`), leaving `DigiVPetComplication()` as the only widget in the bundle
- [ ] `docs/widget-refresh-granularity.md` is **kept** — it is the deliverable — with a line recording that the instrument was removed on this date and that the AOD floor is still unmeasured
- [ ] `grep -rn "RefreshGranularitySpike\|SpikeEntry\|SpikeBand" Sources Tests` returns nothing
- [ ] A DEBUG build succeeds — the spike was DEBUG-only, so a release build passing proves nothing
- [ ] Widget picker on the simulator shows one Digimon complication and no "SPIKE refresh" entry
- [ ] `ComplicationTests` still pass
- [ ] Typecheck passes, tests pass

---

### US-107: One-second complication cadence

**Description:** As a user, I want the Digimon on my watch face to move at a lively pace rather
than shuffling one step every five seconds.

**Read `docs/widget-refresh-granularity.md` before starting.** It is the measurement this
changes, and it says what the risk is. 1 s was *honoured but jittery* — repaint intervals
between 1.00 s and 2.00 s across three passes, with no stable pattern. Frames will sometimes be
served late. The product owner has accepted that.

**The real constraint is the horizon, not the spacing.** US-048 established that a whole
batched timeline is **one** budget charge however many entries it holds. So the reload rate must
not go up when the spacing goes down. Keeping the current 5-minute horizon at 1 s means
`motionEntryCount` goes from 60 to **300**, not the horizon dropping to one minute — a
one-minute horizon would be 1440 reloads a day and would exhaust the budget, at which point
WidgetKit freezes on the last entry and the complication is *worse* than the 5 s version it
replaced.

If 300 entries per batch turns out not to be accepted verbatim, **do not force it**: fall back
to 2 s / 150 entries (the doc's conservative number), write down what was observed, and say so
in `notes`. A steady 2 s beats a stuttering 1 s.

**Acceptance Criteria:**
- [ ] `ComplicationTimeline.frameInterval` is 1 s and `motionEntryCount` is 300, preserving the five-minute horizon
- [ ] `reloadDate(for:from:)` still lands one `frameInterval` past the last entry, so the final frame is held as long as the 299 before it
- [ ] The cadence doc comment (`ComplicationViews.swift:33-58`) is rewritten: it currently argues *for* 5 s over 1 s and would directly contradict the code
- [ ] Held poses (`sleeping`, `sick`, `dead`, `messy`) still emit exactly **one** entry and the `heldRefreshInterval` path is untouched — a Digimon must not appear to walk while asleep or dead
- [ ] Test: `entries(for:from:)` on an animating snapshot returns 300 entries spaced exactly 1 s apart, alternating step parity 0,1,0,1
- [ ] Test: `entries(for:from:)` on each held pose returns exactly 1 entry
- [ ] Test: `reloadDate` is 300 s after start for an animating pose and `heldRefreshInterval` after start for a held one
- [ ] Observe on the simulator that the batch is accepted **verbatim** — chronod logs `entry count: 300` with the authored date range, the same reading US-048 took. If it is coalesced or truncated, record the observed count and fall back to 2 s / 150
- [ ] Verify on the simulator via `-complicationDemo`: two screenshots one second apart show different sprite frames
- [ ] `docs/widget-refresh-granularity.md` gains a short section recording what shipped, the entry count actually accepted, and that AOD remains unmeasured
- [ ] Typecheck passes, tests pass

---

## Functional Requirements

- **FR-1:** `SpriteAnimation` must provide a `pose(SpriteFrame)` case whose stage frames are `[thatFrame, .walk1]`, held at the shared 0.5 s V-Pet beat.
- **FR-2:** `pose(_)` must yield no egg frames, so a Digitama falls through to the placeholder rather than drawing the hatch frame.
- **FR-3:** `.still(_)` must be retained for genuinely motionless poses: the dead Digimon and the battle result screen.
- **FR-4:** The food-refusal, training-outcome and cleaning-celebration poses must each be a `pose(_)` loop, and must keep their existing `ActionMotion` displacement and caption.
- **FR-5:** A battle projectile must not be rendered once its flight duration has elapsed within a turn.
- **FR-6:** A battle projectile must never render at a position closer to its own attacker than it was at the previous sample — no reverse travel, under any turn ordering.
- **FR-7:** The projectile's progress reset must occur outside any animated transaction.
- **FR-8:** During a turn, the attacker must play the attack loop for the whole turn; the defender must play `.idle` until impact and the hurt loop after impact.
- **FR-9:** Impact state must reset at the start of every turn.
- **FR-10:** The frame mapping for a battle turn must remain a static pure function of (side, turn, landed), assertable without instantiating a view.
- **FR-11:** `RefreshGranularitySpike.swift` and its bundle entry must be removed; `docs/widget-refresh-granularity.md` must be kept.
- **FR-12:** The complication timeline must emit 300 entries at 1 s spacing for animating poses, preserving the existing five-minute horizon and therefore the existing reload rate.
- **FR-13:** The complication must continue to emit exactly one entry for `sleeping`, `sick`, `dead` and `messy`.
- **FR-14:** Every sprite drawn anywhere must continue to use `.interpolation(.none)`.

## Non-Goals (Out of Scope)

- **No new sprite art.** Every loop in this PRD is built from the 12 frames that already exist on the 48×64 sheet. Do not draw, generate or commission frames.
- **No `sad` case.** Decision 4 makes sad and refuse the same loop; adding a second name for one loop is out of scope.
- **No animating the complication's `sleeping` / `sick` poses.** They hold one frame today and continue to. Raised in Open Questions, not decided here.
- **No AOD measurement.** It needs real hardware, has needed it since US-048, and still does. Do not attempt it in the Simulator — `docs/widget-refresh-granularity.md` explains why the Simulator is not a trustworthy model of AOD throttling.
- **No sensor-driven complication frames.** Ruled out with reasoning in `tasks/prd-vpet-enhancements.md`; a widget is not a running process. Do not revive it.
- **No change to battle resolution.** `BattleEngine` decides outcomes before the view appears. This PRD touches the replay only — no damage numbers, no HP, no win conditions move.
- **No change to `ActionMotion`.** Its displacement tracks stay exactly as US-095 shipped them. Frame swapping is added *alongside* motion, not instead of it.
- **No new pacing constants for the battle.** `introDuration`, `turnDuration` and `flightDuration` keep their shipped values.

## Design Considerations

**Two independent layers, deliberately.** Frame swapping (which drawing) and `ActionMotion`
(where it sits) are separate and compose. The eat action already does both and is the reference:
`show(.eat, motion: .chew, …)`. Nothing in this PRD should merge them.

**Why pose ↔ walk1 and not something cleverer.** It is what the physical V-Pet does, it works
for all 157+ Digimon without checking any individual sheet, and `walk1` is guaranteed to exist
on every stage sheet by `SpriteSheet.init?`'s own validation. A hand-picked partner per pose
would be a judgement call repeated for every future frame.

**The 0.5 s beat is shared on purpose.** `SpriteAnimation.frameDuration` is what makes idle,
eat, sleep and now the action poses feel like one creature. Only `.sick` departs from it, and it
departs for a stated reason (US-068: a hurt loop at battle pace reads as being hit repeatedly,
not as being ill).

## Technical Considerations

- **Reload budget is the thing that can go wrong in US-107.** Spacing is free; horizon is not. Keep the five-minute horizon. A one-minute horizon at 1 s would be 1440 reloads/day, the budget would be exhausted, and WidgetKit would freeze on the last entry — a *still* sprite, which is worse than the 5 s walk being replaced.
- **The widget extension does not compile `DigimonSpriteView.swift`.** `ComplicationPose` deliberately restates the frame cycles rather than sharing `SpriteAnimation`, and `ComplicationTests` asserts the two definitions agree. US-102 adds a case to `SpriteAnimation`; check whether that agreement test needs extending, and do not try to share the type across the process boundary.
- **`ComplicationPose.messy` holds one frame for a stated reason that this PRD dissolves** — *"its frame is `angry`, and the sheet has no second angry frame to alternate with"* (`ComplicationSnapshot.swift:37`). US-102 supplies exactly such a pairing. Animating `messy` is *not* in scope here, but the comment will be stale; either correct it or note the follow-up.
- **`SpriteSheetCache` decodes and crops once per Digimon.** Adding loops adds no decode cost — every frame is already cropped and cached. Never re-crop per tick.
- **The clock stays injectable.** `SpriteAnimation.frameIndex(at:count:duration:)` is already derived from wall-clock time so a rebuilt view picks up mid-loop. Keep it pure; tests must not wait real time.
- **Battle tests drive `run()` directly** at injected millisecond pacing with a haptic spy. US-104 and US-105 must remain testable that way — no test may wait out a real 1.4 s turn.
- **Verification commands** are in `CLAUDE.md`. Export `DEVELOPER_DIR=/Applications/Xcode_26_4_1.app/Contents/Developer` before any `xcodebuild`, and re-run `xcodegen generate` after US-106 deletes a source file.

## Success Metrics

- Two screenshots 0.5 s apart of any action pose (refuse, attack, angry, happy) differ in the sprite tile's pixels. Today they are identical.
- No screenshot taken at any instant of a battle turn shows a projectile between the defender and the attacker travelling backward, and none shows a projectile after `flightDuration`.
- Two screenshots of the complication one second apart show different frames. Today the frame changes every five seconds.
- The widget picker lists exactly one complication.
- Test count goes up, and the full suite stays green (1256 cases as of US-101).

## Open Questions

1. **Should the complication's `sleeping` pose animate?** `sleep1 ↔ sleep2` is a breathing motion, not walking, so it would not violate US-049's actual constraint ("must not appear to walk"). Deliberately left out of US-107 to keep that story to one variable. Worth a follow-up story.
2. **Should `messy` animate now that `angry ↔ walk1` exists?** Same shape of question. Its one stated blocker is removed by US-102.
3. **AOD repaint rate is still unmeasured** and has been since US-048. Needs a real Apple Watch. At 1 s authored spacing the wrist-down behaviour is completely unknown; the design must not depend on it.
4. **Does the attacker's loop want to be `attack ↔ walk1` or should it hold `attack` at the moment of impact?** US-105 specifies the loop throughout, which is simplest and matches decision 3. If the swing reads better with the attack frame *held* for the ~0.3 s tail, that is a small follow-up, not a change to this story.
