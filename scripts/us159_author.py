"""US-159 — Orphan sweep: Perfect H-L.

Authors the eleven orphaned Perfect whose display name begins H-L and the five Ultimates they
climb into that had no node. Run once; it refuses to run twice (every id it adds must be absent).

Kept in `scripts/` beside `us157_author.py` and `us158_author.py` for the same reason: the JSON
round-trips byte-exactly through `json.dumps(indent=2, ensure_ascii=False)`, which is what makes
scripted authoring of sixteen nodes across three files safe.
"""
import collections
import json
import sys

ROOT = "/Users/red/Documents/SourceCode/ios_project/digi/"

# (id, displayName, spriteFile, line, parent, parentEnergy, ultimate, climbEnergy)
PERFECTS = [
    ("hangyomon", "Hangyomon", "Hangyomon", "penc-ds",
     "ebidramon", "spirit", "vikemon", "spirit"),
    ("hisyaryumon", "Hisyaryumon", "Hisyaryumon", "penc-me",
     "omekamon", "strength", "ouryumon", "strength"),
    ("insekimon", "Insekimon", "Insekimon", "penc-nso",
     "icemon", "stamina", "pencnso_boltmon", "stamina"),
    ("jazarichmon", "Jazarichmon", "Jazarichmon", "tamers",
     "jazardmon", "strength", "metallicdramon", "strength"),
    ("karatenmon", "Karatenmon", "Karatenmon", "wanyamon",
     "igamon", "spirit", "tengumon", "spirit"),
    ("ladydevimon", "LadyDevimon", "LadyDevimon", "tamers",
     "kyubimon", "spirit", "beelzebumon", "spirit"),
    ("ladydevimon_x", "LadyDevimon X", "LadyDevimon_X", "tamers",
     "numemon_x", "vitality", "beelstarmon_x", "vitality"),
    ("lavogaritamon", "Lavogaritamon", "Lavogaritamon", "penc-nso",
     "lavorvomon", "strength", "volcanicdramon", "strength"),
    ("lilamon", "Lilamon", "Lilamon", "palmon",
     "sunflowmon", "vitality", "rosemon", "vitality"),
    ("lilimon_x", "Lilimon X", "Lilimon_X", "palmon",
     "togemon_x", "spirit", "rosemon", "spirit"),
    ("lucemon_falldown", "Lucemon Falldown", "Lucemon_Falldown", "penc-nso",
     "pencnso_devimon", "stamina", "venomvamdemon", "stamina"),
]

# The Ultimates this story had to open, in the order they are appended.
ULTIMATES = [
    ("ouryumon", "Ouryumon", "Ouryumon", "penc-me"),
    ("metallicdramon", "Metallicdramon", "Metallicdramon", "tamers"),
    ("tengumon", "Tengumon", "Tengumon", "wanyamon"),
    ("beelstarmon_x", "BeelStarmon X", "BeelStarmon_X", "tamers"),
    ("volcanicdramon", "Volcanicdramon", "Volcanicdramon", "penc-nso"),
]

# The nine Champions that were LEAVES before this story: giving one an out-edge means giving it its
# line's junk floor in the same edit, or `EvolutionCriteriaTests` fails on the node just wired.
# Every floor here already existed, so `junkIds` does not move — the same shape US-158 had.
JUNK_FLOORS = {
    "omekamon": ("locomon", "strength"),
    "icemon": ("darumamon", "strength"),
    "jazardmon": ("catchmamemon", "strength"),
    "igamon": ("karakurumon", "spirit"),
    "kyubimon": ("catchmamemon", "spirit"),
    "numemon_x": ("catchmamemon", "vitality"),
    "lavorvomon": ("darumamon", "strength"),
    "sunflowmon": ("jyagamon", "vitality"),
    "togemon_x": ("jyagamon", "spirit"),
}

# The criteria on each new in-edge. Two apiece: one HealthKit, one care counter, so no edge is
# earned by walking alone and none by playing alone.
CONDITIONS = {
    "hangyomon": [
        ("health.distanceSwimming", "stage", "atLeast", 6000, "Take it out past the shelf and back"),
        ("care.battleCount", "lifetime", "atLeast", 22, "And let the harpoon settle every argument"),
    ],
    "hisyaryumon": [
        ("health.exerciseMinutes", "stage", "atLeast", 940, "Draw the blade until the draw is the strike"),
        ("care.trainingSessions", "stage", "atLeast", 24, "And come back to the dojo the next day"),
    ],
    "insekimon": [
        ("health.flightsClimbed", "stage", "atLeast", 260, "Climb to where the sky drops its stones"),
        ("care.overfeeds", "stage", "atMost", 2, "And keep the weight of a rock, not of a meal"),
    ],
    "jazarichmon": [
        ("health.activeEnergy", "stage", "atLeast", 9400, "Burn hot enough to gild the scales"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.7, "And win far more of the set than it drops"),
    ],
    "karatenmon": [
        ("health.sleep", "stage", "atMost", 5600, "Keep the crow's hours and skip the long night"),
        ("care.trainingSessions", "stage", "atLeast", 22, "And drill the two blades in the dark"),
    ],
    "ladydevimon": [
        ("health.sleep", "stage", "atLeast", 9800, "Let it keep the hours the fallen keep"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And never put the light on over it"),
    ],
    "ladydevimon_x": [
        ("health.mindfulMinutes", "stage", "atLeast", 220, "Sit with it until the ribbon stops moving"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.8, "And leave almost nothing standing"),
    ],
    "lavogaritamon": [
        ("health.activeEnergy", "stage", "atLeast", 10000, "Keep the crust glowing all the way through"),
        ("care.battleCount", "lifetime", "atLeast", 26, "And let something cool itself on the rock"),
    ],
    "lilamon": [
        ("health.daylight", "stage", "atLeast", 640, "Give it the whole of the afternoon sun"),
        ("care.overfeeds", "stage", "atMost", 1, "And let the flower take only what it needs"),
    ],
    "lilimon_x": [
        ("health.standHours", "stage", "atLeast", 180, "Stand it in the light, hour after hour"),
        ("care.trainingSessions", "stage", "atLeast", 20, "And keep the vines strong enough to hold"),
    ],
    "lucemon_falldown": [
        ("health.steps", "stage", "atLeast", 52000, "Walk it further from the light than it can return"),
        ("care.sleepDisturbances", "stage", "atLeast", 8, "And wake it, over and over, until it hates the lamp"),
    ],
}

COMMENTS = {
    "hangyomon": (
        "Ebidramon is Hangyomon's SOLE bolded `Evolves From` on Wikimon — drawn with or without "
        "Shellmon, with certain Pendulum Ver.20th Digimon, or with any Data Adult from the Digimon "
        "Pendulum — and it has been on `penc-ds` since US-139, so the bolded arrow needs no new "
        "node below. The climb is Vikemon, on the page's `Evolves To` (with or without "
        "Shakkoumon, or Zudomon and Shakkoumon) and already this line's Mega over Zudomon; "
        "Neptunemon is the bolded climb and has no sheet in this pack, Plesiomon already carries "
        "US-158's Gusokumon and Metal Seadramon US-139's MegaSeadramon, so Vikemon is the one "
        "whose rung is empty. **THIS EDGE FILLS EBIDRAMON**: vitality went to Anomalocarimon in "
        "US-139, stamina to Anomalocarimon X in US-157 and strength to Gusokumon in US-158, so "
        "spirit is the last of the four and this Champion can never branch again."),
    "hisyaryumon": (
        "NOT THE BOLDED PARENT, AND THIS SAYS SO. Wikimon bolds Ginryumon (with or without Blast "
        "Evolution, or Growmon (X-Antibody) or Omekamon) and Ryudamon (Warp Evolution), and BOTH "
        "are on `commandramon` — a line with no Perfect rung at all, so taking that reading would "
        "have cost a junk Perfect floor and a new `junkIds` entry on top of this node, and left "
        "all three stranded, because Ryudamon and Ginryumon are already on "
        "`EvolutionCriteriaTests`' stranded list. **HISYARYUMON IS THEREFORE `commandramon`'s "
        "REHOME CANDIDATE the day that line's Perfect rung opens** — the same pin US-153 and "
        "US-157 left on Kinkakumon for `penc-sw`. What is taken instead is Omekamon, which is the "
        "OTHER Digimon the Ginryumon clause names — the page carries a standalone `Omekamon (with "
        "or without Ginryumon)` bullet — and which has been a LEAF on `penc-me` since US-152, so "
        "the arrow clears a dead end. The climb is Ouryumon, bolded on the page (with or without "
        "Blast Evolution, or Triceramon (X-Antibody)), which had no node. Strength is what a "
        "drawn blade earns and Omekamon had every energy free."),
    "insekimon": (
        "Wikimon gives Insekimon one bolded `Evolves From`, Gottsumon, which has no sheet in this "
        "pack at all. Icemon is the parent on the page's unbolded list that this graph already "
        "has AND is the Digimon Insekimon is visibly the other half of — the two are the same "
        "boulder, one iced over and one struck from the sky — and it has been a LEAF on "
        "`penc-nso` since US-152, so the arrow clears a dead end as well as filling one. The "
        "climb is Boltmon, on the page's `Evolves To` and already `penc-nso`'s Mega over "
        "BlueMeramon since US-157. Ancient Volcamon is the page's other drawable climb and is on "
        "`wanyamon`, which holds no cited parent for Insekimon. Stamina is what a rock earns and "
        "Icemon had every energy free."),
    "jazarichmon": (
        "Jazardmon is Jazarichmon's SOLE bolded `Evolves From` on Wikimon, and it has been a LEAF "
        "on `tamers` since US-150 — so the bolded arrow is also the one that clears a dead end, "
        "which is the cheapest shape this rung has. The climb is Metallicdramon, the page's other "
        "bolded name, which had no node; Hououmon (`penc-wg`) and Tiger Vespamon (`palmon`) are "
        "the page's drawable alternatives and neither line holds a cited parent for this Digimon, "
        "so both lost on the line rather than on boldness. Strength is what a gilded jaw earns "
        "and Jazardmon had every energy free."),
    "karatenmon": (
        "Wikimon gives Karatenmon no bolded `Evolves From` at all, so the arrow rests on the "
        "cited parent whose line can also draw the climb: Igamon, the Iga ninja, has been a LEAF "
        "on `wanyamon` since US-150, and a ninja becoming a crow tengu is the same story the "
        "sprite tells. The climb is Tengumon, the page's SOLE bolded `Evolves To`, which had no "
        "node — so `wanyamon` gains its third Mega one story after US-158 gave it its first two. "
        "Peckmon (`tamers`) is the other leaf on the cited list and lost because `tamers` holds "
        "no cited climb for Karatenmon, and Tiger Vespamon, the only cited climb already in the "
        "graph, is on `palmon`, which holds no cited parent. Spirit is what a tengu earns and "
        "Igamon had every energy free."),
    "ladydevimon": (
        "Wikimon's bolded `Evolves From` is Angewomon, which is a PERFECT and can never be an "
        "in-edge, "
        "and the other two — Botamon and Bubbmon — are Warp Evolutions out of Baby I, which the "
        "validator's one-rung rule forbids just as firmly. So the arrow comes off the page's "
        "unbolded list, and Kyubimon is the entry there that has been a LEAF on `tamers` since "
        "US-150: it clears a dead end, and it puts LadyDevimon on the line whose junk Champion is "
        "Numemon X, which is the ONLY cited parent anywhere in this graph for LadyDevimon "
        "(X-Antibody) — so both halves of the pair land on one line, which is what the criteria's "
        "variant rule asks. Piemon on `penc-nso` was the rejected reading: it is cited too, and it "
        "would have split the pair across two lines. The climb is Beelzebumon, on the page's "
        "`Evolves To` and already `tamers`' Mega over Baalmon since US-157. Spirit is what a "
        "fallen angel earns and Kyubimon had every energy free."),
    "ladydevimon_x": (
        "Numemon (X-Antibody) is one of only three parents Wikimon gives LadyDevimon "
        "(X-Antibody) that this pack can draw at the right rung — the bolded one is LadyDevimon "
        "itself, a Perfect, and Velgrmon is Armor-Hybrid — and it is the only one on the line "
        "this story put the base form on, which is why LadyDevimon went to `tamers` rather than "
        "to `penc-nso`. Numemon X is `tamers`' junk Champion (US-148) and has been a LEAF ever "
        "since, so this arrow clears a dead end too; a junk Champion with an earned branch is the "
        "Scumon arrangement US-133 recorded and the third of its kind here after Raremon and "
        "Scumon. Mantaraymon (X-Antibody) is the page's other drawable parent and is on `vital`, "
        "which still has no Perfect rung — **LadyDevimon X is therefore `vital`'s rehome "
        "candidate**, beside the Boutmon US-157 pinned. The climb is Beel Starmon (X-Antibody), "
        "on the page's `Evolves To`, which had no node and joins the Starmon and DarkSuperstarmon "
        "US-158 put on this same line. Vitality is what an X-Antibody earns and Numemon X had "
        "every energy free."),
    "lavogaritamon": (
        "The tidiest thread in this sweep and both arrows bolded: Wikimon draws Lavogaritamon out "
        "of Lavorvomon and into Volcanicdramon, and Lavorvomon has been a LEAF on `penc-nso` "
        "since US-156 — so the bolded in-edge clears a dead end and the only cost is "
        "Volcanicdramon, which had no node. Ancient Volcamon is the page's other drawable climb "
        "and is on `wanyamon`, which holds no cited parent for this Digimon, so it lost on the "
        "line. Strength is what a lava flow earns and Lavorvomon had every energy free."),
    "lilamon": (
        "**THE ONLY NODE IN THIS SWEEP THAT COST NOTHING ABOVE OR BELOW, AND BOTH ARROWS ARE "
        "BOLDED.** Wikimon draws Lilamon out of Sunflowmon and into Rosemon, and BOTH ENDS WERE "
        "ALREADY ON `palmon`: Sunflowmon is one of the Children US-149 wired a Champion for and "
        "has been a LEAF ever since, and Rosemon has been this line's Mega over Lilimon since "
        "US-134 — so US-152's rule of intersecting `Evolves From` against `Evolves To` closes "
        "with no new node AND clears a dead end. Lotusmon is the page's other bolded climb and "
        "has no node anywhere. Vitality is what a flower earns and Sunflowmon had every energy "
        "free."),
    "lilimon_x": (
        "Togemon (X-Antibody) is a bolded `Evolves From` for Lilimon (X-Antibody) on Wikimon — "
        "the other "
        "bolded one is Lilimon itself, a Perfect, which can never be an in-edge — and "
        "`togemon_x` has been a LEAF on `palmon` since US-155. So this is the X-to-X pairing "
        "drawn exactly as the page draws it, on the line the plain Lilimon already sits on, which "
        "is the criteria's variant rule; and it clears a dead end. The climb is Rosemon, cited on "
        "the page and already Lilimon's own Mega, so the two Lilimon converge the way the two "
        "Togemon diverge. Rosemon (X-Antibody) is the bolded climb and has no sheet in this pack. "
        "Spirit is the energy Togemon X had free — it had all four — and it is deliberately NOT "
        "the vitality Sunflowmon spends on Lilamon in this same story, so no `palmon` Champion "
        "offers two flowers on one energy."),
    "lucemon_falldown": (
        "**THE CANONICAL ARROW IS UNDRAWABLE AND THIS SAYS SO RATHER THAN FAKING IT.** Wikimon's "
        "sole bolded `Evolves From` is Lucemon, which is a CHILD on `dmc-v3` — a Child cannot "
        "reach a Perfect in one rung, and the validator's one-rung rule refuses the edge — and "
        "the only `dmc-v3` Adult on the page's list is Scumon, that line's junk Champion, which "
        "holds no cited climb for this Digimon either. So the node goes where the rest of the "
        "page's fallen angels already live: Devimon is a cited parent on `penc-nso`, the "
        "Nightmare Soldiers line, and VenomVamdemon is a cited climb that has been its Mega since "
        "US-140. Ogudomon, Lucemon (X-Antibody), Lucemon: Larva and Lucemon: Satan Mode are the "
        "bolded climbs; only Ogudomon has a sheet, it is an Ultimate orphan of its own, and it "
        "belongs over whichever Demon Lord line a later sweep opens rather than over one Perfect "
        "here. Stamina is the energy Devimon had free after Vamdemon took spirit."),
    # The five Ultimates.
    "ouryumon": (
        "Hisyaryumon's bolded `Evolves To` on Wikimon, drawn with or without Blast Evolution or "
        "Triceramon (X-Antibody), and opened for exactly one Perfect. Ouryumon is the top of the "
        "Ryudamon line the `commandramon` device tree draws from below, and it sits here on "
        "`penc-me` because the Perfect under it does — see Hisyaryumon's comment for the rehome "
        "that would move both. A leaf, as every Ultimate in this file is."),
    "metallicdramon": (
        "Jazarichmon's bolded `Evolves To` on Wikimon, opened for exactly one Perfect. It is "
        "`tamers`' seventh Mega, on a line that had none at all before US-157. A leaf, as every "
        "Ultimate in this file is."),
    "tengumon": (
        "Karatenmon's SOLE bolded `Evolves To` on Wikimon, opened for exactly one Perfect and "
        "`wanyamon`'s third Mega, one story after US-158 gave that line its first two. A crow "
        "tengu's Mega is the tengu itself, which is the whole reason Karatenmon went over Igamon "
        "the ninja rather than over Peckmon. A leaf, as every Ultimate in this file is."),
    "beelstarmon_x": (
        "LadyDevimon (X-Antibody)'s `Evolves To` on Wikimon, opened for exactly one Perfect. "
        "US-158 wanted Beel Starmon over DarkSuperstarmon and could not take it — this pack ships "
        "only the X-Antibody form, which that page does not cite — so the sheet waited for the "
        "one page that DOES cite it. It lands beside the Starmon and DarkSuperstarmon already on "
        "`tamers`. A leaf, as every Ultimate in this file is."),
    "volcanicdramon": (
        "Lavogaritamon's bolded `Evolves To` on Wikimon, opened for exactly one Perfect, and the "
        "top of the only wholly-bolded thread in this sweep. A leaf, as every Ultimate in this "
        "file is."),
}

ELEMENTS = {
    "hangyomon": ("water", "virus"),
    "hisyaryumon": ("steel", "data"),
    "insekimon": ("earth", "data"),
    "jazarichmon": ("dark", "data"),
    "karatenmon": ("wind", "data"),
    "ladydevimon": ("dark", "virus"),
    "ladydevimon_x": ("dark", "virus"),
    "lavogaritamon": ("fire", "virus"),
    "lilamon": ("plant", "data"),
    "lilimon_x": ("plant", "data"),
    "lucemon_falldown": ("dark", "virus"),
    "ouryumon": ("light", "vaccine"),
    "metallicdramon": ("machine", "data"),
    "tengumon": ("wind", "vaccine"),
    "beelstarmon_x": ("dark", "virus"),
    "volcanicdramon": ("fire", "virus"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
# `projectileSymbol|tint` must be unique WITHIN a line and `signatureName` GLOBALLY; `check()`
# below proves both against the real files before anything is written.
MOVES = {
    "hangyomon": ("triangle.fill", "teal", "Strike Fishing", "triangle.fill"),
    "hisyaryumon": ("scissors", "blue", "Ryuuga Zanshouken", "scissors"),
    "insekimon": ("circle.fill", "brown", "Meteor Shard", "circle.fill"),
    "jazarichmon": ("triangle.fill", "red", "Gilded Fang", "triangle.fill"),
    "karatenmon": ("wind", "purple", "Crow Feather Blade", "wind"),
    "ladydevimon": ("hand.raised.fill", "indigo", "Darkness Wave", "hand.raised.fill"),
    "ladydevimon_x": ("triangle.fill", "purple", "Darkness Wave Cross", "triangle.fill"),
    "lavogaritamon": ("drop.fill", "orange", "Magma Bomb", "flame.fill"),
    "lilamon": ("wind", "pink", "Lila Shower", "wind"),
    "lilimon_x": ("triangle.fill", "green", "Flower Cannon Cross", "triangle.fill"),
    "lucemon_falldown": ("star.fill", "purple", "Purgatorial Flame", "flame.fill"),
    "ouryumon": ("hammer.fill", "yellow", "Ouryuuken", "hammer.fill"),
    "metallicdramon": ("gearshape.fill", "indigo", "Metallic Roar", "gearshape.fill"),
    "tengumon": ("wind", "indigo", "Tengu Gale", "wind"),
    "beelstarmon_x": ("star.fill", "gray", "Fatal Bullet Cross", "star.fill"),
    "volcanicdramon": ("triangle.fill", "red", "Volcanic Napalm", "flame.fill"),
}


def condition(metric, window, comparison, value, hint):
    return {"metric": metric, "window": window, "comparison": comparison,
            "value": value, "hint": hint}


def check(nodes, moves):
    """Every collision this rung can produce, proven BEFORE the edit rather than by a red suite."""
    line = {n["id"]: n["line"] for n in nodes}
    for pid, _, _, new_line, *_ in PERFECTS:
        line[pid] = new_line
    for uid, _, _, new_line in ULTIMATES:
        line[uid] = new_line

    combos = collections.defaultdict(set)
    names = collections.Counter()
    for i, v in moves.items():
        combos[line.get(i, "?")].add((v["projectileSymbol"], v["tint"]))
        names[v["signatureName"]] += 1
    for i, (symbol, tint, signature, _) in MOVES.items():
        if (symbol, tint) in combos[line[i]]:
            sys.exit("move collision on %s: %s|%s already used on %s" % (i, symbol, tint, line[i]))
        combos[line[i]].add((symbol, tint))
        names[signature] += 1
        if names[signature] > 1:
            sys.exit("signatureName collision on %s: '%s'" % (i, signature))


def main():
    path = ROOT + "Resources/evolutions.json"
    doc = json.loads(open(path).read())
    nodes = doc["nodes"]
    by_id = {n["id"]: n for n in nodes}

    new_ids = [p[0] for p in PERFECTS] + [u[0] for u in ULTIMATES]
    for i in new_ids:
        if i in by_id:
            sys.exit("already authored: " + i)

    check(nodes, json.loads(open(ROOT + "Resources/moves.json").read())["moves"])

    # 1. the in-edges, and a junk floor for every parent that was a leaf.
    for pid, _, _, _, parent, energy, _, _ in PERFECTS:
        node = by_id[parent]
        was_leaf = not node.get("evolutions")
        node.setdefault("evolutions", [])
        edge = {"to": pid, "requiredEnergy": energy, "minEnergy": 120, "maxCareMistakes": 2,
                "conditions": [condition(*c) for c in CONDITIONS[pid]]}
        # The fallback stays last, which is how every other node in the file reads.
        fallback = [e for e in node["evolutions"] if e.get("isDefault")]
        earned = [e for e in node["evolutions"] if not e.get("isDefault")] + [edge]
        if was_leaf:
            junk, junk_energy = JUNK_FLOORS[parent]
            fallback = [{"to": junk, "requiredEnergy": junk_energy, "minEnergy": 0,
                         "maxCareMistakes": 99, "isDefault": True}]
        node["evolutions"] = earned + fallback

    # 2. the eleven Perfects, each a single isDefault climb, the shape every Perfect in the file
    #    has carried since US-134.
    for pid, name, sprite, line, _, _, ultimate, climb in PERFECTS:
        nodes.append({
            "id": pid, "displayName": name, "stage": "Perfect", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[pid],
            "evolutions": [{"to": ultimate, "requiredEnergy": climb, "minEnergy": 150,
                            "maxCareMistakes": 2, "isDefault": True}],
        })

    # 3. the five Ultimates, terminal and so with no `evolutions` key at all.
    for uid, name, sprite, line in ULTIMATES:
        nodes.append({
            "id": uid, "displayName": name, "stage": "Ultimate-Super Ultimate", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[uid],
        })

    open(path, "w").write(json.dumps(doc, indent=2, ensure_ascii=False))

    # 4. elements.json and moves.json, one entry apiece for all sixteen.
    for name, table, key in [("elements.json", ELEMENTS, "types"),
                             ("moves.json", MOVES, "moves")]:
        p = ROOT + "Resources/" + name
        d = json.loads(open(p).read())
        for i in new_ids:
            if name == "elements.json":
                element, attribute = table[i]
                d[key][i] = {"element": element, "attribute": attribute}
            else:
                symbol, tint, signature, sig_symbol = table[i]
                d[key][i] = {"projectileSymbol": symbol, "tint": tint,
                             "signatureName": signature, "signatureSymbol": sig_symbol}
        open(p, "w").write(json.dumps(d, indent=2, ensure_ascii=False))

    print("authored", len(new_ids), "nodes; graph is now", len(nodes))


if __name__ == "__main__":
    main()
