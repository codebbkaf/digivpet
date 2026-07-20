#!/usr/bin/env python3
"""Generate Resources/roster.json — the whole 1,022-Digimon roster the Dex shows.

This is NOT the evolution graph. `Resources/evolutions.json` stays the hand-authored, curated
subset that the evolution engine walks; the roster is every sprite on disk, carrying only what
the Dex needs to draw a grid entry. It deliberately has no `line` and no `evolutions`:

  - `EvolutionNode.line` is `decode`, not `decodeIfPresent`, so one line-less node fails the
    WHOLE graph load, which fatalErrors at launch. ~950 of these entries belong to no authored
    line, so pouring them into evolutions.json would either break that load or force `line`
    optional and silently drop nodes from every tree.
  - an entry with no edges is not a claim that it cannot evolve, only that nobody authored it.
    Leaving the field off says that; an empty `evolutions: []` would say the opposite.

Pipeline (both steps run by this script, so one command is the whole regeneration):

    python3 scripts/build_roster.py          # -> roster.generated.json, Resources/roster.json

  1. `import_roster.build()` derives id/displayName/stage/spriteFile/variant/dexOnly from where
     each sprite sits on disk, and re-emits roster.generated.json (the reviewable intermediate).
  2. The dexOnly Digimon whose art is only in the flat `Idle Frame Only/` folder come out with
     `"stage": null` — nothing on disk says what stage they are. They are resolved here through
     `dex_only_stages.json`, and a null stage with no entry there is a hard ERROR: the Swift
     loader rejects a null stage rather than defaulting one, so a guess would be the only way a
     wrong stage could ship, and this refuses to guess.

Documented in README.md.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import import_roster

# The only fields a roster entry carries, in emitted order. `variant` and `dexOnly` are written
# only when they say something (see RosterEntry: both decodeIfPresent).
FIELDS = ("id", "displayName", "stage", "spriteFile", "variant", "dexOnly")


def load_stage_table(path: str) -> dict[str, str]:
    with open(path) as f:
        table = json.load(f)["stages"]

    unknown = sorted(s for s in set(table.values()) if s not in import_roster.STAGE_FOLDERS)
    if unknown:
        sys.exit(f"error: {os.path.basename(path)} names stages that are not folders / Stage raw "
                 f"values: {', '.join(unknown)}")
    return table


def on_disk_ids(root: str) -> set[str]:
    """The id of every sprite that exists, which is exactly what the roster is.

    `import_roster.build()` also carries forward "orphans" — graph nodes with no sprite of their
    own, which reuse another node's art under a second id (`piyo_tanemon` draws Tanemon). Those
    are an evolution-graph concern: giving each one its own Dex tile would show the same Digimon
    twice under two names.
    """
    names = [n for folder in import_roster.STAGE_FOLDERS
             for n in import_roster.sprite_names(root, folder)]
    names += import_roster.sprite_names(root, import_roster.IDLE_FOLDER)
    return {n.lower() for n in names}


def resolve(nodes: list[dict], stages: dict[str, str], table_path: str,
            keep: set[str]) -> list[dict]:
    """Strip each node to the roster fields, filling in a null stage from the table."""
    entries: list[dict] = []
    unresolved: list[str] = []

    for node in nodes:
        if node["id"] not in keep:
            continue
        entry = {k: node[k] for k in FIELDS if node.get(k) is not None}
        if entry.get("stage") is None:
            stage = stages.get(node["id"])
            if stage is None:
                unresolved.append(node["id"])
                continue
            entry["stage"] = stage
        entries.append(entry)

    if unresolved:
        sys.exit(
            f"error: {len(unresolved)} entr(y/ies) have no stage on disk and no entry in "
            f"{os.path.relpath(table_path)}:\n  " + "\n  ".join(unresolved) +
            "\nAdd each to its \"stages\" table. Do not default one: the stage is what the Dex "
            "files the entry under, and the Swift loader rejects a null rather than pick.")

    # Same order as the graph: up the ladder, then by id — so the Dex grid reads Digitama first
    # without the view having to sort 1,022 entries on every appearance.
    order = {stage: i for i, stage in enumerate(import_roster.STAGE_FOLDERS)}
    entries.sort(key=lambda e: (order[e["stage"]], e["id"]))
    return [{k: e[k] for k in FIELDS if k in e} for e in entries]


def main() -> None:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sprites", default=os.path.join(here, "16x16 Digimon Sprites"))
    parser.add_argument("--graph", default=os.path.join(here, "Resources", "evolutions.json"),
                        help="read-only: only consulted for stages a human already assigned")
    parser.add_argument("--stages", default=os.path.join(here, "scripts", "dex_only_stages.json"))
    parser.add_argument("--generated", default=os.path.join(here, "roster.generated.json"))
    parser.add_argument("--out", default=os.path.join(here, "Resources", "roster.json"))
    args = parser.parse_args()

    nodes, _ = import_roster.build(args.sprites, args.graph)
    with open(args.generated, "w") as f:
        json.dump({"nodes": nodes}, f, indent=2, ensure_ascii=False)
        f.write("\n")

    keep = on_disk_ids(args.sprites)
    entries = resolve(nodes, load_stage_table(args.stages), args.stages, keep)
    skipped = len(nodes) - len(entries)

    with open(args.out, "w") as f:
        json.dump({"entries": entries}, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"{len(entries)} entries -> {os.path.relpath(args.out, here)}"
          + (f"  ({skipped} graph node(s) with no sprite of their own skipped)" if skipped else ""))
    for stage in import_roster.STAGE_FOLDERS:
        count = sum(1 for e in entries if e["stage"] == stage)
        dex_only = sum(1 for e in entries if e["stage"] == stage and e.get("dexOnly"))
        print(f"  {stage:<26} {count:>4}  ({dex_only} dexOnly)")


if __name__ == "__main__":
    main()
