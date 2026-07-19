# DigiVPet

A standalone watchOS V-Pet that turns HealthKit data into food for a Digimon. Steps, active
calories, sleep and exercise minutes become four energy types, which hatch a Digitama and decide
what it evolves into. Everything stays on the watch.

Requirements and rationale: `tasks/prd-digimon-health-vpet.md`. Story-by-story state: `prd.json`.

## Building

The Xcode project is **generated** — never hand-edit `.xcodeproj`. Edit `project.yml` and
regenerate.

```bash
export DEVELOPER_DIR=/Applications/Xcode_26_4_1.app/Contents/Developer
xcodegen generate

xcodebuild build -project DigiVPet.xcodeproj -scheme DigiVPet \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'

xcodebuild test -project DigiVPet.xcodeproj -scheme DigiVPet \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

## Layout

| Path | What |
|---|---|
| `Sources/` | The app. |
| `Tests/` | XCTest unit tests. The app is the `TEST_HOST`. |
| `Resources/evolutions.json` | The shipped evolution graph — **hand-curated data**, see below. |
| `16x16 Digimon Sprites/` | Sprite tree, bundled as a folder reference (not an asset catalog). |
| `docs/evolutions-schema.md` | The graph file format, field by field. |
| `scripts/` | Dev tools. Not shipped, not part of the build. |

## Sprites

Sheets are **48×64 = a 3×4 grid of 16×16 frames**, row-major, indices 0–11: walk1, walk2, eat1,
eat2, sleep1, sleep2, refuse, happy, angry, hurt1, hurt2, attack. Digitama are **48×16 = 3
frames** (idle, wobble, hatch).

Frames are sliced **at runtime** with `CGImage.cropping(to:)` at `x = (i % 3) * 16`,
`y = (i / 3) * 16`. Do not ship pre-cut frames: runtime slicing measured 15× faster to load and a
quarter of the bytes, because PNG decode cost is dominated by fixed per-file overhead that dwarfs
a 16×16 image. Decode each sheet once, crop to 12 `CGImage`s, cache the array.

Render with `.interpolation(.none)`. Smoothed pixel art is a bug.

### Roster shape

The ~2,270 PNGs double-count the same Digimon across the black-and-white and idle-frame folders.
The counts that matter, and that `scripts/import_roster.py` reproduces exactly:

| | Count |
|---|---|
| Animated sheets across the 8 stage folders (**playable**) | **865** |
| Idle-only, no animated sheet (**`dexOnly`**) | **157** |
| Unique Digimon | **1,022** |

## Dev tools

### `scripts/import_roster.py` — roster boilerplate

Walks the sprite tree and emits one graph node per sprite with `id`, `displayName`, `stage`,
`spriteFile`, `variant` and `dexOnly` filled in. All six are already implied by where a sprite
sits on disk, so typing them by hand for 1,022 Digimon is error-prone busywork.

```bash
python3 scripts/import_roster.py                    # -> roster.generated.json (gitignored)
python3 scripts/import_roster.py --out FILE
python3 scripts/import_roster.py --graph FILE --out FILE   # merge in place
```

**It generates boilerplate, never edges.** `evolutions[]` exists in no artifact in this project —
`LCD Checklist.xlsx` records which physical V-Pet each sprite came from and has no stage or
evolution column — so every edge is authored by hand. The script deliberately has no opinion
about them.

**Re-running never clobbers your work.** `--graph` (default `Resources/evolutions.json`) is read
for the two things the script cannot derive — hand-authored `evolutions[]`, and a `dexOnly`
node's `stage` — and both are carried onto the regenerated nodes. Running it with the same path
for `--graph` and `--out` is an in-place merge and is idempotent. A node in the graph whose
sprite has vanished is kept verbatim and reported, never silently dropped.

Output goes to `roster.generated.json` (gitignored) rather than over the shipped graph, because
`Resources/evolutions.json` is **curated**: it holds three complete, playable lines. Regenerating
it wholesale would replace them with ~1,000 terminal nodes, and 54 of 57 Digitama would have no
hatch edge. Expand the shipped graph deliberately, a line at a time. The PRD's advice — build the
loop on 3–4 lines, then grow the data — is the reason.

#### What it derives, and what it refuses to guess

- **Variants.** Only `_X`, `_Black`, `_Blue`, `_Virus`, `_2006`, `_2010`, `_YnK` become a
  `variant` field. The tree carries ~40 other trailing tokens and they are *not* all variants —
  `Belphemon_Sleep` and `Choasmon_ValdurArm` are forms whose suffix belongs in the name. Anything
  unlisted stays in `displayName` and is printed under "unrecognized trailing tokens" for a human
  to rule on. Add to `VARIANT_SUFFIXES` to promote one.
- **Stage suffixes.** `Algomon_Child` → `displayName` "Algomon", `spriteFile` `Algomon_Child`. A
  suffix is stripped **only when it names the folder the sprite is actually in**, so it can never
  be wrong about a stage: the folder is the authority and the suffix merely agrees. `_Digitama`
  is never stripped — it is part of the name, and the seed spells it "Agu Digitama".
- **Digitama → Child.** `Digitama/_How this works.txt` says the author assigns a unique egg per
  Child-level Digimon, so `Agu_Digitama` implies `Agumon`. Every candidate is checked against a
  file that exists; 47 of 57 match. The other 10 are printed, not guessed: their Child form has
  no animated sheet (`Betamon`, `Kamemon`, `Kudamon`, `Zubamon`, `PawnChessmon_*` are idle-only)
  or does not exist at all (`Espimon`, `Liollmon`). This is a report — it authors no hatch edge,
  because an egg's edge points at a **Baby I**, and which Baby I is not derivable from anything.

#### The `dexOnly` stage gap — read before promoting generated nodes

The 157 idle-only Digimon are marked `"dexOnly": true` so the evolution engine can never make one
playable (animating one means slicing 12 frames out of a lone 16×16 sprite). Their art resolves
in the flat `Idle Frame Only/` folder, not under a stage folder.

**Their stage is derivable from nothing in this project**, which was checked exhaustively:
`Idle Frame Only/` is flat; `Black and White Sprites/` has stage subfolders but covers only 1 of
the 157; `LCD Checklist.xlsx` has no stage column; `Visual Checklist.png` is an unlabeled
collage. Only 5 name their own stage (`Arkadimon_Adult`, `Arkadimon_Perfect`,
`Arkadimon_Ultimate`, `Arkadimon_SuperUltimate`, `Meicoo_Child`) and those are believed;
`Arkadimon_Baby` could be Baby I or Baby II, so it is left unknown rather than picked.

The remaining 152 are emitted as **`"stage": null`**, meaning *unknown* — not a guess.

> **`stage: null` is a generator convention that `Sources/EvolutionGraph.swift` does NOT yet
> accept**: `EvolutionNode.stage` is a non-optional `Stage`, so a null-stage node fails the
> decode, and `EvolutionGraph.bundled` traps at launch on a graph it cannot read. Nothing is
> broken today — the generated file is not bundled and the shipped graph has no such node — but
> **assign a stage before promoting a `dexOnly` node into `Resources/evolutions.json`.** Re-runs
> preserve what you assign. Making `stage` optional (`Stage?` = "unknown", legal only when
> `dexOnly`) is the alternative, and is a schema change with its own validator rule.

### `scripts/check_sprites.py` — art availability, before seeding a line

Answers one question for a list of names: does this Digimon have an animated sheet (`animated`),
only a single idle frame (`dexOnly`, never playable), or no art at all (`missing`)? Run it before
writing `spriteFile` values, not after — Kokatorimon is absent from the asset pack entirely and
Poyomon has no sheet, and both look like perfectly ordinary names until you check.

```bash
python3 scripts/check_sprites.py Patamon Poyomon Kokatorimon
python3 scripts/check_sprites.py --eggs --tree "Version 3"   # names read from the trees md
```

`--tree` pulls the names from `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`,
the source of truth for the trees — do not re-parse the PDFs. Exits non-zero if anything checked
is not `animated`, so it can gate a seeding change. The committed result for the Color V3/V4/V5
lines is [docs/sprite-availability.md](docs/sprite-availability.md).

### `scripts/cut_sprites.swift` — frame inspection

Exports frames as individual PNGs to `sprites_cut/` (gitignored) so slicing math and frame labels
can be eyeballed. **Dev tool only** — the app slices at runtime and never ships cut frames.

```bash
swift scripts/cut_sprites.swift --demo   # 21 sheets, 225 frames
```
