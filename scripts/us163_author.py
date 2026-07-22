"""US-163 — Orphan sweep: Ultimate-Super Ultimate A-B, the first sweep at the top rung.

Authors the thirty orphaned Ultimate whose display name begins A-B. An Ultimate is TERMINAL — the
AC asks for an out-edge only "unless it is a terminal Ultimate", and every Ultimate in this file is
one — so this rung is an IN-EDGE sweep and nothing else: thirty new nodes, thirty new edges, and no
node above them to open. That is why it costs no junk floor and no new line.

Two shapes of in-edge, and the difference is the parent rather than the taste:

  * a LEAF Perfect (five of them) gains its single `isDefault` climb, the shape every other Perfect
    in the file has carried since US-134 — `minEnergy` 150, `maxCareMistakes` 2, no conditions,
    because `SeedRosterTests.testEveryNonTerminalNodeHasExactlyOneDefaultEdge` requires a node with
    edges to have exactly one fallback and US-020 takes it whatever the gates say. Each of the five
    also clears a dead end off `ChildSweepAToFTests`' ledger.
  * every other Perfect already HAS that climb, so the new arrow is an EARNED branch beside it:
    `minEnergy` 150, `maxCareMistakes` 2, two conditions (one HealthKit, one care counter), and a
    `requiredEnergy` that differs from the climb's and from every other earned branch on that node.
    `EvolutionEngine.qualifies` matches on the DOMINANT type, so two branches sharing one energy
    would make the lower-`minEnergy` one unreachable; distinct energies are what make the fork real.

`EvolutionCriteriaTests.branchingNodes` filters to Child and Adult, so the 2..5 ceiling and the
junk-floor rule do not reach the Perfect rung: a Perfect with an earned branch beside its climb owes
no junk fallback, and its climb IS the fallback.

Run once; it refuses to run twice (every id it adds must be absent).

Kept in `scripts/` beside `us157_author.py` .. `us162_author.py` for the same reason: the JSON
round-trips byte-exactly through `json.dumps(indent=2, ensure_ascii=False)`.
"""
import collections
import json
import sys

ROOT = "/Users/red/Documents/SourceCode/ios_project/digi/"

# (id, displayName, spriteFile, line, parent, energy)
# `energy` is the new edge's `requiredEnergy`: for a leaf parent it is the climb's own type, for
# every other parent it is the earned branch's, chosen to differ from what that node already spends.
ULTIMATES = [
    ("agumon_ynk", "Agumon YnK", "Agumon_YnK", "dmc-v1",
     "metalgreymon_virus", "vitality"),
    ("algomon_ultimate", "Algomon", "Algomon_Ultimate", "penc-nso",
     "mummymon", "vitality"),
    ("alphamon", "Alphamon", "Alphamon", "tamers",
     "grademon", "strength"),
    ("alphamon_ouryuken", "Alphamon Ouryuken", "Alphamon_Ouryuken", "tamers",
     "doruguremon", "spirit"),
    ("amaterasumon", "Amaterasumon", "Amaterasumon", "vital",
     "shishimamon", "spirit"),
    ("ancientbeatmon", "AncientBeatmon", "AncientBeatmon", "penc-nsp",
     "atlurkabuterimon_red", "stamina"),
    ("ancientmegatheriumon", "AncientMegatheriumon", "AncientMegatheriumon", "penc-nso",
     "mammon", "vitality"),
    ("ancientmermaimon", "AncientMermaimon", "AncientMermaimon", "penc-ds",
     "mermaimon", "vitality"),
    ("ancientsphinxmon", "AncientSphinxmon", "AncientSphinxmon", "penc-nso",
     "mummymon", "spirit"),
    ("anubimon", "Anubimon", "Anubimon", "penc-me",
     "cerberumon_x", "spirit"),
    ("apocalymon", "Apocalymon", "Apocalymon", "tamers",
     "ladydevimon", "vitality"),
    ("arcturusmon", "Arcturusmon", "Arcturusmon", "penc-vb",
     "canoweissmon", "vitality"),
    ("ariemon", "Ariemon", "Ariemon", "dmc-v3",
     "marinbullmon", "strength"),
    ("armagemon", "Armagemon", "Armagemon", "dmc-v1",
     "chimairamon", "stamina"),
    ("armamon", "Armamon", "Armamon", "xros",
     "omegashoutmon", "vitality"),
    ("bagramon", "Bagramon", "Bagramon", "tamers",
     "mametyramon", "strength"),
    ("bancholilimon", "BanchoLilimon", "BanchoLilimon", "palmon",
     "lilamon", "spirit"),
    ("barbamon", "Barbamon", "Barbamon", "penc-nso",
     "mephismon", "spirit"),
    ("barbamon_x", "Barbamon X", "Barbamon_X", "penc-nso",
     "mephismon", "strength"),
    ("beelzebumon_blast", "Beelzebumon Blast", "Beelzebumon_Blast", "tamers",
     "baalmon", "strength"),
    ("beelzebumon_x", "Beelzebumon X", "Beelzebumon_X", "tamers",
     "baalmon", "vitality"),
    ("belialvamdemon", "BelialVamdemon", "BelialVamdemon", "penc-nso",
     "vamdemon", "vitality"),
    ("belphemon_rage", "Belphemon Rage", "Belphemon_Rage", "penc-me",
     "astamon", "stamina"),
    ("belphemon_x", "Belphemon X", "Belphemon_X", "penc-me",
     "astamon", "vitality"),
    ("blacksaintgalgomon", "BlackSaintGalgomon", "BlackSaintGalgomon", "tamers",
     "blackrapidmon", "strength"),
    ("blackseraphimon", "BlackSeraphimon", "BlackSeraphimon", "penc-vb",
     "holyangemon", "strength"),
    ("blackwargreymon_x", "BlackWarGreymon X", "BlackWarGreymon_X", "dmc-v1",
     "metalgreymon_virus_x", "stamina"),
    ("blastmon", "Blastmon", "Blastmon", "penc-nso",
     "insekimon", "strength"),
    ("breakdramon", "Breakdramon", "Breakdramon", "tamers",
     "megalogrowmon", "strength"),
    ("brigadramon", "Brigadramon", "Brigadramon", "penc-me",
     "cargodramon", "strength"),
]

# The five Perfects that were LEAVES before this story. Each gains its single `isDefault` climb,
# which is also five entries off the dead-end ledger in `ChildSweepAToFTests`.
LEAF_PARENTS = {"grademon", "canoweissmon", "mametyramon", "blackrapidmon", "megalogrowmon"}

# Two criteria on every EARNED in-edge: one HealthKit metric, one care counter, so no Mega is
# earned by walking alone and none by playing alone. `care.battleCount` and `care.battleWinRatio`
# are answerable only over `lifetime` and every other `care.*` only over `stage` — US-150's rule.
CONDITIONS = {
    "agumon_ynk": [
        ("health.exerciseMinutes", "stage", "atLeast", 1240, "Keep moving beside it, because this one is about the bond"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And never once wake it in the night"),
    ],
    "algomon_ultimate": [
        ("health.steps", "stage", "atLeast", 62000, "Let the crawler walk the whole network"),
        ("care.trainingSessions", "stage", "atLeast", 28, "And run the routine until it runs itself"),
    ],
    "alphamon_ouryuken": [
        ("health.activeEnergy", "stage", "atLeast", 12400, "Spend everything the knight has, twice over"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And let the sword lose almost nothing"),
    ],
    "amaterasumon": [
        ("health.daylight", "stage", "atLeast", 1100, "Keep it in the sun from first light to last"),
        ("care.trainingSessions", "stage", "atLeast", 26, "And dance the shrine dance until it is right"),
    ],
    "ancientbeatmon": [
        ("health.flightsClimbed", "stage", "atLeast", 320, "Take the beetle up, storey after storey"),
        ("care.battleCount", "lifetime", "atLeast", 34, "And let the thunder settle a great many fights"),
    ],
    "ancientmegatheriumon": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 48000, "Walk the mammoth the length of the ice age"),
        ("care.overfeeds", "stage", "atMost", 2, "And keep the great bulk lean while you do it"),
    ],
    "ancientmermaimon": [
        ("health.distanceSwimming", "stage", "atLeast", 6600, "Take the tide out past every shelf"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And let the deep sleep undisturbed"),
    ],
    "ancientsphinxmon": [
        ("health.sleep", "stage", "atLeast", 10400, "Let it lie still as long as a tomb does"),
        ("care.battleCount", "lifetime", "atLeast", 32, "And let the riddle be asked of many"),
    ],
    "anubimon": [
        ("health.standHours", "stage", "atLeast", 260, "Keep the judge on its feet through every hour"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.8, "And let its verdicts almost always stand"),
    ],
    "apocalymon": [
        ("health.sleep", "stage", "atMost", 2800, "Give it no rest, because this is what grief with no rest becomes"),
        ("care.battleWinRatio", "lifetime", "atMost", 0.4, "And let it lose far more than it wins"),
    ],
    "ariemon": [
        ("health.flightsClimbed", "stage", "atLeast", 300, "Put the ram up every slope there is"),
        ("care.trainingSessions", "stage", "atLeast", 27, "And let it butt the post until the post gives"),
    ],
    "armagemon": [
        ("health.steps", "stage", "atLeast", 66000, "Let the swarm walk until it is a multitude"),
        ("care.overfeeds", "stage", "atLeast", 8, "And feed it far past full, because it never stops eating"),
    ],
    "armamon": [
        ("health.activeEnergy", "stage", "atLeast", 11600, "Burn the whole arsenal down and refill it"),
        ("care.trainingSessions", "stage", "atLeast", 30, "And drill every weapon it carries"),
    ],
    "bancholilimon": [
        ("health.exerciseMinutes", "stage", "atLeast", 1300, "Keep the flower out on the streets"),
        ("care.battleCount", "lifetime", "atLeast", 36, "And let the boss settle every dispute herself"),
    ],
    "barbamon": [
        ("health.steps", "stage", "atLeast", 64000, "Send the miser out after everything it can carry"),
        ("care.overfeeds", "stage", "atLeast", 7, "And let greed be fed until it is fat"),
    ],
    "barbamon_x": [
        ("health.standHours", "stage", "atLeast", 270, "Keep the antibody upright over its hoard"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.82, "And let almost nothing be taken back from it"),
    ],
    "beelzebumon_blast": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 52000, "Ride it as far as the road goes"),
        ("care.battleCount", "lifetime", "atLeast", 38, "And let the guns be used often"),
    ],
    "beelzebumon_x": [
        ("health.activeEnergy", "stage", "atLeast", 12800, "Burn everything the antibody has"),
        ("care.trainingSessions", "stage", "atLeast", 30, "And drill the draw until it is faster than thought"),
    ],
    "belialvamdemon": [
        ("health.daylight", "stage", "atMost", 140, "Keep the count out of every dawn"),
        ("care.battleCount", "lifetime", "atLeast", 35, "And let it take what it wants, night after night"),
    ],
    "belphemon_rage": [
        ("health.sleep", "stage", "atLeast", 12000, "Let the sleeping demon sleep, because that is the whole of it"),
        ("care.sleepDisturbances", "stage", "atLeast", 6, "And then wake it, which is what turns sloth into rage"),
    ],
    "belphemon_x": [
        ("health.sleep", "stage", "atLeast", 11200, "Let the antibody dream through the long dark"),
        ("care.overfeeds", "stage", "atMost", 2, "And let it wake hungry rather than heavy"),
    ],
    "blackseraphimon": [
        ("health.daylight", "stage", "atMost", 180, "Keep the angel out of the light it was made for"),
        ("care.battleWinRatio", "lifetime", "atMost", 0.45, "And let it fall, because a fallen angel is one that lost"),
    ],
    "blackwargreymon_x": [
        ("health.exerciseMinutes", "stage", "atLeast", 1360, "Work the black armour until the antibody takes"),
        ("care.battleCount", "lifetime", "atLeast", 33, "And let it look for a fight it cannot win"),
    ],
    "blastmon": [
        ("health.activeEnergy", "stage", "atLeast", 13200, "Grow the crystal by burning everything around it"),
        ("care.overfeeds", "stage", "atLeast", 9, "And feed the general until the general is enormous"),
    ],
    "brigadramon": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 56000, "Run the engine the whole length of the line"),
        ("care.trainingSessions", "stage", "atLeast", 29, "And drill the crew until the couplings never slip"),
    ],
}

COMMENTS = {
    "agumon_ynk": (
        "Agumon -Yuki no Kizuna- on Wikimon, which is where the YnK in the sheet name comes from. "
        "**THE LINE IS CITED OUTRIGHT AND THE RUNG IS A REHOME**, the US-141 shape: five of the "
        "seven names in its `Evolves From` are `dmc-v1` — Agumon, Agumon (Black), Greymon and War "
        "Greymon, with the bolded parent being Agumon itself, a CHILD, which "
        "`GraphValidationError.invalidStageTransition` refuses exactly as it refused Lucemon under "
        "Lucemon Falldown in US-159 — so the Perfect between the cited Greymon below and the cited "
        "War Greymon above is what this arrow wants. MetalGreymon is that rung and could not be "
        "taken: `SeedRosterTests.testTheThreeNamedLinesAreTheOnesShipped` walks the EARNED path from "
        "it and pins it to WarGreymon, so a second earned branch there would redirect one of US-002's "
        "three named lines. MetalGreymon (Virus) is the same fork one arrow over — the V1 document's "
        "own Perfect over Greymon since US-133 — so the thread the citation names is kept and the "
        "seed line is left alone. Agumon (2006 Anime Version) on `wanyamon` and Scumon on `dmc-v3` "
        "are the two cited parents off this line, and Master Tyranomon has no sheet in this pack. "
        "Vitality, the bond this Digimon is named for; MetalGreymon (Virus) spends spirit on "
        "BlitzGreymon."),
    "algomon_ultimate": (
        "**THE ONLY DRAWABLE PARENT WIKIMON GIVES IT, AND IT IS OFF ITS OWN LINE — SAID PLAINLY.** "
        "Algomon (Ultimate)'s Wikimon `Evolves From` is two names: the bolded Algomon (Perfect), which has "
        "no sheet in this pack at all — the `algomon` folder holds Baby I, Baby II, Child, Adult and "
        "this — and Mummymon, which is `penc-nso`'s since US-160. So the crawler climbs on the "
        "Nightmare Soldiers line beside the mummy, and the `algomon` line keeps no Ultimate of its "
        "own. That is inherited rather than chosen: US-162 proved `algomon`'s Perfect rung can never "
        "open, because the only Champion any orphan cites on it (Siesamon) sits on a thread Ghost "
        "Digitama cannot reach, and the Perfect rung closed with that story — so no line-mate was "
        "ever available to this node and none can be authored later. Vitality; Mummymon spends "
        "stamina on Deathmon and spirit on AncientSphinxmon, authored in this same edit."),
    "alphamon": (
        "Grademon is a BOLDED `Evolves From` on Wikimon and had been a LEAF on `tamers` since "
        "US-154, so the bolded arrow clears a dead end and costs nothing but the edge. The page's "
        "other two bolded parents are DORUguremon, also `tamers` and taken by Alphamon: Ouryuken in "
        "this same edit, and DORUmon, a CHILD — `GraphValidationError.invalidStageTransition` "
        "refuses a Child to Ultimate edge, the shape US-159 recorded on Lucemon Falldown. Alphamon "
        "is the Royal Knight the DORUmon line climbs to and `tamers` is where that whole line lives, "
        "so the pair of them land together. Strength, and it is this Perfect's FIRST edge, so it is "
        "the `isDefault` climb every other Perfect in the file carries — the shape US-134 set."),
    "alphamon_ouryuken": (
        "DORUguremon is a cited `Evolves From` on Wikimon and is on `tamers`, where Alphamon lands "
        "in this same edit — which is the point: Alphamon: Ouryuken is Alphamon wielding Ouryumon, "
        "so the two belong on one line whatever else is true. The page's bolded parents are Alphamon "
        "and Ouryumon themselves, and BOTH are Ultimates, so neither can ever be an in-edge — the "
        "Triceramon X shape US-162 recorded, where the canonical arrow comes from the rung above. "
        "Gaioumon (`dmc-v5`), Metal Piranimon (`penc-ds`) and Tiger Vespamon (`palmon`) are the "
        "other cited parents and every one is an Ultimate too. Spirit; DORUguremon spends strength "
        "on Dorugoramon, so the fork is real in both directions."),
    "amaterasumon": (
        "Shishimamon is a cited `Evolves From` on Wikimon and has been `vital`'s since US-162, and "
        "the flavour is exact: Amaterasu is the Shinto sun goddess and a Shishimai is the lion that "
        "dances at her shrines. The page bolds nothing at all, so there is no bolded reading to "
        "reject. Oboromon is the other cited parent on this line and Marin Bullmon and Darumamon "
        "the two off it; Marin Bullmon takes Ariemon in this same edit, which is what left "
        "Shishimamon carrying this one. Spirit; Shishimamon spends strength on Zanbamon."),
    "ancientbeatmon": (
        "Atlur Kabuterimon (Red) is a cited `Evolves From` on Wikimon and is `penc-nsp`'s since "
        "US-157, beside the plain AtlurKabuterimon the Nature Spirits document has drawn since "
        "US-138 — and BOTH are cited, so the line is doubly named. **BLITZMON, THE BOLDED PARENT, "
        "HAS NO SHEET IN THIS PACK**, and neither do Bolgmon, Metallife Kuwagamon or Rhino "
        "Kabuterimon, the other beetles the page lists; Jewelbeemon, Wisemon and Silphymon are "
        "roster entries that are idle-only, which `edgeToDexOnlyNode` forbids. AncientBeetlemon is "
        "the Ancient Warrior of Thunder and a beetle, so the Nature Spirits line — Kabuterimon, both "
        "AtlurKabuterimon, HerakleKabuterimon — is the one place it has relatives at all. Stamina; "
        "Atlur Kabuterimon (Red) spends strength on HerakleKabuterimon."),
    "ancientmegatheriumon": (
        "Mammon is a cited `Evolves From` on Wikimon and is `penc-nso`'s since US-140 — Mammothmon "
        "under the pack's Japanese spelling, which is the whole argument: AncientMegatheriumon is "
        "the Ancient Warrior of Ice and a giant ground sloth, and a mammoth is the only other "
        "ice-age mammal wired anywhere in this file. **CHACKMON, THE BOLDED PARENT, HAS NO SHEET**, "
        "nor do Blizzarmon or Frozomon; Brachimon and Shakkoumon are idle-only. Panjyamon and "
        "Panjyamon X (`penc-nsp`), Zudomon and Mermaimon (`penc-ds`) and Sirenmon (`vital`) are the "
        "cited alternatives and each is a snow or sea beast rather than an ice-age one. Vitality; "
        "Mammon spends strength on SkullMammon."),
    "ancientmermaimon": (
        "Mermaimon is a cited `Evolves From` on Wikimon and is `penc-ds`'s since US-160, which is "
        "both the obvious arrow and the cheap one: a mermaid warrior into the Ancient Warrior of "
        "Water, on the Deep Savers line where seven of this page's cited parents already live "
        "(Anomalocarimon, Gusokumon, Marin Devimon, Piranimon, Thetismon, WaruSeadramon and "
        "Mermaimon itself). The page bolds nothing. Cerberumon, Calamaramon, Ranamon and Splashmon "
        "have no sheet; Marin Angemon is an Ultimate and Coelamon an Adult, so neither is a legal "
        "in-edge. Vitality; Mermaimon spends spirit on Vikemon."),
    "ancientsphinxmon": (
        "Mummymon is a cited `Evolves From` on Wikimon and is `penc-nso`'s since US-160 — an "
        "Egyptian mummy under an Egyptian sphinx, which is as close as this file gets to the tomb "
        "AncientSphinxmon comes out of. **LÖWEMON, THE BOLDED PARENT, HAS NO SHEET IN THIS PACK**, "
        "and neither do Cerberumon or Nefertimon; Loader Leomon, Skull Satamon and Kumbhiramon are "
        "idle-only. Digitamamon (`dmc-v4`), Jyagamon (`palmon`), Scorpiomon and Skull Baluchimon are "
        "the cited alternatives with nodes, and Scorpiomon — the sand scorpion US-162 put on "
        "`penc-me` — was the near miss; Mummymon wins because it is the only one whose own Wikimon "
        "page is Egyptian too. Spirit; Mummymon spends stamina on Deathmon and vitality on Algomon, "
        "authored in this same edit."),
    "anubimon": (
        "**THE BOLDED PARENT IS UNDRAWABLE AND ITS X-ANTIBODY FORM IS NOT — WHICH IS WHY THIS ARROW "
        "IS STILL A CITATION.** Wikimon bolds three `Evolves From` for Anubimon: Cerberumon, which "
        "has NO SHEET in this pack under that name at all, Labramon, a CHILD (`invalidStageTransition` "
        "again), and Pharaohmon, which has no sheet either. Cerberumon (X-Antibody) IS drawn — "
        "`penc-me`'s since US-157 — and is cited on the same page one bullet below the bolded plain "
        "form, so the hellhound-into-jackal-god arrow is kept under the only spelling the pack "
        "carries, the Gomamon substitution US-152 recorded. Karatenmon (`wanyamon`), Mammon "
        "(`penc-nso`), WaruMonzaemon (`penc-me`) and Blossomon, Garudamon and Paildramon (`penc-wg`) "
        "are the cited alternatives; none is a psychopomp. Spirit; Cerberumon X spends strength on "
        "WarGreymon."),
    "apocalymon": (
        "Lady Devimon is a BOLDED `Evolves From` on Wikimon and is `tamers`' since US-159, so the "
        "bolded arrow lands on a line for nothing. The page's other bolded parent, Vamdemon, is "
        "`penc-nso`'s and carries BelialVamdemon in this same edit — which is the better use of it, "
        "since BelialVamdemon is Vamdemon's own final form while Apocalymon is nobody's. Fantomon "
        "and Mega Seadramon are the other cited parents. **THE CRITERIA ARE INVERTED ON PURPOSE**, "
        "the WereGarurumon Black shape US-162 recorded: Apocalymon is the Digimon that despair and "
        "defeat make, so it asks for a losing record and for a Digimon given no rest, rather than "
        "for a well-raised one. Vitality; Lady Devimon spends spirit on Beelzebumon."),
    "arcturusmon": (
        "Canoweissmon is a cited `Evolves From` on Wikimon and had been a LEAF on `penc-vb` since "
        "US-156, so the arrow clears a dead end and gives the Virus Busters line its second Mega "
        "thread. It is also where this Digimon comes from: Arcturusmon and Canoweissmon are both "
        "Vital Bracelet BE Digimon and the page bolds nothing, so a cited parent on the line whose "
        "device drew them both is as close to canonical as this page gets. Regulusmon is the other "
        "cited `penc-vb` parent — Arcturus and Regulus are both fixed stars, and Regulusmon already "
        "climbs to MetalGarurumon, while Canoweissmon climbed nowhere. MetalGreymon, MetalGreymon "
        "(Virus), Metal Mamemon and Vamdemon are the cited parents off this line. Vitality, and it "
        "is this Perfect's FIRST edge, so it is the `isDefault` climb."),
    "ariemon": (
        "Marin Bullmon is a BOLDED `Evolves From` on Wikimon and has been `dmc-v3`'s since US-160, "
        "so the bolded arrow lands on an existing line at no cost. Sekkamon, the other `dmc-v3` "
        "parent, is cited but not bolded and already climbs to Ryugumon; Darumamon (`penc-nso`) and "
        "Shishimamon (`vital`) are the two off-line citations, and Shishimamon carries Amaterasumon "
        "in this same edit. Ariemon is the ram of the zodiac and Marin Bullmon the bull of it, which "
        "is the arrow Wikimon is drawing. Strength; Marin Bullmon spends vitality on Ryugumon."),
    "armagemon": (
        "**THE LINE THIS DIGIMON BELONGS TO CANNOT TAKE IT, AND THE REASON IS ART RATHER THAN "
        "SHAPE.** Wikimon's `Evolves From` for it is what says so. Armagemon is what the Kuramon swarm becomes, and `diablomon` is that line — but "
        "its bolded parent Kuramon is a BABY I (`invalidStageTransition` refuses everything but one "
        "rung), and Chrysalimon and Infermon, the two Perfect rungs the swarm actually climbs "
        "through, are BOTH idle-only in this pack, which `edgeToDexOnlyNode` forbids. So the "
        "`diablomon` line has no Perfect that could carry this arrow and no story can author one "
        "into it. Chimairamon is the cited parent that can: `dmc-v1`'s since US-157, and the flavour "
        "is the same idea under another name — Kimeramon is a Digimon assembled out of the parts of "
        "many others, Armagemon a Digimon assembled out of a multitude of Kuramon. Metal Tyranomon "
        "and Mummymon are the other cited parents with nodes; every remaining name on the page is an "
        "Ultimate. Stamina; Chimairamon spends strength on Millenniumon."),
    "armamon": (
        "**ONE CITED PARENT ANYWHERE, AND IT IS ON THE LINE NO EGG CAN REACH.** Wikimon gives "
        "Armamon three `Evolves From`: Arresterdramon, an ADULT, Zeke Greymon, an ULTIMATE, and "
        "OmegaShoutmon, which is `xros`' since US-161 and the only one at the rung below. So this "
        "node lands on `xros` and INHERITS that line's strandedness — `xros` has no Digitama, "
        "because US-144 and US-145 spent all fifty-seven, so every node above Shoutmon King is "
        "unreachable from any egg and always was. `EvolutionCriteriaTests`' stranded list names it "
        "for exactly that reason and proves the inheritance through the parent loop. This is the "
        "Xros Loader line, and every node on it names that device in its comment — US-146's rule, "
        "checked from four separate files. Vitality; "
        "OmegaShoutmon spends strength on ZekeGreymon."),
    "bagramon": (
        "Mametyramon is a cited `Evolves From` on Wikimon and had been a LEAF on `tamers` since "
        "US-154, so the arrow clears a dead end. **BAGRAMON (ARCHANGEL FORM), THE BOLDED PARENT, HAS "
        "NO SHEET IN THIS PACK** — it is the same Digimon before it fell, not a separate one this "
        "file could draw — and the only other cited names are Stiffilmon (`penc-vb`, which already "
        "climbs to Rasenmon) and Kaiser Leomon, an Armor-Hybrid and so off the ladder entirely. "
        "Bagramon is the emperor the Bagra Army serves and `xros`, the line it would belong to, "
        "holds no cited parent for it at all; `tamers` is where the citation points. Strength, and "
        "it is this Perfect's FIRST edge, so it is the `isDefault` climb."),
    "bancholilimon": (
        "**THE BOLDED PARENT WAS REFUSED BY A TEST RATHER THAN BY A RULE OF THE DATA, AND THAT IS "
        "WORTH SAYING.** Lilimon is the bolded `Evolves From` on Wikimon and is on `palmon` — but "
        "`SeedRosterTests.testTheThreeNamedLinesAreTheOnesShipped` pins US-002's first named line as "
        "Palmon -> Togemon -> Lilimon -> Rosemon and walks it by preferring the EARNED edge at every "
        "rung, so hanging an earned branch on Lilimon would silently redirect that line to "
        "BanchoLilimon. Lilamon is the page's other cited parent, is on the same line, and is "
        "Lilimon's own sister form — the variant rule's weaker half, same line rather than same "
        "parent, and here it is the only half available. Eosmon (Perfect) has no sheet. Spirit; "
        "Lilamon spends vitality on Rosemon, which BanchoLilimon's own page names as a sibling form "
        "rather than as a climb."),
    "barbamon": (
        "Mephismon is a cited `Evolves From` on Wikimon and is `penc-nso`'s since US-160 — a "
        "Mephistopheles under the demon lord of greed, on the Nightmare Soldiers line where nine of "
        "this page's cited parents already live. **THE BOLDED `Evolves From` IS THE CODE KEY OF "
        "GREED, AN ITEM AND NOT A DIGIMON**, which is the same thing US-151's Deckerdramon comment "
        "recorded about class-level citations: a bolded name is not always a Digimon to draw an "
        "arrow from. Vamdemon, Fantomon, Death Meramon, Blue Meramon and Mummymon are the other "
        "cited `penc-nso` parents and every one of them was already spoken for by a Mega of its own; "
        "Mephismon was free. Spirit; Mephismon spends vitality on Piemon."),
    "barbamon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT, WHICH IS THE STRONG FORM OF THE VARIANT RULE US-160 "
        "recorded. Wikimon gives Barbamon (X-Antibody) thirteen `Evolves From` and every single one "
        "is an ULTIMATE — the bolded one is Barbamon itself — so there is no drawable in-edge "
        "anywhere in its own citations and none ever will be: an Ultimate can never be a parent at "
        "this rung. Mephismon carries the plain Barbamon in this same edit, so the two land on one "
        "Perfect and the player who raises a Mephismon can reach either. Strength, distinct from the "
        "spirit Barbamon takes and from the vitality Mephismon spends on Piemon, so all three edges "
        "are separately reachable."),
    "beelzebumon_blast": (
        "Baalmon is a cited `Evolves From` on Wikimon and is `tamers`' since US-157 — the Digimon "
        "Beelzebumon itself climbs from, so Blast Mode lands beside the base form it upgrades. Both "
        "bolded parents are undrawable as in-edges here: Beelzebumon is an ULTIMATE and Impmon a "
        "CHILD, the two shapes `invalidStageTransition` refuses either side of the rung. Neo Devimon "
        "(`dmc-v1`) is the only other cited parent at the Perfect rung, and every remaining name on "
        "the page is an Ultimate. Strength; Baalmon spends spirit on Beelzebumon and vitality on "
        "Beelzebumon X, authored in this same edit — three edges, three energies, so the fork holds."),
    "beelzebumon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT, the same strong variant rule Barbamon X follows above. "
        "Wikimon's bolded parents are again Beelzebumon (an Ultimate) and Impmon (a Child), and the "
        "two drawable citations it does have — Death Meramon on `penc-nso` and Metal Tyranomon "
        "(X-Antibody) on `dmc-v5` — would each have split this variant from the base form and from "
        "Blast Mode. Baalmon carries all three, which is what US-160's rule is for. Vitality; "
        "Baalmon spends spirit on Beelzebumon and strength on Blast Mode."),
    "belialvamdemon": (
        "Vamdemon is the BOLDED `Evolves From` on Wikimon and is `penc-nso`'s since US-140, so the "
        "bolded arrow lands on an existing line for nothing — and it is the arrow this Digimon is: "
        "BelialVamdemon is what Vamdemon becomes, one rung past VenomVamdemon, which this line "
        "already draws over the same Perfect. Vamdemon (X-Antibody), authored by US-162, is cited "
        "too and is on the same line and the same rung, so either reading kept the family together; "
        "the bolded one wins. Cho·Hakkaimon, Holy Angemon, Lilimon, MegaloGrowmon X and Metal "
        "Tyranomon X are the cited parents off this line. Vitality; Vamdemon spends spirit on "
        "VenomVamdemon."),
    "belphemon_rage": (
        "Astamon is a BOLDED `Evolves From` on Wikimon and is `penc-me`'s since US-157, so the "
        "bolded arrow lands on an existing line at no cost. The page's other bolded names are the "
        "Code Key of Sloth, an ITEM, and Belphemon: Sleep Mode, which has no sheet in this pack — "
        "so Rage Mode is the only Belphemon this file can draw and it is reached directly. **THE "
        "CRITERIA ARE THE DIGIMON**: sloth asks for a Digimon that slept a very great deal and was "
        "then woken repeatedly, which is exactly the myth — Belphemon sleeps for a thousand years "
        "and wakes in a rage. Mammon, Mephismon, Crescemon, Dark Knightmon, Skull Baluchimon and "
        "four MegaloGrowmon are the other cited parents with nodes. Stamina; Astamon spends strength "
        "on VenomVamdemon and vitality on Belphemon X, authored in this same edit."),
    "belphemon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT, the third and last of this story's X-Antibody Megas to "
        "do so and the one with the fewest alternatives of any: Wikimon gives Belphemon (X-Antibody) "
        "five `Evolves From` and the bolded pair are both Belphemon itself, Rage Mode and Sleep "
        "Mode, of which Sleep Mode has no sheet and Rage Mode is an ULTIMATE this same edit authors. "
        "The other three — Cherubimon (Vice) X, Metal Piranimon and Rosemon X — are Ultimates too. "
        "So Astamon carries both Belphemon, and the antibody is asked for the sleep without the "
        "waking. Vitality; Astamon spends strength on VenomVamdemon and stamina on Rage Mode."),
    "blacksaintgalgomon": (
        "Black Rapidmon is a cited `Evolves From` on Wikimon and had been a LEAF on `tamers` since "
        "US-156, so the arrow clears a dead end AND puts this Digimon on its base form's own line: "
        "SaintGalgomon is `tamers`' Mega over Rapidmon, and the black pair now runs Youkomon -> "
        "BlackRapidmon -> BlackSaintGalgomon beside it. The page bolds nothing. Bastemon, Bishop "
        "Chessmon (White), Rapidmon Perfect and Rook Chessmon (Black) have no sheet; Gigadramon and "
        "both Metal Tyranomon (`dmc-v5`) and Megadramon (`dmc-v4`) are the cited parents off this "
        "line, and each would have split the variant from its base form. Strength, and it is this "
        "Perfect's FIRST edge, so it is the `isDefault` climb."),
    "blackseraphimon": (
        "Holy Angemon is a cited `Evolves From` on Wikimon and is `penc-vb`'s since US-143, where it "
        "already carries Seraphimon — which is the whole argument: BlackSeraphimon is the fallen "
        "Seraphimon, so it belongs on the Perfect that draws the unfallen one. **MERCUREMON AND "
        "SERAPHIMON, THE TWO BOLDED PARENTS, ARE UNDRAWABLE**: Mercuremon has no sheet in this pack "
        "and Seraphimon is an ULTIMATE, so neither can be an in-edge. Ancient Wisemon is idle-only "
        "and Holy Angemon: Priest Mode and Sephirothmon have no sheet. **THE CRITERIA ARE INVERTED**, "
        "the Lucemon Falldown and WereGarurumon Black shape: this is the angel that fell, so it asks "
        "for a losing record and for a Digimon kept out of the light. Strength; Holy Angemon spends "
        "spirit on Seraphimon and vitality on Cherubimon (Virtue), so this line's one Perfect now "
        "forks three ways and every branch has its own energy."),
    "blackwargreymon_x": (
        "FOLLOWS A CITED PARENT RATHER THAN ITS BASE FORM'S LINE, and the parent is the whole "
        "X-Antibody thread rather than a stand-in: Metal Greymon (Virus) (X-Antibody) is a cited "
        "`Evolves From` on Wikimon and is `dmc-v1`'s since US-160, sitting exactly where the "
        "Agumon (Black) X -> Greymon (Virus) X -> Metal Greymon (Virus) X -> BlackWarGreymon X "
        "chain the Digital Monster X device draws puts it. The plain BlackWarGreymon is on "
        "`adventure02` — US-162 put it over Vermillimon, the only Champion that line could open at "
        "all — and Vermillimon does not cite this variant, so the escape hatch "
        "`ChildSweepMToZTests.testEveryVariantSitsWithItsBaseFormOrFollowsACitedParent` opened is "
        "what this takes. The page bolds nothing. Mametyramon and three MegaloGrowmon (`tamers`) and "
        "Stiffilmon (`penc-vb`) are the other cited parents. Stamina; Metal Greymon (Virus) X spends "
        "strength on BlitzGreymon."),
    "blastmon": (
        "Insekimon is a cited `Evolves From` on Wikimon and is `penc-nso`'s since US-159 — a "
        "meteorite given limbs under a Digimon made of crystal, which is the closest thing to "
        "Blastmon's own body anywhere in this file. The page's `Evolves From` bolds nothing and "
        "names DigiXros, which is a FUSION list and not an evolution — the Bombmon trap US-145 "
        "recorded — so the citations that remain are the ones to read. Gravimon and Vulturemon have "
        "no sheet; Atlur Kabuterimon (Blue) (`penc-nsp`), Gogmamon (`wanyamon`), Jyagamon (`palmon`), "
        "Mummymon (`penc-nso`), Scorpiomon (`penc-me`) and Triceramon (`dmc-v4`) are the cited "
        "alternatives, and Mummymon carries two Megas already in this same edit. Blastmon is a Death "
        "General of the Bagra Army and `xros` holds no cited parent for it, exactly as it held none "
        "for Bagramon. Strength; Insekimon spends stamina on Boltmon."),
    "breakdramon": (
        "Megalo Growmon is a cited `Evolves From` on Wikimon and had been a LEAF on `tamers` since "
        "US-151 — the longest-standing dead end this story clears, and the one that has been cited "
        "for a Mega by three separate sweeps without being given one. **GROUNDRAMON, THE BOLDED "
        "PARENT, HAS NO SHEET IN THIS PACK**, and neither do Savior Huckmon, Tankdramon or "
        "Wingdramon, the other machine dragons on the page. Both other MegaloGrowmon, DORUguremon "
        "and Triceramon are cited too; the plain form is the one that led nowhere. A cyborg dragon "
        "with a chest cannon under a colossal drilling dragon is the flavour, and both are `tamers`. "
        "Strength, and it is this Perfect's FIRST edge, so it is the `isDefault` climb."),
    "brigadramon": (
        "Cargodramon is a cited `Evolves From` on Wikimon and is `penc-me`'s since US-157, and the "
        "arrow is the Digimon: Cargodramon is a freight-hauling dragon and Brigadramon the "
        "locomotive it grows into, on the Metal Empire line where every machine in this file lives. "
        "The page bolds nothing. Tankdramon has no sheet; Hisyaryumon is the other cited `penc-me` "
        "parent and already climbs to Ouryumon, and Megadramon (`dmc-v4`) is the one citation off "
        "this line. Strength; Cargodramon spends stamina on Mugendramon."),
}

ELEMENTS = {
    "agumon_ynk": ("fire", "vaccine"),
    "algomon_ultimate": ("machine", "virus"),
    "alphamon": ("light", "vaccine"),
    "alphamon_ouryuken": ("light", "vaccine"),
    "amaterasumon": ("light", "vaccine"),
    "ancientbeatmon": ("electric", "free"),
    "ancientmegatheriumon": ("ice", "free"),
    "ancientmermaimon": ("water", "free"),
    "ancientsphinxmon": ("dark", "free"),
    "anubimon": ("dark", "vaccine"),
    "apocalymon": ("dark", "virus"),
    "arcturusmon": ("light", "vaccine"),
    "ariemon": ("earth", "data"),
    "armagemon": ("dark", "virus"),
    "armamon": ("steel", "data"),
    "bagramon": ("dark", "virus"),
    "bancholilimon": ("plant", "data"),
    "barbamon": ("dark", "virus"),
    "barbamon_x": ("dark", "virus"),
    "beelzebumon_blast": ("dark", "virus"),
    "beelzebumon_x": ("dark", "virus"),
    "belialvamdemon": ("dark", "virus"),
    "belphemon_rage": ("fire", "virus"),
    "belphemon_x": ("fire", "virus"),
    "blacksaintgalgomon": ("machine", "virus"),
    "blackseraphimon": ("dark", "virus"),
    "blackwargreymon_x": ("steel", "virus"),
    "blastmon": ("earth", "virus"),
    "breakdramon": ("machine", "virus"),
    "brigadramon": ("machine", "data"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
# `projectileSymbol|tint` must be unique WITHIN a line and `signatureName` GLOBALLY; `check()`
# proves both against the real files before anything is written.
MOVES = {
    "agumon_ynk": ("flame.fill", "mint", "Bond of Bravery", "flame.fill"),
    "algomon_ultimate": ("eye.fill", "green", "Total Algorithm", "eye.fill"),
    "alphamon": ("shield.fill", "red", "Digitalize of Soul", "shield.fill"),
    "alphamon_ouryuken": ("bolt.fill", "mint", "Ouryuken Slash", "bolt.fill"),
    "amaterasumon": ("star.fill", "yellow", "Heavenly Rock Door", "star.fill"),
    "ancientbeatmon": ("bolt.fill", "green", "Thunder Fist", "bolt.fill"),
    "ancientmegatheriumon": ("snowflake", "teal", "Great Blizzard", "snowflake"),
    "ancientmermaimon": ("drop.fill", "yellow", "Ocean Trident", "drop.fill"),
    "ancientsphinxmon": ("moon.fill", "yellow", "Necro Mist", "moon.fill"),
    "anubimon": ("triangle.fill", "yellow", "Pyramid Power", "triangle.fill"),
    "apocalymon": ("moon.fill", "blue", "Darkness Zone", "moon.fill"),
    "arcturusmon": ("star.fill", "blue", "Arcturus Lance", "star.fill"),
    "ariemon": ("hammer.fill", "orange", "Golden Fleece", "hammer.fill"),
    "armagemon": ("circle.fill", "purple", "Ultimate Flare", "circle.fill"),
    "armamon": ("shield.fill", "orange", "Full Armament", "shield.fill"),
    "bagramon": ("moon.fill", "teal", "Darkness Loader", "moon.fill"),
    "bancholilimon": ("hand.raised.fill", "pink", "Bancho Bloom", "hand.raised.fill"),
    "barbamon": ("sparkles", "orange", "Pandemonium Lost", "sparkles"),
    "barbamon_x": ("sparkles", "yellow", "Greed Cross", "sparkles"),
    "beelzebumon_blast": ("bolt.fill", "teal", "Death the Cannon", "bolt.fill"),
    "beelzebumon_x": ("bolt.fill", "cyan", "Double Impact Cross", "bolt.fill"),
    "belialvamdemon": ("moon.fill", "green", "Melting Blood", "moon.fill"),
    "belphemon_rage": ("flame.fill", "orange", "Gift of Darkness", "flame.fill"),
    "belphemon_x": ("flame.fill", "indigo", "Lampranthus Cross", "flame.fill"),
    "blacksaintgalgomon": ("hammer.fill", "gray", "Giant Missile Black", "hammer.fill"),
    "blackseraphimon": ("sparkles", "gray", "Fallen Excalibur", "sparkles"),
    "blackwargreymon_x": ("flame.fill", "teal", "Terra Destroyer Cross", "flame.fill"),
    "blastmon": ("sparkles", "green", "Crystal Barrage", "sparkles"),
    "breakdramon": ("gearshape.fill", "orange", "Destruction Drill", "gearshape.fill"),
    "brigadramon": ("bolt.fill", "blue", "Brigade Cannon", "bolt.fill"),
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

    # No hint may state a number (`EvolutionCriteriaTests.testNoConditionHintContainsADigit`).
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
        if parent in LEAF_PARENTS and uid in CONDITIONS:
            sys.exit("%s is a leaf's isDefault climb and must not carry criteria" % uid)
        if parent not in LEAF_PARENTS and uid not in CONDITIONS:
            sys.exit("%s is an earned branch and must carry criteria" % uid)

    # Every edge on a Perfect needs its own energy, or `EvolutionEngine.qualifies` — which matches
    # on the DOMINANT type — makes the lower-`minEnergy` one unreachable.
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

    # 1. the in-edges. A leaf Perfect gains its single `isDefault` climb; every other Perfect gains
    #    an EARNED branch beside the climb it already has, and the climb stays last.
    for uid, _, _, _, parent, energy in ULTIMATES:
        node = by_id[parent]
        node.setdefault("evolutions", [])
        if parent in LEAF_PARENTS:
            node["evolutions"] = [{"to": uid, "requiredEnergy": energy, "minEnergy": 150,
                                   "maxCareMistakes": 2, "isDefault": True}]
            continue
        edge = {"to": uid, "requiredEnergy": energy, "minEnergy": 150, "maxCareMistakes": 2,
                "conditions": [condition(*c) for c in CONDITIONS[uid]]}
        fallback = [e for e in node["evolutions"] if e.get("isDefault")]
        earned = [e for e in node["evolutions"] if not e.get("isDefault")] + [edge]
        node["evolutions"] = earned + fallback

    # 2. the thirty Ultimates, terminal and so with no `evolutions` key at all.
    for uid, name, sprite, line, _, _ in ULTIMATES:
        nodes.append({
            "id": uid, "displayName": name, "stage": "Ultimate-Super Ultimate", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[uid],
        })

    open(path, "w").write(json.dumps(doc, indent=2, ensure_ascii=False))

    # 3. elements.json and moves.json, one entry apiece for all thirty.
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
