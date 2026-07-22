"""US-160 — Orphan sweep: Perfect M.

Authors the twenty-one orphaned Perfect whose display name begins with M, the five Ultimates they
climb into that had no node, and the one junk Perfect floor `diablomon` needed before its Champion
could branch at all. Run once; it refuses to run twice (every id it adds must be absent).

Kept in `scripts/` beside `us157_author.py`, `us158_author.py` and `us159_author.py` for the same
reason: the JSON round-trips byte-exactly through `json.dumps(indent=2, ensure_ascii=False)`, which
is what makes scripted authoring of twenty-seven nodes across three files safe.
"""
import collections
import json
import sys

ROOT = "/Users/red/Documents/SourceCode/ios_project/digi/"

# (id, displayName, spriteFile, line, parent, parentEnergy, ultimate, climbEnergy)
PERFECTS = [
    ("machgaogamon", "MachGaogamon", "MachGaogamon", "wanyamon",
     "gaogamon", "strength", "ancientvolcamon", "strength"),
    ("mamemon_x", "Mamemon X", "Mamemon_X", "dmc-v1",
     "greymon_blue", "strength", "banchomamemon", "strength"),
    ("mammon_x", "Mammon X", "Mammon_X", "penc-nso",
     "shimaunimon", "strength", "pencnso_skullmammon", "strength"),
    ("manticoremon", "Manticoremon", "Manticoremon", "tamers",
     "growmon", "strength", "dukemon", "strength"),
    ("marinbullmon", "MarinBullmon", "MarinBullmon", "dmc-v3",
     "shellmon", "vitality", "ryugumon", "vitality"),
    ("marinchimairamon", "MarinChimairamon", "MarinChimairamon", "penc-ds",
     "octmon", "vitality", "plesiomon", "vitality"),
    ("megaseadramon_x", "MegaSeadramon X", "MegaSeadramon_X", "penc-nsp",
     "hyougamon", "strength", "metalseadramon", "strength"),
    ("megalogrowmon_orange", "MegaloGrowmon Orange", "MegaloGrowmon_Orange", "tamers",
     "growmon_orange", "strength", "dukemon", "strength"),
    ("megalogrowmon_x", "MegaloGrowmon X", "MegaloGrowmon_X", "tamers",
     "blackgalgomon", "strength", "chaosdukemon", "strength"),
    ("meicrackmon", "Meicrackmon", "Meicrackmon", "diablomon",
     "meicoomon", "vitality", "rasielmon", "vitality"),
    ("meicrackmon_vicious", "Meicrackmon Vicious", "Meicrackmon_Vicious", "diablomon",
     "meicoomon", "spirit", "raguelmon", "spirit"),
    ("mephismon", "Mephismon", "Mephismon", "penc-nso",
     "wizarmon", "vitality", "piemon", "vitality"),
    ("mephismon_x", "Mephismon X", "Mephismon_X", "penc-nso",
     "pencnso_devimon", "vitality", "dinorexmon", "vitality"),
    ("mermaimon", "Mermaimon", "Mermaimon", "penc-ds",
     "ikkakumon", "spirit", "vikemon", "spirit"),
    ("metalgreymon_virus_x", "MetalGreymon Virus X", "MetalGreymon_Virus_X", "dmc-v1",
     "devimon", "strength", "blitzgreymon", "strength"),
    ("metalmamemon_x", "MetalMamemon X", "MetalMamemon_X", "penc-me",
     "thunderballmon", "spirit", "princemamemon", "spirit"),
    ("metalphantomon", "MetalPhantomon", "MetalPhantomon", "dmc-v3",
     "bakemon", "spirit", "gokumon", "spirit"),
    ("metaltyranomon_v2", "MetalTyranomon V2", "MetalTyranomon_V2", "dmc-v5",
     "darktyranomon", "vitality", "mugendramon", "vitality"),
    ("metaltyranomon_x", "MetalTyranomon X", "MetalTyranomon_X", "dmc-v5",
     "cyclomon", "strength", "mugendramon", "strength"),
    ("monzaemon_x", "Monzaemon X", "Monzaemon_X", "dmc-v1",
     "numemon", "spirit", "dmcv1_shinmonzaemon", "spirit"),
    ("mummymon", "Mummymon", "Mummymon", "penc-nso",
     "pencnso_bakemon", "stamina", "deathmon", "stamina"),
]

# The Ultimates this story had to open, in the order they are appended.
ULTIMATES = [
    ("dukemon", "Dukemon", "Dukemon", "tamers"),
    ("ryugumon", "Ryugumon", "Ryugumon", "dmc-v3"),
    ("rasielmon", "Rasielmon", "Rasielmon", "diablomon"),
    ("raguelmon", "Raguelmon", "Raguelmon", "diablomon"),
    ("dinorexmon", "Dinorexmon", "Dinorexmon", "penc-nso"),
]

# The one junk PERFECT this story had to invent: `diablomon` had no Perfect rung at all, and
# `EvolutionCriteriaTests` refuses a branching Champion with no `isDefault` edge onto a junk node
# of its own line. (id, displayName, spriteFile, line).
JUNK_PERFECTS = [
    ("diablomon_gerbemon", "Gerbemon", "Gerbemon", "diablomon"),
]

# The five Champions that were LEAVES before this story: giving one an out-edge means giving it its
# line's junk floor in the same edit. Four of the five floors already existed; `diablomon`'s is the
# one node in JUNK_PERFECTS above.
JUNK_FLOORS = {
    "greymon_blue": ("blackkingnumemon", "strength"),
    "growmon": ("catchmamemon", "strength"),
    "blackgalgomon": ("catchmamemon", "strength"),
    "hyougamon": ("pumpmon", "strength"),
    "meicoomon": ("diablomon_gerbemon", "vitality"),
}

# The criteria on each new in-edge. Two apiece: one HealthKit, one care counter, so no edge is
# earned by walking alone and none by playing alone.
CONDITIONS = {
    "machgaogamon": [
        ("health.exerciseMinutes", "stage", "atLeast", 980, "Put it through the whole workout, every day"),
        ("care.trainingSessions", "stage", "atLeast", 26, "And drill the fists until they are a machine"),
    ],
    "mamemon_x": [
        ("health.standHours", "stage", "atLeast", 190, "Keep the little one on its feet all day"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.75, "And let the small fist win most of the fights"),
    ],
    "mammon_x": [
        ("health.steps", "stage", "atLeast", 54000, "March it across the whole of the frozen plain"),
        ("care.overfeeds", "stage", "atMost", 2, "And let it carry weight it grew, not weight you gave"),
    ],
    "manticoremon": [
        ("health.activeEnergy", "stage", "atLeast", 9800, "Keep the furnace in its chest roaring"),
        ("care.battleCount", "lifetime", "atLeast", 24, "And let the tail sting settle every argument"),
    ],
    "marinbullmon": [
        ("health.distanceSwimming", "stage", "atLeast", 6400, "Take it out over the reef and back"),
        ("care.trainingSessions", "stage", "atLeast", 21, "And keep the horns hard against the current"),
    ],
    "marinchimairamon": [
        ("health.distanceSwimming", "stage", "atLeast", 7200, "Swim it until the parts stop arguing"),
        ("care.battleCount", "lifetime", "atLeast", 28, "And let every mouth take its turn"),
    ],
    "megaseadramon_x": [
        ("health.distanceSwimming", "stage", "atLeast", 6800, "Give the long body the whole length of the sea"),
        ("care.sleepDisturbances", "stage", "atMost", 2, "And never wake it in the deep water"),
    ],
    "megalogrowmon_orange": [
        ("health.activeEnergy", "stage", "atLeast", 10400, "Burn until the plating glows the wrong colour"),
        ("care.trainingSessions", "stage", "atLeast", 25, "And drill the arm blades past the point of aching"),
    ],
    "megalogrowmon_x": [
        ("health.exerciseMinutes", "stage", "atLeast", 1020, "Work it until the antibody takes hold"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.78, "And leave the record almost unblemished"),
    ],
    "meicrackmon": [
        ("health.mindfulMinutes", "stage", "atLeast", 200, "Sit with it while the cat learns what it is"),
        ("care.trainingSessions", "stage", "atLeast", 20, "And give the claws somewhere to go"),
    ],
    "meicrackmon_vicious": [
        ("health.sleep", "stage", "atMost", 5200, "Keep it awake past the hour the cat turns"),
        ("care.sleepDisturbances", "stage", "atLeast", 7, "And break its rest until nothing gentle is left"),
    ],
    "mephismon": [
        ("health.daylight", "stage", "atMost", 220, "Keep it out of the sun until the horns come in"),
        ("care.battleCount", "lifetime", "atLeast", 25, "And let the goat settle things by force"),
    ],
    "mephismon_x": [
        ("health.sleep", "stage", "atLeast", 10200, "Let the demon dream the whole night through"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.8, "And wake to a record almost without loss"),
    ],
    "mermaimon": [
        ("health.distanceSwimming", "stage", "atLeast", 5800, "Give it a whole ocean to comb through"),
        ("care.trainingSessions", "stage", "atLeast", 22, "And teach the anchor to swing like a sword"),
    ],
    "metalgreymon_virus_x": [
        ("health.activeEnergy", "stage", "atLeast", 11000, "Drive the reactor in its chest to the red"),
        ("care.overfeeds", "stage", "atMost", 1, "And keep the alloy lean under the plating"),
    ],
    "metalmamemon_x": [
        ("health.flightsClimbed", "stage", "atLeast", 240, "Bounce it up every stair it can find"),
        ("care.battleCount", "lifetime", "atLeast", 23, "And let the little sphere pick its fights"),
    ],
    "metalphantomon": [
        ("health.sleep", "stage", "atLeast", 9600, "Let it keep the hours the scythe keeps"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And never put the light on over it"),
    ],
    "metaltyranomon_v2": [
        ("health.steps", "stage", "atLeast", 50000, "Walk the heavy frame until the joints run smooth"),
        ("care.trainingSessions", "stage", "atLeast", 24, "And test the cannon on something that fights back"),
    ],
    "metaltyranomon_x": [
        ("health.exerciseMinutes", "stage", "atLeast", 1060, "Work the old chassis into the new one"),
        ("care.overfeeds", "stage", "atMost", 2, "And keep the armour bolted to muscle"),
    ],
    "monzaemon_x": [
        ("health.mindfulMinutes", "stage", "atLeast", 240, "Sit quietly with the bear until it means it"),
        ("care.sleepDisturbances", "stage", "atMost", 2, "And let the toy sleep the way a toy should"),
    ],
    "mummymon": [
        ("health.standHours", "stage", "atLeast", 200, "Keep it upright long past when it should have lain down"),
        ("care.battleCount", "lifetime", "atLeast", 27, "And let the bandages take the hits"),
    ],
}

COMMENTS = {
    "machgaogamon": (
        "Gaogamon is MachGaogamon's bolded `Evolves From` on Wikimon — the other bolded name is "
        "Gaomon, a CHILD, which the validator's one-rung rule refuses exactly as it refused "
        "Lucemon under Lucemon Falldown in US-159 — and it has been on `wanyamon` since US-151, so "
        "the bolded arrow needs no new node below. The climb is Ancient Volcamon, on the page's "
        "`Evolves To` and already this line's Mega over Gogmamon: **Mirage Gaogamon and Z'd "
        "Garurumon, the two BOLDED climbs, are both idle-only in this pack** (`Idle Frame Only/`, "
        "dexOnly, and `edgeToDexOnlyNode` forbids the edge), so the canonical top of this thread "
        "cannot be drawn at all and the cited one is taken instead. Strength is what a martial "
        "artist earns; Gaogamon spends stamina on Gogmamon and spirit on its junk fall."),
    "mamemon_x": (
        "Greymon (Blue) is a cited `Evolves From` for Mamemon (X-Antibody) on Wikimon — the bolded one is "
        "Mamemon itself, a Perfect, which can never be an in-edge — and it has been a LEAF on "
        "`dmc-v1` since US-137, so the arrow clears a dead end. It is also the placement the "
        "variant rule wants: the plain Mamemon is on `dmc-v1`, and Bancho Mamemon, this node's "
        "climb, is cited on the page AND is the plain Mamemon's own Mega, so the two Mamemon "
        "converge the way US-159's two Lilimon do. **THIS EDGE OPENS GREYMON (BLUE)**, which had "
        "every energy free and now carries one earned branch and the `dmc-v1` junk floor."),
    "mammon_x": (
        "NOT A CITED PARENT, AND PLACED BY THE VARIANT RULE INSTEAD. Wikimon gives Mammon "
        "(X-Antibody) three `Evolves From`: Mammon itself (a Perfect, never an in-edge), "
        "Monochromon on `dmc-v4` and Tobucatmon on `tamers` — and neither of those two lines holds "
        "a cited climb, so taking either would have split the pair off its base form AND opened a "
        "new Ultimate. Shimaunimon is the Champion the plain Mammon already hangs off on "
        "`penc-nso`, which is the `AdultSweepEToGTests.testTheOneVariantSitsWithItsBaseForm` "
        "shape — the variant hangs off its base form's own parent. The climb IS cited: "
        "\"Skull Mammon\" is on the page's `Evolves To`, and `pencnso_skullmammon` is this line's "
        "own SkullMammon (the alias US-140 authored on the shared sheet), which is also where the "
        "plain Mammon climbs. Strength is what a tusk earns; Shimaunimon spends spirit on Mammon."),
    "manticoremon": (
        "Growmon is a cited `Evolves From` for Manticoremon on Wikimon and has been a LEAF on "
        "`tamers` since US-150, so the arrow clears a dead end — and the climb, Dukemon, is cited "
        "on the same page and had no node anywhere. That is the whole argument for spending "
        "`tamers`' bolded Growmon here rather than on MegaloGrowmon Orange: the Orange form has to "
        "hang off Growmon (Orange) under the variant rule, and EVERY other reading of Manticoremon "
        "opens a Perfect rung on a line that has none — Mimicmon is `algomon`, Reppamon and Tia "
        "Ludomon are `vital`, and neither line has a Perfect or an Ultimate, so each would have "
        "cost a junk floor and a Mega on top of this node. Angemon on `dmc-v2` is the fourth "
        "citation and holds no cited climb. Strength is what a manticore earns and Growmon had "
        "every energy free."),
    "marinbullmon": (
        "BOTH ARROWS BOLDED. Wikimon draws MarinBullmon out of Shellmon and into Ryugumon — the "
        "other bolded parent, Sangomon, is a CHILD on `dmc-v3` and the one-rung rule refuses it — "
        "and Shellmon has been on `dmc-v3` since US-135, so only the climb is new. Ariemon is the "
        "page's other bolded `Evolves To` and lost on flavour rather than on art: Ryugumon is the "
        "dragon palace under the sea, which is where a horned sea-bull belongs. Vitality is what a "
        "bull earns; Shellmon spends stamina on Andromon and on its junk fall."),
    "marinchimairamon": (
        "NOT the Chimairamon on `dmc-v1` under another name — the pack ships `MarinChimairamon.png` "
        "and `Chimairamon.png` as two sheets, so they are two nodes, which is the rule US-158 set "
        "with Fantomon and Phantomon. Octmon is a cited `Evolves From` on Wikimon and has been on "
        "`penc-ds` since US-139; Plesiomon is a cited `Evolves To` and has been this line's Mega "
        "since US-139 too, so US-152's rule of intersecting both ends closes with no new node. "
        "Vitality rather than the strength Octmon's junk edge to Piranimon already asks: sharing "
        "would be legal (the Scumon arrangement) but there was a free energy, so it costs nothing "
        "to keep the two apart."),
    "megaseadramon_x": (
        "PLACED BY THE VARIANT RULE, WITH A CITED CLIMB. MegaSeadramon (X-Antibody) has eleven "
        "drawable `Evolves From` on Wikimon and not one of them is on `penc-nsp`, where the plain "
        "MegaSeadramon lives — so following a citation would have split the pair. Hyougamon is "
        "`penc-nsp`'s remaining LEAF (US-152) and takes the arrow instead, which also clears a "
        "dead end. The climb needs no such argument: Metal Seadramon is on the page's `Evolves To` "
        "and is the plain MegaSeadramon's own Mega on this line, so the two MegaSeadramon "
        "converge. **THIS EDGE OPENS HYOUGAMON**, which had every energy free and now carries one "
        "earned branch and `penc-nsp`'s junk floor."),
    "megalogrowmon_orange": (
        "Growmon (Orange) is a cited `Evolves From` on Wikimon AND is the Champion the plain "
        "MegaloGrowmon already hangs off on `tamers`, so the colour variant hangs off the colour "
        "variant of its base form's parent — the tidiest reading the variant rule can have. Growmon "
        "itself is the BOLDED parent and was deliberately not taken: it is the only leaf on this "
        "line that Manticoremon could have used without opening a Perfect rung elsewhere, and the "
        "variant rule pins this node to Growmon (Orange) anyway. The climb is Dukemon, bolded on "
        "the page and authored by this story — the Mega `tamers` has been owed since US-151 opened "
        "it. Strength; Growmon (Orange) spends vitality on MegaloGrowmon and on its junk fall."),
    "megalogrowmon_x": (
        "BlackGalgomon is a cited `Evolves From` for MegaloGrowmon (X-Antibody) on Wikimon — the bolded one is "
        "MegaloGrowmon itself, a Perfect, which can never be an in-edge — and it has been a LEAF on "
        "`tamers` since US-151, so the arrow clears a dead end on the line the base form is already "
        "on. The climb is Chaos Dukemon, cited on the page and this line's Mega over "
        "BlackMegaloGrowmon since US-152, which keeps the black thread together: BlackGalgomon -> "
        "MegaloGrowmon X -> Chaos Dukemon runs beside BlackGrowmon -> BlackMegaloGrowmon -> Chaos "
        "Dukemon. Dukemon, this story's other new Mega, is cited too and went to the Orange form "
        "so that the two do not share a climb. **THIS EDGE OPENS BLACKGALGOMON.**"),
    "meicrackmon": (
        "Meicoomon is Meicrackmon's SOLE `Evolves From` on Wikimon and it is bolded, and it is the "
        "ONLY parent this pack can draw for either Meicrackmon — which is why this story opens "
        "`diablomon`'s Perfect rung rather than rehoming the pair. That costs three nodes in one "
        "breath, the shape US-151 paid one rung down: the junk floor Gerbemon under Meicoomon "
        "(`EvolutionCriteriaTests` refuses a branching Champion without one), this node, and "
        "Rasielmon over it. Rasielmon is the page's BOLDED `Evolves To`; Holydramon, Mugendramon, "
        "Plesiomon and War Greymon are the cited alternatives and every one is on another line. "
        "Vitality is what a creature still deciding what it is earns."),
    "meicrackmon_vicious": (
        "The second half of the Meicoomon pair, and the reason `diablomon` was opened rather than "
        "the pair being split: Meicoomon is bolded on BOTH Wikimon pages, so one Champion carries both "
        "modes — vitality for the plain Meicrackmon, spirit for this one, which is the "
        "distinct-energy rule `SeedRosterTests` enforces on earned branches. Meicrackmon itself is "
        "the page's other bolded parent and is a Perfect, so it can never be an in-edge; "
        "Pucchiemon and Chrysalimon are idle-only. The climb is Raguelmon, bolded on the page, "
        "authored here; Mastemon is the cited alternative and has no node, and Rosemon is on "
        "`palmon`. The criteria are the mirror of the plain Meicrackmon's on purpose — that one is "
        "earned by sitting with it, this one by never letting it rest."),
    "mephismon": (
        "Wizarmon is Mephismon's SOLE bolded `Evolves From` on Wikimon and has been on `penc-nso` "
        "since US-140, so the bolded arrow needs no new node below. The climb is Piemon, on the "
        "page's `Evolves To` and already this line's Mega over Phantomon, Archnemon and Fantomon "
        "— Metal Seadramon is the page's other drawable climb and is on `penc-nsp`, which holds no "
        "cited parent for this Digimon. Vitality rather than the strength Wizarmon's junk edge to "
        "Darumamon asks: sharing would be legal but there was a free energy. Wizarmon now carries "
        "three earned branches (Pumpmon, Fantomon, Mephismon) plus the fall, and **its last free "
        "energy is strength, which is the one its junk edge already uses** — so a fourth earned "
        "branch here would have to share, and this Champion is effectively closed."),
    "mephismon_x": (
        "**NO DRAWABLE CITED PARENT EXISTS ANYWHERE FOR THIS DIGIMON, AND THIS SAYS SO.** Wikimon "
        "gives Mephismon (X-Antibody) exactly two `Evolves From`: Mephismon itself, which is a "
        "Perfect and can never be an in-edge, and Velgrmon, which is Armor-Hybrid and off the "
        "ladder entirely — the same dead end LadyDevimon X had in US-159, except that one at least "
        "had Numemon X. So the node is placed by the variant rule, on the line this story puts the "
        "plain Mephismon on, and the parent is chosen on flavour among that line's Champions: "
        "Devimon, which is a cited parent of the BASE form and is the demon the goat-demon belongs "
        "beside. The climb is Dinorexmon, the page's SOLE `Evolves To`, which had no node. "
        "Vitality is the energy Devimon had left after Vamdemon took spirit and Lucemon Falldown "
        "stamina in US-159."),
    "mermaimon": (
        "Ikkakumon is a cited `Evolves From` on Wikimon — the bolded one, Shakomon, is a CHILD on "
        "this same `penc-ds` and the one-rung rule refuses it — and Vikemon is a cited "
        "`Evolves To` that has been this line's Mega over Zudomon since US-139 and over Hangyomon "
        "since US-159. So the whole thread is one line's own: Ikkakumon -> Zudomon -> Vikemon is "
        "the document's, and Ikkakumon -> Mermaimon -> Vikemon runs beside it. Spirit; Ikkakumon "
        "spends strength on Zudomon and on its junk fall to Piranimon."),
    "metalgreymon_virus_x": (
        "PLACED BY THE VARIANT RULE. Wikimon's drawable `Evolves From` for MetalGreymon (Virus) "
        "(X-Antibody) are Filmon on `penc-vb` and Scumon on `dmc-v3`, plus the two MetalGreymon "
        "themselves, which are Perfects — and neither of those two lines holds a cited climb, "
        "while `dmc-v1` holds two (Blitz Greymon and War Greymon). Devimon is one of the three "
        "Champions the plain MetalGreymon (Virus) already hangs off on `dmc-v1`, so the variant "
        "hangs off its base form's own parent, and the climb is Blitz Greymon, cited on the page "
        "and the plain form's own Mega. Strength is the energy Devimon had free — it spends spirit "
        "on MetalGreymon (Virus) and on its junk fall."),
    "metalmamemon_x": (
        "FOLLOWS A CITED PARENT RATHER THAN ITS BASE FORM, AND BOTH ARROWS ARE CITED. The plain "
        "MetalMamemon is on `dmc-v2`, whose only cited climb here is Metal Garurumon but which "
        "offers NO cited parent at all — so honouring the variant rule would have meant an "
        "invented arrow at both ends. Thunderballmon and Prince Mamemon are both on the Wikimon "
        "page and both on `penc-me`, and Prince Mamemon is the Mamemon family's own Mega, so the "
        "whole thread is cited: an electric sphere becomes a metal sphere becomes the prince of "
        "spheres. Same escape hatch `ChildSweepMToZTests.testEveryVariantSitsWithItsBaseFormOr"
        "FollowsACitedParent` opened for Shakomon X. Spirit; Thunderballmon spends stamina on "
        "Knightmon and strength on Boutmon and on its junk fall to Locomon."),
    "metalphantomon": (
        "BOTH ARROWS BOLDED. Wikimon draws MetalPhantomon out of Bakemon and into Gokumon, and "
        "both have been on `dmc-v3` since US-135 and US-061, so this node costs nothing above or "
        "below it — the only free placement in the whole sweep. The page's other bolded parent is "
        "Fantomon, a Perfect on `penc-nso`; note that this is NOT that Digimon under another name "
        "the way US-143's HolyAngemon and MagnaAngemon were — `MetalPhantomon.png`, `Fantomon.png` "
        "and `Phantomon.png` are three sheets, so they are three nodes. Spirit; Bakemon spends "
        "vitality on Giromon and on its junk fall to Etemon."),
    "metaltyranomon_v2": (
        "BOTH ARROWS BOLDED, and the variant rule is satisfied for free: DarkTyranomon is the "
        "Champion the plain MetalTyranomon already hangs off on `dmc-v5`, and Mugendramon is that "
        "same MetalTyranomon's own Mega, so the V2 form runs beside the plain one on one line "
        "under one parent. Wikimon bolds exactly this pair. Vitality; DarkTyranomon spends "
        "strength on MetalTyranomon and on its junk fall to Vademon."),
    "metaltyranomon_x": (
        "PLACED BY THE VARIANT RULE, WITH A CITED CLIMB. The drawable `Evolves From` Wikimon gives "
        "MetalTyranomon (X-Antibody) are BlackGrowmon on `tamers` and Monochromon on `dmc-v4`, "
        "neither of which holds a cited climb; Rhinomon is Armor-Hybrid, and the two Tyranomon it "
        "names — Metal Tyranomon (bolded) and Ex-Tyranomon — are Perfects. So the parent is the "
        "OTHER Champion the plain MetalTyranomon hangs off on `dmc-v5`, Cyclomon, which keeps this "
        "node and MetalTyranomon V2 on separate parents rather than piling three Tyranomon on "
        "DarkTyranomon. The climb, Mugendramon, is cited on the page. Strength; Cyclomon spends "
        "vitality on MetalTyranomon and on its junk fall."),
    "monzaemon_x": (
        "PLACED BY THE VARIANT RULE, WITH A CITED CLIMB, AND OFF A JUNK CHAMPION. Wikimon gives "
        "Monzaemon (X-Antibody) one drawable `Evolves From` that is not itself a Perfect — Omekamon "
        "on `penc-me` — and `penc-me` holds no cited climb, while `dmc-v1` holds two (Platinum "
        "Numemon and Shin Monzaemon). Numemon is the Champion the plain Monzaemon already hangs "
        "off on `dmc-v1`, so the variant hangs off its base form's own parent; that it is also "
        "this line's JUNK Champion is the Scumon arrangement US-133 recorded and the fourth of its "
        "kind here, after Raremon, Scumon and Numemon X. The climb is Shin Monzaemon, cited on the "
        "page and the plain Monzaemon's own Mega, so the two teddy bears converge. Spirit; Numemon "
        "spends strength on MetalGreymon and on its junk fall, and vitality on Monzaemon."),
    "mummymon": (
        "Bakemon is a cited `Evolves From` on Wikimon and this line has its OWN Bakemon — "
        "`pencnso_bakemon`, the alias US-140 authored on the shared sheet — so the citation is "
        "honoured on `penc-nso` rather than on `dmc-v3`, where the plain Bakemon is already spent "
        "on MetalPhantomon in this same story. That matters: no single Champion offers two of this "
        "sweep's undead. The climb is Deathmon, cited on the page and this line's Mega over "
        "Darumamon since US-140 — VenomVamdemon is the other cited climb and already carries "
        "US-159's Lucemon Falldown. Stamina is what a thing that refuses to lie down earns; "
        "`pencnso_bakemon` spends vitality on Phantomon and strength on its junk fall."),
    # The five Ultimates.
    "dukemon": (
        "MegaloGrowmon Orange's bolded `Evolves To` on Wikimon and a cited climb for Manticoremon, "
        "and the Mega `tamers` has been owed since US-151 opened that line's Perfect rung: this is "
        "the Guilmon line's own top, drawn at last. It is the only Ultimate in this story with two "
        "parents, which is deliberate — the pair are the two Perfects on this line whose pages "
        "both name it. A leaf, as every Ultimate in this file is."),
    "ryugumon": (
        "MarinBullmon's bolded `Evolves To` on Wikimon, opened for exactly one Perfect. Ryugumon "
        "is the dragon of the undersea palace and sits on `dmc-v3` because the Perfect under it "
        "does — Shellmon's line. A leaf, as every Ultimate in this file is."),
    "rasielmon": (
        "Meicrackmon's bolded `Evolves To` on Wikimon and the first Ultimate `diablomon` has ever "
        "had. US-158 wrote that a sweep opening a Perfect rung on one of the six lines with none "
        "owes an Ultimate over it in the same story or it re-opens the gap; this and Raguelmon are "
        "that debt paid. A leaf, as every Ultimate in this file is."),
    "raguelmon": (
        "Meicrackmon: Vicious Mode's bolded `Evolves To` on Wikimon, and `diablomon`'s second "
        "Ultimate. Ordinemon, the Digimon the tri. films put above it, has no sheet in this pack. "
        "A leaf, as every Ultimate in this file is."),
    "dinorexmon": (
        "Mephismon (X-Antibody)'s SOLE `Evolves To` on Wikimon, opened for exactly one Perfect. It "
        "sits on `penc-nso` because the Perfect under it does — see that node's comment for why "
        "the whole pair is placed by the variant rule rather than by citation. A leaf, as every "
        "Ultimate in this file is."),
    # The one junk Perfect.
    "diablomon_gerbemon": (
        "FLAVOUR, AND A LINE-SCOPED ALIAS RATHER THAN A NEW SHEET. The `diablomon` line had no "
        "junk PERFECT and every branching Champion needs one (`EvolutionCriteriaTests`), so "
        "opening this line's Perfect rung for the two Meicrackmon meant authoring a floor under "
        "Meicoomon in the same edit — the bill US-151 paid for `wanyamon` and `tamers` and US-157 "
        "for `penc-sw`. It is an ALIAS on the Gerbemon sheet rather than a fresh orphan because "
        "not one of the fifty-eight Perfect still orphaned when this story ran is junk-flavoured; "
        "the `dmcv2_vademon` pattern applies exactly. So unlike CatchMamemon, Karakurumon and "
        "Pandamon this floor removes no orphan. Gerbemon — a bag of rubbish with a Numemon inside "
        "— follows Troopmon, the faceless mook US-148 chose as this line's junk CHAMPION. "
        "`grep -rn Gerbemon` finds it in no tree markdown, the check US-140 insists on."),
}

ELEMENTS = {
    "machgaogamon": ("wind", "data"),
    "mamemon_x": ("steel", "data"),
    "mammon_x": ("ice", "data"),
    "manticoremon": ("fire", "virus"),
    "marinbullmon": ("water", "data"),
    "marinchimairamon": ("water", "virus"),
    "megaseadramon_x": ("water", "data"),
    "megalogrowmon_orange": ("fire", "virus"),
    "megalogrowmon_x": ("fire", "virus"),
    "meicrackmon": ("dark", "virus"),
    "meicrackmon_vicious": ("dark", "virus"),
    "mephismon": ("dark", "virus"),
    "mephismon_x": ("dark", "virus"),
    "mermaimon": ("water", "data"),
    "metalgreymon_virus_x": ("steel", "virus"),
    "metalmamemon_x": ("steel", "data"),
    "metalphantomon": ("dark", "data"),
    "metaltyranomon_v2": ("steel", "virus"),
    "metaltyranomon_x": ("steel", "virus"),
    "monzaemon_x": ("light", "vaccine"),
    "mummymon": ("dark", "virus"),
    "dukemon": ("light", "vaccine"),
    "ryugumon": ("water", "data"),
    "rasielmon": ("light", "vaccine"),
    "raguelmon": ("dark", "virus"),
    "dinorexmon": ("earth", "data"),
    "diablomon_gerbemon": ("dark", "virus"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
# `projectileSymbol|tint` must be unique WITHIN a line and `signatureName` GLOBALLY; `check()`
# below proves both against the real files before anything is written.
MOVES = {
    "machgaogamon": ("hand.raised.fill", "purple", "Winning Knuckle", "hand.raised.fill"),
    "mamemon_x": ("circle.fill", "red", "Smiley Bomb Cross", "circle.fill"),
    "mammon_x": ("snowflake", "red", "Tundra Press", "snowflake"),
    "manticoremon": ("triangle.fill", "yellow", "Sting Tail", "flame.fill"),
    "marinbullmon": ("drop.fill", "purple", "Coral Charge", "drop.fill"),
    "marinchimairamon": ("bolt.fill", "teal", "Deep Chimera", "bolt.fill"),
    "megaseadramon_x": ("bolt.fill", "orange", "Thunder Javelin Cross", "bolt.fill"),
    "megalogrowmon_orange": ("circle.fill", "pink", "Atomic Blaster Orange", "flame.fill"),
    "megalogrowmon_x": ("scissors", "gray", "Double Edge Cross", "scissors"),
    "meicrackmon": ("scissors", "purple", "Hollow Eyes", "scissors"),
    "meicrackmon_vicious": ("triangle.fill", "indigo", "Vicious Claw", "triangle.fill"),
    "mephismon": ("flame.fill", "indigo", "Black Sabbath", "flame.fill"),
    "mephismon_x": ("hand.raised.fill", "red", "Death Cloud Cross", "hand.raised.fill"),
    "mermaimon": ("triangle.fill", "cyan", "Anchor Swing", "triangle.fill"),
    "metalgreymon_virus_x": ("triangle.fill", "gray", "Giga Destroyer Cross", "triangle.fill"),
    "metalmamemon_x": ("circle.fill", "mint", "Magnetic Bomb", "circle.fill"),
    "metalphantomon": ("scissors", "indigo", "Soul Predator", "scissors"),
    "metaltyranomon_v2": ("bolt.fill", "brown", "Nuclear Laser V2", "bolt.fill"),
    "metaltyranomon_x": ("gearshape.fill", "brown", "Nuclear Laser Cross", "gearshape.fill"),
    "monzaemon_x": ("heart.fill", "red", "Heart Attack Cross", "heart.fill"),
    "mummymon": ("hand.raised.fill", "purple", "Necro Bandage", "hand.raised.fill"),
    "dukemon": ("bolt.fill", "brown", "Royal Saber", "bolt.fill"),
    "ryugumon": ("drop.fill", "mint", "Palace Tide", "drop.fill"),
    "rasielmon": ("star.fill", "white", "Prayer of Light", "star.fill"),
    "raguelmon": ("circle.fill", "gray", "Chaos Degradation", "circle.fill"),
    "dinorexmon": ("triangle.fill", "brown", "Dino Rex Fang", "triangle.fill"),
    "diablomon_gerbemon": ("drop.fill", "gray", "Refuse Bag", "drop.fill"),
}


def condition(metric, window, comparison, value, hint):
    return {"metric": metric, "window": window, "comparison": comparison,
            "value": value, "hint": hint}


def check(nodes, moves):
    """Every collision this rung can produce, proven BEFORE the edit rather than by a red suite."""
    line = {n["id"]: n["line"] for n in nodes}
    for pid, _, _, new_line, *_ in PERFECTS:
        line[pid] = new_line
    for uid, _, _, new_line in ULTIMATES + JUNK_PERFECTS:
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

    # No hint may state a number (`EvolutionCriteriaTests.testNoConditionHintContainsADigit`).
    for pid, cs in CONDITIONS.items():
        for c in cs:
            if any(ch.isdigit() for ch in c[4]):
                sys.exit("hint states a number on %s: %s" % (pid, c[4]))

    # Earned branches off one Champion need distinct energies (`SeedRosterTests`).
    by_id = {n["id"]: n for n in nodes}
    spend = collections.defaultdict(list)
    for pid, _, _, _, parent, energy, _, _ in PERFECTS:
        spend[parent].append(energy)
    for parent, energies in spend.items():
        node = by_id[parent]
        used = [e.get("requiredEnergy") for e in node.get("evolutions", []) if not e.get("isDefault")]
        allE = used + energies
        if len(set(allE)) != len(allE):
            sys.exit("%s branches twice on one energy: %s" % (parent, allE))
        total = len([e for e in node.get("evolutions", []) if not e.get("isDefault")]) + len(energies)
        total += 1  # the isDefault fall, which every branching Champion carries
        if total > 5:
            sys.exit("%s would have %d edges, over the ceiling" % (parent, total))


def main():
    path = ROOT + "Resources/evolutions.json"
    doc = json.loads(open(path).read())
    nodes = doc["nodes"]
    by_id = {n["id"]: n for n in nodes}

    new_ids = ([p[0] for p in PERFECTS] + [u[0] for u in ULTIMATES]
               + [j[0] for j in JUNK_PERFECTS])
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

    # 2. the twenty-one Perfects, each a single isDefault climb, the shape every Perfect in the
    #    file has carried since US-134.
    for pid, name, sprite, line, _, _, ultimate, climb in PERFECTS:
        nodes.append({
            "id": pid, "displayName": name, "stage": "Perfect", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[pid],
            "evolutions": [{"to": ultimate, "requiredEnergy": climb, "minEnergy": 150,
                            "maxCareMistakes": 2, "isDefault": True}],
        })

    # 3. the one junk Perfect, a leaf like every other junk floor in the file.
    for jid, name, sprite, line in JUNK_PERFECTS:
        nodes.append({
            "id": jid, "displayName": name, "stage": "Perfect", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[jid], "evolutions": [],
        })

    # 4. the five Ultimates, terminal and so with no `evolutions` key at all.
    for uid, name, sprite, line in ULTIMATES:
        nodes.append({
            "id": uid, "displayName": name, "stage": "Ultimate-Super Ultimate", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[uid],
        })

    open(path, "w").write(json.dumps(doc, indent=2, ensure_ascii=False))

    # 5. elements.json and moves.json, one entry apiece for all twenty-seven.
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
