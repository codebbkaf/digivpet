"""US-158 — Orphan sweep: Perfect D-G.

Authors the fourteen orphaned Perfect whose display name begins D-G that still needed a node, the
seven Ultimates they climb into that had none, and renames one node: the fifteenth orphan in the
band, `ex-tyranomon`, was ALREADY DRAWN on `dmc-v5` under the hyphen-less id `extyranomon`, so it
costs a rename rather than a node. Run once; it refuses to run twice (every id it adds must be
absent).

Kept in `scripts/` beside `us157_author.py` for the same reason: the JSON round-trips byte-exactly
through `json.dumps(indent=2)`, which is what makes scripted authoring of twenty-one nodes safe.
"""
import json
import sys

ROOT = "/Users/red/Documents/SourceCode/ios_project/digi/"

# (id, displayName, spriteFile, line, parent, parentEnergy, ultimate, climbEnergy)
PERFECTS = [
    ("darkknightmon", "DarkKnightmon", "DarkKnightmon", "penc-nsp",
     "tailmon", "spirit", "darkknightmon_x", "spirit"),
    ("darksuperstarmon", "DarkSuperstarmon", "DarkSuperstarmon", "tamers",
     "starmon", "spirit", "titamon", "spirit"),
    ("delumon", "Delumon", "Delumon", "penc-wg",
     "kiwimon", "vitality", "griffomon", "vitality"),
    ("doruguremon", "DORUguremon", "DORUguremon", "tamers",
     "dorugamon", "strength", "dorugoramon", "strength"),
    ("duramon", "Duramon", "Duramon", "penc-me",
     "raptordramon", "stamina", "pencme_wargreymon", "stamina"),
    ("entmon", "Entmon", "Entmon", "penc-vb",
     "cockatrimon", "vitality", "cherubimon_virtue", "vitality"),
    ("fantomon", "Fantomon", "Fantomon", "penc-nso",
     "wizarmon", "stamina", "piemon", "stamina"),
    ("flaremon", "Flaremon", "Flaremon", "penc-nso",
     "firamon", "vitality", "apollomon", "vitality"),
    ("garudamon_x", "Garudamon X", "Garudamon_X", "penc-wg",
     "pencwg_birdramon", "spirit", "hououmon", "spirit"),
    ("gigadramon", "Gigadramon", "Gigadramon", "dmc-v5",
     "devidramon", "strength", "mugendramon", "strength"),
    ("gogmamon", "Gogmamon", "Gogmamon", "wanyamon",
     "gaogamon", "stamina", "ancientvolcamon", "stamina"),
    ("gokuwmon", "Gokuwmon", "Gokuwmon", "penc-sw",
     "ginkakumon", "strength", "seitengokuwmon", "strength"),
    ("grappleomon", "Grappleomon", "Grappleomon", "wanyamon",
     "gryzmon", "strength", "dinotigermon", "strength"),
    ("gusokumon", "Gusokumon", "Gusokumon", "penc-ds",
     "ebidramon", "strength", "plesiomon", "strength"),
]

# The Ultimates this story had to open, in the order they are appended.
ULTIMATES = [
    ("darkknightmon_x", "DarkKnightmon X", "DarkKnightmon_X", "penc-nsp"),
    ("titamon", "Titamon", "Titamon", "tamers"),
    ("dorugoramon", "DORUgoramon", "DORUgoramon", "tamers"),
    ("apollomon", "Apollomon", "Apollomon", "penc-nso"),
    ("ancientvolcamon", "AncientVolcamon", "AncientVolcamon", "wanyamon"),
    ("dinotigermon", "Dinotigermon", "Dinotigermon", "wanyamon"),
    ("seitengokuwmon", "SeitenGokuwmon", "SeitenGokuwmon", "penc-sw"),
]

# The Champions that were LEAVES before this story: giving one an out-edge means giving it its
# line's junk floor too, or `EvolutionCriteriaTests` fails. Every floor here already existed —
# this story authors no new junk node, which US-157's Pandamon had to.
JUNK_FLOORS = {
    "starmon": ("catchmamemon", "strength"),
    "dorugamon": ("catchmamemon", "strength"),
    "cockatrimon": ("andiramon_virus", "strength"),
    "firamon": ("darumamon", "strength"),
    "gaogamon": ("karakurumon", "spirit"),
    "ginkakumon": ("pandamon", "stamina"),
    "gryzmon": ("karakurumon", "spirit"),
}

# The criteria on each new in-edge. Two apiece: one HealthKit, one care counter, so no edge is
# earned by walking alone and none by playing alone.
CONDITIONS = {
    "darkknightmon": [
        ("health.sleep", "stage", "atMost", 5400, "Keep the black watch and do not sleep it off"),
        ("care.battleCount", "lifetime", "atLeast", 26, "And answer every challenger in armour"),
    ],
    "darksuperstarmon": [
        ("health.sleep", "stage", "atLeast", 9600, "Let it keep the hours a dead star keeps"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And never switch the night on over it"),
    ],
    "delumon": [
        ("health.steps", "stage", "atLeast", 40000, "Walk it the length of the tree line"),
        ("care.overfeeds", "stage", "atMost", 2, "And let it take its food from the soil"),
    ],
    "doruguremon": [
        ("health.activeEnergy", "stage", "atLeast", 8800, "Burn until the ore in its hide wakes"),
        ("care.battleCount", "lifetime", "atLeast", 24, "And test the new claws on something"),
    ],
    "duramon": [
        ("health.exerciseMinutes", "stage", "atLeast", 920, "Swing the blade until the arm forgets it"),
        ("care.trainingSessions", "stage", "atLeast", 22, "And put the reps behind the edge"),
    ],
    "entmon": [
        ("health.standHours", "stage", "atLeast", 170, "Stand as long as a tree stands"),
        ("care.overfeeds", "stage", "atMost", 1, "And take only what the ground gives"),
    ],
    "fantomon": [
        ("health.sleep", "stage", "atMost", 6000, "Walk the small hours instead of sleeping them"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.7, "And take far more souls than it loses"),
    ],
    "flaremon": [
        ("health.activeEnergy", "stage", "atLeast", 9200, "Stoke the mane until it is all flame"),
        ("care.trainingSessions", "stage", "atLeast", 24, "And keep feeding the fire the work"),
    ],
    "garudamon_x": [
        ("health.flightsClimbed", "stage", "atLeast", 250, "Climb until the wings have somewhere to be"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.75, "And come down on nearly everything"),
    ],
    "gigadramon": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 32000, "Fly the patrol the whole way out"),
        ("care.battleCount", "lifetime", "atLeast", 28, "And use the arm cannons on the way back"),
    ],
    "gogmamon": [
        ("health.flightsClimbed", "stage", "atLeast", 230, "Haul the ore up, floor after floor"),
        ("care.trainingSessions", "stage", "atLeast", 20, "And pack the shoulders that carry it"),
    ],
    "gokuwmon": [
        ("health.steps", "stage", "atLeast", 48000, "Walk the pilgrim road ahead of everyone"),
        ("care.battleCount", "lifetime", "atLeast", 30, "And clear whatever is on it with the staff"),
    ],
    "grappleomon": [
        ("health.exerciseMinutes", "stage", "atLeast", 1000, "Drill the throws until they are reflex"),
        ("care.trainingSessions", "stage", "atLeast", 26, "And take the mat again the next day"),
    ],
    "gusokumon": [
        ("health.steps", "stage", "atLeast", 43000, "Crawl the trench end to end"),
        ("care.battleCount", "lifetime", "atLeast", 20, "And harden the shell on something that bites"),
    ],
}

COMMENTS = {
    "darkknightmon": (
        "Wikimon bolds exactly five `Evolves From` for DarkKnightmon and four of them are the "
        "Skull Knightmon family — Skull Knightmon itself, its Big Axe and Cavalier Modes, and "
        "Deadly Axemon — none of which has a sheet in this pack. The FIFTH is Tailmon, which is on "
        "`penc-nsp`, and that is the whole reason this node is on the Nature Spirits line rather "
        "than a knight's one: the arrow is the cited one and the line follows the arrow. The climb "
        "is DarkKnightmon (X-Antibody), also bolded, which had no node — so the X hangs off its "
        "base form exactly as the criteria's variant rule asks. Porcupamon and Troopmon are the "
        "page's other drawable parents and both lost on boldness. Spirit is the energy Tailmon had "
        "free after Angewomon took vitality."),
    "darksuperstarmon": (
        "Wikimon gives DarkSuperstarmon no bolded `Evolves From` at all; Starmon is the parent on "
        "the list that is in this graph AND is the Digimon it is visibly the dark counterpart of, "
        "and it has sat on `tamers` as a LEAF since US-150, so the arrow clears a dead end as well "
        "as filling one. The climb is Titamon, on the page's `Evolves To` and with a sheet in this "
        "pack; Beel Starmon would have been the tidier top and this pack has only BeelStarmon X, "
        "which the page does NOT cite, so it was not taken. NOTE FOR THE S-Z SWEEP: the plain "
        "Superstarmon is still an orphan and belongs over this same Starmon, which is where the "
        "variant rule now pins it. Spirit is what a star earns and Starmon had every energy free."),
    "delumon": (
        "Wikimon draws Delumon out of Kiwimon and into Griffomon (bolded), and BOTH ENDS WERE "
        "ALREADY ON `penc-wg`: Kiwimon is one of the Wind Guardians Champions US-141 wired and "
        "Griffomon the Ultimate over Blossomon, so US-152's rule of intersecting `Evolves From` "
        "against `Evolves To` closes with no new node. Delumon is a Bird AND Plant type, which is "
        "Kiwimon exactly, so the flavour agrees with the citation for once. Rosemon is the page's "
        "other bolded climb and is on `palmon`, a line with no cited parent for Delumon. Vitality "
        "is the energy Kiwimon had free after Blossomon took stamina."),
    "doruguremon": (
        "The tidiest thread in this sweep, and every arrow bolded: Wikimon draws DORUguremon out "
        "of DORUgamon and into DORUgoramon, and DORUmon, DORUgamon are both already on `tamers` "
        "(US-150's Champion, a LEAF ever since). So the in-edge clears a dead end, the line is the "
        "one the whole DORUmon family already sits on, and the only cost is DORUgoramon, which had "
        "no node. Alphamon and Death-X-mon are the page's other bolded climbs and neither has a "
        "sheet in this pack. Strength is what a beast dragon earns and DORUgamon had every energy "
        "free."),
    "duramon": (
        "Wikimon's ONLY bolded `Evolves From` for Duramon is Zubaeagermon and its only bolded "
        "`Evolves To` is Durandamon — both are in this pack as IDLE-ONLY sheets, so both are "
        "dexOnly and neither can be on an edge. What is left is the page's unbolded lists, and "
        "`penc-me` is where they intersect: Raptordramon is a cited parent and both Mugendramon "
        "(with Andromon) and War Greymon (with or without Cyberdramon) are cited climbs that the "
        "Metal Empire line already holds. War Greymon is taken because Mugendramon already carries "
        "four of this file's Perfects. Duramon is a Weapon type, which is `penc-me`'s whole "
        "subject. Stamina is the energy Raptordramon had free after Cerberumon X took strength."),
    "entmon": (
        "NO CITATION FOR THE CLIMB, and this says so rather than dressing a line argument as one. "
        "The in-edge IS cited: Wikimon draws Entmon out of Cockatrimon (with a Virus Attribute "
        "Adult from the Digimon Pendulum Z II), and Cockatrimon has been a LEAF on `penc-vb` since "
        "US-150, so the arrow clears a dead end. The `Evolves To` list is three names and this "
        "pack can draw none of them: Ancient Troiamon is idle-only and therefore dexOnly, and "
        "Ornismon and Xuanwumon have no sheet at all. Cherubimon (Virtue) is a LINE argument — the "
        "nature-and-beast Ultimate of the line Cockatrimon sits on — and the day an Ornismon or "
        "Xuanwumon sheet appears it is the first thing to revisit. Vitality is the energy that "
        "suits a tree and Cockatrimon had every one free."),
    "fantomon": (
        "**FANTOMON AND PHANTOMON ARE ONE DIGIMON UNDER A JP AND A DUB NAME, AND THIS PACK SHIPS "
        "BOTH SHEETS** — `Perfect/Fantomon.png` and `Perfect/Phantomon.png` are different art of "
        "the same reaper, which is why the roster has two entries and why the graph now has two "
        "nodes rather than US-143's one-node HolyAngemon/MagnaAngemon treatment: there, one sheet "
        "served two names; here, two sheets exist and the roster is one entry per SHEET. They are "
        "deliberately NOT hung off the same Champion — Phantomon is Bakemon's since US-138 and "
        "Fantomon is Wizarmon's, which Wikimon lists as a parent — so no Champion offers the same "
        "Digimon twice under two names. The climb, Piemon, is on the page too and `penc-nso` "
        "already had it. Stamina is the energy Wizarmon had free after Pumpmon took spirit."),
    "flaremon": (
        "Wikimon's SOLE bolded `Evolves From` for Flaremon is Firamon (with or without Leomon and "
        "Strikedramon), and Firamon has been a LEAF on `penc-nso` since US-149 — so this arrow "
        "costs nothing below and clears a dead end at the same time. The climb is Apollomon, the "
        "page's sole bolded `Evolves To` (with or without Agnimon and Fladramon), which had no "
        "node; Coronamon, Firamon, Flaremon, Apollomon is now a complete four-rung thread on one "
        "line, which is the shape this sweep is trying to produce. Vitality is what a lion of fire "
        "earns and Firamon had every energy free."),
    "garudamon_x": (
        "Wikimon's bolded `Evolves From` for Garudamon (X-Antibody) is Garudamon itself — a "
        "Perfect, which can never be an in-edge — so the arrow comes off the page's unbolded list, "
        "where Birdramon is the parent this graph already has. It lands on `penc-wg` because that "
        "is where the plain Garudamon lives, which is the criteria's variant rule; the same "
        "Birdramon reaches both, so the pair reads as one family. The climb is Hououmon, on the "
        "page and already the Ultimate over the base form. Hououmon (X-Antibody) has a sheet and "
        "would have been the tidier X-to-X pairing, but it is an Ultimate orphan of its own and "
        "the plain one costs nothing. Spirit is the energy Birdramon had free after Garudamon took "
        "vitality."),
    "gigadramon": (
        "Wikimon bolds Devidramon among Gigadramon's `Evolves From` and Mugendramon among its "
        "`Evolves To`, and BOTH are on `dmc-v5` — Devidramon since US-137 and Mugendramon over "
        "MetalTyranomon — so US-152's intersection closes with no new node. Gigadramon is "
        "Megadramon's other half and Megadramon is on `dmc-v4`; that was the rejected reading, "
        "because `dmc-v4` holds no cited parent for Gigadramon at all and pairing the two would "
        "have meant inventing one. Strength is the energy Devidramon had free after Ex-Tyranomon "
        "took spirit."),
    "gogmamon": (
        "**THE FIRST OF THE TWO NODES THAT GIVE `wanyamon` AN ULTIMATE RUNG AT LAST** — US-157 "
        "handed it on by name as the last line in the file with Perfects and no Mega above them. "
        "Wikimon gives Gogmamon no bolded `Evolves From`; Gaogamon is the parent on its list that "
        "this graph already has, and it has been a LEAF on `wanyamon` since US-150, so the arrow "
        "clears a dead end. The climb is Ancient Volcamon, on the page's `Evolves To` and with a "
        "sheet: Gogmamon is an Ore type and the Ancient of earth and fire is the reading that "
        "keeps that. Mirage Gaogamon is the page's tidier climb — it is Gaogamon's own Mega — and "
        "is IDLE-ONLY in this pack, therefore dexOnly and unusable; that is the arrow to draw the "
        "day the sheet gains frames. Stamina is what an ore-carrier earns and Gaogamon had every "
        "energy free."),
    "gokuwmon": (
        "NO CITATION FOR THE IN-EDGE, AND THIS SAYS SO. Wikimon gives Gokuwmon three parents — "
        "Hanumon (`penc-nso`), Kinkakumon (`penc-ds`) and Turuiemon (`penc-vb`) — and not one of "
        "them is on `penc-sw`, the Saiyu Warriors line this Digimon obviously belongs to: it is "
        "Son Goku, and Cho-Hakkaimon (Zhu Bajie) has been over Hakubamon since US-157. So the "
        "in-edge is a LINE argument off Ginkakumon, the Silver-Horn King of the same Journey to "
        "the West cast and a LEAF on `penc-sw` since US-150 — and it is the CHEAP shape of that "
        "argument, because Ginkakumon's twin Kinkakumon IS a cited parent and is exactly the node "
        "US-153 and US-157 both pinned as `penc-sw`'s rehome candidate. Rehome Kinkakumon off "
        "`penc-ds` and this arrow becomes a citation; that is the story to write, and it is not "
        "this one. The climb is cited and bolded: Seiten Gokuwmon, with or without Cho-Hakkaimon "
        "or Sagomon. Shakamon, the line's other bolded climb, is already Cho-Hakkaimon's. Strength "
        "is what a staff earns and Ginkakumon had every energy free."),
    "grappleomon": (
        "**THE SECOND OF THE TWO NODES THAT GIVE `wanyamon` AN ULTIMATE RUNG.** Wikimon bolds "
        "Gryzmon among Grappleomon's `Evolves From` — beside Leomon and three warp evolutions — "
        "and Gryzmon has been a LEAF on `wanyamon` since US-150, so the bolded arrow is also the "
        "one that clears a dead end. Leomon is on `dmc-v4`, whose four Ultimates the page does not "
        "name, so it lost on price rather than on boldness. All three bolded climbs are undrawable "
        "here — Heavy Leomon and Pile Volcamon are idle-only and therefore dexOnly, and Marsmon "
        "and Saber Leomon's line hold no parent — so the climb comes off the unbolded list: "
        "Dinotigermon, a Beast Man Mega for a Beast Man Perfect on a line of beasts. Strength is "
        "what a grappler earns and Gryzmon had every energy free."),
    "gusokumon": (
        "Wikimon's sole bolded `Evolves From` for Gusokumon is Ebidramon, which is on `penc-ds` "
        "and already branching, and its `Evolves To` names Plesiomon (with a Virus Attribute "
        "Perfect), which `penc-ds` has had over Whamon since US-139 — so US-152's intersection "
        "closes with no new node and without touching the dead-end ledger. Aegisdramon and Metal "
        "Seadramon are the page's other drawable climbs; Aegisdramon already carries two of this "
        "file's Perfects and Plesiomon only one. Strength is the last energy Ebidramon had free: "
        "vitality went to Anomalocarimon in US-139 and stamina to Anomalocarimon X in US-157, so "
        "this node is now one earned branch off the ceiling."),
    # The seven Ultimates.
    "darkknightmon_x": (
        "DarkKnightmon's bolded `Evolves To` on Wikimon, opened for exactly one Perfect and "
        "landing on its base form's line, which is the criteria's variant rule read from the top "
        "rather than the bottom. A leaf, as every Ultimate in this file is."),
    "titamon": (
        "DarkSuperstarmon's `Evolves To` on Wikimon, opened for exactly one Perfect. It is only "
        "the FIFTH Ultimate `tamers` has — the line had none at all until US-157 — and the first "
        "on it that is not a Digimon Tamers name, which is what a dark star's Mega is going to be. "
        "A leaf, as every Ultimate in this file is."),
    "dorugoramon": (
        "DORUguremon's bolded `Evolves To` on Wikimon, drawn with or without MetalGreymon or "
        "Okuwamon (X-Antibody), and opened for exactly one Perfect. It completes the DORUmon "
        "thread on `tamers` from Child to Mega in one story. Alphamon was the bolded alternative "
        "and has no sheet in this pack. A leaf, as every Ultimate in this file is."),
    "apollomon": (
        "Flaremon's SOLE bolded `Evolves To` on Wikimon, drawn with or without Agnimon and "
        "Fladramon, and opened for exactly one Perfect. It is `penc-nso`'s ninth Ultimate and the "
        "top of the only complete Coronamon thread in the file. A leaf, as every Ultimate in this "
        "file is."),
    "ancientvolcamon": (
        "**THE FIRST ULTIMATE `wanyamon` HAS EVER HAD.** Gogmamon's `Evolves To` on Wikimon, "
        "opened for exactly one Perfect, and the node that finally closes the gap US-157 handed "
        "on: `wanyamon` was the last line in the file with a Perfect rung and nothing above it. "
        "One of the Ten Ancient Warriors, which is company Gogmamon's Ore type earns. A leaf, as "
        "every Ultimate in this file is."),
    "dinotigermon": (
        "Grappleomon's `Evolves To` on Wikimon, opened for exactly one Perfect and the second of "
        "the two Ultimates that open `wanyamon`'s top rung. A Beast Man Mega on a line of beasts, "
        "which is the reason it was taken over the page's other unbolded names. A leaf, as every "
        "Ultimate in this file is."),
    "seitengokuwmon": (
        "Gokuwmon's bolded `Evolves To` on Wikimon, drawn with or without Cho-Hakkaimon or "
        "Sagomon, and opened for exactly one Perfect. The SECOND Ultimate the Saiyu Warriors line `penc-sw` has ever had, "
        "after US-157's Shakamon, and stranded with the rest of the line, which has no Digitama. A "
        "leaf, as every Ultimate in this file is."),
}

ELEMENTS = {
    "darkknightmon": ("dark", "virus"),
    "darksuperstarmon": ("dark", "virus"),
    "delumon": ("plant", "data"),
    "doruguremon": ("dark", "data"),
    "duramon": ("steel", "data"),
    "entmon": ("plant", "virus"),
    "fantomon": ("dark", "virus"),
    "flaremon": ("fire", "vaccine"),
    "garudamon_x": ("wind", "vaccine"),
    "gigadramon": ("machine", "virus"),
    "gogmamon": ("earth", "vaccine"),
    "gokuwmon": ("earth", "virus"),
    "grappleomon": ("earth", "vaccine"),
    "gusokumon": ("water", "vaccine"),
    "darkknightmon_x": ("dark", "virus"),
    "titamon": ("dark", "virus"),
    "dorugoramon": ("dark", "data"),
    "apollomon": ("fire", "vaccine"),
    "ancientvolcamon": ("earth", "free"),
    "dinotigermon": ("earth", "vaccine"),
    "seitengokuwmon": ("light", "vaccine"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
MOVES = {
    "darkknightmon": ("triangle.fill", "purple", "Twin Spear", "triangle.fill"),
    "darksuperstarmon": ("star.fill", "purple", "Black Nova", "star.fill"),
    "delumon": ("leaf.fill", "teal", "Feather Bloom", "leaf.fill"),
    "doruguremon": ("wind", "gray", "Metal Cast", "wind"),
    "duramon": ("shield.fill", "gray", "Blade Vow", "shield.fill"),
    "entmon": ("leaf.fill", "brown", "Root Bind", "leaf.fill"),
    "fantomon": ("scissors", "purple", "Soul Chopper", "scissors"),
    "flaremon": ("hand.raised.fill", "orange", "Lion King Advance", "flame.fill"),
    "garudamon_x": ("wind", "red", "Shadow Wing Cross", "wind"),
    "gigadramon": ("gearshape.fill", "indigo", "Giga Stick Bomb", "gearshape.fill"),
    "gogmamon": ("hammer.fill", "gray", "Ore Crusher", "hammer.fill"),
    "gokuwmon": ("hammer.fill", "yellow", "Nyoi Staff", "hammer.fill"),
    "grappleomon": ("hand.raised.fill", "cyan", "Rapid Fist", "hand.raised.fill"),
    "gusokumon": ("scissors", "cyan", "Trench Shear", "scissors"),
    "darkknightmon_x": ("triangle.fill", "indigo", "Demon's Disaster Cross", "triangle.fill"),
    "titamon": ("hammer.fill", "purple", "Titan Bringer", "hammer.fill"),
    "dorugoramon": ("wind", "indigo", "Brave Metal", "wind"),
    "apollomon": ("star.fill", "orange", "Solblaster", "flame.fill"),
    "ancientvolcamon": ("flame.fill", "brown", "Plasma Pillar", "flame.fill"),
    "dinotigermon": ("scissors", "orange", "Tiger Ripper", "scissors"),
    "seitengokuwmon": ("sparkles", "orange", "Ruyi Jingu Bang", "sparkles"),
}


def condition(metric, window, comparison, value, hint):
    return {"metric": metric, "window": window, "comparison": comparison,
            "value": value, "hint": hint}


def main():
    path = ROOT + "Resources/evolutions.json"
    doc = json.loads(open(path).read())
    nodes = doc["nodes"]
    by_id = {n["id"]: n for n in nodes}

    new_ids = [p[0] for p in PERFECTS] + [u[0] for u in ULTIMATES]
    for i in new_ids:
        if i in by_id:
            sys.exit("already authored: " + i)

    # 0. The fifteenth orphan in the band is a RENAME, not a node. `extyranomon` is the roster's
    #    `ex-tyranomon` with the hyphen dropped — one Digimon under two spellings of one id, which
    #    `DMCVersion5TreeTests` has pinned as spelling drift since US-137. Appendix B counts the
    #    hyphenated sheet id as an orphan because nothing points at it, so reconciling the two
    #    clears the orphan and retires the drift in the same edit.
    if "ex-tyranomon" in by_id:
        sys.exit("ex-tyranomon already exists")
    by_id["extyranomon"]["id"] = "ex-tyranomon"
    for node in nodes:
        for edge in node.get("evolutions", []):
            if edge["to"] == "extyranomon":
                edge["to"] = "ex-tyranomon"

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

    # 2. the fourteen Perfects, each a single isDefault climb, the shape every Perfect in the file
    #    has carried since US-134.
    for pid, name, sprite, line, _, _, ultimate, climb in PERFECTS:
        nodes.append({
            "id": pid, "displayName": name, "stage": "Perfect", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[pid],
            "evolutions": [{"to": ultimate, "requiredEnergy": climb, "minEnergy": 150,
                            "maxCareMistakes": 2, "isDefault": True}],
        })

    # 3. the seven Ultimates, terminal and so with no `evolutions` key at all.
    for uid, name, sprite, line in ULTIMATES:
        nodes.append({
            "id": uid, "displayName": name, "stage": "Ultimate-Super Ultimate", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[uid],
        })

    open(path, "w").write(json.dumps(doc, indent=2, ensure_ascii=False))

    # 4. elements.json and moves.json, one entry apiece for all twenty-one, plus the rename.
    for name, table, key in [("elements.json", ELEMENTS, "types"),
                             ("moves.json", MOVES, "moves")]:
        p = ROOT + "Resources/" + name
        d = json.loads(open(p).read())
        # Rebuilt rather than popped so the renamed row keeps its place in the file.
        d[key] = {("ex-tyranomon" if k == "extyranomon" else k): v for k, v in d[key].items()}
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
