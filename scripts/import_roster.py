#!/usr/bin/env python3
"""Generate evolution-graph node boilerplate from the sprite filenames.

The roster is ~1,000 Digimon. Hand-typing `id`/`displayName`/`stage`/`spriteFile` for each is
hours of error-prone work, and every one of those four fields is already implied by where the
sprite sits on disk. This script derives them; humans author the part that is NOT on disk — the
`evolutions[]` edges, which exist in no artifact in this project (see the PRD's Key Asset Facts).

So this is a boilerplate generator, not a graph generator. It never invents an edge.

Re-running is safe: hand-authored data is harvested from the existing graph and carried onto the
regenerated nodes, so edits are never clobbered. See --graph/--out.

    python3 scripts/import_roster.py                      # write roster.generated.json
    python3 scripts/import_roster.py --out some/file.json

Documented in README.md.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict

# --- Facts about the sprite tree. Verified on disk; see README.md before changing any of these.

# The stage folders, in ladder order. These strings are the `Stage` raw values in
# Sources/GameState.swift AND the folder names — one spelling serves both, so a node needs no
# mapping table to find its art. A rename here is a rename there.
STAGE_FOLDERS = (
    "Digitama",
    "Baby I",
    "Baby II",
    "Child",
    "Adult",
    "Perfect",
    "Ultimate-Super Ultimate",
    "Armor-Hybrid",
)

# Flat folder of single 16x16 idle sprites. A Digimon found ONLY here has no animated sheet.
IDLE_FOLDER = "Idle Frame Only"

# Variant suffixes recognized as a `variant` field rather than part of the name. This is exactly
# the set US-010 names, deliberately: the tree carries ~40 other trailing tokens (Red, Core,
# Burst, Vicious, Falldown, ...) and they are NOT all variants — `Belphemon_Sleep` and
# `Choasmon_ValdurArm` are forms whose suffix belongs in the name. Guessing which is which is how
# a roster fills with wrong data, so anything not listed here stays in `displayName` and gets
# reported under "unrecognized suffixes" for a human to rule on.
VARIANT_SUFFIXES = ("X", "Black", "Blue", "Virus", "2006", "2010", "YnK")

# Trailing tokens that disambiguate a name spanning several stages (`Algomon_Child` vs
# `Algomon_Adult`). Stripped from `displayName`, kept in `spriteFile`.
#
# A suffix is only stripped when it names the folder the sprite is ACTUALLY in, so this can never
# be wrong about a stage — the folder is the authority, the suffix merely agrees with it.
#
# Digitama is absent on purpose: `_Digitama` is part of the name, not a disambiguator. The
# hand-authored seed spells it "Agu Digitama", and this table keeps it that way.
STAGE_SUFFIX_ALIASES = {
    "Baby I": ("babyi", "baby"),
    "Baby II": ("babyii", "baby"),
    "Child": ("child",),
    "Adult": ("adult",),
    "Perfect": ("perfect",),
    "Ultimate-Super Ultimate": ("ultimate", "superultimate", "ultimatesuperultimate"),
    "Armor-Hybrid": ("armorhybrid", "armor", "hybrid"),
}

DIGITAMA_SUFFIX = "_Digitama"


def normalize(token: str) -> str:
    return token.lower().replace(" ", "").replace("-", "").replace("_", "")


# alias -> the stages it could mean. Built from the table above so the two can never drift.
_STAGES_BY_ALIAS: dict[str, set[str]] = defaultdict(set)
for _stage, _aliases in STAGE_SUFFIX_ALIASES.items():
    for _alias in _aliases:
        _STAGES_BY_ALIAS[_alias].add(_stage)


def parse_name(basename: str, stage: str | None) -> tuple[str, str | None, list[str]]:
    """Split a sprite basename into (displayName, variant, unrecognized trailing tokens).

    `stage` is the folder the sprite is in, or None when it is not filed by stage (the idle-only
    Digimon). Only a suffix matching that folder is treated as stage-disambiguating.
    """
    tokens = basename.split("_")

    # Peel recognized variants off the TAIL first, so `Foo_Child_X` gives up its X before the
    # stage suffix underneath it is considered.
    variants: list[str] = []
    while len(tokens) > 1 and tokens[-1] in VARIANT_SUFFIXES:
        variants.insert(0, tokens.pop())

    if stage is not None and len(tokens) > 1:
        if normalize(tokens[-1]) in STAGE_SUFFIX_ALIASES.get(stage, ()):
            tokens.pop()

    # Everything still trailing that is neither a variant nor this folder's stage. Reported, not
    # guessed at. An egg's `_Digitama` is excluded: keeping it is the rule, not an open question.
    unrecognized = [] if stage == "Digitama" else list(tokens[1:])

    display_name = " ".join(tokens + variants)
    return display_name, (" ".join(variants) or None), unrecognized


def stage_from_filename(basename: str) -> str | None:
    """The stage a basename's own suffix names, when it names exactly one.

    This is the ONLY stage source for an idle-only Digimon, whose sprite is not filed by stage.
    `Arkadimon_Adult` says Adult and is believed; `Arkadimon_Baby` could be Baby I or Baby II, so
    it is left unknown rather than picked. Returns None when the suffix is absent or ambiguous.
    """
    tokens = basename.split("_")
    if len(tokens) < 2:
        return None
    stages = _STAGES_BY_ALIAS.get(normalize(tokens[-1]), set())
    return next(iter(stages)) if len(stages) == 1 else None


def sprite_names(root: str, folder: str) -> list[str]:
    path = os.path.join(root, folder)
    if not os.path.isdir(path):
        sys.exit(f"error: no such sprite folder: {path}")
    return sorted(f[:-4] for f in os.listdir(path) if f.endswith(".png"))


def match_child_form(egg_basename: str, child_names: set[str]) -> list[str]:
    """The Child sprites an egg's prefix could name.

    `Digitama/_How this works.txt` says the author assigns a unique egg to each CHILD-level
    Digimon, so `Agu_Digitama` implies `Agumon`. That is a naming convention, not data, so every
    candidate is checked against a file that really exists and ambiguity is reported rather than
    resolved.

    Returns every match (0 = report as unmatched, 2+ = report as ambiguous).
    """
    prefix = egg_basename[: -len(DIGITAMA_SUFFIX)]
    found: list[str] = []

    for separator in ("", "-"):  # V_Digitama -> V-mon
        candidate = f"{prefix}{separator}mon"
        if candidate in child_names:
            found.append(candidate)

    # A variant baked into the prefix: Agu2006 -> Agumon_2006, GabuBlack -> Gabumon_Black.
    for variant in VARIANT_SUFFIXES:
        if prefix.endswith(variant) and len(prefix) > len(variant):
            candidate = f"{prefix[: -len(variant)]}mon_{variant}"
            if candidate in child_names:
                found.append(candidate)

    return found


def harvest(path: str) -> tuple[dict, dict, list]:
    """Read back the parts of an existing graph this script cannot derive.

    Two things are hand-authored and must survive a re-run:
      - `evolutions[]`, which exists nowhere on disk;
      - a dexOnly node's `stage`, which is likewise derivable from nothing (see README).

    Also returns nodes whose sprite is gone, so the caller can carry them rather than delete
    somebody's work silently.
    """
    if not os.path.exists(path):
        return {}, {}, []

    with open(path) as f:
        nodes = json.load(f).get("nodes", [])

    edges = {n["id"]: n["evolutions"] for n in nodes if n.get("evolutions")}
    stages = {n["id"]: n["stage"] for n in nodes if n.get("dexOnly") and n.get("stage")}
    return edges, stages, nodes


def build(root: str, graph_path: str) -> tuple[list[dict], dict]:
    edges, dex_stages, existing = harvest(graph_path)

    staged: dict[str, str] = {}  # basename -> stage folder
    for stage in STAGE_FOLDERS:
        for name in sprite_names(root, stage):
            staged[name] = stage

    idle_only = [n for n in sprite_names(root, IDLE_FOLDER) if n not in staged]

    nodes: list[dict] = []
    unrecognized: dict[str, list[str]] = defaultdict(list)

    def add(basename: str, stage: str | None, dex_only: bool) -> None:
        display_name, variant, extra = parse_name(basename, stage)
        for token in extra:
            unrecognized[token].append(basename)

        node = {"id": basename.lower(), "displayName": display_name, "stage": stage,
                "spriteFile": basename}
        if variant:
            node["variant"] = variant
        if dex_only:
            node["dexOnly"] = True
        if node["id"] in edges:  # hand-authored; never regenerated, never dropped
            node["evolutions"] = edges[node["id"]]
        nodes.append(node)

    for basename, stage in staged.items():
        add(basename, stage, dex_only=False)

    for basename in idle_only:
        # dexOnly art is NOT filed by stage, so the folder cannot say what stage it is. A stage a
        # human already assigned wins; otherwise the filename is the last resort; otherwise
        # unknown, and left that way.
        stage = dex_stages.get(basename.lower()) or stage_from_filename(basename)
        add(basename, stage, dex_only=True)
        if stage is not None:
            # Re-strip now that the stage is known: Arkadimon_Adult -> "Arkadimon".
            nodes[-1]["displayName"], _, _ = parse_name(basename, stage)

    generated_ids = {n["id"] for n in nodes}
    orphans = [n for n in existing if n["id"] not in generated_ids]
    nodes.extend(orphans)  # keep, do not silently delete

    order = {stage: i for i, stage in enumerate(STAGE_FOLDERS)}
    nodes.sort(key=lambda n: (order.get(n["stage"], len(STAGE_FOLDERS)), n["id"]))

    child_names = {n for n, s in staged.items() if s == "Child"}
    eggs = sorted(n for n, s in staged.items() if s == "Digitama")
    matches = {egg: match_child_form(egg, child_names) for egg in eggs}

    report = {
        "per_stage": {s: sum(1 for n in nodes if n["stage"] == s and not n.get("dexOnly"))
                      for s in STAGE_FOLDERS},
        "dex_only": [n for n in nodes if n.get("dexOnly")],
        "unmatched_eggs": [e for e, m in matches.items() if not m],
        "ambiguous_eggs": {e: m for e, m in matches.items() if len(m) > 1},
        "matched_eggs": {e: m[0] for e, m in matches.items() if len(m) == 1},
        "unrecognized": unrecognized,
        "orphans": orphans,
        "preserved_edges": sum(1 for n in nodes if n.get("evolutions")),
    }
    return nodes, report


def summarize(nodes: list[dict], report: dict, out: str) -> None:
    print(f"{len(nodes)} nodes -> {out}\n")

    print("per stage (playable):")
    for stage, count in report["per_stage"].items():
        print(f"  {stage:<26} {count:>4}")
    playable = sum(report["per_stage"].values())
    print(f"  {'':<26} {'----':>4}\n  {'playable total':<26} {playable:>4}")

    dex_only = report["dex_only"]
    unstaged = [n for n in dex_only if n["stage"] is None]
    print(f"\ndexOnly (idle-only, no animated sheet): {len(dex_only)}")
    print(f"  marked dexOnly: true, never selectable by the evolution engine")
    print(f"  with a stage:    {len(dex_only) - len(unstaged)}")
    print(f"  stage UNKNOWN:   {len(unstaged)}  <- emitted as \"stage\": null; see README.md")

    print(f"\nhand-authored edges preserved: {report['preserved_edges']} nodes")
    if report["orphans"]:
        print(f"  WARNING: {len(report['orphans'])} node(s) in the graph have no sprite on disk "
              f"and were kept verbatim: {', '.join(n['id'] for n in report['orphans'])}")

    matched, unmatched = report["matched_eggs"], report["unmatched_eggs"]
    print(f"\nDigitama -> Child: {len(matched)} matched, {len(unmatched)} unmatched")
    if report["ambiguous_eggs"]:
        print("  AMBIGUOUS (resolve by hand):")
        for egg, candidates in report["ambiguous_eggs"].items():
            print(f"    {egg:<24} {' | '.join(candidates)}")
    if unmatched:
        print("  UNMATCHED — no animated Child sprite fits the prefix, so the line cannot be")
        print("  authored from these eggs until one exists:")
        for egg in unmatched:
            print(f"    {egg}")

    if report["unrecognized"]:
        print("\nunrecognized trailing tokens (left in displayName — add to VARIANT_SUFFIXES if")
        print("one is really a variant):")
        for token, owners in sorted(report["unrecognized"].items()):
            shown = ", ".join(owners[:3]) + (" ..." if len(owners) > 3 else "")
            print(f"  _{token:<18} {len(owners):>3}  ({shown})")


def main() -> None:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sprites", default=os.path.join(here, "16x16 Digimon Sprites"),
                        help="sprite tree root")
    parser.add_argument("--graph", default=os.path.join(here, "Resources", "evolutions.json"),
                        help="existing graph to carry hand-authored edges over from")
    parser.add_argument("--out", default=os.path.join(here, "roster.generated.json"),
                        help="file to write (pass the same path as --graph to merge in place)")
    parser.add_argument("--quiet", action="store_true", help="write the file, skip the summary")
    args = parser.parse_args()

    nodes, report = build(args.sprites, args.graph)

    with open(args.out, "w") as f:
        json.dump({"nodes": nodes}, f, indent=2, ensure_ascii=False)
        f.write("\n")

    if not args.quiet:
        summarize(nodes, report, os.path.relpath(args.out, here))


if __name__ == "__main__":
    main()
