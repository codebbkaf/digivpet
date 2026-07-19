#!/usr/bin/env python3
"""Report, for a list of Digimon names, whether each has art we can actually ship.

Seeding a line means writing `spriteFile` values into Resources/evolutions.json, and a name that
looks obvious can still be absent from the asset pack (Kokatorimon) or present only as a single
idle frame with no animated sheet (Poyomon). Either mistake ships a broken node, so the check runs
before the data is authored, not after.

Three outcomes per name:

    animated   a sheet exists under a stage folder  -> playable
    dexOnly    found ONLY in `Idle Frame Only/`     -> never playable, never in an evolution edge
    missing    no file anywhere                     -> cannot be seeded at all

Names come either from the command line or, with --tree, from the extraction that already exists:

    python3 scripts/check_sprites.py Patamon Poyomon Kokatorimon
    python3 scripts/check_sprites.py --tree "Version 3" --tree "Version 4" --tree "Version 5"

--tree reads Resources/Digimon_Color_And_Pendulum_Color_Evolution_Trees.md. That file is the
source of truth for the trees; do NOT re-parse the PDFs or refetch humulos.com.

The committed result for the Color V3/V4/V5 lines is docs/sprite-availability.md.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from import_roster import (  # noqa: E402  (path setup must precede the import)
    DIGITAMA_SUFFIX,
    IDLE_FOLDER,
    STAGE_FOLDERS,
    VARIANT_SUFFIXES,
    normalize,
    sprite_names,
)

# The md's stage words -> the folder that stage's art lives in. Both Mega and Ultra sit in the one
# top folder; the asset pack does not separate them.
STAGE_FOLDER_BY_LABEL = {
    "Fresh": "Baby I",
    "In-Training": "Baby II",
    "Rookie": "Child",
    "Champion": "Adult",
    "Ultimate": "Perfect",
    "Mega": "Ultimate-Super Ultimate",
    "Ultra": "Ultimate-Super Ultimate",
}

STAGE_LABELS = tuple(STAGE_FOLDER_BY_LABEL)

# `(Jogress with CresGarurumon)` is prose about how an evolution happens. `(Virus)` and
# `(Machinedramon)` are the name itself. Only the latter kind is worth trying as a filename.
PROSE_PARENTHETICAL = re.compile(r"^\s*(jogress|with)\b", re.IGNORECASE)


def candidates(name: str) -> list[str]:
    """The spellings of `name` worth looking for on disk, most specific first.

    `MetalGreymon (Virus)` is filed as `MetalGreymon_Virus`, but `Mugendramon (Machinedramon)` is
    filed under either half, so a parenthetical is tried as a suffix, as a name of its own, and
    dropped entirely rather than guessed at.
    """
    match = re.match(r"^(.*?)\s*\(([^)]*)\)\s*$", name)
    if not match:
        return [name]

    base, inner = match.group(1).strip(), match.group(2).strip()
    if PROSE_PARENTHETICAL.match(inner):
        return [base]
    return [f"{base}_{inner}", base, inner]


def lookup(name: str, index: dict[str, list[tuple[str, str | None]]]) -> dict:
    """Resolve one name to (status, sprite file, stage folder).

    A name resolves to its exact spelling if one exists; otherwise to a variant of it
    (`Tyranomon` -> `Tyranomon_X`) only as a reported fallback, never silently — a variant is a
    different Digimon and the seeding story must decide whether it is the one it meant.
    """
    for candidate in candidates(name):
        exact = index.get(normalize(candidate), [])
        animated = [(f, s) for f, s in exact if s is not None]
        if animated:
            sprite, stage = animated[0]
            return {"status": "animated", "spriteFile": sprite, "stage": stage}
        if exact:
            return {"status": "dexOnly", "spriteFile": exact[0][0], "stage": None}

    # Nothing matched the name itself. Offer near spellings so a typo does not read as "missing".
    near: list[str] = []
    for candidate in candidates(name):
        key = normalize(candidate)
        for variant in VARIANT_SUFFIXES:
            near += [f for f, _ in index.get(key + normalize(variant), [])]
    return {"status": "missing", "spriteFile": None, "stage": None, "near": sorted(set(near))}


def build_index(root: str) -> dict[str, list[tuple[str, str | None]]]:
    """normalized name -> [(basename, stage folder or None when idle-only)].

    A list, not a single value, because two files can normalize alike (`Ex-Tyranomon` and
    `ExTyranomon` would); animated wins over idle-only when both exist, which is the common case
    since `Idle Frame Only/` also holds a frame for most animated Digimon.
    """
    index: dict[str, list[tuple[str, str | None]]] = {}
    staged: set[str] = set()

    for stage in STAGE_FOLDERS:
        for basename in sprite_names(root, stage):
            index.setdefault(normalize(basename), []).append((basename, stage))
            staged.add(basename)

    for basename in sprite_names(root, IDLE_FOLDER):
        if basename not in staged:
            index.setdefault(normalize(basename), []).append((basename, None))

    return index


def parse_tree(path: str, version: str) -> list[tuple[str, str | None]]:
    """The (name, stage label) pairs one `### <version>` section of the trees md names.

    Only Part 1 (Digital Monster Color) is searched, because Pendulum Color reuses the same
    `Version N` headings and this story is about the Color V3/V4/V5 lines.

    A line is a chain of `->`-separated chunks, each optionally `Stage: a / b / c`. An unlabeled
    chunk is the left side of an arrow, naming Digimon the section already labeled elsewhere, so
    its stage is left None and the labeled occurrence supplies it.
    """
    with open(path) as f:
        text = f.read()

    part = text.split("## Part 2", 1)[0]
    sections = re.split(r"^### ", part, flags=re.MULTILINE)[1:]
    matching = [s for s in sections if s.split("\n", 1)[0].startswith(version)]
    if not matching:
        sys.exit(f"error: no '### {version}' section in {path}")
    if len(matching) > 1:
        sys.exit(f"error: '{version}' matches {len(matching)} sections in {path}")

    found: list[tuple[str, str | None]] = []
    for line in matching[0].split("\n")[1:]:
        line = line.strip()
        if not line.startswith("*"):
            continue
        for chunk in line.lstrip("* ").split("->"):
            # `* Champion to Ultimate (Perfect):` and `* Ultra (Jogress):` head a group; the names
            # they introduce are on the lines below. A chunk still ending in ':' after its stage
            # label is peeled off named nothing.
            if chunk.strip().endswith(":"):
                continue
            label = None
            for candidate in STAGE_LABELS:
                if chunk.strip().startswith(candidate + ":"):
                    label = candidate
                    chunk = chunk.strip()[len(candidate) + 1:]
                    break
            for name in chunk.split("/"):
                name = name.strip()
                if name:
                    found.append((name, label))

    # Dedupe. Keyed on the name without its parenthetical, because a tree names the same node both
    # ways — V5 has `Mugendramon (Machinedramon)` as a Mega and a bare `Mugendramon` as the left
    # side of the Ultra arrow. The fuller spelling and the non-None label both win, so the merged
    # row keeps whichever occurrence carried the most information.
    stages: dict[str, tuple[str, str | None]] = {}
    for name, label in found:
        key = re.sub(r"\s*\([^)]*\)\s*$", "", name).strip()
        best_name, best_label = stages.get(key, (name, label))
        stages[key] = (max(best_name, name, key=len), best_label or label)
    return list(stages.values())


def egg_for(child: str, index: dict[str, list[tuple[str, str | None]]]) -> str | None:
    """The Digitama sprite whose prefix names `child`, if one exists.

    Every seeded line starts at an egg and the trees md has no egg column, so this reverses
    import_roster's convention (`Agu_Digitama` -> `Agumon`) to find one.
    """
    if not child.lower().endswith("mon"):
        return None
    prefix = child[: -len("mon")].rstrip("-")
    for sprite, stage in index.get(normalize(prefix + DIGITAMA_SUFFIX), []):
        if stage == "Digitama":
            return sprite
    return None


def report(version: str, rows: list[tuple[str, str | None, dict]]) -> None:
    print(f"\n### {version}")
    for name, label, result in rows:
        status = result["status"]
        detail = result["spriteFile"] or ""
        if status == "animated" and label and result["stage"] != STAGE_FOLDER_BY_LABEL[label]:
            detail += f"  (in {result['stage']}, expected {STAGE_FOLDER_BY_LABEL[label]})"
        if status == "missing" and result.get("near"):
            detail = "near: " + ", ".join(result["near"])
        print(f"  {status:<9} {(label or '-'):<12} {name:<28} {detail}")

    counts = {s: sum(1 for _, _, r in rows if r["status"] == s) for s in
              ("animated", "dexOnly", "missing")}
    print(f"  -- {counts['animated']} animated, {counts['dexOnly']} dexOnly, "
          f"{counts['missing']} missing, {len(rows)} total")


def main() -> None:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*", help="Digimon names to check")
    parser.add_argument("--tree", action="append", default=[], metavar="VERSION",
                        help='a "### <VERSION>" section of the trees md to check, e.g. "Version 3"')
    parser.add_argument("--sprites", default=os.path.join(here, "16x16 Digimon Sprites"),
                        help="sprite tree root")
    parser.add_argument("--trees-doc", default=os.path.join(
        here, "Resources", "Digimon_Color_And_Pendulum_Color_Evolution_Trees.md"),
        help="the extracted evolution trees (source of truth; do not re-parse the PDFs)")
    parser.add_argument("--eggs", action="store_true",
                        help="also report the Digitama sprite for each Rookie")
    args = parser.parse_args()

    if not args.names and not args.tree:
        parser.error("give some names, or --tree VERSION")

    index = build_index(args.sprites)
    unplayable = 0

    if args.names:
        rows = [(name, None, lookup(name, index)) for name in args.names]
        report("names", rows)
        unplayable += sum(1 for _, _, r in rows if r["status"] != "animated")

    for version in args.tree:
        rows = [(name, label, lookup(name, index))
                for name, label in parse_tree(args.trees_doc, version)]
        report(version, rows)
        unplayable += sum(1 for _, _, r in rows if r["status"] != "animated")

        if args.eggs:
            print("  eggs:")
            for name, label, _ in rows:
                if label == "Rookie":
                    print(f"    {name:<28} {egg_for(name, index) or 'NO EGG'}")

    # Non-zero when anything is not playable, so this can gate a seeding change in CI.
    sys.exit(1 if unplayable else 0)


if __name__ == "__main__":
    main()
