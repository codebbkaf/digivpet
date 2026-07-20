#!/usr/bin/env python3
"""US-061: rewrite Resources/evolutions.json with branching criteria and junk evolutions.

One-shot authoring tool, kept in the repo the way scripts/cut_sprites.swift is: the JSON is the
artefact, this is the record of how it was produced. Re-running it is idempotent — it rebuilds the
same edges from the same table rather than patching whatever is on disk.
"""
import collections
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
GRAPH = ROOT / "Resources" / "evolutions.json"
SPRITES = ROOT / "16x16 Digimon Sprites"


def c(metric, window, comparison, value, hint):
    return collections.OrderedDict(
        metric=metric, window=window, comparison=comparison, value=value, hint=hint)


def edge(to, energy, min_energy, max_mistakes, default=False, conditions=None):
    e = collections.OrderedDict(to=to)
    if energy is not None:
        e["requiredEnergy"] = energy
    e["minEnergy"] = min_energy
    e["maxCareMistakes"] = max_mistakes
    if default:
        e["isDefault"] = True
    if conditions:
        e["conditions"] = conditions
    return e


def junk(to, energy):
    """The fallback every branching Child and Adult carries: reachable by doing nothing at all.

    Conditionless and minEnergy 0 on purpose. US-020's fallback ignores an edge's gates anyway, so
    a condition here would be data that never runs; and with no conditions the edge also qualifies
    NORMALLY whenever the good branch does not, losing the max(by: minEnergy) tie-break whenever it
    does. One edge, both routes, same answer.
    """
    return edge(to, energy, 0, 99, default=True)


def node(node_id, name, stage, line, sprite, evolutions=None):
    n = collections.OrderedDict(
        id=node_id, displayName=name, stage=stage, line=line, spriteFile=sprite)
    if evolutions:
        n["evolutions"] = evolutions
    return n


# --- hint vocabulary -------------------------------------------------------------------
# Every hint is spelled in words. US-061 asserts no hint contains a digit: a threshold printed in
# a hint is a number that goes stale the moment the edge is retuned, and it reads as a spec rather
# than a nudge. US-065/US-066 own the real hint vocabulary and the progress-based reveal.

STEPS = "health.steps"
ENERGY = "health.activeEnergy"
EXERCISE = "health.exerciseMinutes"
SLEEP = "health.sleep"
TRAINING = "care.trainingSessions"
OVERFEEDS = "care.overfeeds"
DISTURBANCES = "care.sleepDisturbances"
BATTLES = "care.battleCount"
WIN_RATIO = "care.battleWinRatio"

# Edges, by the node they leave. Anything not named here keeps the edges it already had.
EDGES = {
    # ---- agumon ----------------------------------------------------------------------
    "agumon": [
        edge("greymon", "strength", 60, 3, conditions=[
            c(STEPS, "stage", "atLeast", 60000, "Walk with it most days"),
            c(TRAINING, "stage", "atLeast", 6, "Train it often"),
        ]),
        edge("meramon", "stamina", 60, 3, conditions=[
            c(ENERGY, "stage", "atLeast", 1200, "Burn plenty of active calories"),
            c(OVERFEEDS, "stage", "atMost", 2, "Do not stuff it with food"),
        ]),
        junk("numemon", "strength"),
    ],
    # THE BAND (US-061 AC4), in the Digital Monster Color shape: eight to thirty-one training
    # sessions earns Greymon, and BOTH sides of that fall to the junk branch. Overtraining is
    # punished exactly as hard as never training at all.
    "greymon": [
        edge("metalgreymon", "strength", 100, 2, conditions=[
            c(TRAINING, "stage", "atLeast", 8, "Train it steadily, not idly"),
            c(TRAINING, "stage", "atMost", 31, "Stop once it has had enough for this stage"),
            c(EXERCISE, "stage", "atLeast", 300, "Spend many exercise minutes together"),
        ]),
        junk("blackkingnumemon", "strength"),
    ],
    "meramon": [
        edge("metalgreymon", "stamina", 100, 2, conditions=[
            c(SLEEP, "stage", "atLeast", 1800, "Let it sleep long and undisturbed"),
            c(DISTURBANCES, "stage", "atMost", 2, "Do not wake it in the night"),
        ]),
        junk("blackkingnumemon", "stamina"),
    ],
    "numemon": [
        edge("metalgreymon", "strength", 120, 1, conditions=[
            c(STEPS, "stage", "atLeast", 200000, "Walk further than you ever have"),
            c(BATTLES, "lifetime", "atLeast", 20, "Fight battle after battle"),
        ]),
        junk("blackkingnumemon", "strength"),
    ],

    # ---- gabumon ---------------------------------------------------------------------
    "gabumon": [
        edge("garurumon", "vitality", 60, 3, conditions=[
            c(STEPS, "stage", "atLeast", 50000, "Keep it walking most days"),
            c(OVERFEEDS, "stage", "atMost", 3, "Feed it carefully"),
        ]),
        junk("geremon", "vitality"),
    ],
    "garurumon": [
        edge("weregarurumon", "vitality", 100, 2, conditions=[
            c(EXERCISE, "stage", "atLeast", 240, "Exercise with it most days"),
            c(TRAINING, "stage", "atLeast", 10, "Train it well"),
        ]),
        junk("gerbemon", "vitality"),
    ],
    "geremon": [
        edge("weregarurumon", "vitality", 120, 1, conditions=[
            c(ENERGY, "stage", "atLeast", 2500, "Burn an enormous number of active calories"),
            c(TRAINING, "stage", "atLeast", 18, "Train it without pause"),
        ]),
        junk("gerbemon", "vitality"),
    ],

    # ---- palmon ----------------------------------------------------------------------
    "palmon": [
        edge("togemon", "spirit", 60, 3, conditions=[
            c(SLEEP, "stage", "atLeast", 1500, "Let it rest well every night"),
            c(DISTURBANCES, "stage", "atMost", 1, "Almost never disturb its sleep"),
        ]),
        junk("karatsukinumemon", "spirit"),
    ],
    "togemon": [
        edge("lilimon", "spirit", 100, 2, conditions=[
            c(STEPS, "stage", "atLeast", 90000, "Walk with it a great deal"),
            c(OVERFEEDS, "stage", "atMost", 2, "Never overfeed it"),
        ]),
        junk("jyagamon", "spirit"),
    ],
    "karatsukinumemon": [
        edge("lilimon", "spirit", 120, 1, conditions=[
            c(EXERCISE, "stage", "atLeast", 600, "Exercise relentlessly"),
            c(DISTURBANCES, "stage", "atMost", 1, "Guard its sleep"),
        ]),
        junk("jyagamon", "spirit"),
    ],

    # ---- patamon ---------------------------------------------------------------------
    # Tokomon gained a second branch so the line's four good Adults are covered two per Child.
    # A Baby II is not bound by the two-to-three rule, which is a Child and Adult rule.
    "tokomon": [
        edge("patamon", "spirit", 30, 4, default=True),
        edge("tsukaimon", "vitality", 30, 4),
    ],
    "patamon": [
        edge("unimon", "spirit", 60, 3, conditions=[
            c(STEPS, "stage", "atLeast", 55000, "Take it walking often"),
            c(TRAINING, "stage", "atLeast", 5, "Train it regularly"),
        ]),
        edge("centalmon", "strength", 60, 3, conditions=[
            c(ENERGY, "stage", "atLeast", 1100, "Burn active calories with it"),
            c(BATTLES, "lifetime", "atLeast", 5, "Let it fight a few battles"),
        ]),
        junk("scumon", "spirit"),
    ],
    "tsukaimon": [
        edge("ogremon", "stamina", 60, 3, conditions=[
            c(EXERCISE, "stage", "atLeast", 200, "Exercise beside it"),
            c(OVERFEEDS, "stage", "atMost", 2, "Keep its meals in check"),
        ]),
        edge("bakemon", "vitality", 60, 3, conditions=[
            c(SLEEP, "stage", "atLeast", 1400, "Let it sleep deeply"),
            c(DISTURBANCES, "stage", "atMost", 2, "Leave its nights alone"),
        ]),
        junk("scumon", "vitality"),
    ],
    "unimon": [
        edge("andromon", "spirit", 100, 2, conditions=[
            c(STEPS, "stage", "atLeast", 100000, "Walk a very long way"),
            c(TRAINING, "stage", "atLeast", 12, "Train it hard"),
        ]),
        junk("etemon", "spirit"),
    ],
    "centalmon": [
        edge("andromon", "strength", 100, 2, conditions=[
            c(ENERGY, "stage", "atLeast", 2000, "Burn active calories every day"),
            c(BATTLES, "lifetime", "atLeast", 10, "Battle often"),
        ]),
        junk("etemon", "strength"),
    ],
    "ogremon": [
        edge("giromon", "stamina", 100, 2, conditions=[
            c(EXERCISE, "stage", "atLeast", 320, "Log many exercise minutes"),
            c(OVERFEEDS, "stage", "atMost", 1, "Almost never overfeed it"),
        ]),
        junk("etemon", "stamina"),
    ],
    "bakemon": [
        edge("giromon", "vitality", 100, 2, conditions=[
            c(SLEEP, "stage", "atLeast", 2000, "Give it long, quiet nights"),
            c(DISTURBANCES, "stage", "atMost", 1, "Hardly ever wake it"),
        ]),
        junk("etemon", "vitality"),
    ],
    "scumon": [
        edge("andromon", "spirit", 120, 1, conditions=[
            c(STEPS, "stage", "atLeast", 220000, "Walk an extraordinary distance"),
            c(BATTLES, "lifetime", "atLeast", 25, "Prove it in many battles"),
        ]),
        junk("etemon", "spirit"),
    ],
    # AC5: the win RATIO gate, following the real device's "fifteen battles at eighty percent".
    # Deliberately NOT the isDefault edge — US-020's fallback ignores an edge's gates, so a
    # condition on the default would be a criterion that never runs.
    "etemon": [
        edge("bancholeomon", "vitality", 150, 2, conditions=[
            c(BATTLES, "lifetime", "atLeast", 15, "Fight a good many battles"),
            c(WIN_RATIO, "lifetime", "atLeast", 0.8, "Win nearly all of them"),
        ]),
        junk("kingetemon", "vitality"),
    ],

    # ---- piyomon ---------------------------------------------------------------------
    "piyo_tanemon": [
        edge("piyomon", "spirit", 30, 4, default=True),
        edge("hyokomon", "strength", 30, 4),
        edge("muchomon", "stamina", 30, 4),
    ],
    "piyomon": [
        edge("leomon", "strength", 60, 3, conditions=[
            c(STEPS, "stage", "atLeast", 58000, "Walk with it most days"),
            c(TRAINING, "stage", "atLeast", 6, "Train it often"),
        ]),
        edge("monochromon", "vitality", 60, 3, conditions=[
            c(SLEEP, "stage", "atLeast", 1500, "Let it sleep its fill"),
            c(DISTURBANCES, "stage", "atMost", 2, "Rarely wake it"),
        ]),
        junk("goldnumemon", "strength"),
    ],
    "hyokomon": [
        edge("mojyamon", "spirit", 60, 3, conditions=[
            c(EXERCISE, "stage", "atLeast", 210, "Exercise with it often"),
            c(OVERFEEDS, "stage", "atMost", 2, "Do not overfeed it"),
        ]),
        edge("coelamon", "stamina", 60, 3, conditions=[
            c(ENERGY, "stage", "atLeast", 1300, "Burn active calories together"),
            c(TRAINING, "stage", "atMost", 20, "Do not drill it to exhaustion"),
        ]),
        junk("goldnumemon", "spirit"),
    ],
    "muchomon": [
        edge("kuwagamon", "strength", 60, 3, conditions=[
            c(STEPS, "stage", "atLeast", 70000, "Walk it hard"),
            c(BATTLES, "lifetime", "atLeast", 4, "Give it some fights"),
        ]),
        junk("goldnumemon", "strength"),
    ],
    "leomon": [
        edge("megadramon", "strength", 100, 2, conditions=[
            c(ENERGY, "stage", "atLeast", 2100, "Burn a great many active calories"),
            c(TRAINING, "stage", "atLeast", 12, "Train it hard"),
        ]),
        junk("greatkingscumon", "strength"),
    ],
    "monochromon": [
        edge("megadramon", "vitality", 100, 2, conditions=[
            c(STEPS, "stage", "atLeast", 110000, "Walk a very long way with it"),
            c(OVERFEEDS, "stage", "atMost", 2, "Keep its meals honest"),
        ]),
        junk("greatkingscumon", "vitality"),
    ],
    "mojyamon": [
        edge("piccolomon", "spirit", 100, 2, conditions=[
            c(SLEEP, "stage", "atLeast", 2100, "Give it long nights"),
            c(DISTURBANCES, "stage", "atMost", 1, "Almost never disturb it"),
        ]),
        junk("greatkingscumon", "spirit"),
    ],
    "coelamon": [
        edge("megadramon", "stamina", 100, 2, conditions=[
            c(EXERCISE, "stage", "atLeast", 340, "Spend many exercise minutes with it"),
            c(TRAINING, "stage", "atLeast", 9, "Train it seriously"),
        ]),
        junk("greatkingscumon", "stamina"),
    ],
    # The glutton branch: Digitamamon is earned by doing the opposite of everything Piccolomon
    # wants. Its lower minEnergy loses the tie-break if a Digimon somehow satisfies both.
    "kuwagamon": [
        edge("piccolomon", "strength", 100, 2, conditions=[
            c(STEPS, "stage", "atLeast", 130000, "Walk further than most ever will"),
            c(TRAINING, "stage", "atLeast", 14, "Train it relentlessly"),
        ]),
        edge("digitamamon", "strength", 80, 3, conditions=[
            c(OVERFEEDS, "stage", "atLeast", 5, "Let it eat far more than it needs"),
            c(EXERCISE, "stage", "atMost", 90, "Keep its exercise light"),
        ]),
        junk("greatkingscumon", "strength"),
    ],
    "goldnumemon": [
        edge("megadramon", "strength", 120, 1, conditions=[
            c(STEPS, "stage", "atLeast", 210000, "Walk an enormous distance"),
            c(BATTLES, "lifetime", "atLeast", 22, "Battle again and again"),
        ]),
        junk("greatkingscumon", "strength"),
    ],

    # ---- gazimon ---------------------------------------------------------------------
    "pagumon": [
        edge("gazimon", "strength", 30, 4, default=True),
        edge("gizamon", "stamina", 30, 4),
        edge("psychemon", "spirit", 30, 4),
    ],
    "gazimon": [
        edge("darktyranomon", "strength", 60, 3, conditions=[
            c(STEPS, "stage", "atLeast", 62000, "Keep it moving daily"),
            c(TRAINING, "stage", "atLeast", 7, "Train it often"),
        ]),
        edge("cyclomon", "vitality", 60, 3, conditions=[
            c(SLEEP, "stage", "atLeast", 1600, "Let it sleep soundly"),
            c(DISTURBANCES, "stage", "atMost", 2, "Seldom wake it"),
        ]),
        junk("raremon", "strength"),
    ],
    "gizamon": [
        edge("deltamon", "strength", 60, 3, conditions=[
            c(ENERGY, "stage", "atLeast", 1250, "Burn active calories with it"),
            c(OVERFEEDS, "stage", "atMost", 2, "Do not overfeed it"),
        ]),
        edge("tuskmon", "stamina", 60, 3, conditions=[
            c(EXERCISE, "stage", "atLeast", 230, "Exercise alongside it"),
            c(BATTLES, "lifetime", "atLeast", 6, "Let it fight"),
        ]),
        junk("raremon", "strength"),
    ],
    "psychemon": [
        edge("devidramon", "spirit", 60, 3, conditions=[
            c(SLEEP, "stage", "atLeast", 1700, "Give it quiet nights"),
            c(TRAINING, "stage", "atLeast", 9, "Train it seriously"),
        ]),
        junk("raremon", "spirit"),
    ],
    "darktyranomon": [
        edge("metaltyranomon", "strength", 100, 2, conditions=[
            c(STEPS, "stage", "atLeast", 105000, "Walk a great distance"),
            c(TRAINING, "stage", "atLeast", 11, "Train it hard"),
        ]),
        junk("vademon", "strength"),
    ],
    "cyclomon": [
        edge("metaltyranomon", "vitality", 100, 2, conditions=[
            c(SLEEP, "stage", "atLeast", 2200, "Let it sleep long"),
            c(DISTURBANCES, "stage", "atMost", 1, "Hardly ever disturb it"),
        ]),
        junk("vademon", "vitality"),
    ],
    "devidramon": [
        edge("extyranomon", "spirit", 100, 2, conditions=[
            c(EXERCISE, "stage", "atLeast", 330, "Exercise with it constantly"),
            c(OVERFEEDS, "stage", "atMost", 2, "Keep its appetite honest"),
        ]),
        junk("vademon", "spirit"),
    ],
    "tuskmon": [
        edge("extyranomon", "stamina", 100, 2, conditions=[
            c(ENERGY, "stage", "atLeast", 2200, "Burn a great many calories"),
            c(OVERFEEDS, "stage", "atMost", 1, "Almost never overfeed it"),
        ]),
        junk("vademon", "stamina"),
    ],
    "deltamon": [
        edge("extyranomon", "strength", 100, 2, conditions=[
            c(BATTLES, "lifetime", "atLeast", 12, "Battle often"),
            c(WIN_RATIO, "lifetime", "atLeast", 0.6, "Win more than you lose"),
        ]),
        junk("vademon", "strength"),
    ],
    "raremon": [
        edge("nanomon", "strength", 120, 1, conditions=[
            c(STEPS, "stage", "atLeast", 205000, "Walk an immense distance"),
            c(TRAINING, "stage", "atLeast", 20, "Train it without pause"),
        ]),
        junk("vademon", "strength"),
    ],

    # ---- the junk Perfects -----------------------------------------------------------
    # Each carries a single fallback to a junk Ultimate, so a wholly neglected Digimon still
    # covers all seven rungs rather than dead-ending at Perfect. The consequence for neglect is
    # WHICH Digimon it becomes, not that it stops becoming anything — a line that stopped short
    # would also break the "every line is Digitama to Ultimate" shape US-008 pinned.
    "blackkingnumemon": [junk("platinumnumemon", "strength")],
    "gerbemon": [junk("metaletemon", "vitality")],
    "jyagamon": [junk("shinmonzaemon", "spirit")],
    "greatkingscumon": [junk("boltmon", "strength")],
    "vademon": [junk("ebemon", "strength")],
}

# New nodes, inserted after the node they are keyed on so each line stays contiguous in the file
# (the Dex reads nodes in authored order).
NEW_NODES = {
    "meramon": [node("numemon", "Numemon", "Adult", "agumon", "Numemon")],
    "metalgreymon": [
        node("blackkingnumemon", "BlackKingNumemon", "Perfect", "agumon", "BlackKingNumemon")],
    "wargreymon": [node("platinumnumemon", "PlatinumNumemon", "Ultimate-Super Ultimate", "agumon",
                        "PlatinumNumemon")],
    "garurumon": [node("geremon", "Geremon", "Adult", "gabumon", "Geremon")],
    "weregarurumon": [node("gerbemon", "Gerbemon", "Perfect", "gabumon", "Gerbemon")],
    "metalgarurumon": [node("metaletemon", "MetalEtemon", "Ultimate-Super Ultimate", "gabumon",
                            "MetalEtemon")],
    "togemon": [
        node("karatsukinumemon", "KaratsukiNumemon", "Adult", "palmon", "KaratsukiNumemon")],
    "lilimon": [node("jyagamon", "Jyagamon", "Perfect", "palmon", "Jyagamon")],
    "rosemon": [node("shinmonzaemon", "ShinMonzaemon", "Ultimate-Super Ultimate", "palmon",
                     "ShinMonzaemon")],
    "patamon": [node("tsukaimon", "Tsukaimon", "Child", "patamon", "Tsukaimon")],
    "bancholeomon": [node("kingetemon", "KingEtemon", "Ultimate-Super Ultimate", "patamon",
                          "KingEtemon")],
    "piyomon": [
        node("hyokomon", "Hyokomon", "Child", "piyomon", "Hyokomon"),
        node("muchomon", "Muchomon", "Child", "piyomon", "Muchomon"),
    ],
    "kuwagamon": [node("goldnumemon", "GoldNumemon", "Adult", "piyomon", "GoldNumemon")],
    "digitamamon": [
        node("greatkingscumon", "GreatKingScumon", "Perfect", "piyomon", "GreatKingScumon")],
    "gankoomon": [node("boltmon", "Boltmon", "Ultimate-Super Ultimate", "piyomon", "Boltmon")],
    "gizamon": [node("psychemon", "Psychemon", "Child", "gazimon", "Psychemon")],
    "nanomon": [node("vademon", "Vademon", "Perfect", "gazimon", "Vademon")],
    "raidenmon": [node("ebemon", "Ebemon", "Ultimate-Super Ultimate", "gazimon", "Ebemon")],
}


def main():
    graph = json.loads(GRAPH.read_text(), object_pairs_hook=collections.OrderedDict)

    rebuilt = []
    for n in graph["nodes"]:
        if n["id"] in EDGES:
            n["evolutions"] = EDGES[n["id"]]
        rebuilt.append(n)
        for fresh in NEW_NODES.get(n["id"], []):
            if fresh["id"] in EDGES:
                fresh["evolutions"] = EDGES[fresh["id"]]
            rebuilt.append(fresh)
    graph["nodes"] = rebuilt

    # Fail loudly rather than writing a graph the Swift validator would only reject later.
    ids = {n["id"] for n in graph["nodes"]}
    stage_of = {n["id"]: n["stage"] for n in graph["nodes"]}
    for n in graph["nodes"]:
        art = SPRITES / n["stage"] / (n["spriteFile"] + ".png")
        assert art.exists(), f"{n['id']}: no sprite at {art}"
        for e in n.get("evolutions", []):
            assert e["to"] in ids, f"{n['id']} -> {e['to']} names no node"
        if stage_of[n["id"]] in ("Child", "Adult") and n.get("evolutions"):
            assert 2 <= len(n["evolutions"]) <= 3, \
                f"{n['id']} has {len(n['evolutions'])} outgoing edges"

    GRAPH.write_text(json.dumps(graph, indent=2) + "\n")
    print(f"wrote {len(graph['nodes'])} nodes")


if __name__ == "__main__":
    main()
