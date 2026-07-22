"""US-165 — Orphan sweep: Ultimate-Super Ultimate E-H, the third sweep at the top rung.

Authors the fourteen orphaned Ultimate whose display name begins E-H that no device tree and no
earlier sweep reached. The rung is TERMINAL, so this is an IN-EDGE sweep and nothing else — fourteen
orphans, fourteen nodes, no junk floor and no new line, exactly the shape US-163/US-164 recorded.

Thirteen hang an EARNED branch beside the climb their Perfect already has (two criteria, one health
metric and one care counter, a `requiredEnergy` distinct from every other edge on that node). ONE is
a LEAF's `isDefault` climb: Pandamon, a bolded Saiyu-Warriors parent of Erlangmon that has been a
Perfect dead end, gains its single unconditional climb — one entry off `ChildSweepAToFTests`' ledger.

Notable placements:
  * `hi-andromon` is the sprite pack's SECOND Hi-Andromon design (Wikimon has only "HiAndromon", the
    dmc-v3 node US-138 wired under Andromon). Like Chaosdramon V2 (US-164) it follows a cited parent:
    the OTHER Andromon, `pencme_andromon` on `penc-me`.
  * `examon_x` and `goddramon_x` are X-variants whose BASE FORM is idle-only (dexOnly), so each
    follows a cited parent rather than the base form — DORUguremon (Examon's Cyber Sleuth parent) and
    Megadramon respectively, the Dynasmon X shape.
  * `ebemon_x`, `gankoomon_x`, `holydramon_x`, `hououmon_x` hang off their base form's OWN Perfect,
    the strong variant rule (Holydramon and Hououmon each have several base-form parents; the variant
    takes the one still free).
  * `enmamon` and `gracenovamon` have an `Evolves From` made ENTIRELY of Ultimates, so each is drawn
    one rung below on the Perfect that climbs into a cited Ultimate (the Cernumon shape, US-164).
  * `holydigitamamon` has an EMPTY `Evolves From` on Wikimon, so it lands on its eponym Digitamamon.

TWO PERFECTS REACH FOUR EDGES: DORUguremon (examon_x) and pencme_andromon (hi-andromon) join
HolyAngemon (US-164) as the file's four-edge, all-energies-spent Perfects.

Run once; it refuses to run twice (every id it adds must be absent).
"""
import collections
import json
import sys

ROOT = "/Users/red/Documents/SourceCode/ios_project/digi/"

# (id, displayName, spriteFile, line, parent, energy)
ULTIMATES = [
    ("ebemon_x", "Ebemon X", "Ebemon_X", "dmc-v5", "vademon", "vitality"),
    ("enmamon", "Enmamon", "Enmamon", "penc-sw", "gokuwmon", "vitality"),
    ("erlangmon", "Erlangmon", "Erlangmon", "penc-sw", "pandamon", "spirit"),
    ("examon_x", "Examon X", "Examon_X", "tamers", "doruguremon", "stamina"),
    ("gankoomon_x", "Gankoomon X", "Gankoomon_X", "dmc-v4", "digitamamon", "vitality"),
    ("gigaseadramon", "GigaSeadramon", "GigaSeadramon", "penc-nsp", "megaseadramon", "strength"),
    ("goddramon_x", "Goddramon X", "Goddramon_X", "dmc-v4", "megadramon", "vitality"),
    ("gracenovamon", "GraceNovamon", "GraceNovamon", "penc-nso", "flaremon", "strength"),
    ("granddracumon", "GrandDracumon", "GrandDracumon", "penc-nso", "vamdemon", "strength"),
    ("hi-andromon", "Hi-Andromon", "Hi-Andromon", "penc-me", "pencme_andromon", "spirit"),
    ("holydigitamamon", "HolyDigitamamon", "HolyDigitamamon", "dmc-v4", "digitamamon", "spirit"),
    ("holydramon_x", "Holydramon X", "Holydramon_X", "penc-nsp", "angewomon", "spirit"),
    ("hououmon_x", "Hououmon X", "Hououmon_X", "penc-wg", "garudamon_x", "vitality"),
    ("hydramon", "Hydramon", "Hydramon", "penc-wg", "blossomon", "vitality"),
]

# The one Perfect that was a LEAF before this story and now carries its single `isDefault` climb.
LEAF_PARENTS = {"pandamon"}

# Two criteria on every EARNED in-edge: one HealthKit metric, one care counter.
# `care.battleCount` and `care.battleWinRatio` answer only over `lifetime`, every other `care.*` only
# over `stage` — US-150's rule.
CONDITIONS = {
    "ebemon_x": [
        ("health.flightsClimbed", "stage", "atLeast", 560, "Lift the saucer above every rooftop it scans"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And leave nothing standing under the beam"),
    ],
    "enmamon": [
        ("health.sleep", "stage", "atMost", 5400, "Hold the long vigil the judge of the dead holds"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.9, "And pass sentence on all who come before it"),
    ],
    "examon_x": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 240000, "Cross the whole realm the dragon emperor claims"),
        ("care.sleepDisturbances", "stage", "atMost", 2, "And still let the great wings rest between flights"),
    ],
    "gankoomon_x": [
        ("health.activeEnergy", "stage", "atLeast", 30000, "Forge the fist in the hottest work there is"),
        ("care.trainingSessions", "stage", "atLeast", 30, "And drill the young knight without a day off"),
    ],
    "gigaseadramon": [
        ("health.distanceSwimming", "stage", "atLeast", 44000, "Dive past the trench the small ones fear"),
        ("care.battleCount", "lifetime", "atLeast", 34, "And crush every rival that shares the deep"),
    ],
    "goddramon_x": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 220000, "Range the whole sky the god dragon owns"),
        ("care.battleCount", "lifetime", "atLeast", 38, "And answer every challenge to the throne"),
    ],
    "gracenovamon": [
        ("health.activeEnergy", "stage", "atLeast", 32000, "Pour the sun's whole heat into the fusion"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And let its grace overwhelm every rival"),
    ],
    "granddracumon": [
        ("health.daylight", "stage", "atMost", 150, "Keep the demon lord out of the sun entirely"),
        ("care.battleCount", "lifetime", "atLeast", 36, "And build its dread one duel at a time"),
    ],
    "hi-andromon": [
        ("health.flightsClimbed", "stage", "atLeast", 620, "Carry the reforged frame up every stair"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And overwrite every foe the sensors read"),
    ],
    "holydigitamamon": [
        ("health.mindfulMinutes", "stage", "atLeast", 1000, "Sit the long vigil the sacred shell asks"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And never crack its rest in the dark"),
    ],
    "holydramon_x": [
        ("health.steps", "stage", "atLeast", 100000, "Walk the pilgrimage the holy beast keeps"),
        ("care.overfeeds", "stage", "atMost", 1, "And keep its temperance unbroken at the table"),
    ],
    "hououmon_x": [
        ("health.exerciseMinutes", "stage", "atLeast", 1600, "Never let the firebird come to rest"),
        ("care.trainingSessions", "stage", "atLeast", 30, "And fan the flame in the training pit"),
    ],
    "hydramon": [
        ("health.flightsClimbed", "stage", "atLeast", 600, "Climb until every head clears the canopy"),
        ("care.overfeeds", "stage", "atLeast", 7, "And feed all of its mouths far past full"),
    ],
}

COMMENTS = {
    "ebemon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT, the strong variant rule. Wikimon bolds only EBEmon "
        "itself for Ebemon (X-Antibody), an ULTIMATE — `invalidStageTransition` — so the antibody "
        "hangs where the base form hangs: Vademon carries the plain EBEmon on `dmc-v5`, and it is the "
        "abductor-and-abducted flavour besides. Every other `Evolves From` on the page is an Ultimate "
        "or a card-game placeholder. Vitality; Vademon spends strength on EBEmon."),
    "enmamon": (
        "**EVERY `Evolves From` Wikimon GIVES IT IS AN ULTIMATE**, the Cernumon shape (US-164): "
        "Amaterasumon, Kaguyamon, Ryugumon, Seiten Gokuwmon and Tengumon are all bolded and all "
        "ULTIMATES, so `invalidStageTransition` refuses the arrow at the rung the page draws it and "
        "it is drawn one rung below, on the Perfect that climbs into a cited Ultimate. Every citation "
        "is Pendulum COLOR 7 Toho Braves, whose cast the file scattered — Amaterasumon and Zanbamon "
        "on `vital`, Ryugumon on `dmc-v3`, Tengumon on `wanyamon` — but Seiten Gokuwmon lives on "
        "`penc-sw`, and Gokuwmon is its parent there, so the underworld judge lands beside the Saiyu "
        "Warriors (Journey-to-the-West) line its one on-line Ultimate belongs to. Vitality; Gokuwmon "
        "spends strength on Seiten Gokuwmon."),
    "erlangmon": (
        "Pandamon is a BOLDED `Evolves From` on Wikimon, cited to Pendulum COLOR 6 Saiyu Warriors, "
        "and had been a PERFECT DEAD END on `penc-sw` — so the arrow clears a leaf AND follows a "
        "bolded citation, the leaf-climb shape every Ultimate sweep uses. Erlangmon is cited to "
        "Saiyu Warriors, the line Pandamon sits on, and the third-eyed warrior god belongs beside "
        "its Journey-to-the-West cast. Cherubimon Virtue and Metal Garurumon are bolded too and both "
        "ULTIMATES; Sanzomon and Andiramon (Deva) are the other `penc-sw` citations and each already "
        "climbs. Spirit, and it is Pandamon's FIRST edge, so it is the `isDefault` climb and carries "
        "no criteria."),
    "examon_x": (
        "**ITS BASE FORM IS IDLE-ONLY, SO A CITATION HAS TO CARRY IT** — the Dynasmon X shape "
        "(US-164). Wikimon bolds only Examon for Examon (X-Antibody), and the roster marks Examon "
        "`dexOnly`, so `edgeToDexOnlyNode` and the Ultimate rung would refuse that arrow twice over. "
        "DORUguremon is Examon's cited `Evolves From` (Digimon Story: Cyber Sleuth) and is `tamers`', "
        "the line the whole DORUmon dragon thread lives on. **THIS MAKES DORUGUREMON A FOUR-EDGE "
        "PERFECT** — Dorugoramon (strength), Alphamon Ouryuken (spirit), Dynasmon X (vitality) and "
        "now Examon X (stamina) — the second such node after HolyAngemon, and it is closed. The other "
        "cited parents (Breakdramon, EBEmon X, Goddramon X, Metallicdramon, Slayerdramon) are "
        "Ultimates or have no sheet. Stamina."),
    "gankoomon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT, the strong variant rule. Wikimon bolds only Gankoomon "
        "for Gankoomon (X-Antibody), an ULTIMATE — `invalidStageTransition` — so the antibody hangs "
        "where the plain Gankoomon hangs: Digitamamon carries it on `dmc-v4`, the tutor Royal Knight "
        "rising from the egg-with-legs. Vitality; Digitamamon spends strength on Gankoomon, and "
        "spirit on HolyDigitamamon in this same edit — three edges, three energies, so every fork "
        "off it holds."),
    "gigaseadramon": (
        "Mega Seadramon is a BOLDED `Evolves From` on Wikimon and is `penc-nsp`'s since US-153 — the "
        "sea-serpent line this file runs its Seadramon on, so the bolded arrow lands on an existing "
        "line for nothing. Metal Seadramon and Mega Seadramon (X-Antibody) are bolded too, the first "
        "an ULTIMATE and the second not a node in this pack; the rest of the long page is card-game "
        "placeholders and off-line citations. Strength; Mega Seadramon spends vitality on its own "
        "climb."),
    "goddramon_x": (
        "**ITS BASE FORM IS IDLE-ONLY, SO A CITATION HAS TO CARRY IT** — the Dynasmon X shape. "
        "Wikimon bolds only Goddramon for Goddramon (X-Antibody), and the roster marks Goddramon "
        "`dexOnly`, so `edgeToDexOnlyNode` refuses the base-form arrow. The plain Goddramon's one "
        "bolded parent is HolyAngemon, which US-164 CLOSED at four edges, so the golden dragon god "
        "cannot follow it; Megadramon is a cited `Evolves From` for BOTH Goddramon and its antibody "
        "and is `dmc-v4`'s, a mechanical dragon rising into a holy one. Seraphimon and Justimon: "
        "Blitz Arm are Ultimates; Grademon (`tamers`), Metal Tyranomon (`dmc-v5`) and the card-game "
        "placeholders are off this line. Vitality; Megadramon spends strength on its own climb."),
    "gracenovamon": (
        "**BOTH BOLDED PARENTS ARE ULTIMATES**, the Cernumon shape: Apollomon (with Dianamon) and "
        "Dianamon (with Apollomon) are the whole bolded `Evolves From` on Wikimon, both ULTIMATES that "
        "`invalidStageTransition` refuses, so the sun-and-moon fusion is drawn one rung below on the "
        "Perfect that climbs into a cited Ultimate. Flaremon is Apollomon's parent on `penc-nso` — "
        "the solar half of the fusion, and the flame the nova is named for. Dianamon's parent "
        "Crescemon sits on `tamers` and would have split the pair from Apollomon; the file cannot "
        "draw a two-parent Jogress, and `jogress.json` does not reserve GraceNovamon, so it is a "
        "real orphan wired here. Strength; Flaremon spends vitality on Apollomon."),
    "granddracumon": (
        "Its two bolded `Evolves From` on Wikimon are both UNDRAWABLE — Dracumon is a CHILD "
        "(`invalidStageTransition`) and Matadormon has no sheet in this pack — so the dark lord falls "
        "to a cited parent. Vamdemon is a cited `Evolves From` (Digimon Accel Evil Genome) and is "
        "`penc-nso`'s, the Nightmare Soldiers line a demon lord belongs to. Mephismon, Phelesmon, "
        "Cerberumon, Astamon, Skull Satamon, Sangloupmon, Scorpiomon and Lucemon: Falldown Mode are "
        "the other citations and each is off this line or already climbs. Strength; Vamdemon spends "
        "vitality on Venom Vamdemon and spirit on its other climb."),
    "hi-andromon": (
        "**THE SPRITE PACK'S SECOND Hi-Andromon DESIGN**, and Wikimon has only one page, `HiAndromon` "
        "— the `dmc-v3` node US-138 wired under Andromon. So like Chaosdramon V2 (US-164) this second "
        "design follows a cited parent rather than duplicating the first: Andromon is HiAndromon's "
        "one bolded `Evolves From`, and the OTHER Andromon in the file, `pencme_andromon`, sits on "
        "`penc-me` where Cyberdramon, Megadramon, Metal Mamemon and Giromon — all cited HiAndromon "
        "parents — also live. **THIS MAKES pencme_andromon A FOUR-EDGE PERFECT** (HiAndromon aside on "
        "its own `dmc-v3`), spending its last free energy after US-164's Craniummon X. Spirit."),
    "holydigitamamon": (
        "**ITS `Evolves From` ON Wikimon IS EMPTY** — no bolded parent, no citation at all — so the "
        "placement rests on the eponym: HolyDigitamamon is the sacred form of Digitamamon, the "
        "egg-with-legs, which is `dmc-v4`'s. Digitamamon carries it beside the plain Gankoomon it "
        "already climbs to and the Gankoomon X wired in this same edit. Spirit; Digitamamon spends "
        "strength on Gankoomon and vitality on Gankoomon X — three edges, three energies."),
    "holydramon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT, the strong variant rule. Wikimon bolds Angewomon and "
        "Tailmon (Warp) for Holydramon, and Angewomon is `penc-nsp`'s, carrying the plain Holydramon "
        "already — so the antibody hangs where the holy beast dragon hangs. Panjyamon, the base "
        "form's other parent on the line, is left for a later sweep. Its own page's citations "
        "(Panjyamon X, Lilimon X, Okuwamon X) are Ultimates or off-line. Spirit; Angewomon spends "
        "vitality on Holydramon."),
    "hououmon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT, the strong variant rule, taking the X-Antibody Garuda "
        "so an antibody rises from an antibody. Garudamon (X-Antibody) is one of the three Perfects "
        "that carry the plain Hououmon on `penc-wg`, the Wind Guardians line the phoenix belongs to; "
        "Garudamon and Yatagaramon, the other two, are left for later sweeps. Every bolded `Evolves "
        "From` on Wikimon (Birdramon, Garudamon, Piyomon) is a Champion or the base Garudamon itself. "
        "Vitality; Garudamon X spends spirit on Hououmon."),
    "hydramon": (
        "Blossomon is a BOLDED `Evolves From` on Wikimon, cited to Pendulum COLOR 4 Wind Guardians, "
        "and is `penc-wg`'s — the Wind Guardians line the many-headed serpent belongs to, so the "
        "bolded arrow lands on an existing line for nothing. Jyureimon and Jewelbeemon are bolded too "
        "and each already climbs or has no node; Archnemon, Lilimon, Gerbemon and Toropiamon are the "
        "other bolded names and each is off this line. Vitality; Blossomon spends stamina on its own "
        "climb."),
}

ELEMENTS = {
    "ebemon_x": ("machine", "virus"),
    "enmamon": ("dark", "virus"),
    "erlangmon": ("light", "vaccine"),
    "examon_x": ("fire", "vaccine"),
    "gankoomon_x": ("fire", "vaccine"),
    "gigaseadramon": ("water", "virus"),
    "goddramon_x": ("light", "vaccine"),
    "gracenovamon": ("fire", "vaccine"),
    "granddracumon": ("dark", "virus"),
    "hi-andromon": ("machine", "vaccine"),
    "holydigitamamon": ("light", "data"),
    "holydramon_x": ("light", "vaccine"),
    "hououmon_x": ("fire", "vaccine"),
    "hydramon": ("wind", "virus"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
MOVES = {
    "ebemon_x": ("eye.fill", "purple", "Dark Network Cross", "eye.fill"),
    "enmamon": ("flame.fill", "purple", "Hell's Judgment", "flame.fill"),
    "erlangmon": ("eye.fill", "white", "Three Pointed Blade", "eye.fill"),
    "examon_x": ("wind", "pink", "Pendragon Glory Cross", "wind"),
    "gankoomon_x": ("hand.raised.fill", "orange", "Kongou Cross", "hand.raised.fill"),
    "gigaseadramon": ("drop.fill", "purple", "Giga Torpedo", "drop.fill"),
    "goddramon_x": ("flame.fill", "white", "Heaven Fire Cross", "flame.fill"),
    "gracenovamon": ("sparkles", "white", "Grace Nova", "sparkles"),
    "granddracumon": ("moon.fill", "white", "Dark Round", "moon.fill"),
    "hi-andromon": ("gearshape.fill", "blue", "Hyper Atomic Ray", "gearshape.fill"),
    "holydigitamamon": ("sparkles", "yellow", "Holy Shell", "sparkles"),
    "holydramon_x": ("sparkles", "pink", "Holy Flame Cross", "sparkles"),
    "hououmon_x": ("flame.fill", "purple", "Star Light Explosion Cross", "flame.fill"),
    "hydramon": ("wind", "green", "Hydra Breath", "wind"),
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
        if (parent in LEAF_PARENTS) != (not node.get("evolutions")):
            sys.exit("%s's leaf status disagrees with LEAF_PARENTS" % parent)

    climbed = set()
    for uid, _, _, _, parent, _ in ULTIMATES:
        is_climb = parent in LEAF_PARENTS and parent not in climbed
        if is_climb:
            climbed.add(parent)
        if is_climb and uid in CONDITIONS:
            sys.exit("%s is a leaf's isDefault climb and must not carry criteria" % uid)
        if not is_climb and uid not in CONDITIONS:
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

    # 1. the in-edges.
    climbed = set()
    for uid, _, _, _, parent, energy in ULTIMATES:
        node = by_id[parent]
        node.setdefault("evolutions", [])
        if parent in LEAF_PARENTS and parent not in climbed:
            climbed.add(parent)
            node["evolutions"] = [{"to": uid, "requiredEnergy": energy, "minEnergy": 150,
                                   "maxCareMistakes": 2, "isDefault": True}]
            continue
        edge = {"to": uid, "requiredEnergy": energy, "minEnergy": 150, "maxCareMistakes": 2,
                "conditions": [condition(*c) for c in CONDITIONS[uid]]}
        fallback = [e for e in node["evolutions"] if e.get("isDefault")]
        earned = [e for e in node["evolutions"] if not e.get("isDefault")] + [edge]
        node["evolutions"] = earned + fallback

    # 2. the fourteen Ultimates, terminal and so with no `evolutions` key at all.
    for uid, name, sprite, line, _, _ in ULTIMATES:
        nodes.append({
            "id": uid, "displayName": name, "stage": "Ultimate-Super Ultimate", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[uid],
        })

    open(path, "w").write(json.dumps(doc, indent=2, ensure_ascii=False))

    # 3. elements.json and moves.json, one entry apiece for all fourteen.
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
