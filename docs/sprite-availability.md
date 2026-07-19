# Sprite availability — Digital Monster Color V3, V4, V5

Checked 2026-07-19 for US-043, before US-044/045/046 seed these lines into
`Resources/evolutions.json`. Regenerate with:

    python3 scripts/check_sprites.py --eggs --tree "Version 3" --tree "Version 4" --tree "Version 5"

Names come from `Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md`, which is the
source of truth for the trees. Do **not** re-parse the PDFs or refetch humulos.com — that
extraction is already done.

Three outcomes:

| status | meaning | may it be seeded? |
| --- | --- | --- |
| `animated` | a 48×64 sheet exists under a stage folder | yes, playable |
| `dexOnly` | found only in `Idle Frame Only/`, single frame, no sheet | Dex entry only — **never** playable, **never** in an evolution edge |
| `missing` | no file anywhere in the asset pack | cannot be seeded at all |

## Known exceptions — confirmed

All four exceptions US-043 names were verified against disk, and all four hold. **None of these
may be seeded as playable.**

| name | tree | status | evidence |
| --- | --- | --- | --- |
| Poyomon | V3 Fresh | `dexOnly` | `Idle Frame Only/Poyomon.png` only; absent from `Baby I/` |
| Nanimon | V4 Champion | `dexOnly` | `Idle Frame Only/Nanimon.png` only; absent from `Adult/` |
| Flymon | V5 Champion | `dexOnly` | `Idle Frame Only/Flymon.png` only; absent from `Adult/` |
| Kokatorimon | V4 Champion | `missing` | `find "16x16 Digimon Sprites" -iname "*kokatori*"` → zero hits |

Poyomon is the one that costs a line its root: V3's Fresh stage has no animated art, so the
Patamon line cannot start where the tree says it starts. US-044 has to decide what to do about
that — the other two lines' Fresh stages (Yuramon, Zurumon) are both fine.

## Other findings the seeding stories need

- **`HiAndromon` is filed as `Hi-Andromon.png`.** The tree spells it without the hyphen. The
  `spriteFile` must be `Hi-Andromon`; the check only matched it because lookup normalizes away
  hyphens.
- **Gizamon has no Digitama.** Every other Rookie across the three lines has one
  (`Pata_Digitama`, `Kune_Digitama`, `Piyo_Digitama`, `Pal_Digitama`, `Gazi_Digitama`), but no
  `Giza_Digitama.png` exists. A V5 line rooted at Gizamon needs a different egg or no egg.
- Both Ultra nodes (`Chaosmon`, `Chaosdramon`) have animated sheets, but each is a Jogress with a
  node from *another* version's line, which the current graph schema has no way to express. They
  are listed here as available art, not as seedable edges.
- `Mugendramon` and `Machinedramon` are one Digimon; the sheet is `Mugendramon.png`.

## Full result

Column order is: status, stage from the tree, name as the tree spells it, sprite file on disk.

```
### Version 3
  dexOnly   Fresh        Poyomon                      Poyomon
  animated  In-Training  Tokomon                      Tokomon
  animated  Rookie       Patamon                      Patamon
  animated  Champion     Unimon                       Unimon
  animated  Champion     Centalmon                    Centalmon
  animated  Champion     Ogremon                      Ogremon
  animated  Champion     Bakemon                      Bakemon
  animated  Champion     Scumon                       Scumon
  animated  Rookie       Kunemon                      Kunemon
  animated  Champion     Shellmon                     Shellmon
  animated  Champion     Drimogemon                   Drimogemon
  animated  Ultimate     Andromon                     Andromon
  animated  Ultimate     Giromon                      Giromon
  animated  Ultimate     Etemon                       Etemon
  animated  Mega         HiAndromon                   Hi-Andromon
  animated  Mega         Gokumon                      Gokumon
  animated  Mega         BanchoLeomon                 BanchoLeomon
  -- 16 animated, 1 dexOnly, 0 missing, 17 total
  eggs:
    Patamon                      Pata_Digitama
    Kunemon                      Kune_Digitama

### Version 4
  animated  Fresh        Yuramon                      Yuramon
  animated  In-Training  Tanemon                      Tanemon
  animated  Rookie       Piyomon                      Piyomon
  animated  Champion     Monochromon                  Monochromon
  missing   Champion     Kokatorimon                  
  animated  Champion     Leomon                       Leomon
  animated  Champion     Kuwagamon                    Kuwagamon
  dexOnly   Champion     Nanimon                      Nanimon
  animated  Rookie       Palmon                       Palmon
  animated  Champion     Coelamon                     Coelamon
  animated  Champion     Mojyamon                     Mojyamon
  animated  Ultimate     Megadramon                   Megadramon
  animated  Ultimate     Piccolomon                   Piccolomon
  animated  Ultimate     Digitamamon                  Digitamamon
  animated  Mega         Darkdramon                   Darkdramon
  animated  Mega         BloomLordmon                 BloomLordmon
  animated  Mega         Gankoomon                    Gankoomon
  animated  Ultra        Chaosmon (Jogress with BanchoLeomon) Chaosmon
  -- 16 animated, 1 dexOnly, 1 missing, 18 total
  eggs:
    Piyomon                      Piyo_Digitama
    Palmon                       Pal_Digitama

### Version 5
  animated  Fresh        Zurumon                      Zurumon
  animated  In-Training  Pagumon                      Pagumon
  animated  Rookie       Gazimon                      Gazimon
  animated  Champion     DarkTyranomon                DarkTyranomon
  animated  Champion     Cyclomon                     Cyclomon
  animated  Champion     Devidramon                   Devidramon
  animated  Champion     Tuskmon                      Tuskmon
  animated  Champion     Raremon                      Raremon
  animated  Rookie       Gizamon                      Gizamon
  dexOnly   Champion     Flymon                       Flymon
  animated  Champion     Deltamon                     Deltamon
  animated  Ultimate     MetalTyranomon               MetalTyranomon
  animated  Ultimate     Ex-Tyranomon                 Ex-Tyranomon
  animated  Ultimate     Nanomon                      Nanomon
  animated  Mega         Mugendramon (Machinedramon)  Mugendramon
  animated  Mega         Gaioumon                     Gaioumon
  animated  Mega         Raidenmon                    Raidenmon
  animated  Ultra        Chaosdramon (Jogress with Darkdramon) Chaosdramon
  -- 17 animated, 1 dexOnly, 0 missing, 18 total
  eggs:
    Gazimon                      Gazi_Digitama
    Gizamon                      NO EGG
```

`check_sprites.py` exits non-zero when anything checked is not `animated`, so it can gate a
seeding change. All three of these versions exit 1 today, and that is correct — the four
exceptions above are real and permanent.
