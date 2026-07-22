"""US-161 — Orphan sweep: Perfect N-R.

Authors the fifteen orphaned Perfect whose display name begins with N through R, the seven
Ultimates they climb into that had no node, and the two junk Perfect floors that the two lines
this story OPENS — `vital` and `xros` — needed before their Champions could branch
at all. Run once; it refuses to run twice (every id it adds must be absent).

Kept in `scripts/` beside `us157_author.py` .. `us160_author.py` for the same reason: the JSON
round-trips byte-exactly through `json.dumps(indent=2, ensure_ascii=False)`, which is what makes
scripted authoring of twenty-four nodes across three files safe.
"""
import collections
import json
import sys

ROOT = "/Users/red/Documents/SourceCode/ios_project/digi/"

# (id, displayName, spriteFile, line, parent, parentEnergy, ultimate, climbEnergy)
PERFECTS = [
    ("neodevimon", "NeoDevimon", "NeoDevimon", "dmc-v1",
     "devimon", "stamina", "blitzgreymon", "stamina"),
    ("oboromon", "Oboromon", "Oboromon", "vital",
     "kokeshimon", "spirit", "zanbamon", "spirit"),
    ("okuwamon", "Okuwamon", "Okuwamon", "penc-me",
     "kuwagamon_x", "strength", "grankuwagamon", "strength"),
    ("okuwamon_x", "Okuwamon X", "Okuwamon_X", "penc-me",
     "kuwagamon_x", "vitality", "grandiskuwagamon", "vitality"),
    ("omegashoutmon", "OmegaShoutmon", "OmegaShoutmon", "xros",
     "shoutmon_king", "strength", "zekegreymon", "strength"),
    ("omegashoutmon_x", "OmegaShoutmon X", "OmegaShoutmon_X", "xros",
     "shoutmon_king", "spirit", "zekegreymon", "spirit"),
    ("orochimon", "Orochimon", "Orochimon", "penc-nso",
     "dokugumon", "vitality", "pencnso_metalgarurumon", "vitality"),
    ("paildramon", "Paildramon", "Paildramon", "penc-wg",
     "xv-mon_black", "strength", "ulforcev-dramon", "strength"),
    ("panjyamon", "Panjyamon", "Panjyamon", "penc-nsp",
     "pencnsp_leomon", "strength", "holydramon", "strength"),
    ("panjyamon_x", "Panjyamon X", "Panjyamon_X", "penc-nsp",
     "pencnsp_leomon", "vitality", "saberleomon", "vitality"),
    ("raijiludomon", "RaijiLudomon", "RaijiLudomon", "vital",
     "tialudomon", "strength", "bryweludramon", "strength"),
    ("rapidmon", "Rapidmon", "Rapidmon", "tamers",
     "galgomon", "spirit", "saintgalgomon", "spirit"),
    ("regulusmon", "Regulusmon", "Regulusmon", "penc-vb",
     "gulusgammamon", "spirit", "pencvb_metalgarurumon", "spirit"),
    ("rizegreymon", "RizeGreymon", "RizeGreymon", "wanyamon",
     "geogreymon", "strength", "ravmon", "strength"),
    ("rizegreymon_x", "RizeGreymon X", "RizeGreymon_X", "penc-me",
     "omekamon", "vitality", "ouryumon", "vitality"),
]

# The Ultimates this story had to open, in the order they are appended.
ULTIMATES = [
    ("zanbamon", "Zanbamon", "Zanbamon", "vital"),
    ("bryweludramon", "Bryweludramon", "Bryweludramon", "vital"),
    ("grankuwagamon", "GranKuwagamon", "GranKuwagamon", "penc-me"),
    ("grandiskuwagamon", "GrandisKuwagamon", "GrandisKuwagamon", "penc-me"),
    ("zekegreymon", "ZekeGreymon", "ZekeGreymon", "xros"),
    ("saintgalgomon", "SaintGalgomon", "SaintGalgomon", "tamers"),
    ("ravmon", "Ravmon", "Ravmon", "wanyamon"),
]

# The two junk PERFECTS this story had to invent, one for each line whose Perfect rung it opens.
# `EvolutionCriteriaTests` refuses a branching Champion with no `isDefault` edge onto a junk node
# of its own line, and not one of the thirty-seven Perfect still orphaned when this story ran is
# junk-flavoured — so both are line-scoped ALIASES, the `diablomon_gerbemon` pattern.
# (id, displayName, spriteFile, line).
JUNK_PERFECTS = [
    ("vital_darumamon", "Darumamon", "Darumamon", "vital"),
    ("xros_etemon", "Etemon", "Etemon", "xros"),
]

# The six Champions that were LEAVES before this story: giving one an out-edge means giving it
# its line's junk floor in the same edit. Four floors already existed; two are the nodes above.
JUNK_FLOORS = {
    "kuwagamon_x": ("locomon", "spirit"),
    "shoutmon_king": ("xros_etemon", "vitality"),
    "galgomon": ("catchmamemon", "strength"),
    "geogreymon": ("karakurumon", "spirit"),
    "kokeshimon": ("vital_darumamon", "strength"),
    "tialudomon": ("vital_darumamon", "spirit"),
}

# The criteria on each new in-edge. Two apiece: one HealthKit, one care counter, so no edge is
# earned by walking alone and none by playing alone.
CONDITIONS = {
    "neodevimon": [
        ("health.daylight", "stage", "atMost", 200, "Keep the mask out of the sun until it fuses"),
        ("care.sleepDisturbances", "stage", "atLeast", 6, "And break its rest until the wings come in black"),
    ],
    "oboromon": [
        ("health.exerciseMinutes", "stage", "atLeast", 1000, "Drill the blade arm until the form is muscle"),
        ("care.trainingSessions", "stage", "atLeast", 27, "And let the doll practise the draw over and over"),
    ],
    "okuwamon": [
        ("health.steps", "stage", "atLeast", 52000, "March the armoured shell the length of the forest"),
        ("care.battleCount", "lifetime", "atLeast", 26, "And let the pincers settle every argument"),
    ],
    "okuwamon_x": [
        ("health.flightsClimbed", "stage", "atLeast", 250, "Take the wings up every stair there is"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.76, "And let the antibody win most of the fights"),
    ],
    "omegashoutmon": [
        ("health.activeEnergy", "stage", "atLeast", 10600, "Sing until the whole body is burning"),
        ("care.trainingSessions", "stage", "atLeast", 26, "And drill the fists between the songs"),
    ],
    "omegashoutmon_x": [
        ("health.exerciseMinutes", "stage", "atLeast", 1080, "Work the little king until the antibody takes"),
        ("care.battleCount", "lifetime", "atLeast", 29, "And let the crown be argued for, never given"),
    ],
    "orochimon": [
        ("health.water", "stage", "atLeast", 5400, "Give every head its fill of the rice wine's water"),
        ("care.overfeeds", "stage", "atLeast", 8, "And let all eight of them eat past full"),
    ],
    "paildramon": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 42000, "Run the two halves together until they keep step"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.74, "And let the pair win far more than they lose"),
    ],
    "panjyamon": [
        ("health.standHours", "stage", "atLeast", 210, "Keep the white lion on its feet through the cold"),
        ("care.trainingSessions", "stage", "atLeast", 23, "And teach the blade to answer before the roar"),
    ],
    "panjyamon_x": [
        ("health.mindfulMinutes", "stage", "atLeast", 220, "Sit with it in the silence the snow makes"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.79, "And leave the record almost unblemished"),
    ],
    "raijiludomon": [
        ("health.flightsClimbed", "stage", "atLeast", 260, "Take it up until the thunder is below you"),
        ("care.battleCount", "lifetime", "atLeast", 25, "And let the lightning have something to strike"),
    ],
    "rapidmon": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 40000, "Run it until the boosters are worn smooth"),
        ("care.trainingSessions", "stage", "atLeast", 22, "And drill the missiles until they never miss"),
    ],
    "regulusmon": [
        ("health.sleep", "stage", "atLeast", 9800, "Let the little heart dream under the whole sky"),
        ("care.overfeeds", "stage", "atMost", 2, "And keep the frame lean enough for the stars"),
    ],
    "rizegreymon": [
        ("health.activeEnergy", "stage", "atLeast", 10200, "Drive the engine in its arm to the red"),
        ("care.battleCount", "lifetime", "atLeast", 24, "And give the revolver something to aim at"),
    ],
    "rizegreymon_x": [
        ("health.activeEnergy", "stage", "atLeast", 11400, "Feed the heavier gun all the power it wants"),
        ("care.trainingSessions", "stage", "atLeast", 28, "And drill the arm until the recoil means nothing"),
    ],
}

COMMENTS = {
    "neodevimon": (
        "Devimon is NeoDevimon's SOLE bolded `Evolves From` on Wikimon and has been on `dmc-v1` "
        "since the seed roster, so the bolded arrow needs no new node below. The climb is Blitz "
        "Greymon, on the page's `Evolves To` and already this line's Mega over MetalGreymon "
        "(Virus) and, since US-160, over MetalGreymon (Virus) X — so the whole demon thread runs "
        "beside the metal one under one Champion. **Done Devimon, the page's BOLDED climb, is "
        "idle-only in this pack** (`Idle Frame Only/`, dexOnly, and `edgeToDexOnlyNode` forbids the "
        "edge), which is the MachGaogamon shape US-160 recorded: the canonical top of the thread "
        "cannot be drawn, so the cited one is taken. Stamina is what a thing bolted into a mask "
        "endures; Devimon spends spirit on MetalGreymon (Virus) and on its junk fall, and strength "
        "on the X."),
    "oboromon": (
        "Kokeshimon is a cited `Evolves From` on Wikimon — the page bolds nothing at all — and it "
        "is one of the two `vital` Champions this story branches to open that line's Perfect rung "
        "at last. Dokugumon, Fugamon, Ginryumon and Musyamon are the other drawable citations and "
        "each sits on a line whose Perfect rung is already open; taking one would have left `vital` "
        "with thirty-three nodes and no rung, which US-160 named the cheapest one still owed. The "
        "climb, Zanbamon, is on the page's `Evolves To` and had no node — Ouryumon (`penc-me`) and "
        "Tengumon (`wanyamon`) are the cited alternatives and both are on another line. Spirit is "
        "what a doll that learns to draw a sword earns; Kokeshimon's junk fall takes strength."),
    "okuwamon": (
        "Kuwagamon (X-Antibody) is a cited `Evolves From` on Wikimon and has been a LEAF on "
        "`penc-me` since US-152, so the arrow clears a dead end — and it is cited for the X form "
        "too, which is the whole reason it beats the BOLDED parent. Kuwagamon on `dmc-v4` is that "
        "bolded name and holds a cited climb of its own (Darkdramon), but `dmc-v4` holds NO cited "
        "climb for Okuwamon (X-Antibody), so honouring the bold would have split the pair across "
        "two lines; one leaf Champion takes both instead. The climb is Gran Kuwagamon, BOLDED on "
        "this page and authored here. Strength is what a pair of pincers earns."),
    "okuwamon_x": (
        "The second half of the Kuwagamon (X-Antibody) pair, and the reason that leaf was worth "
        "spending: Kuwagamon (X-Antibody) is cited on BOTH Wikimon pages, so one Champion carries "
        "the base form and the variant — strength for Okuwamon, vitality for this one, which is "
        "the distinct-energy rule `SeedRosterTests` enforces on earned branches. Okuwamon itself "
        "is this page's other bolded parent and is a Perfect, so it can never be an in-edge. The "
        "climb is Grandis Kuwagamon, BOLDED here exactly as Gran Kuwagamon is bolded on the base "
        "form's page, so the two beetles converge on their own two Megas rather than sharing one."),
    "omegashoutmon": (
        "Shoutmon (King Ver.) is a BOLDED `Evolves From` on Wikimon and has been a LEAF on `xros` "
        "since US-149 — the page's other bolded parent is Shoutmon itself, a CHILD, which "
        "`GraphValidationError.invalidStageTransition` refuses exactly as it refused Lucemon under "
        "Lucemon Falldown in US-159. So the arrow clears a dead end AND opens the `xros` line's "
        "Perfect rung, which US-160 left as one of five still owed; US-158's rule then makes that "
        "cost a junk floor and a Mega in the same story. The climb is Zeke Greymon, bolded on the "
        "page — Shoutmon DX, Shoutmon X and the other bolded climbs are all DigiXros fusions with "
        "no sheet in this pack, and Kazuchimon, the one cited climb with a node, is on `penc-me`. "
        "Strength is what a king who sings earns."),
    "omegashoutmon_x": (
        "**NO CITED PARENT AND NO CITED CLIMB EXISTS ON THIS LINE, AND THIS SAYS SO.** Wikimon "
        "gives OmegaShoutmon (X-Antibody) four drawable `Evolves From` — Meramon X and Siesamon X "
        "on `tamers`, Omekamon on `penc-me`, Scumon on `dmc-v3` — and not one of those lines holds "
        "a cited climb either (its `Evolves To` reach Dinotigermon on `wanyamon` and Tiger "
        "Vespamon on `palmon`), so there is no line anywhere where both ends are cited. The "
        "variant rule therefore wins outright: the node hangs off the very Champion its base form "
        "hangs off, and converges on the base form's own Mega, which is the Monzaemon X and "
        "Mamemon X arrangement US-160 recorded. It belongs on this line on its own account as "
        "well — Wikimon's Virtual Pets section lists OmegaShoutmon (X-Antibody) in the Digimon "
        "Xros Loader, which is the fact `xros` groups on. Spirit; Shoutmon King spends strength "
        "on OmegaShoutmon and vitality on its junk fall."),
    "orochimon": (
        "Dokugumon is a cited `Evolves From` on Wikimon and has been on `penc-nso` since US-140, "
        "and Metal Garurumon is a cited `Evolves To` that has been this line's Mega over "
        "WereGarurumon since US-140 too — so US-152's rule of intersecting both ends closes with "
        "no new node. The page bolds only Mad Leomon and Nidhoggmon: the first is an ADULT (the "
        "arrow is a devolution, not a climb) and the second is idle-only, so neither is drawable. "
        "Deltamon on `dmc-v5` is the better flavour — a three-headed dragon under an eight-headed "
        "serpent — and lost because `dmc-v5` holds no cited climb at all. Vitality is the energy "
        "Dokugumon had free; it spends stamina on Phantomon, spirit on Archnemon and strength on "
        "its junk fall to Darumamon."),
    "paildramon": (
        "XV-mon (Black) is a cited `Evolves From` on Wikimon and Ulforce V-dramon is a cited "
        "`Evolves To` that has been `penc-wg`'s Mega over AeroV-dramon since US-141, so both ends "
        "are cited on the line the whole V-dramon thread already lives on. **THE PLAIN XV-mon WAS "
        "DELIBERATELY NOT TAKEN, AND THE REASON IS AN EGG RATHER THAN A CITATION.** It is a cited "
        "parent too, and the LAST LEAF on `adventure02` since US-156, so the arrow would have "
        "cleared a dead end and opened that line's Perfect rung — but `adventure02` carries TWO "
        "Digitama and only one of them, V Digitama, descends through XV-mon. Worm Digitama "
        "descends through Wormmon to Sorcerymon, which would still have had no Perfect above it "
        "and no orphan in this band it could take, so opening the rung would have left an egg "
        "unraisable on a line that HAS one — exactly what `PerfectSweepHToLTests` refuses. "
        "`adventure02` therefore stays a whole-line job for a later story, and this node goes to "
        "the black XV-mon instead, which is the variant of the very Champion the citation names. "
        "Imperialdramon: Fighter Mode is the page's drawable BOLDED climb and is left orphaned for "
        "the Ultimate sweeps; Dragon Mode, the other bolded one, is dexOnly. Strength is what a "
        "fused pair earns; XV-mon Black spends stamina on AeroV-dramon and on its junk fall."),
    "panjyamon": (
        "Leomon is Panjyamon's SOLE bolded `Evolves From` on Wikimon and `penc-nsp` has its own — "
        "`pencnsp_leomon`, on the shared sheet — and Holydramon is a cited `Evolves To` that has "
        "been this line's Mega over Angewomon since US-138. Both ends cited on one line, and the "
        "same line holds a cited climb for the X form as well, which is why the pair is here "
        "rather than on `dmc-v4` (where Leomon and the cited Gankoomon both sit, but where the X "
        "form has no cited climb at all). Strength is what a white lion earns; `pencnsp_leomon` "
        "spends stamina on Asuramon and on its junk fall to Pumpmon."),
    "panjyamon_x": (
        "PLACED BY THE VARIANT RULE IN ITS STRONGEST FORM — SAME PARENT — AND WITH BOTH ENDS "
        "CITED. Leomon is on Panjyamon (X-Antibody)'s Wikimon `Evolves From` exactly as it is on "
        "the base form's, and Saber Leomon is on its `Evolves To` and has been `penc-nsp`'s Mega "
        "over Asuramon since US-138 — so the variant hangs off the very Champion its base form "
        "hangs off and climbs the OTHER lion Mega of the same line, and the two Panjyamon run "
        "beside each other. Panjyamon itself is this page's other bolded parent and is a Perfect, "
        "so it can never be an in-edge. Vitality; the base form took strength."),
    "raijiludomon": (
        "Tia Ludomon is RaijiLudomon's BOLDED `Evolves From` on Wikimon and Reppamon is the only "
        "other drawable one — BOTH are on `vital`, so this Digimon has no home anywhere else and "
        "`vital` had to open whatever else this story did. That is the Meicoomon shape US-160 "
        "paid for `diablomon`: a junk floor under the Champions, this node, and a Mega over it in "
        "the same breath. The climb is Bryweludramon, BOLDED on the page and with no node "
        "anywhere; Dukemon is the one cited alternative with a node and is on `tamers`. Strength "
        "is what a thunder beast earns; Tia Ludomon's junk fall takes spirit."),
    "rapidmon": (
        "Galgomon is Rapidmon's bolded `Evolves From` on Wikimon — the other bolded name is "
        "Terriermon, a CHILD, which the one-rung rule refuses — and it has been a LEAF on `tamers` "
        "since US-149, so the arrow clears a dead end on the line the whole Terriermon thread "
        "already lives on. The climb is Saint Galgomon, bolded on the same page and with no node "
        "anywhere: Cherubimon (Vice), Cherubimon (Virtue), Hi Andromon, Metal Etemon and "
        "Mugendramon are the cited alternatives and every one is on another line, and Black "
        "Rapidmon, the page's other bolded climb, is a PERFECT already on `tamers`. Spirit is what "
        "a Digimon made of its partner's faith earns."),
    "regulusmon": (
        "Gulus Gammamon is a BOLDED `Evolves From` on Wikimon and has been on `penc-vb` since "
        "US-151 — the page's other bolded name, Canoweissmon, is a PERFECT on this same line and "
        "so can never be an in-edge — and Metal Garurumon is a cited `Evolves To` that has been "
        "`penc-vb`'s Mega since US-142. Both ends cited on the Gammamon line, which is where every "
        "Regulusmon reading points anyway: Betel, Kaus and Wezen Gammamon are all cited parents "
        "too. Siriusmon and Arcturusmon are the flavour-perfect climbs and neither has a node; "
        "they are left for the Ultimate sweeps, which will find Regulusmon waiting under them. "
        "Spirit; Gulus Gammamon spends strength on HolyAngemon and on its junk fall."),
    "rizegreymon": (
        "Geo Greymon is a BOLDED `Evolves From` on Wikimon and has been a LEAF on `wanyamon` since "
        "US-151, so the bolded arrow clears a dead end — and `wanyamon` is where this Digimon "
        "belongs twice over, since it is the Data Squad line and RizeGreymon is Agumon's own "
        "Champion-to-Perfect step in that show. **Shine Greymon and Victory Greymon, the two "
        "BOLDED climbs, are both idle-only in this pack** (dexOnly, and `edgeToDexOnlyNode` "
        "forbids the edge) — the third time this story meets the MachGaogamon shape — so the "
        "climb is Ravmon, cited on the page, with no node anywhere, and the Mega of the OTHER "
        "Data Squad partner. Strength; Geo Greymon's junk fall takes spirit."),
    "rizegreymon_x": (
        "FOLLOWS A CITED PARENT RATHER THAN ITS BASE FORM, AND BOTH ARROWS ARE CITED. The plain "
        "RizeGreymon is on `wanyamon` above, which offers this variant NO cited parent and NO "
        "cited climb — Wikimon gives RizeGreymon (X-Antibody) four drawable `Evolves From` "
        "(Omekamon on `penc-me`, Paledramon on `tamers`, Tylomon X on `dmc-v3`, Wizarmon X on "
        "`diablomon`) and none of them is there. Omekamon and Ouryumon are both on the page and "
        "both on `penc-me`, so the whole thread is cited: the same escape hatch "
        "`ChildSweepMToZTests.testEveryVariantSitsWithItsBaseFormOrFollowsACitedParent` opened for "
        "Shakomon X and US-160 used for MetalMamemon X. Vitality; Omekamon spends strength on "
        "Hisyaryumon and on its junk fall to Locomon."),
    # The eight Ultimates.
    "zanbamon": (
        "Oboromon's cited `Evolves To` on Wikimon, and the first Ultimate `vital` has ever had. "
        "US-158's rule is that a sweep opening a Perfect rung on a line with none owes an Ultimate "
        "over it in the same story or it re-opens the gap; this and Bryweludramon are that debt "
        "paid for `vital`. A leaf, as every Ultimate in this file is."),
    "bryweludramon": (
        "RaijiLudomon's BOLDED `Evolves To` on Wikimon, and `vital`'s second Ultimate. The two "
        "together are what makes this line's nine Champions worth raising at all — "
        "`MainScreenModel.startingDigitamaId` filters on `graph.reachesUltimate`, so a line with "
        "no top rung has no legal starting egg either. A leaf, as every Ultimate in this file is."),
    "grankuwagamon": (
        "Okuwamon's BOLDED `Evolves To` on Wikimon, opened for exactly one Perfect. It sits on "
        "`penc-me` because the Perfect under it does — see that node's comment for why the whole "
        "Kuwagamon (X-Antibody) pair is here rather than under the bolded Kuwagamon on `dmc-v4`. "
        "A leaf, as every Ultimate in this file is."),
    "grandiskuwagamon": (
        "Okuwamon (X-Antibody)'s BOLDED `Evolves To` on Wikimon, the twin of Gran Kuwagamon above: "
        "the base form and the variant get one Mega each rather than converging on one, because "
        "each page bolds its own. A leaf, as every Ultimate in this file is."),
    "zekegreymon": (
        "OmegaShoutmon's bolded `Evolves To` on Wikimon and the first Ultimate `xros` has ever "
        "had, taken by BOTH OmegaShoutmon and its X form — the only Ultimate in this story with "
        "two parents, and deliberately so: the X form has no cited climb anywhere on this line, so "
        "converging on the base form's Mega is the variant rule's own answer. Every other bolded "
        "climb on that page (Shoutmon DX, Shoutmon X, Atlur Ballistamon, Yaeger Dorulumon) is a "
        "DigiXros fusion with no sheet in this pack. A leaf, as every Ultimate in this file is."),
    "saintgalgomon": (
        "Rapidmon's bolded `Evolves To` on Wikimon, opened for exactly one Perfect. It sits on "
        "`tamers` because the whole Terriermon thread does: Terriermon -> Galgomon -> Rapidmon -> "
        "Saint Galgomon is that Digimon's own ladder, drawn at last. A leaf, as every Ultimate in "
        "this file is."),
    "ravmon": (
        "RizeGreymon's cited `Evolves To` on Wikimon, taken because both of that page's BOLDED "
        "climbs — Shine Greymon and Victory Greymon — are idle-only in this pack and "
        "`edgeToDexOnlyNode` forbids the edge. It sits on `wanyamon`, the Data Squad line, which "
        "is where Ravmon belongs on its own account as well. A leaf, as every Ultimate in this "
        "file is."),
    # The three junk Perfects, all line-scoped aliases.
    "vital_darumamon": (
        "FLAVOUR, CITED, AND A LINE-SCOPED ALIAS RATHER THAN A NEW SHEET. `vital` had no junk "
        "PERFECT and every branching Champion needs one (`EvolutionCriteriaTests`), so opening "
        "this line's Perfect rung for Oboromon and RaijiLudomon meant authoring a floor under "
        "Kokeshimon and Tia Ludomon in the same edit. Darumamon is on Kokeshimon's own Wikimon "
        "`Evolves To`, and the flavour could not be tidier: a kokeshi doll falls into a daruma "
        "doll. It is an ALIAS on the Darumamon sheet rather than a fresh orphan because not one of "
        "the thirty-seven Perfect still orphaned when this story ran is junk-flavoured — the "
        "`dmcv2_vademon` pattern exactly — so unlike CatchMamemon and Pandamon this floor removes "
        "no orphan."),
    "xros_etemon": (
        "FLAVOUR, CITED, AND A LINE-SCOPED ALIAS. `xros`'s own junk CHAMPION is Targetmon (US-149) "
        "and Etemon is on Targetmon's Wikimon `Evolves To`, so the line's junk thread is drawn "
        "end to end out of its own citations: a faceless target falls into a monkey in a bad suit. "
        "Shoutmon (King Ver.), the Champion this story branches, cites no junk Perfect at all. "
        "Etemon belongs on this line on its own account too — Wikimon's Virtual Pets section "
        "lists it in the Digimon Xros Loader, which is the fact `xros` groups on. An alias on the "
        "Etemon sheet for the same reason as `vital_darumamon` above; it removes no orphan."),
}

ELEMENTS = {
    "neodevimon": ("dark", "virus"),
    "oboromon": ("dark", "virus"),
    "okuwamon": ("plant", "virus"),
    "okuwamon_x": ("plant", "virus"),
    "omegashoutmon": ("fire", "data"),
    "omegashoutmon_x": ("fire", "data"),
    "orochimon": ("water", "virus"),
    "paildramon": ("electric", "free"),
    "panjyamon": ("ice", "vaccine"),
    "panjyamon_x": ("ice", "vaccine"),
    "raijiludomon": ("electric", "vaccine"),
    "rapidmon": ("machine", "vaccine"),
    "regulusmon": ("dark", "data"),
    "rizegreymon": ("machine", "vaccine"),
    "rizegreymon_x": ("machine", "vaccine"),
    "zanbamon": ("dark", "virus"),
    "bryweludramon": ("electric", "vaccine"),
    "grankuwagamon": ("plant", "virus"),
    "grandiskuwagamon": ("plant", "virus"),
    "zekegreymon": ("fire", "data"),
    "saintgalgomon": ("machine", "vaccine"),
    "ravmon": ("wind", "vaccine"),
    "vital_darumamon": ("fire", "virus"),
    "xros_etemon": ("earth", "virus"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
# `projectileSymbol|tint` must be unique WITHIN a line and `signatureName` GLOBALLY; `check()`
# below proves both against the real files before anything is written.
MOVES = {
    "neodevimon": ("hand.raised.fill", "gray", "Guilty Claw", "hand.raised.fill"),
    "oboromon": ("scissors", "gray", "Kagerou Blade", "scissors"),
    "okuwamon": ("scissors", "green", "Double Scissor Claw", "scissors"),
    "okuwamon_x": ("scissors", "gray", "Destruction Pincer", "scissors"),
    "omegashoutmon": ("flame.fill", "white", "Heavy Metal Vulcan", "flame.fill"),
    "omegashoutmon_x": ("flame.fill", "gray", "Hard Rock Soul", "flame.fill"),
    "orochimon": ("drop.fill", "green", "Sake Breath", "drop.fill"),
    "paildramon": ("bolt.fill", "green", "Desperado Blaster", "bolt.fill"),
    "panjyamon": ("snowflake", "cyan", "Zetsu Ei Ken", "snowflake"),
    "panjyamon_x": ("snowflake", "blue", "Frozen Fang Cross", "snowflake"),
    "raijiludomon": ("bolt.fill", "indigo", "Thunder Fang", "bolt.fill"),
    "rapidmon": ("triangle.fill", "green", "Golden Triangle", "triangle.fill"),
    "regulusmon": ("star.fill", "indigo", "Regulus Impact", "star.fill"),
    "rizegreymon": ("circle.fill", "red", "Trident Revolver", "circle.fill"),
    "rizegreymon_x": ("circle.fill", "teal", "Rising Destroyer Cross", "circle.fill"),
    "zanbamon": ("scissors", "red", "Hell Slash", "scissors"),
    "bryweludramon": ("bolt.fill", "white", "Brave Snarl", "bolt.fill"),
    "grankuwagamon": ("scissors", "teal", "Dimension Scissor", "scissors"),
    "grandiskuwagamon": ("scissors", "brown", "Grandis Cutter", "scissors"),
    "zekegreymon": ("star.fill", "orange", "Zeke Flame", "star.fill"),
    "saintgalgomon": ("triangle.fill", "white", "Giant Missile", "triangle.fill"),
    "ravmon": ("wind", "white", "Celestial Blade", "wind"),
    "vital_darumamon": ("flame.fill", "red", "Daruma Roll", "flame.fill"),
    "xros_etemon": ("music.note", "brown", "Dark Network", "music.note"),
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

    # 2. the fifteen Perfects, each a single isDefault climb, the shape every Perfect in the file
    #    has carried since US-134.
    for pid, name, sprite, line, _, _, ultimate, climb in PERFECTS:
        nodes.append({
            "id": pid, "displayName": name, "stage": "Perfect", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[pid],
            "evolutions": [{"to": ultimate, "requiredEnergy": climb, "minEnergy": 150,
                            "maxCareMistakes": 2, "isDefault": True}],
        })

    # 3. the two junk Perfects, leaves like every other junk floor in the file.
    for jid, name, sprite, line in JUNK_PERFECTS:
        nodes.append({
            "id": jid, "displayName": name, "stage": "Perfect", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[jid], "evolutions": [],
        })

    # 4. the seven Ultimates, terminal and so with no `evolutions` key at all.
    for uid, name, sprite, line in ULTIMATES:
        nodes.append({
            "id": uid, "displayName": name, "stage": "Ultimate-Super Ultimate", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[uid],
        })

    open(path, "w").write(json.dumps(doc, indent=2, ensure_ascii=False))

    # 5. elements.json and moves.json, one entry apiece for all twenty-four.
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
