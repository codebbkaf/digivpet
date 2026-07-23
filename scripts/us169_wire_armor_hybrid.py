#!/usr/bin/env python3
"""US-169: wire the 16 Armor-Hybrid orphans into the evolution graph.

Armor-Hybrid is off the ladder (no `ladderIndex`), so an edge into one is never a
stage-transition error. Each orphan takes an EARNED in-edge from an existing,
Digitama-reachable Child on that Child's line, so no edge crosses a line boundary
and every new form is genuinely obtainable. The forms are terminal apex forms,
wired exactly the way US-163..US-168 wired the terminal Ultimates: an in-edge and
nothing above (Armor-Hybrid is the top of its own side branch, and a fallback
out-edge would have to be an unconditional junk edge to nowhere).
"""
import json, collections, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EVO = os.path.join(ROOT, "Resources/evolutions.json")
ELE = os.path.join(ROOT, "Resources/elements.json")
MOV = os.path.join(ROOT, "Resources/moves.json")

# id -> (displayName, spriteFile, line, element, attribute, symbol, tint, signatureName)
NODES = {
    # --- Armor forms on the Adventure 02 Digi-Egg partners (adventure02) ---
    "goldv-dramon":   ("GoldV-dramon", "GoldV-dramon", "adventure02", "light", "vaccine", "sun.max.fill", "yellow", "Golden Rapid Fire"),
    "submarimon":     ("Submarimon", "Submarimon", "adventure02", "water", "data", "drop.fill", "teal", "Oxygen Torpedo"),
    "rapidmon_armor": ("Rapidmon", "Rapidmon_Armor", "adventure02", "steel", "vaccine", "shield.fill", "green", "Twin Missile"),
    "daipenmon":      ("Daipenmon", "Daipenmon", "adventure02", "ice", "data", "snowflake", "cyan", "Beak Buster"),
    "manbomon":       ("Manbomon", "Manbomon", "adventure02", "water", "data", "drop.fill", "cyan", "Sunfish Splash"),
    "shadramon":      ("Shadramon", "Shadramon", "adventure02", "fire", "virus", "flame.fill", "orange", "Flame Fist"),
    # --- Armor forms grouped on the commandramon line ---
    "bitmon":         ("Bitmon", "Bitmon", "commandramon", "machine", "data", "gearshape.fill", "gray", "Byte Storm"),
    "raihimon":       ("Raihimon", "Raihimon", "commandramon", "electric", "data", "bolt.fill", "yellow", "Thunder Lance"),
    "rhinomon":       ("Rhinomon", "Rhinomon", "commandramon", "earth", "vaccine", "mountain.2.fill", "brown", "Atomic Burst"),
    # --- The Frontier Spirit / Hybrid warriors, grouped on the vital line ---
    "beowolfmon":     ("Beowolfmon", "Beowolfmon", "vital", "light", "vaccine", "sun.max.fill", "white", "Cleansing Light"),
    "kaisergreymon":  ("KaiserGreymon", "KaiserGreymon", "vital", "fire", "vaccine", "flame.fill", "yellow", "Pyro Dragons"),
    "duskmon":        ("Duskmon", "Duskmon", "vital", "dark", "virus", "moon.fill", "purple", "Deadly Gaze"),
    "velgrmon":       ("Velgrmon", "Velgrmon", "vital", "dark", "virus", "moon.fill", "indigo", "Dark Vortex"),
    "lynxmon":        ("Lynxmon", "Lynxmon", "vital", "fire", "data", "flame.fill", "cyan", "Wildfire Tackle"),
    "kaiserleomon":   ("KaiserLeomon", "KaiserLeomon", "vital", "dark", "virus", "moon.fill", "gray", "Ebony Blast"),
    "sheepmon":       ("Sheepmon", "Sheepmon", "vital", "light", "data", "sun.max.fill", "yellow", "Holy Fleece"),
}

# parent -> list of (child, requiredEnergy, [(metric, window, comparison, value, hint), ...]).
# Every parent is a Digitama-reachable Child, and every new edge takes an energy the parent had
# free, so `EvolutionEngine.qualifies` can tell the branches apart.
PARENT_EDGES = {
    "v-mon": [
        ("goldv-dramon", "vitality", [
            ("care.trainingSessions", "stage", "atLeast", 28, "Polish the golden crest until it shines"),
            ("health.activeEnergy", "stage", "atLeast", 24000, "and let a Miracle's worth of fire pour in")]),
        ("submarimon", "spirit", [
            ("health.distanceSwimming", "stage", "atLeast", 300, "Take the dive the surface partner cannot"),
            ("care.battleCount", "lifetime", "atLeast", 20, "and earn the reef's trust in battle")]),
        ("rapidmon_armor", "stamina", [
            ("health.steps", "stage", "atLeast", 60000, "Run the long patrol without tiring"),
            ("care.trainingSessions", "stage", "atLeast", 25, "and drill the twin shot straight")]),
    ],
    "wormmon": [
        ("daipenmon", "strength", [
            ("care.battleCount", "lifetime", "atLeast", 24, "Charge the ice like a battering beak"),
            ("health.flightsClimbed", "stage", "atLeast", 40, "and never stop climbing higher")]),
        ("manbomon", "vitality", [
            ("health.exerciseMinutes", "stage", "atLeast", 90, "Drift the open water with an easy heart"),
            ("care.overfeeds", "stage", "atMost", 1, "never overfed, always light in the current")]),
        ("shadramon", "spirit", [
            ("health.activeEnergy", "stage", "atLeast", 26000, "Stoke the insect flame white-hot"),
            ("care.trainingSessions", "stage", "atLeast", 26, "and temper the shell in daily drill")]),
    ],
    "commandramon": [
        ("bitmon", "vitality", [
            ("care.trainingSessions", "stage", "atLeast", 30, "Compile every drill into clean code"),
            ("health.standHours", "stage", "atLeast", 10, "and keep the watch all day")]),
        ("raihimon", "spirit", [
            ("health.exerciseMinutes", "stage", "atLeast", 80, "Store the storm in every stride"),
            ("care.battleCount", "lifetime", "atLeast", 22, "and let the lance fall in battle")]),
        ("rhinomon", "stamina", [
            ("health.steps", "stage", "atLeast", 70000, "March the armored charge for miles"),
            ("care.sleepDisturbances", "stage", "atMost", 1, "and rest sound between the runs")]),
    ],
    "pulsemon": [
        ("beowolfmon", "strength", [
            ("care.battleWinRatio", "lifetime", "atLeast", 0.7, "Carry the Beast Spirit of Light nearly unbeaten"),
            ("care.trainingSessions", "stage", "atLeast", 28, "and drill the wolf's blade true")]),
        ("kaisergreymon", "spirit", [
            ("health.activeEnergy", "stage", "atLeast", 30000, "Fuse the five flames into one crown"),
            ("care.battleCount", "lifetime", "atLeast", 26, "forged over many battles")]),
        ("duskmon", "stamina", [
            ("health.steps", "stage", "atLeast", 65000, "Walk the long night the Spirit demands"),
            ("care.sleepDisturbances", "stage", "atLeast", 3, "its rest broken by the darkness within")]),
    ],
    "kokabuterimon": [
        ("velgrmon", "vitality", [
            ("health.exerciseMinutes", "stage", "atLeast", 85, "Beat the raven's wings until they thunder"),
            ("care.overfeeds", "stage", "atMost", 1, "kept lean enough to take flight")]),
        ("lynxmon", "spirit", [
            ("health.activeEnergy", "stage", "atLeast", 22000, "Kindle the beast's inner blaze"),
            ("care.trainingSessions", "stage", "atLeast", 24, "and sharpen the pounce in drill")]),
    ],
    "sunarizamon": [
        ("kaiserleomon", "strength", [
            ("care.battleWinRatio", "lifetime", "atLeast", 0.65, "Tame the lion's fury into a champion's"),
            ("care.trainingSessions", "stage", "atLeast", 26, "honed over many drills")]),
        ("sheepmon", "spirit", [
            ("health.sleep", "stage", "atLeast", 420, "Gather calm from long, deep sleep"),
            ("care.battleWinRatio", "lifetime", "atLeast", 0.6, "and win gently, more than you lose")]),
    ],
}

COMMENTS = {
    "goldv-dramon": "GoldVeedramon is V-mon's Golden Armor (Digi-Egg of Miracles), so it lands on adventure02 beside V-mon. Terminal apex form.",
    "submarimon": "Submarimon, a Digi-Egg armor; hung on V-mon's adventure02 Digi-Egg line as a coherent group. Terminal apex.",
    "rapidmon_armor": "The Armor Rapidmon (Digi-Egg of Destiny); grouped on the adventure02 Digi-Egg line. Distinct id from the Tamers Rapidmon. Terminal apex.",
    "daipenmon": "Daipenmon, a penguin armor; grouped on Wormmon's adventure02 Digi-Egg branch. Terminal apex.",
    "manbomon": "Manbomon, a sunfish water armor; grouped on Wormmon's adventure02 Digi-Egg branch. Terminal apex.",
    "shadramon": "Shadramon (Digi-Egg of Courage), an insect flame armor; grouped on Wormmon's adventure02 Digi-Egg branch. Terminal apex.",
    "bitmon": "Bitmon, a machine armor; grouped on the commandramon line. Terminal apex.",
    "raihimon": "Raihimon, a thunder armor; grouped on the commandramon line. Terminal apex.",
    "rhinomon": "Rhinomon, an earth charge armor; grouped on the commandramon line. Terminal apex.",
    "beowolfmon": "Beowolfmon, the Beast Spirit of Light warrior; grouped with the Frontier Hybrids on the vital line. Terminal apex.",
    "kaisergreymon": "KaiserGreymon (EmperorGreymon), the Fusion Spirit of Flame; grouped with the Frontier Hybrids on the vital line. Terminal apex.",
    "duskmon": "Duskmon, the Human Spirit of Darkness; grouped with the Frontier Hybrids on the vital line. Terminal apex.",
    "velgrmon": "Velgrmon (Velgemon), the Beast Spirit of Darkness; grouped with the Frontier Hybrids on the vital line. Terminal apex.",
    "lynxmon": "Lynxmon (Digi-Egg of Courage), a fire beast armor; grouped on the vital line. Terminal apex.",
    "kaiserleomon": "KaiserLeomon (JagerLoweemon), the purified Beast Spirit of Darkness; grouped with the Frontier Hybrids on the vital line. Terminal apex.",
    "sheepmon": "Sheepmon, a holy light armor; grouped on the vital line. Terminal apex.",
}


def condition(metric, window, comparison, value, hint):
    return {"metric": metric, "window": window, "comparison": comparison, "value": value, "hint": hint}


def edge(to, energy, conds, min_energy=60, max_care=3):
    return {"to": to, "requiredEnergy": energy, "minEnergy": min_energy,
            "maxCareMistakes": max_care, "conditions": [condition(*c) for c in conds]}


def main():
    evo = json.load(open(EVO))
    nodes = evo["nodes"]
    by_id = {n["id"]: n for n in nodes}

    # 1. The 16 new terminal nodes.
    for nid, (display, sprite, line, *_rest) in NODES.items():
        nodes.append({
            "id": nid,
            "displayName": display,
            "stage": "Armor-Hybrid",
            "line": line,
            "spriteFile": sprite,
            "comment": COMMENTS[nid],
            "evolutions": [],
        })

    # 2. Earned in-edges on the six existing parents, inserted before each parent's fallback.
    for parent, children in PARENT_EDGES.items():
        p = by_id[parent]
        new_edges = [edge(child, energy, conds) for child, energy, conds in children]
        evs = p["evolutions"]
        insert_at = next((i for i, e in enumerate(evs) if e.get("isDefault")), len(evs))
        p["evolutions"] = evs[:insert_at] + new_edges + evs[insert_at:]

    json.dump(evo, open(EVO, "w"), indent=2, ensure_ascii=False)
    open(EVO, "a").write("\n")

    # 3. elements.json entries.
    ele = json.load(open(ELE))
    for nid, (_d, _s, _l, el, at, *_r) in NODES.items():
        ele["types"][nid] = {"element": el, "attribute": at}
    json.dump(ele, open(ELE, "w"), indent=2, ensure_ascii=False)
    open(ELE, "a").write("\n")

    # 4. moves.json entries.
    mov = json.load(open(MOV))
    for nid, (_d, _s, _l, _el, _at, sym, tint, sig) in NODES.items():
        mov["moves"][nid] = {"projectileSymbol": sym, "tint": tint,
                             "signatureName": sig, "signatureSymbol": sym}
    json.dump(mov, open(MOV, "w"), indent=2, ensure_ascii=False)
    open(MOV, "a").write("\n")

    # Sanity: no per-line move collision and no repeated signature name.
    m = mov["moves"]
    per_line, sigs, clash = collections.defaultdict(dict), {}, False
    for n in nodes:
        mv = m.get(n["id"])
        if not mv:
            continue
        key = mv["projectileSymbol"] + "|" + mv["tint"]
        if key in per_line[n["line"]]:
            print("MOVE CLASH", n["line"], key, n["id"], per_line[n["line"]][key]); clash = True
        per_line[n["line"]][key] = n["id"]
        if mv["signatureName"] in sigs and sigs[mv["signatureName"]] != n["id"]:
            print("SIG CLASH", mv["signatureName"], n["id"], sigs[mv["signatureName"]]); clash = True
        sigs[mv["signatureName"]] = n["id"]
    print("clash:", clash, "total nodes:", len(nodes))
    print("line sizes:", {l: sum(1 for n in nodes if n["line"] == l) for l in ["adventure02", "commandramon", "vital"]})


if __name__ == "__main__":
    main()
