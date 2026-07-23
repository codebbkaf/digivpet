# Background wild-battle nudge (US-205)

A player who walks 500+ steps into their map should be *told* there is a wild Digimon
waiting, even before they open the app. This is that notification — and, just as
important, this is why it is **best-effort and carries no timing guarantee.**

## The one hard constraint: watchOS does not promise a schedule

There is no guaranteed background-execution interval on watchOS. The app *asks* to be
woken — through `WKApplication.scheduleBackgroundRefresh` and through HealthKit
observer queries — and the system grants those wakes **when it chooses**, budgeting
them against battery, usage patterns and everything else on the watch. So the whole
feature is opportunistic by construction: a crossing may be announced within minutes,
or not until the next wake the system happens to grant, or not until the player opens
the app themselves.

- **Requested cadence:** `BackgroundRefreshSchedule.interval` = **30 minutes**, re-armed
  after every refresh (`BackgroundRefreshCoordinator.scheduleNext`). That is a *request*,
  not a promise — see the comment on that constant, and `docs/widget-refresh-granularity.md`
  for the measured reality of watchOS refresh budgeting.
- **The timelier path:** a HealthKit observer wake (`healthDataChanged`) fires when new
  steps actually land, which is usually sooner than the next scheduled refresh. It runs
  the same background refresh, so it can raise the same nudge.

Nothing about correctness rides on any of this. The encounter itself is re-derived from
the saved step counter the instant the app is foregrounded (US-201), so a nudge that
never fires costs only the nudge — never the battle.

## What actually happens

`MainScreenModel.refresh(background:)` is the one refresh path both a foregrounding and a
background wake run. The `background` flag changes exactly one thing, at the very tail:

| Path | Tail behaviour |
|---|---|
| Foreground (app in front) | `checkForWildEncounter()` — raise the on-screen BATTLE/FLEE dialog. |
| Background (BGAppRefreshTask or observer) | `notifyWildEncounterIfDue()` — raise a local notification. |

They are mutually exclusive: there is no screen to draw a dialog on in the background, and
no reason to nudge a player who is already looking at the app. `BackgroundRefreshCoordinator`
passes `background: true` from both `performRefresh()` and `healthDataChanged()`.

`notifyWildEncounterIfDue()` reads the **same** trigger as the foreground check — 500 steps
into the map past `PlayerProfile.encounterMarker` — under the **same** guards (a pending
encounter, battle, round, training, evolution or memorial; no map selected; a dead Digimon).
A boss due at the same time therefore takes precedence, exactly as it does for the dialog.

## No double-scheduling, across process death

The notification fires **at most once per threshold crossing.** A crossing is keyed by the
`encounterMarker` it is measured from, and that marker only moves when an encounter *resolves*
(flee / win / loss). So:

1. A background wake finds the crossing due and delivers the notice.
2. It stamps `PlayerProfile.wildBattleNotifiedMarker` with the current marker **and saves.**
3. Any later background wake — even after the app process was killed and relaunched, since the
   stamp is persisted — finds the same marker already stamped and stays silent.
4. When the player finally acts, the encounter resolves, the marker moves, and the *next* fresh
   500 steps is a new crossing that nudges again.

Because the request identifier is `wildBattle` (the kind's raw value), a re-post would coalesce
rather than stack anyway; the saved marker is what stops it re-*alerting* every 30 minutes.

The stamp is taken **only on actual delivery.** A crossing the sleep window or a switched-off
toggle held back is left un-stamped, so it is still owed and gets its nudge from a later wake
rather than being silently spent.

## Gates

- **Toggle.** `Wild Battles` in the notification settings; default on. Off suppresses it entirely.
- **Sleep window.** `NotificationKind.wildBattle.firesWhileAsleep` is **false** — a "go and
  battle" at 3am is a notice at the one hour it cannot be acted on, and unlike the death warning
  nothing is lost by holding it. The next background wake past the window raises it.

## Tapping it opens the dialog

Tapping the notification launches the app. The app's foreground refresh re-derives the encounter
from the saved counter (US-201) and puts the BATTLE/FLEE dialog up — no deep-link plumbing of its
own is needed, because a local notification launching the app is enough. Surfacing that dialog
also withdraws the now-stale nudge (`notifications.cancel(.wildBattle)`), the same way cleaning
withdraws the mess notice.

## Simulator limitations (for whoever verifies this by hand)

Background verification cannot be done in the Simulator with any fidelity:

- **HealthKit is empty in the Simulator**, so no step samples ever cross 500 on their own — the
  observer path has nothing to observe. The tests seed the map counter directly and call
  `refresh(background:)`; that is the honest way to prove the logic, and it is what
  `WildBattleNotificationTests` does.
- **`scheduleBackgroundRefresh` is not honoured on a real schedule in the Simulator.** You can
  force one BGAppRefreshTask from Xcode's Debug ▸ Simulate Background Fetch, but the ~30-minute
  cadence and the system's budgeting are hardware behaviour a simulator does not model.
- The end-to-end "watch notices 500 steps on its own and buzzes your wrist" path is therefore a
  **device-only** check. Everything decidable without the OS scheduler is covered by the tests.
