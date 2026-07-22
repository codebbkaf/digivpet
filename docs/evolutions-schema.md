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
prose — twenty-two nodes have one today, in the `dmc-v1`, `dmc-v2`, `patamon`, `piyomon` and
`gazimon` lines.

## Current contents

`Resources/evolutions.json` holds 111 nodes across six `line` values — `dmc-v1` (21 nodes),
`dmc-v2` (23), `palmon` (10), `patamon` (17), `piyomon` (20) and `gazimon` (20) — each a complete
line from Digitama through Ultimate.

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
  and the Dex candidate ceiling with it. V4's Palmon and V5's Gizamon are SIX wide, so expect to
  raise it again.
- **Vegimon replaced Geremon as the junk fallback.** A device tree's junk Champion is the one BOTH
  Rookies fall to — Numemon in V1, Vegimon in V2. Geremon is still reachable and still junk: it is
  Elecmon's overfeeding branch now, and it keeps its own Perfect and Ultimate underneath it.
- **Whamon is a Perfect, not the tree's Champion.** Its only animated sheet lives under `Perfect/`,
  so an Adult node would resolve to no art. It stands beside MetalMamemon rather than beneath it,
  off the same two Champions the document puts on its row. See the `comment` on the `whamon` node.
- **Its last row is a Jogress, not an edge** — the other half of Version 1's. CresGarurumon →
  Omegamon Alter-S with BlitzGreymon lives in `Resources/jogress.json`, which is why
  CresGarurumon is terminal here.

`patamon` is US-044's Digital Monster Color V3 line and is much wider: Patamon branches five ways
into Unimon / Centalmon / Ogremon / Bakemon / Scumon, which converge into three Perfects
(Andromon, Giromon, Etemon) and three Ultimates (HiAndromon, Gokumon, BanchoLeomon). Two things
about it are worth knowing before editing it:

- **Its Baby I is Puttimon, not the V3 tree's Poyomon.** Poyomon is one of the 157 idle-only
  Digimon, so it may never be playable. See the `comment` on the `puttimon` node.
- **Five Champions, four energy types.** Scumon — the V3 tree's junk evolution — is the
  `isDefault` edge rather than an earned one, and shares Bakemon's `vitality` gate from below on
  `minEnergy`. A neglected Patamon lands on Scumon; a well-raised vitality one still gets Bakemon.

`piyomon` is US-045's Digital Monster Color V4 line and has the same five-wide shape: Piyomon
branches into Monochromon / Leomon / Kuwagamon / Coelamon / Mojyamon, converging into Megadramon /
Piccolomon / Digitamamon and then Darkdramon / BloomLordmon / Gankoomon. Three things about it:

- **Its Baby I and Baby II are `piyo_yuramon` and `piyo_tanemon`, not `yuramon` and `tanemon`.**
  The V4 tree roots both this line and Palmon's at Yuramon → Tanemon, and the `palmon` line
  already owned those ids. They are the same Digimon on the same art with line-scoped ids, not
  copies. Sharing the nodes was the alternative and was rejected: `line` is single-valued and the
  Dex draws one tree per line, so a shared node sits in one tree and `EvolutionTreeLayout` drops
  every connector crossing into the other. See the `comment` on `piyo_yuramon`.
- **Two Champions are omitted for want of art** — Kokatorimon (absent entirely) and Nanimon
  (idle-only). Coelamon and Mojyamon, which the V4 tree hangs off its Palmon rookie, fill the gap.
- **Digitamamon is rehomed onto Kuwagamon.** Its only tree parent is Nanimon, which cannot be
  seeded, so it and Gankoomon would be unreachable. Kuwagamon is also this line's `isDefault`
  Champion, so the neglect path is one thread: Piyomon → Kuwagamon → Digitamamon → Gankoomon.

`gazimon` is US-046's Digital Monster Color V5 line and is the widest of the six, because it is
the only one that seeds **both** of its tree's Rookies:

- **Pagumon branches.** It is the first Baby II in the file with two outgoing edges — Gazimon on
  strength (the `isDefault`) and Gizamon on stamina. V3 and V4 dropped their second Rookies;
  this line keeps its, because Deltamon hangs off Gizamon alone and would go unseeded otherwise.
- **Gizamon has no Digitama**, the only Rookie across V3/V4/V5 that does not
  (docs/sprite-availability.md). Hanging it off Pagumon is what makes that a non-problem: reached
  through Gazimon's egg, it needs none of its own.
- **Flymon is the line's only omission** — idle-only, so it may not be named by an edge. That
  leaves both Rookies with five Champions apiece, four of them shared, converging into
  MetalTyranomon / Ex-Tyranomon / Nanomon and then Mugendramon / Gaioumon / Raidenmon.
- **Raremon is the `isDefault` on both Rookies**, sharing each one's strength gate from below. It
  is the V5 tree's junk Champion in the way Scumon is V3's, so unlike Piyomon's Kuwagamon the
  fallback slot has a natural occupant here.
