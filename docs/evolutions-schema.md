# `evolutions.json` schema

The evolution tree is data, not code. Adding a Digimon means adding a node to
`Resources/evolutions.json` — never editing a Swift file. The Swift models that decode this file
live in `Sources/EvolutionGraph.swift`; `docs/` is not bundled, only `Resources/` is.

The file is a single object with one key:

```json
{ "nodes": [ /* EvolutionNode, ... */ ] }
```

An object (rather than a bare array) so a schema version or roster metadata can be added later
without breaking every decoder.

## Node

```json
{
  "id": "koromon",
  "displayName": "Koromon",
  "stage": "Baby II",
  "line": "dmc-v1",
  "spriteFile": "Koromon",
  "variant": null,
  "dexOnly": false,
  "evolutions": []
}
```

| Field | Type | Required | Meaning |
|---|---|---|---|
| `id` | string | yes | Unique key that edges point at. Separate from `spriteFile` so art can be renamed or shared without rewriting edges. Convention: the sprite basename, lowercased. |
| `displayName` | string | yes | Shown to the user. Stage-disambiguating suffixes (`_Child`, `_Adult`) are stripped here but kept in `spriteFile`. |
| `stage` | string | yes | One of `Digitama`, `Baby I`, `Baby II`, `Child`, `Adult`, `Perfect`, `Ultimate-Super Ultimate`, `Armor-Hybrid`. These are the `Stage` raw values, which are also the sprite subfolder names. |
| `line` | string | yes | Which evolution line the node belongs to, e.g. `dmc-v1`, `patamon`. The Dex draws one tree per line. Two conventions: the `id` of the line's Child-stage Digimon (the older lines), or a device slug for a line that is a whole shipped device tree (`dmc-v1` = Digital Monster Color Version 1, US-133 onward). A device slug names no node, so its heading comes from `DexModel.lineTitles` — add an entry there or the section header shows the raw key. Keep those titles short: a 41mm `navigationTitle` truncates at about fifteen characters. Required and never blank — a node with no line appears in no tree, and nothing at runtime would say so. Unlike `dexOnly` and `evolutions` this has **no default**: omitting the key fails the whole load. |
| `spriteFile` | string | yes | Filename **without** `.png`, under `16x16 Digimon Sprites/<stage>/`. Must exist on disk — US-009 checks. Never blank: `Bundle.url(forResource:)` treats an empty name like nil and returns an arbitrary PNG. |
| `variant` | string | no | Variant suffix parsed off the filename: `X`, `Black`, `Blue`, `Virus`, `2006`, `2010`, `YnK`. Omitted for the base form. Variants are separate nodes, not skins. |
| `dexOnly` | bool | no, default `false` | True for the 157 Digimon that exist only in `Idle Frame Only/` with no animated 48×64 sheet. They may appear in the Dex but must never be playable or named by an edge — animating one means slicing a sheet that does not exist. |
| `evolutions` | edge[] | no, default `[]` | Outgoing edges. Two or more = a branching node. Omitted entirely = terminal. |

## Edge

```json
{
  "to": "greymon",
  "requiredEnergy": "strength",
  "minEnergy": 60,
  "maxCareMistakes": 2,
  "minBattleWins": 3,
  "isDefault": true
}
```

| Field | Type | Required | Meaning |
|---|---|---|---|
| `to` | string | yes | `id` of the node evolved into. |
| `requiredEnergy` | string | yes, except on a Digitama | Which energy type must be **dominant** for this edge to qualify: `strength`, `vitality`, `spirit`, or `stamina`. See "Digitama hatch edges" below for the one exception. |
| `minEnergy` | int | yes | Energy threshold for the edge, against the per-stage total. |
| `maxCareMistakes` | int | yes | The edge is blocked once care mistakes exceed this — neglect closes off the good lines. |
| `minBattleWins` | int | no | Battle wins required. Omitted = ungated, which is most edges. |
| `isDefault` | bool | no, default `false` | Taken when the time gate has passed and nothing else qualifies, so a Digimon is never permanently stuck. Exactly one edge per non-terminal node sets this. |
| `conditions` | condition[] | no, default `[]` | Extra criteria, **all** of which must hold. See "Conditions" below. Omitted on every edge in the file today. |

## Conditions

The four fields above are a fixed set: adding a fifth kind of gate used to mean adding a field to
`EvolutionEdge` and a branch to the engine. A condition instead names its metric **as data**, so a
new criterion is a JSON edit. `conditions` is the single gating vocabulary going forward.

```json
{
  "metric": "care.trainingSessions",
  "window": "stage",
  "comparison": "atLeast",
  "value": 8,
  "hint": "Train at least 8 times"
}
```

| Field | Type | Required | Meaning |
|---|---|---|---|
| `metric` | string | yes | What is measured. One of the vocabulary below — an unrecognised value is a **validator** error, not a decode error, so a typo names itself instead of trapping at launch. |
| `window` | string | yes | `stage`, `day`, or `lifetime`. See below. |
| `comparison` | string | yes | `atLeast` or `atMost`. |
| `value` | number | yes | Threshold in the metric's own unit. Never negative. |
| `hint` | string | yes | One line shown to the player, in their terms. Never blank — a criterion with no hint is undiscoverable, which reads as the evolution being random. |

### Windows

| Value | Span |
|---|---|
| `stage` | Since the Digimon entered its current stage. The default reading of a criterion: what you did to *earn* this evolution, not what you did two forms ago. |
| `day` | Today only, from local midnight. For "10,000 steps in a single day", which a stage-long total would trivially satisfy. |
| `lifetime` | The whole life of this Digimon, across every stage. |

### Metric family: `health.*`

HealthKit-backed. Every one is an identifier US-055 probed and marked **usable** on watchOS 26.4
(`docs/health-metrics.md`); **nothing may be added here without probing it first.**

`health.steps` · `health.distanceWalkingRunning` · `health.flightsClimbed` ·
`health.exerciseMinutes` · `health.standTime` · `health.activeEnergy` · `health.basalEnergy` ·
`health.vo2Max` · `health.restingHeartRate` · `health.heartRateVariability` ·
`health.respiratoryRate` · `health.oxygenSaturation` · `health.distanceSwimming` ·
`health.distanceCycling` · `health.water` · `health.daylight` · `health.physicalEffort` ·
`health.audioExposure` · `health.handwashing` · `health.mindfulMinutes` · `health.standHours` ·
`health.toothbrushing` · `health.sleep` · `health.highHeartRateEvents` ·
`health.lowCardioFitnessEvents` · `health.walkingSteadinessEvents` · `health.workouts`

"Usable" means the type exists and is readable. It does **not** mean it ever carries data — the
Simulator's health database is empty, so no identifier is certified as having any. Seven are
typically iPhone- or feature-sourced rather than watch-sourced (`health.toothbrushing`,
`health.handwashing`, `health.water`, `health.daylight`, `health.audioExposure`,
`health.lowCardioFitnessEvents`, `health.walkingSteadinessEvents`); gate a **bonus** branch on one
of those, never the only way out of a node, or an empty metric on real hardware makes that Digimon
unreachable.

### Metric family: `care.*`

Game counters the engine keeps itself. These exist because nothing in the edge schema could
express them: the four fields above are the whole of the old vocabulary.

| Metric | Unit |
|---|---|
| `care.trainingSessions` | count |
| `care.overfeeds` | count |
| `care.sleepDisturbances` | count |
| `care.battleCount` | count |
| `care.battleWinRatio` | **fraction, 0.0–1.0** — `0.8` is 80%. `80` is rejected by the validator; it would make the edge unreachable forever. |

`care.careMistakes` is deliberately **not** a metric. The edge's `maxCareMistakes` field already
gates on that counter, and two ways to say one thing invites a later iteration to delete one of
them — and to delete the wrong one, because the shipped edges use the field.

`minBattleWins` likewise stays and keeps working. `care.battleWinRatio` *adds* ratio gating, which
a win count cannot express; an edge may use either or both.

### The band idiom

A **band** is two conditions on one metric — `atLeast X` plus `atMost Y`:

```json
"conditions": [
  {"metric": "care.trainingSessions", "window": "stage", "comparison": "atLeast",
   "value": 8, "hint": "Train at least 8 times"},
  {"metric": "care.trainingSessions", "window": "stage", "comparison": "atMost",
   "value": 31, "hint": "But do not train more than 31 times"}
]
```

That reproduces the Digital Monster Color pattern where training 8–31 earns the good branch while
0–7 **and** 32+ both fall through to the junk one: overtraining is punished exactly as much as
undertraining. There is no `between` comparison — two conditions already say it, and a third
spelling of the same idea is a third thing to validate.

The same shape expresses DMC's "15+ battles at 80%+ wins": `care.battleCount atLeast 15` plus
`care.battleWinRatio atLeast 0.8`. A win *count* alone would let 15 wins in 200 battles through.

### What the validator rejects

An unknown `metric`, a negative `value`, a blank `hint`, and a `care.battleWinRatio` outside
0.0–1.0. An unknown metric suppresses the range rules on that condition — an unrecognised metric
has no unit, so `value` cannot be judged against one.

## Branching and converging

Both fall out of the shape rather than needing special support:

- **Branching**: give a node several edges with different `requiredEnergy` values. The engine
  picks by dominant energy, and among several qualifying edges, the highest `minEnergy` wins
  (most specific).
- **Converging**: several nodes may name the same `to`. Nothing enforces one parent — edges are
  stored on the parent, so `EvolutionGraph.parents(of:)` scans for them.

`line` is display grouping only; no validator rule ties it to edges. A branch that stays in the
family keeps the family's line (Meramon is `dmc-v1`, not its own line), so the Dex draws it as a
branch of that tree rather than a one-node tree of its own.

In practice a line IS a closed tree, even though nothing enforces it: `EvolutionTreeLayout` drops
any connector whose target it did not place, so an edge leaving its line is an arrow the Dex
simply does not draw. When a tree needs a Digimon another line already owns, give it a
line-scoped id on the same art rather than pointing across — `piyo_yuramon` (US-045) and
`dmcv1_shinmonzaemon` (US-133) and `dmcv2_vademon` / `dmcv2_ebemon` (US-134) are the shipped
examples.

## Digitama hatch edges

A Digitama's single edge omits `requiredEnergy`. Hatching (US-018) fires on **total** energy
across all four types, so no one type gates it, and naming one here would be data that lies —
a later reader would eventually "fix" the engine to respect it and break hatching. `nil` means
"no dominant-type gate", and it is valid **only** on a Digitama's edge.

The rest of the edge stays meaningful: `minEnergy` is the 50-point hatch threshold, and
`maxCareMistakes` is deliberately permissive (99) because US-018 gates hatching on energy alone.
The edge's real job is to name which Baby I this egg hatches into.

## Generating nodes

`scripts/import_roster.py` derives `id`, `displayName`, `stage`, `spriteFile`, `variant` and
`dexOnly` for all 1,022 Digimon. It does **not** derive `line` — nothing in a sprite filename
says which family a Digimon belongs to — so a generated node must be given one by hand before it
is promoted into this file, exactly as `stage: null` must be resolved (see below) from the sprite filenames, and carries hand-authored
`evolutions[]` over on a re-run. It never authors an edge — no artifact in this project holds
evolution data. See README.md for what it derives and what it deliberately refuses to guess.

It writes `roster.generated.json`, **not** this file: `Resources/evolutions.json` is curated, and
regenerating it wholesale would swap three playable lines for ~1,000 terminal nodes.

One generator convention is **not** part of this schema: a `dexOnly` node whose stage is unknown
is emitted as `"stage": null`. `stage` is required and non-optional here, so such a node does not
decode — give it a stage before promoting it into this file. README.md has the detail.

## Comments

JSON has no comment syntax, so a node may carry a **`comment`** string. It is not a schema field:
`EvolutionNode`'s `CodingKeys` do not mention it, so the decoder never reads it and it costs
nothing at runtime. Use it where the data departs from the source evolution trees in
`Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, so the next reader diffing the
two finds the reason in the file rather than in a commit message. It is not a place for general
prose — 166 nodes have one today, in the `dmc-v1`, `dmc-v2`, `dmc-v3`, `dmc-v4`,
`dmc-v5`, `penc-nsp`, `penc-ds`, `penc-nso`, `penc-wg` and `penc-me` lines.

## Current contents

`Resources/evolutions.json` holds 270 nodes across eleven `line` values — `dmc-v1` (21 nodes),
`dmc-v2` (23), `dmc-v3` (20), `dmc-v4` (21), `dmc-v5` (20), `palmon` (10), `penc-nsp` (30),
`penc-ds` (31), `penc-nso` (31), `penc-wg` (31) and `penc-me` (32) — each a complete line from
Digitama through Ultimate.

`palmon` is what is left of US-008's seed. `dmc-v1` was the second of them: US-008
authored it as `agumon`, a pruned Digital Monster Color Version 1 tree, and US-133 renamed it and
filled the rest of that tree in. Renaming rather than opening a second line beside it is the
point — Botamon, Koromon, Agumon, Greymon, Meramon, Numemon and MetalGreymon were already here,
and a `dmc-v1` line holding only the new nodes would have been a tree whose every arrow crossed a
line boundary and so was never drawn. Three things about it:

- **Its second Rookie is Swimmon, not the V1 tree's Betamon.** Betamon is one of the 157
  idle-only Digimon. Airdramon and Seadramon hang off Betamon alone in the tree, so without a
  stand-in they could not be seeded at all. See the `comment` on the `swimmon` node.
- **Tyranomon is absent entirely**, the one V1 name with no colour sheet anywhere in the asset
  pack — only a monochrome `Black and White Sprites/Adult/Tyranomon.png`, which the roster does
  not index. Mamemon, its Ultimate in the tree, is reached through Meramon and Seadramon instead.
- **Both MetalGreymon are here.** The V1 tree's Ultimate is MetalGreymon (Virus), a separate
  sprite and a separate id; the Vaccine one US-008 authored out of Greymon stays beside it, so
  Greymon forks.
- **Its last row is a Jogress, not an edge.** BlitzGreymon → Omegamon Alter-S with CresGarurumon
  lives in `Resources/jogress.json` (US-130), which is why BlitzGreymon is terminal here.

`dmc-v2` is the same story one version along: US-008 authored it as `gabumon`, a pruned Digital
Monster Color Version 2 tree, and US-134 renamed it and filled that tree in. It is the widest line
in the file — every one of the Version 2 names is drawable, so nothing prunes it the way an
idle-only Betamon and a missing Tyranomon pruned Version 1. Four things about it:

- **Gabumon and Elecmon are five-wide.** The document gives each Rookie five Champions and they
  all exist, so US-134 raised the out-degree ceiling in `EvolutionCriteriaTests` from four to five
  and the Dex candidate ceiling with it. V4's Palmon and V5's Gizamon are SIX wide in the document,
  but US-136 found V4's needed no raise — two of Palmon's six have no animated sheet, so its
  drawable row is four. V5's Gizamon is still ahead.
- **Vegimon replaced Geremon as the junk fallback.** A device tree's junk Champion is the one BOTH
  Rookies fall to — Numemon in V1, Vegimon in V2. Geremon is still reachable and still junk: it is
  Elecmon's overfeeding branch now, and it keeps its own Perfect and Ultimate underneath it.
- **Whamon is a Perfect, not the tree's Champion.** Its only animated sheet lives under `Perfect/`,
  so an Adult node would resolve to no art. It stands beside MetalMamemon rather than beneath it,
  off the same two Champions the document puts on its row. See the `comment` on the `whamon` node.
- **Its last row is a Jogress, not an edge** — the other half of Version 1's. CresGarurumon →
  Omegamon Alter-S with BlitzGreymon lives in `Resources/jogress.json`, which is why
  CresGarurumon is terminal here.

`dmc-v3` is the third of the same story: US-044 authored it as `patamon`, a pruned Digital Monster
Color Version 3 tree, and US-135 renamed it and filled that tree in. It was the least pruned of the
three — Patamon's five Champions converging into Andromon / Giromon / Etemon and then HiAndromon /
Gokumon / BanchoLeomon were all already here — so completing it took only three new nodes. Four
things about it:

- **Its Baby I is Puttimon, not the V3 tree's Poyomon.** Poyomon is one of the 157 idle-only
  Digimon, so it may never be playable. It is the ONLY name in the Version 3 section with no
  animated sheet. See the `comment` on the `puttimon` node.
- **Kunemon is the second Rookie, and Tsukaimon is a third the device never had.** US-061 split
  Patamon's five Champions across Patamon and an invented Tsukaimon, because a Child could carry
  only two earned branches then. US-135 put all five back on Patamon, where the document draws
  them, but left Tsukaimon its Ogremon and Bakemon rather than emptying it: a shipped Digimon that
  evolves into nothing is an orphan made by the story whose job is to remove them.
- **Scumon is the junk Champion and Etemon the junk Perfect.** A device tree's junk Champion is the
  one BOTH Rookies fall to — Numemon in V1, Vegimon in V2, Scumon here — so it is the `isDefault`
  edge on all three Children, and shares Unimon's `spirit` gate from below on `minEnergy`.
- **It has no Ultra row at all**, unlike Versions 1, 2 and 4, so all three of its Megas are
  terminal and none of them appears in `Resources/jogress.json`.

`dmc-v4` is the fourth of the same story: US-045 authored it as `piyomon`, a pruned Digital
Monster Color Version 4 tree, and US-136 renamed it and filled that tree in. Completing it took a
single new node — the document's second Rookie — because US-045 had already borrowed that Rookie's
Champions. Six things about it:

- **Three of its names carry line-scoped ids**: `piyo_yuramon`, `piyo_tanemon` and `dmcv4_palmon`.
  The V4 tree roots at Yuramon → Tanemon and its second Rookie IS Palmon, and the `palmon` line
  already owned all three ids. They are the same Digimon on the same art with line-scoped ids, not
  copies. Sharing the nodes was the alternative and was rejected: `line` is single-valued and the
  Dex draws one tree per line, so a shared node sits in one tree and `EvolutionTreeLayout` drops
  every connector crossing into the other. See the `comment` on `piyo_yuramon`.
- **Two Champions are omitted for want of art** — Kokatorimon (absent entirely, not even a
  monochrome sheet) and Nanimon (idle-only). They are the only two names in the Version 4 section
  with no animated sheet.
- **The six-wide Rookie needed no ceiling raise.** The document gives Palmon six Champions, which
  US-134 and US-135 both expected to force the out-degree ceiling past five. It did not: those two
  omissions take the drawable row down to four, which plus the junk fallback is exactly five edges
  — and four earned branches is the hard ceiling anyway, one per energy type.
- **Hyokomon and Muchomon are in no source tree.** US-045 invented them to carry Coelamon,
  Mojyamon and Kuwagamon while the plain `palmon` id was another line's. US-136 gave those
  Champions to `dmcv4_palmon` where the document draws them but left the two invented Children
  their branches, rather than turning them into shipped Digimon that evolve into nothing.
- **Digitamamon is rehomed onto Kuwagamon.** Its only tree parent is Nanimon, which cannot be
  seeded, so it and Gankoomon would be unreachable. It is Kuwagamon's overfeeding branch instead.
- **Its last row is a Jogress, not an edge.** Darkdramon → Chaosmon with BanchoLeomon lives in
  `Resources/jogress.json`, which is why Darkdramon is terminal here. BanchoLeomon is the Version 3
  tree's Mega, so this recipe reaches across two device trees.

`dmc-v5` is the last of the same story: US-046 authored it as `gazimon`, a pruned Digital Monster
Color Version 5 tree, and US-137 renamed it and filled that tree in. It is the widest of the six,
because it is the only one that seeds **both** of its tree's Rookies — and completing it took no
new node at all, only four edges, because US-046 had already seeded every name in the section.
Seven things about it:

- **Pagumon branches.** It is the first Baby II in the file with two outgoing edges — Gazimon on
  strength (the `isDefault`) and Gizamon on stamina. V3 and V4 dropped their second Rookies;
  this line keeps its, because Deltamon hangs off Gizamon alone and would go unseeded otherwise.
- **Gizamon has no Digitama**, the only Rookie across V3/V4/V5 that does not
  (docs/sprite-availability.md). Hanging it off Pagumon is what makes that a non-problem: reached
  through Gazimon's egg, it needs none of its own.
- **Flymon is the line's only omission** — idle-only, so it may not be named by an edge. That
  leaves both Rookies with five Champions apiece, four of them shared, converging into
  MetalTyranomon / Ex-Tyranomon / Nanomon and then Mugendramon / Gaioumon / Raidenmon.
- **The second six-wide Rookie needed no ceiling raise either.** The document gives Gizamon six
  Champions, and US-136 predicted this one really would force the out-degree ceiling past five
  because Flymon is the section's only art-absent name. It does not: five drawable Champions is
  four earned branches plus the junk fallback, which is exactly five edges.
- **Psychemon is in no source tree.** US-061 invented it as a third Rookie while a Child could
  carry only two earned branches. US-137 gave Gazimon and Gizamon their full rows, which makes
  Psychemon's Devidramon redundant, but it keeps its branches rather than becoming a shipped Child
  that evolves into nothing — the Geremon / Tsukaimon / Hyokomon call, made a fourth time.
- **Raremon is the `isDefault` on all three Rookies**, sharing each one's gate from below. It
  is the V5 tree's junk Champion in the way Scumon is V3's, so unlike Piyomon's Kuwagamon the
  fallback slot has a natural occupant here.
- **Its last row is a Jogress, not an edge.** Mugendramon → Chaosdramon with Darkdramon lives in
  `Resources/jogress.json`, which is why Mugendramon is terminal here. Darkdramon is the Version 4
  tree's Mega, so this recipe reaches across two device trees, as V4's own Ultra row does.

`penc-nsp` is the Pendulum Color V1 Nature Spirits tree (US-138), and it is the first line in the
file that was authored from **nothing**: the five `dmc-v*` lines each renamed a pruned seed line
that US-008/US-044/US-045/US-046 had already written, and there was no Pendulum seed to rename. At
30 nodes it was the widest line here until `penc-ds` and `penc-nso` overtook it by one each.
Six things about it:

- **Twelve of its thirty nodes are line-scoped aliases**, the `piyo_yuramon` pattern at four times
  the previous largest scale. This tree shares twelve Digimon with the Digital Monster Color
  trees — Botamon and Koromon, the whole Agumon → Greymon → MetalGreymon → WarGreymon thread and
  Seadramon with `dmc-v1`, Leomon with `dmc-v4`, and Kabuterimon / Garurumon / WereGarurumon /
  MetalGarurumon with `dmc-v2` — and `line` is single-valued, so a Digimon in two trees is two
  nodes on one roster entry. Each alias needs its own `elements.json` and `moves.json` entry too,
  and the move's `signatureName` is globally unique, so it cannot be copied from the node it
  aliases.
- **Betamon, the document's second Rookie, is idle-only** and may never sit on an edge. That is
  the costliest absence in Phase E so far: dropping it would have stranded Seadramon, Tailmon and
  the four Digimon above them, so its two Champions are rehomed — Seadramon onto Agumon (which is
  where `dmc-v1` already hangs one) and Tailmon onto Angoramon.
- **Its egg is `tento_digitama`, a real roster Digitama, not a scoped one.** `maps.json` grants a
  Digitama by ROSTER id and an alias has no roster entry, so a line rooted at an alias egg could
  never be started by a player however well it was wired. Tento Digitama belongs to Tentomon, one
  of this tree's own Rookies, and was an orphan on `08_jungle` until this story.
- **Its junk chain is this app's invention, not the document's.** The Pendulum Color V1 section
  draws no junk branch at all, while every Child and Adult here needs an `isDefault` edge reachable
  by inaction (US-061). PlatinumScumon → Pumpmon → NoblePumpmon were chosen off unused sheets, so
  the neglect path costs the tree nothing it was already using.
- **AtlurKabuterimon is the Blue sheet.** The document writes the name unqualified and the asset
  pack has both Blue and Red; Wikimon gives Digimon Pendulum Ver.1 Nature Spirits as the Blue
  form's debut and HerakleKabuterimon as its evolution, while Red is Digimon Adventure's.
- **Its Mega row is half Jogress.** "WarGreymon / Omegamon (Jogress)" — Omegamon is the
  WarGreymon + MetalGarurumon recipe in `Resources/jogress.json`, and this is the only line that
  holds BOTH of that recipe's parents.

`penc-ds` is the Pendulum Color V2 Deep Savers tree (US-139), the second line authored from
nothing and, at 31 nodes, tied with `penc-nso` as the widest in the file. It is also the first Phase E tree with **no
absent name**: every one of the twenty-seven Digimon the section draws has a playable 48x64 sheet.
Five things about it:

- **Six of the document's names are not the names the art is filed under**, and that is the whole
  reason the tree is complete. Four have nothing at all under the document's spelling and a real
  sheet under another — Pichimon/`Pitchmon`, Bukamon/`Pukamon`, Syakomon/`Shakomon` and
  Dragomon/`Dagomon` (the Dragomon–Dagomon identification is Wikimon's; the rest are alternate
  romanizations the pack itself uses). Two more have a **dexOnly twin under the document's
  spelling**: `octomon` and `marinedevimon` are idle-only, while `Adult/Octmon.png` and
  `Perfect/MarinDevimon.png` are the animated sheets of the same two Digimon. Taking the document
  at face value would have called four names absent and stranded Pukumon and Leviamon behind two
  dexOnly Champions.
- **Five of its thirty-one nodes are line-scoped aliases** — Coelamon (from `dmc-v4`), Seadramon
  (`dmc-v1`), Whamon (`dmc-v2`), and MegaSeadramon and MetalSeadramon (`penc-nsp`). The last two
  are the first aliases in the file whose plain id belongs to another **Pendulum** tree rather than
  to a Digital Monster one.
- **Its Baby rungs are its own Digimon, not aliases.** Pitchmon and Pukamon belong to no other
  line, which is why this is the first Phase E story to remove an orphan at Baby I or Baby II.
- **Its egg is `goma_digitama`, a real roster Digitama**, for the same reason `penc-nsp`'s is:
  `maps.json` grants a Digitama by ROSTER id and an alias has no roster entry. Goma Digitama is
  Gomamon's, and Gomamon is the Rookie the In-Training falls to by inaction.
- **Its junk chain is this app's invention, not the document's** — the Pendulum sections draw no
  junk branch at all. Diginorimon → Piranimon → MetalPiranimon were chosen off unused sheets, so
  the neglect path pays for itself in orphans; Diginorimon keeps one earned edge back up to
  Zudomon, the way `penc-nsp`'s PlatinumScumon does.

`penc-nso` is the Pendulum Color V3 Nightmare Soldiers tree (US-140), the third line authored from
nothing and the third at 31 nodes. It is the tree where the **respelling** problem is worst and the
first Phase E tree since US-138 with names that are genuinely absent. Five things about it:

- **Fifteen of the section's twenty-eight names are filed under a spelling the document does not
  use.** Six of those the document disambiguates itself, in brackets — Tapirmon (`Bakumon`),
  DemiDevimon (`PicoDevimon`), Apemon (`Hanumon`), SkullMeramon (`DeathMeramon`), Myotismon
  (`Vamdemon`) and PetitMeramon (`PetiMeramon`). The other **nine** it does not, and every one of
  them would have been reported absent by a `find` on the document's spelling alone:
  Candlemon/`Candmon`, Wizardmon/`Wizarmon`, Mammothmon/`Mammon`, SkullMammothmon/`SkullMammon`,
  Pumpkinmon/`Pumpmon`, NoblePumpkinmon/`NoblePumpmon`, VenomMyotismon/`VenomVamdemon`,
  Piedmon/`Piemon` and Soloogamon/`Soloogarmon`. Unlike US-139's, none of them is a dexOnly-twin
  case — they are dub names and romanizations, nothing more.
- **Two names really are absent, and both are on the unlockable sixth slot's thread.** `Loogamon`
  (the Rookie) and `Helloogamon` (the Champion) have no sheet anywhere: `find -iname '*loog*'`
  returns exactly three files — `Adult/Loogarmon.png`, `Perfect/Soloogarmon.png` and
  `Ultimate-Super Ultimate/Fenriloogamon.png` — and `find -iname '*hell*'` returns only Shellmon.
  Wikimon's Loogarmon page puts Loogarmon directly above Loogamon and lists both Soloogarmon and
  Helloogarmon among its evolutions, so `loogarmon` is wired as the rung of that line the art pack
  actually ships and hung under Bakumon beside Garurumon. Without it the thread would have lost
  Soloogarmon and Fenriloogamon too.
- **Ten of its thirty-one nodes are line-scoped aliases**, the worst ratio of any tree, and three
  of them are the file's first **triples**: V2's whole Garurumon → WereGarurumon → MetalGarurumon
  thread is drawn by `dmc-v2`, `penc-nsp` and `penc-nso` alike, so each of those three Digimon is
  three nodes on one roster entry. `pencnso_pumpmon` and `pencnso_noblepumpmon` are the sharpest
  case of why an alias is not merely tidiness: US-138 chose Pumpmon as Nature Spirits' invented
  **junk** Perfect, and the V3 document draws the same Digimon as an **earned** branch above
  Wizardmon. One node could not be both.
- **Its egg is `baku_digitama`, a real roster Digitama** — Bakumon's own, Bakumon being the Rookie
  the In-Training falls to by inaction, and `03_ocean` already drops it, so the line is startable
  without touching `maps.json`.
- **Its junk chain is this app's invention** — Gokimon → Darumamon → Deathmon, all three off
  orphan sheets, with Gokimon keeping one earned edge back up to Phantomon. WaruMonzaemon was the
  first choice for the Perfect rung and had to be dropped: the **Version 5** Metal Empire section
  draws it as an earned Ultimate over Mekanorimon, so it belongs to US-142. Grep the document
  before choosing a junk node.

`penc-wg` is the Pendulum Color V4 Wind Guardians tree (US-141), the fourth line authored from
nothing and the fourth at 31 nodes. It is the first Pendulum tree whose **Rookie rung is drawn
whole** — all four of the section's Rookies have sheets, including the unlockable seventh slot —
and the first whose gaps are in the MIDDLE and at the TOP of threads rather than at the bottom.
Five things about it:

- **Eleven of the section's twenty-eight names are filed under a spelling the document does not
  use**, and the brackets the document supplies are not always right either: `Cherrymon
  (Jureimon)` is on disk as `Jyureimon`, and `Puppetmon (Pinocchimon)` as `Pinochimon`. The rest
  are Yokomon/`Pyocomon`, Biyomon/`Piyomon`, Mushroomon/`Mushmon`, Veedramon/`V-dramon`,
  AeroVeedramon/`AeroV-dramon`, UlforceVeedramon/`UlforceV-dramon`, Lillymon/`Lilimon`,
  Gryphonmon/`Griffomon`, RedVegiemon/`RedVegimon` and Garbagemon/`Gerbemon`.
- **Garbagemon is the dexOnly-twin trap of US-139 again.** Searching the roster by substring finds
  `garbamon` — a DIFFERENT Digimon, idle-only — so the name looks both present and unusable. The
  real sheet is `Perfect/Gerbemon.png`, under the Japanese name. Read every substring hit's
  `dexOnly` AND keep looking.
- **Three names really are absent, and Wikimon supplied a stand-in on the same thread for each.**
  `Deramon` (the Perfect over Kiwimon) has no sheet — `find -iname '*dera*'` over the whole pack
  returns only Thunderballmon — so `Blossomon`, which Wikimon lists both as something Kiwimon
  evolves into and as something Griffomon evolves from, takes that rung. `Crossmon` / `Eaglemon`
  (the Mega over Garbagemon) are equally absent, so `Rafflesimon`, which Wikimon lists as a
  Gerbemon evolution, tops that thread. US-140's rule — price the rehome before dropping a
  thread — applied to a missing middle rung and a missing top one.
- **Six of its thirty-one nodes are line-scoped aliases**, the best ratio of any Pendulum tree, and
  three of them are the file's first whole **three-rung thread** to be scoped: Togemon → Lilimon →
  Rosemon have belonged to `palmon` since US-008 and the V4 Pendulum draws all three over
  Floramon. `pencwg_gerbemon` is the second Pumpmon case — `dmc-v2`'s junk Perfect is this tree's
  earned branch above RedVegimon.
- **Its egg is `flora_digitama`, and it is the first Pendulum egg that is NOT the default Rookie's
  own.** Pyocomon falls to Piyomon, but `piyo_digitama` went to `dmc-v4` in US-136 — the Digital
  Monster Ver.4 tree is Piyomon's too — and one egg cannot root two lines, so the egg is
  Floramon's — `14_farmland` already drops it, beside `piyo_digitama` itself, so `maps.json` was
  not touched. Its junk chain is this app's invention as ever: Zassoumon → TonosamaGekomon →
  ElDoradimon, all three off orphan sheets and all three linked to each other on Wikimon, with
  Zassoumon keeping one earned edge back up to Blossomon.

`penc-me` is the Pendulum Color V5 Metal Empire tree (US-142), the fifth line authored from
nothing and, at 32 nodes, the widest in the file. It is the first tree whose threads MERGE rather
than only fork: Tankmon and Thunderballmon both climb to Knightmon, and Andromon is drawn twice by
the document — once over Revolmon on the way to Machinedramon and once over Guardromon on the way
to HiAndromon — so `pencme_andromon` is the only Perfect in the file with two parents AND two
children. Five things about it:

- **Five of the section's twenty-eight names are filed under a spelling the document does not
  use**: Kapurimon/`Caprimon`, Deputymon/`Revolmon`, Mekanorimon/`Mechanorimon`,
  Machinedramon/`Mugendramon` and VenomMyotismon/`VenomVamdemon`. The dub-name lesson of US-140,
  unchanged.
- **One thread is broken at BOTH ends, and in the two different ways Phase E has met.** `Machmon`
  (the Champion over Rebellimon) IS in the roster and IS on disk — but only under
  `Idle Frame Only/`, so it is `dexOnly` and may never sit on an edge, which is US-139's twin trap.
  `HeavyMetaldramon` (the Mega above it) does not exist in the pack at all. Wikimon supplied a
  stand-in for each on the same thread: `Minotaurmon`, which it lists in Junkmon's *Evolves To* and
  in Rebellimon's *Evolves From*, and `Gundramon`, which it lists in Rebellimon's *Evolves To*.
- **`Chaosdramon` was the other candidate for that Mega and was deliberately left alone.** Line 90
  of the tree document draws it as the Ver.5 Jogress Ultra and `jogress.json` already makes it
  twice. That is the grep US-140's notes demand, run before authoring rather than after.
- **Eight of its thirty-two nodes are line-scoped aliases**, the most of any tree.
  `pencme_greymon` / `pencme_metalgreymon` / `pencme_wargreymon` make Agumon's Champion-and-up the
  file's second whole thread drawn by THREE trees, after US-140's Garurumon one. `pencme_raremon`
  is the third Pumpmon case and the first where the plain id is junk in *both* lines: Raremon is
  `dmc-v5`'s junk Champion and this tree's too.
- **Its egg is `funbee_digitama`, and it belongs to no rung of its own tree.** None of ToyAgumon,
  Kokuwamon, Hagurumon and Junkmon has a Digitama on disk, so all that survives of the rule is "a
  real roster Digitama that a map drops" — `06_industrial`, the machine map, drops this one, so
  `maps.json` was not touched. Its junk chain is this app's invention as ever, and the
  best-supported one yet: Raremon → Locomon → GrandLocomon, every arrow of it drawn by Wikimon,
  which lists Raremon in Junkmon's *Evolves To* and gives Locomon six of this tree's nine
  Champions as prior forms. Raremon keeps one earned edge back up to Rebellimon.
