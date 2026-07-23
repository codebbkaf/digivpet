"""US-168 — Orphan sweep: Ultimate-Super Ultimate S-Z, the SIXTH and last Ultimate sweep.

Authors the seventeen playable Ultimate whose display name begins S-Z that no device tree and no
earlier sweep reached. The rung is TERMINAL, so this is an IN-EDGE sweep and nothing else, exactly as
US-163..US-167 recorded: seventeen orphans cost seventeen nodes, each hung as an EARNED branch beside
the climb its Perfect already has (two criteria — one health metric, one care counter — and a
`requiredEnergy` distinct from every other edge on that node). No leaf parents this story: every one
of the sixteen Perfects already led somewhere.

Chaosdramon and Chaosmon are NOT here: they begin with C, not S-Z, and both device trees pin them to
NO node (they are Jogress results, `DMCVersion5/4TreeTests` and `PendulumMetalEmpireTreeTests`), so
they stay orphaned by design and the Ultimate bucket lands at 2, not 0.

Two are Jogress results whose parents sit at the Ultimate rung (Tlalocmon, the Cernumon shape) or one
of whose parents IS a Perfect (Voltobautamon, the Mastemon shape); each still takes a Perfect in-edge
here, exactly as Mastemon/Mitamamon/Millenniumon did. `jogress.json` keeps its recipes all the same.

Sleipmon (X-Antibody) has NO base form on disk (there is no `sleipmon` roster entry at all), so it
cannot use the strong-variant rule; it follows a cited Perfect (Skull Baluchimon, its Digital Monster
X evolution partner) directly.

Run once; it refuses to run twice (every id it adds must be absent).
"""
import collections
import json
import sys

ROOT = "/Users/red/Documents/SourceCode/ios_project/digi/"

# (id, displayName, spriteFile, line, parent, energy)
ULTIMATES = [
    ("sakuyamon", "Sakuyamon", "Sakuyamon", "wanyamon", "machgaogamon", "stamina"),
    ("sakuyamon_x", "Sakuyamon X", "Sakuyamon_X", "wanyamon", "machgaogamon", "vitality"),
    ("shagaramon", "Shagaramon", "Shagaramon", "penc-sw", "pandamon", "strength"),
    ("takutoumon", "Takutoumon", "Takutoumon", "penc-sw", "xingtianmon", "strength"),
    ("xiangpengmon", "Xiangpengmon", "Xiangpengmon", "penc-sw", "sagomon", "strength"),
    ("siriusmon", "Siriusmon", "Siriusmon", "penc-vb", "canoweissmon", "strength"),
    ("slashangemon", "SlashAngemon", "SlashAngemon", "penc-nsp", "asuramon", "strength"),
    ("susanoomon", "Susanoomon", "Susanoomon", "penc-me", "superstarmon", "strength"),
    ("tlalocmon", "Tlalocmon", "Tlalocmon", "penc-wg", "tonosamagekomon", "stamina"),
    ("valdurmon", "Valdurmon", "Valdurmon", "penc-wg", "yatagaramon", "strength"),
    ("ulforcev-dramon_x", "UlforceV-dramon X", "UlforceV-dramon_X", "penc-wg", "aerov-dramon", "vitality"),
    ("ultimatebrachimon", "UltimateBrachimon", "UltimateBrachimon", "dmc-v4", "triceramon", "stamina"),
    ("voltobautamon", "VoltoBautamon", "VoltoBautamon", "penc-nso", "vamdemon", "stamina"),
    ("skullmammon_x", "SkullMammon X", "SkullMammon_X", "penc-nso", "mammon", "stamina"),
    ("wargreymon_x", "WarGreymon X", "WarGreymon_X", "dmc-v3", "metalgreymon_x", "stamina"),
    ("sleipmon_x", "Sleipmon X", "Sleipmon_X", "commandramon", "skullbaluchimon", "strength"),
    ("yukinamon", "Yukinamon", "Yukinamon", "dmc-v3", "sekkamon", "strength"),
]

# The five X-Antibody nodes carry variant "X" (the roster does too).
VARIANTS = {"sakuyamon_x", "ulforcev-dramon_x", "skullmammon_x", "wargreymon_x", "sleipmon_x"}

# No leaf parents this story: every Perfect already had a climb.
LEAF_PARENTS = set()

# Two criteria on every EARNED in-edge: one HealthKit metric, one care counter.
# `care.battleCount`/`care.battleWinRatio` answer only over `lifetime`; every other `care.*` over
# `stage`. Hints spell numbers as words — a sweep test rejects any digit.
CONDITIONS = {
    "sakuyamon": [
        ("health.mindfulMinutes", "stage", "atLeast", 950, "Sit the shrine priestess in a long meditation"),
        ("care.trainingSessions", "stage", "atLeast", 30, "And temper her spirit power in daily rites"),
    ],
    "sakuyamon_x": [
        ("health.steps", "stage", "atLeast", 105000, "Walk the whole spirit road the fox reworks"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.88, "And let her golden staff end every duel"),
    ],
    "shagaramon": [
        ("health.flightsClimbed", "stage", "atLeast", 580, "Haul the stone dragon up every ridge"),
        ("care.trainingSessions", "stage", "atLeast", 28, "And drill the earth pilgrim in the training pit"),
    ],
    "takutoumon": [
        ("health.exerciseMinutes", "stage", "atLeast", 1650, "Keep the sword saint in constant motion"),
        ("care.battleCount", "lifetime", "atLeast", 38, "And prove the twin blades over countless bouts"),
    ],
    "xiangpengmon": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 230000, "March the roc-warrior across the whole grid"),
        ("care.trainingSessions", "stage", "atLeast", 30, "And harden its wings in the training pit"),
    ],
    "siriusmon": [
        ("health.activeEnergy", "stage", "atLeast", 34000, "Pour a hero's spirit into the star knight"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.9, "And let the dog star go unbeaten"),
    ],
    "slashangemon": [
        ("health.flightsClimbed", "stage", "atLeast", 620, "Raise the blade angel higher than any tower"),
        ("care.battleCount", "lifetime", "atLeast", 40, "And let its swords answer every challenger"),
    ],
    "susanoomon": [
        ("health.exerciseMinutes", "stage", "atLeast", 1700, "Train the storm god without a wasted hour"),
        ("care.trainingSessions", "stage", "atLeast", 32, "And forge the ten warriors into one daily"),
    ],
    "tlalocmon": [
        ("health.activeEnergy", "stage", "atLeast", 33000, "Loose the rain god's whole gathered storm"),
        ("care.overfeeds", "stage", "atLeast", 7, "And swell the flood far past every meal"),
    ],
    "valdurmon": [
        ("health.flightsClimbed", "stage", "atLeast", 640, "Lift the sky eagle above every peak"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And let its aurora talons turn each blow"),
    ],
    "ulforcev-dramon_x": [
        ("health.steps", "stage", "atLeast", 110000, "Walk the whole circuit the blue knight reworks"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.9, "And let the Ulforce saber spare no rival"),
    ],
    "ultimatebrachimon": [
        ("health.distanceSwimming", "stage", "atLeast", 44000, "Cross the deep the titan reptile rules"),
        ("care.battleCount", "lifetime", "atLeast", 40, "And drag every challenger under the tide"),
    ],
    "voltobautamon": [
        ("health.activeEnergy", "stage", "atLeast", 36000, "Burn the puppet lord's whole dark engine"),
        ("care.battleCount", "lifetime", "atLeast", 42, "And build its dread one duel at a time"),
    ],
    "skullmammon_x": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 240000, "Range the frozen waste the bone mammoth reworks"),
        ("care.battleCount", "lifetime", "atLeast", 38, "And let its tusks meet every foe"),
    ],
    "wargreymon_x": [
        ("health.flightsClimbed", "stage", "atLeast", 600, "Lift the reforged dragon above every peak"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.88, "And let the Brave Shield turn each blow"),
    ],
    "sleipmon_x": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 250000, "Gallop the reworked knight across the frozen north"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And let its bolt bow end every chase"),
    ],
    "yukinamon": [
        ("health.mindfulMinutes", "stage", "atLeast", 880, "Sit the ice fox in a still winter calm"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And never break its snowbound rest"),
    ],
}

COMMENTS = {
    "sakuyamon": (
        "The Renamon-line fox priestess. Wikimon's `Evolves From` bolds Taomon and Renamon (a Perfect "
        "with no node and a Child), so the drawable citation is Mach Gaogamon (Dα-247) — and Mach "
        "Gaogamon is `wanyamon`'s, the line US-166 already gathered the sister priestess Kuzuhamon onto "
        "(off Karatenmon). Placing Sakuyamon there keeps the two shrine-maiden forms on ONE line. "
        "Stamina; Sakuyamon X takes vitality off the same Perfect in this same edit."),
    "sakuyamon_x": (
        "SITS ON ITS BASE FORM'S OWN PERFECT, the strong variant rule. Wikimon's `Evolves From` for "
        "Sakuyamon (X-Antibody) bolds only the plain Sakuyamon, an Ultimate `invalidStageTransition` "
        "refuses, so the antibody hangs where the plain Sakuyamon hangs — Mach Gaogamon on `wanyamon`. "
        "Vitality; the second of Mach Gaogamon's two priestess branches, distinct from Sakuyamon's "
        "stamina."),
    "shagaramon": (
        "A Saiyu Warriors (Journey to the West) beast. Wikimon bolds Calamaramon (no node), and every "
        "other cited `Evolves From` — Cho·Hakkaimon, Huankunmon, Pandamon, Sagomon — is a Saiyu "
        "Warriors Perfect. Pandamon is `penc-sw`'s and takes the earth dragon here. `penc-sw` (Saiyu "
        "Warriors) has no Digitama in this pack, so Shagaramon is stranded-from-egg like every node on "
        "the line. Strength."),
    "takutoumon": (
        "A Saiyu Warriors sword saint. Wikimon's `Evolves From` cites Xingtianmon, Sagomon and "
        "Sanzomon — all Saiyu Warriors Perfects — beside the off-line Beowolfmon/Bryweludramon. "
        "Xingtianmon is `penc-sw`'s and carries the twin-bladed warrior here. `penc-sw` (Saiyu "
        "Warriors) has no Digitama, so Takutoumon is stranded-from-egg like every node on the line. "
        "Strength."),
    "xiangpengmon": (
        "A Saiyu Warriors roc-warrior. Wikimon bolds Huankunmon (a Saiyu Warriors Perfect the roster "
        "wired to `dmc-v4`) and also cites Sagomon, which is `penc-sw`'s — so Sagomon keeps the roc on "
        "the Saiyu Warriors line proper. `penc-sw` (Saiyu Warriors) has no Digitama, so Xiangpengmon "
        "is stranded-from-egg like every node on the line. Strength."),
    "siriusmon": (
        "Wikimon BOLDS Canoweissmon (Digimon Masters, Pendulum COLOR ZERO Virus Busters, Digimon RPG) "
        "as the star knight's `Evolves From`, and Canoweissmon is `penc-vb`'s — the Virus Busters line "
        "the whole Bemon -> Canoweissmon -> Regulusmon -> Siriusmon thread belongs to — so Siriusmon "
        "lands on its own line for nothing. Its other citations (Regulusmon, Metal Greymon, Gammamon) "
        "are off this thread or already spoken for. Strength."),
    "slashangemon": (
        "Wikimon bolds Shakkoumon (no node) for the blade angel and cites Holy Angemon, Asuramon, "
        "Giromon, Piccolomon and Knightmon among its Perfects. Holy Angemon and Knightmon are FULL — "
        "all four energies spent — and Seraphimon is an Ultimate, so Asuramon is the drawable holy-line "
        "Perfect: it is `penc-nsp`'s, the angel line Angewomon and Seraphimon already sit on, keeping "
        "SlashAngemon among the seraphim. Strength."),
    "susanoomon": (
        "**ITS `Evolves From` IS A JOGRESS OF TWO FRONTIER ULTIMATES**, the Cernumon shape: Wikimon "
        "bolds Kaiser Greymon and Magna Garurumon (with the Warrior Ten), both Ultimates "
        "`invalidStageTransition` refuses. Among its drawable Perfect citations only Superstarmon is a "
        "node, and it is `penc-me`'s, so the storm god is drawn one rung below on the Perfect that "
        "cites it (Superstarmon, Magnamon). Strength."),
    "tlalocmon": (
        "**ITS `Evolves From` IS A JOGRESS OF THREE ULTIMATES**, the Cernumon/Mitamamon shape: Wikimon "
        "draws Tlalocmon from El Doradimon, Metal Etemon and Saber Leomon (Pendulum COLOR 1 Nature "
        "Spirits), all Ultimates `invalidStageTransition` refuses. Tonosamagekomon climbs into El "
        "Doradimon on `penc-wg`, so the Aztec rain god lands one rung below on that Perfect. "
        "`jogress.json` reserves the recipe, which is wired all the same. Stamina."),
    "valdurmon": (
        "A holy sky-eagle of the Norse pantheon. Wikimon bolds Falcomon (a Child) and cites Garudamon, "
        "Yatagaramon and Hououmon among its Perfects — all `penc-wg`'s, the Wind Guardians bird line. "
        "Yatagaramon (the three-legged crow) carries Valdurmon here, keeping the winged holy Digimon "
        "with the phoenix and the roc. Strength; Yatagaramon spends spirit on its Hououmon climb."),
    "ulforcev-dramon_x": (
        "SITS ON ITS BASE FORM'S OWN PERFECT, the strong variant rule — an antibody rising from an "
        "antibody. Wikimon bolds only the plain Ulforce V-dramon (an Ultimate) for Ulforce V-dramon "
        "(X-Antibody), so it hangs where the base form hangs: Aero V-dramon on `penc-wg`, the V-mon "
        "Wind Guardians line that climbs into the blue Royal Knight. Vitality; Aero V-dramon spends "
        "stamina on Magnamon X and strength on its own Ulforce climb."),
    "ultimatebrachimon": (
        "A titan marine reptile. Wikimon bolds Brachimon (no node) and cites Triceramon, Metal "
        "Tyranomon, Mametyramon and others among its Perfects. Triceramon is `dmc-v4`'s, the dinosaur "
        "line, and carries the giant here — keeping UltimateBrachimon with the reptiles it evolves "
        "beside. Stamina; Triceramon spends strength on its DarkTyranomon-thread DarkDramon climb."),
    "voltobautamon": (
        "**A JOGRESS whose parents on Wikimon are Vamdemon (a Perfect) and Piemon (an Ultimate)**, the "
        "Mastemon shape: because ONE parent is a Perfect, the puppet lord hangs directly off it as a "
        "legal Perfect -> Ultimate edge. Vamdemon is `penc-nso`'s, the Nightmare Soldiers demon line. "
        "`jogress.json` reserves the Vamdemon+Piemon recipe, which is wired all the same. Stamina; the "
        "fourth and last energy on Vamdemon, beside BelialVamdemon, GranDracumon and VenomVamdemon."),
    "skullmammon_x": (
        "SITS ON ITS BASE FORM'S OWN PERFECT, the strong variant rule. Wikimon bolds only the plain "
        "Skull Mammon (an Ultimate) for Skull Mammon (X-Antibody); the sole Perfect it cites is "
        "Mammon, which is `penc-nso`'s and already climbs into the base SkullMammon. So the antibody "
        "bone-mammoth hangs where its base form hangs. Stamina; Mammon spends vitality on "
        "AncientMegatheriumon and strength on its plain SkullMammon climb."),
    "wargreymon_x": (
        "AN ANTIBODY RISING FROM AN ANTIBODY. WarGreymon's base line runs through Metal Greymon on "
        "`dmc-v1`, which US-002 walks and no sweep may fork; but Wikimon BOLDS Metal Greymon "
        "(X-Antibody) for WarGreymon (X-Antibody), and MetalGreymon X is `dmc-v3`'s. So the X dragon "
        "rises from the X Champion, off the walked line entirely. Stamina; MetalGreymon X spends "
        "vitality on Omegamon X and strength on its ChaosDramon climb."),
    "sleipmon_x": (
        "**HAS NO BASE FORM ON DISK** — there is no `sleipmon` roster entry at all — so the strong "
        "variant rule cannot apply and it follows a cited Perfect directly. Wikimon cites Skull "
        "Baluchimon (Digital Monster X) as an `Evolves From` for Sleipmon (X-Antibody), the same "
        "Digital Monster X evolution partner; Skull Baluchimon is `commandramon`'s. Strength; Skull "
        "Baluchimon spends stamina on its ChaosDramon X climb."),
    "yukinamon": (
        "Wikimon BOLDS Sekkamon (Digimon Alysion, Pendulum COLOR 7 Toho Braves) as the ice fox's "
        "`Evolves From`, and Sekkamon is `dmc-v3`'s, so Yukinamon lands on an existing line for "
        "nothing. Its other citations, Karakurumon and Marin Bullmon, are off this thread. Strength; "
        "Sekkamon spends spirit on its Ryugumon climb."),
}

ELEMENTS = {
    "sakuyamon": ("light", "data"),
    "sakuyamon_x": ("light", "data"),
    "shagaramon": ("earth", "data"),
    "takutoumon": ("steel", "data"),
    "xiangpengmon": ("wind", "data"),
    "siriusmon": ("light", "vaccine"),
    "slashangemon": ("light", "vaccine"),
    "susanoomon": ("light", "free"),
    "tlalocmon": ("water", "data"),
    "valdurmon": ("wind", "vaccine"),
    "ulforcev-dramon_x": ("light", "vaccine"),
    "ultimatebrachimon": ("water", "data"),
    "voltobautamon": ("dark", "virus"),
    "skullmammon_x": ("ice", "virus"),
    "wargreymon_x": ("fire", "vaccine"),
    "sleipmon_x": ("ice", "vaccine"),
    "yukinamon": ("ice", "data"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
MOVES = {
    "sakuyamon": ("sparkles", "purple", "Amethyst Mandala", "sparkles"),
    "sakuyamon_x": ("sparkles", "pink", "Amethyst Wind Cross", "sparkles"),
    "shagaramon": ("flame.fill", "green", "Boulder Crush", "flame.fill"),
    "takutoumon": ("scissors", "white", "Heavenly Twin Blades", "scissors"),
    "xiangpengmon": ("wind", "yellow", "Roc Gale", "wind"),
    "siriusmon": ("star.fill", "red", "Dog Star Saber", "star.fill"),
    "slashangemon": ("scissors", "white", "Heaven's Ripper", "scissors"),
    "susanoomon": ("wind", "red", "Heavenly Ten Blade", "wind"),
    "tlalocmon": ("drop.fill", "blue", "Divine Deluge", "drop.fill"),
    "valdurmon": ("wind", "cyan", "Aurora Undulation", "wind"),
    "ulforcev-dramon_x": ("bolt.fill", "cyan", "Tensegrity Cross", "bolt.fill"),
    "ultimatebrachimon": ("drop.fill", "purple", "Deep Arbiter", "drop.fill"),
    "voltobautamon": ("scissors", "white", "Marionette Storm", "scissors"),
    "skullmammon_x": ("snowflake", "purple", "Tusk Crusher Cross", "snowflake"),
    "wargreymon_x": ("flame.fill", "green", "Gaia Force Cross", "flame.fill"),
    "sleipmon_x": ("snowflake", "blue", "Bifrost Cross", "snowflake"),
    "yukinamon": ("snowflake", "red", "Blizzard Fang", "snowflake"),
}


def condition(metric, window, comparison, value, hint):
    return {"metric": metric, "window": window, "comparison": comparison,
            "value": value, "hint": hint}


def check(nodes, moves):
    """Every collision this rung can produce, proven BEFORE the edit rather than by a red suite."""
    line = {n["id"]: n["line"] for n in nodes}
    for uid, _, _, new_line, *_ in ULTIMATES:
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

    by_name = {n["displayName"]: n for n in nodes}
    for uid, name, *_ in ULTIMATES:
        sig = MOVES[uid][2]
        if name in sig:
            sys.exit("signatureName contains displayName on %s: '%s'" % (uid, sig))

    for uid, cs in CONDITIONS.items():
        for c in cs:
            if any(ch.isdigit() for ch in c[4]):
                sys.exit("hint states a number on %s: %s" % (uid, c[4]))

    by_id = {n["id"]: n for n in nodes}
    for uid, _, _, new_line, parent, energy in ULTIMATES:
        node = by_id.get(parent)
        if node is None:
            sys.exit("%s has no parent node %s" % (uid, parent))
        if node["stage"] != "Perfect":
            sys.exit("%s's parent %s is %s, not a Perfect" % (uid, parent, node["stage"]))
        if node["line"] != new_line:
            sys.exit("%s is on %s but its parent is on %s" % (uid, new_line, node["line"]))

    for uid in CONDITIONS:
        pass
    for uid, *_ in ULTIMATES:
        if uid not in CONDITIONS:
            sys.exit("%s is an earned branch and must carry criteria" % uid)

    spend = collections.defaultdict(list)
    for uid, _, _, _, parent, energy in ULTIMATES:
        spend[parent].append(energy)
    for parent, energies in spend.items():
        existing = [e.get("requiredEnergy") for e in by_id[parent].get("evolutions", [])]
        allE = existing + energies
        if len(set(allE)) != len(allE):
            sys.exit("%s would spend one energy twice: %s" % (parent, allE))


def main():
    path = ROOT + "Resources/evolutions.json"
    doc = json.loads(open(path).read())
    nodes = doc["nodes"]
    by_id = {n["id"]: n for n in nodes}

    new_ids = [u[0] for u in ULTIMATES]
    for i in new_ids:
        if i in by_id:
            sys.exit("already authored: " + i)

    check(nodes, json.loads(open(ROOT + "Resources/moves.json").read())["moves"])

    # 1. the in-edges (all EARNED — no leaf climbs this story).
    for uid, _, _, _, parent, energy in ULTIMATES:
        node = by_id[parent]
        node.setdefault("evolutions", [])
        edge = {"to": uid, "requiredEnergy": energy, "minEnergy": 150, "maxCareMistakes": 2,
                "conditions": [condition(*c) for c in CONDITIONS[uid]]}
        fallback = [e for e in node["evolutions"] if e.get("isDefault")]
        earned = [e for e in node["evolutions"] if not e.get("isDefault")] + [edge]
        node["evolutions"] = earned + fallback

    # 2. the seventeen Ultimates, terminal and so with no `evolutions` key at all.
    for uid, name, sprite, line, _, _ in ULTIMATES:
        node = {
            "id": uid, "displayName": name, "stage": "Ultimate-Super Ultimate", "line": line,
            "spriteFile": sprite,
        }
        if uid in VARIANTS:
            node["variant"] = "X"
        node["comment"] = COMMENTS[uid]
        nodes.append(node)

    open(path, "w").write(json.dumps(doc, indent=2, ensure_ascii=False))

    # 3. elements.json and moves.json, one entry apiece for all seventeen.
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
