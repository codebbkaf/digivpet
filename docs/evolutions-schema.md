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

## Digitama hatch edges

A Digitama's single edge omits `requiredEnergy`. Hatching (US-018) fires on **total** energy
across all four types, so no one type gates it, and naming one here would be data that lies —
a later reader would eventually "fix" the engine to respect it and break hatching. `nil` means
"no dominant-type gate", and it is valid **only** on a Digitama's edge.

The rest of the edge stays meaningful: `minEnergy` is the 50-point hatch threshold, and
`maxCareMistakes` is deliberately permissive (99) because US-018 gates hatching on energy alone.
The edge's real job is to name which Baby I this egg hatches into.

## Current contents

`Resources/evolutions.json` holds one partial line — `Agu_Digitama → Botamon → Koromon →
Agumon`, terminal at Agumon. US-008 seeds the three full lines (Agumon, Gabumon, Palmon, each
Digitama through Ultimate, with a branching node); US-010 generates node boilerplate for the
rest of the roster from the sprite filenames.
