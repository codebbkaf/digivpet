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
  "line": "agumon",
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
| `line` | string | yes | Which evolution line the node belongs to, e.g. `agumon`, `patamon`. The Dex draws one tree per line. Convention: the `id` of the line's Child-stage Digimon. Required and never blank — a node with no line appears in no tree, and nothing at runtime would say so. Unlike `dexOnly` and `evolutions` this has **no default**: omitting the key fails the whole load. |
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

## Branching and converging

Both fall out of the shape rather than needing special support:

- **Branching**: give a node several edges with different `requiredEnergy` values. The engine
  picks by dominant energy, and among several qualifying edges, the highest `minEnergy` wins
  (most specific).
- **Converging**: several nodes may name the same `to`. Nothing enforces one parent — edges are
  stored on the parent, so `EvolutionGraph.parents(of:)` scans for them.

`line` is display grouping only; no validator rule ties it to edges. A branch that stays in the
family keeps the family's line (Meramon is `agumon`, not its own line), so the Dex draws it as a
branch of that tree rather than a one-node tree of its own.

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
prose — three nodes have one today, all in the `patamon` line.

## Current contents

`Resources/evolutions.json` holds 37 nodes across four `line` values — `agumon` (8 nodes),
`gabumon` (7), `palmon` (7) and `patamon` (15) — each a complete line from Digitama through
Ultimate.

The first three are US-008's seed. `agumon` includes Meramon as the target of its one branching
node (Agumon → Greymon on strength, or → Meramon on stamina, converging back at MetalGreymon).

`patamon` is US-044's Digital Monster Color V3 line and is much wider: Patamon branches five ways
into Unimon / Centalmon / Ogremon / Bakemon / Scumon, which converge into three Perfects
(Andromon, Giromon, Etemon) and three Ultimates (HiAndromon, Gokumon, BanchoLeomon). Two things
about it are worth knowing before editing it:

- **Its Baby I is Puttimon, not the V3 tree's Poyomon.** Poyomon is one of the 157 idle-only
  Digimon, so it may never be playable. See the `comment` on the `puttimon` node.
- **Five Champions, four energy types.** Scumon — the V3 tree's junk evolution — is the
  `isDefault` edge rather than an earned one, and shares Bakemon's `vitality` gate from below on
  `minEnergy`. A neglected Patamon lands on Scumon; a well-raised vitality one still gets Bakemon.
