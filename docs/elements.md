# The two type axes: elements and attributes

US-086. The vocabulary lives in `Sources/DigimonElement.swift` (pure Foundation) and its colours in
`Sources/ElementColors.swift` (SwiftUI), the split `MoveTint` uses. This document is the chart's
prose companion — the code is the source of truth, and `Tests/ElementTests.swift` pins every claim
made here, including the "weak to" column, which is *derived* rather than authored.

Design decision D-2 in `tasks/prd-elements-battle-depth-and-care-polish.md`.

## Why two axes

Every Digimon carries **both**:

| Axis | Values | Origin | Weight |
|---|---|---|---|
| **attribute** | `vaccine` `data` `virus` `free` | canon | a small triangle |
| **element** | twelve, below | this app's invention | the headline |

They are separate fields rather than one merged enum because a Digimon is genuinely both — Agumon
is a Vaccine *and* a Fire type — and merging them would force a choice that throws canon away.

Canon is a source of **flavour** (Agumon breathes fire, so it is `fire`), never a source of
**rules**: the franchise has no consistent elemental chart, so this one is designed here.

Both enums are `String`-backed and `Codable` so `elements.json` (US-087) authors them by name, and a
misspelled value is a **decode failure at load** rather than a silent mis-typing at battle time.

## The element chart

Each row lists what that element beats. "Therefore weak to" is never authored anywhere — it is the
`beats` relation read backwards, so the two halves cannot drift apart.

| Element | Badge | Beats | Therefore weak to |
|---|---|---|---|
| fire | FIRE | plant, ice, steel | water, earth |
| water | WATER | fire, earth, machine | plant, electric |
| plant | PLANT | water, earth | fire, ice, wind, steel, machine |
| electric | ELEC | water, machine, steel | earth |
| ice | ICE | plant, wind | fire, steel, machine |
| wind | WIND | earth, plant | ice |
| earth | EARTH | fire, electric | water, plant, wind |
| steel | STEEL | ice, plant | fire, electric |
| light | LIGHT | dark | dark |
| dark | DARK | light | light |
| machine | MECH | plant, ice | water, electric |
| neutral | NEUT | — | — |

Every element other than `neutral` beats at least one and is beaten by at least one, so **no element
is strictly best or strictly worst** — pick any Digimon and there is both a matchup it wins and one
it loses. That property is pinned by a test rather than left to the eye.

## Why `neutral` is inert

`neutral` beats nothing and is beaten by nothing.

It is the **last-resort fallback** at the bottom of the US-087 lookup chain: a roster-only Digimon
that nobody has hand-authored resolves to `neutral`. A fallback must never hand out an advantage —
otherwise the ~930 unauthored roster entries would all quietly share whatever matchup luck the
fallback element happened to have, and "we forgot to type this one" would become a strategy.

`free` is inert on the attribute axis for exactly the same reason.

## Why light and dark beat each other

That is not a bug in the table. The multipliers are applied to **both** sides, so a mutual advantage
multiplies out to no advantage at all (1.25 × 0.8 = 1.0). It is how "eternal rivals" is expressed in
a ratio-based engine, and it costs nothing: the pair is even, as it should be.

`effectiveness(against:)` therefore reports `.advantage` for **both** directions of light vs dark.
The type answers "am I strong here?", not "who wins?" — cancelling the two out is US-092's
arithmetic (D-4), not the vocabulary's job. A test proves this pair is the *only* mutual one.

## The attribute triangle

```
vaccine → virus → data → vaccine
```

`free` is inert. There are no mutual pairs — a triangle cannot have one, and a test says so.

## `Effectiveness`

`advantage | disadvantage | even`. Three cases, not a multiplier: the numbers belong to
`BattleModifiers` (D-4), so the chart can be re-tuned without touching this vocabulary, and the
vocabulary can be rendered (US-088) without pulling in the battle engine.

## Who is typed what — `elements.json`

US-087. `Sources/ElementCatalog.swift` decodes `Resources/elements.json` and resolves a Digimon's
`DigimonType` (element + attribute) in four tiers, mirroring `MoveCatalog` so there is one lookup
idiom in the codebase:

| Tier | Section | Covers |
|---|---|---|
| 1 | `types`, by `id` | all **88** nodes of `evolutions.json`, hand-authored |
| 2 | `lineDefaults`, by `line` | a node added to a curated line later |
| 3 | `keywordRules`, ordered substrings on the id | 161 roster-only Digimon typed off their name |
| 4 | `DigimonType.unauthored` | the remaining 776, as `neutral`/`free` |

Elements are chosen for **flavour** and agree with the Digimon's authored attack in `moves.json`
(Meramon throws flame, so it is `fire`). They need not be constant down a line — `agumon` fire →
`greymon` fire → `metalgreymon` machine is correct. Attributes follow **canon** wherever canon
exists; the file's `_comment` names every id that was a judgement call instead, so a later reader
can tell the two apart.

The keyword table is **ordered and first-match-wins**, and that ordering is the collision resolver:
`trice` is tested before `ice` so Triceramon is earth rather than an ice type by accident of
spelling, and `haguru`, `kaguya`, `orange`, `aquila` and `yuki` all exist to be reached before
`agu`/`ange`/`aqua` would swallow them. An explicit `types` entry beats the table outright, which is
how Darkdramon — a Vaccine machine dragon whose name says `dark` — is typed correctly.

Three quarters of the roster reaching `neutral` is the honest number, not a gap to paper over: a
keyword rule invented to cover a family nobody has looked at would hand out real matchups on a
guess, and the inert floor is designed for exactly this (see above).
