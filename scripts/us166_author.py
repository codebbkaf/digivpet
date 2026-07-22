"""US-166 — Orphan sweep: Ultimate-Super Ultimate I-M, the fourth sweep at the top rung.

Authors the twenty-seven orphaned Ultimate whose display name begins I-M that no device tree and no
earlier sweep reached, and that no Jogress recipe already reaches as a NODE (Mastemon and Mitamamon
are Jogress results, but Jogress results still take an evolution in-edge here — the same as Cernumon,
Aegisdramon and Millenniumon before them). The rung is TERMINAL, so this is an IN-EDGE sweep and
nothing else — twenty-seven orphans, twenty-seven nodes, no junk floor and no new line, exactly the
shape US-163/US-164/US-165 recorded.

Twenty-six hang an EARNED branch beside the climb their Perfect already has (two criteria, one health
metric and one care counter, a `requiredEnergy` distinct from every other edge on that node). ONE is
a LEAF's `isDefault` climb: Karakurumon, a bolded parent of Kaguyamon that has been a Perfect dead
end on `wanyamon`, gains its single unconditional climb — one entry off `ChildSweepAToFTests`' ledger.

FIVE PERFECTS REACH FOUR EDGES (all energies spent): Paildramon (the three Imperialdramon Modes),
SaviorHackmon (the three Jesmon), LadyDevimon (Lilithmon + Lilithmon X), Knightmon (LordKnightmon X)
and Digitamamon (Minervamon X) — joining HolyAngemon, DORUguremon and pencme_andromon.

Run once; it refuses to run twice (every id it adds must be absent).
"""
import collections
import json
import sys

ROOT = "/Users/red/Documents/SourceCode/ios_project/digi/"

# (id, displayName, spriteFile, line, parent, energy)
ULTIMATES = [
    ("imperialdramon_fighter", "Imperialdramon Fighter", "Imperialdramon_Fighter", "penc-wg", "paildramon", "stamina"),
    ("imperialdramon_fighter_black", "Imperialdramon Fighter Black", "Imperialdramon_Fighter_Black", "penc-wg", "paildramon", "spirit"),
    ("imperialdramon_paladin", "Imperialdramon Paladin", "Imperialdramon_Paladin", "penc-wg", "paildramon", "vitality"),
    ("jesmon", "Jesmon", "Jesmon", "penc-nso", "saviorhackmon", "strength"),
    ("jesmon_x", "Jesmon X", "Jesmon_X", "penc-nso", "saviorhackmon", "stamina"),
    ("jesmon_gx", "Jesmon GX", "Jesmon_GX", "penc-nso", "saviorhackmon", "vitality"),
    ("jougamon", "Jougamon", "Jougamon", "penc-sw", "chohakkaimon", "strength"),
    ("jumbogamemon", "JumboGamemon", "JumboGamemon", "penc-sw", "shawujinmon", "stamina"),
    ("justimon_x", "Justimon X", "Justimon_X", "penc-me", "cyberdramon_x", "strength"),
    ("kaguyamon", "Kaguyamon", "Kaguyamon", "wanyamon", "karakurumon", "strength"),
    ("kuzuhamon", "Kuzuhamon", "Kuzuhamon", "wanyamon", "karatenmon", "strength"),
    ("leviamon_x", "Leviamon X", "Leviamon_X", "penc-ds", "marindevimon", "strength"),
    ("lilithmon", "Lilithmon", "Lilithmon", "tamers", "ladydevimon", "strength"),
    ("lilithmon_x", "Lilithmon X", "Lilithmon_X", "tamers", "ladydevimon", "stamina"),
    ("lordknightmon_x", "LordKnightmon X", "LordKnightmon_X", "penc-me", "knightmon", "stamina"),
    ("lotusmon", "Lotusmon", "Lotusmon", "palmon", "lilamon", "strength"),
    ("lucemon_satan", "Lucemon Satan", "Lucemon_Satan", "penc-nso", "lucemon_falldown", "strength"),
    ("lucemon_x", "Lucemon X", "Lucemon_X", "penc-nso", "lucemon_falldown", "spirit"),
    ("magnamon_x", "Magnamon X", "Magnamon_X", "penc-wg", "aerov-dramon", "stamina"),
    ("marinangemon", "MarinAngemon", "MarinAngemon", "penc-ds", "pencds_whamon", "strength"),
    ("mastemon", "Mastemon", "Mastemon", "penc-nsp", "angewomon", "strength"),
    ("megidramon", "Megidramon", "Megidramon", "tamers", "megalogrowmon", "stamina"),
    ("megidramon_x", "Megidramon X", "Megidramon_X", "tamers", "megalogrowmon", "spirit"),
    ("metalgarurumon_black", "MetalGarurumon Black", "MetalGarurumon_Black", "dmc-v2", "weregarurumon_black", "stamina"),
    ("metalgarurumon_x", "MetalGarurumon X", "MetalGarurumon_X", "penc-nso", "weregarurumon_x", "strength"),
    ("minervamon_x", "Minervamon X", "Minervamon_X", "dmc-v4", "digitamamon", "stamina"),
    ("mitamamon", "Mitamamon", "Mitamamon", "penc-wg", "garudamon", "strength"),
]

# The one Perfect that was a LEAF before this story and now carries its single `isDefault` climb.
LEAF_PARENTS = {"karakurumon"}

# Two criteria on every EARNED in-edge: one HealthKit metric, one care counter.
# `care.battleCount` and `care.battleWinRatio` answer only over `lifetime`, every other `care.*` only
# over `stage` — US-150's rule.
CONDITIONS = {
    "imperialdramon_fighter": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 260000, "March the dragon across the whole grid it guards"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And let the positron cannon settle every fight"),
    ],
    "imperialdramon_fighter_black": [
        ("health.activeEnergy", "stage", "atLeast", 30000, "Burn the dark dragon's engine to its limit"),
        ("care.battleCount", "lifetime", "atLeast", 36, "And blacken its record with battle after battle"),
    ],
    "imperialdramon_paladin": [
        ("health.flightsClimbed", "stage", "atLeast", 640, "Raise the paladin higher than any tower"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.9, "And let the Omega blade go unbeaten"),
    ],
    "jesmon": [
        ("health.exerciseMinutes", "stage", "atLeast", 1700, "Train the young knight without a wasted hour"),
        ("care.trainingSessions", "stage", "atLeast", 32, "And drill its three tails in the ring daily"),
    ],
    "jesmon_x": [
        ("health.steps", "stage", "atLeast", 110000, "Walk the whole circuit the testament demands"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.88, "And answer every trial with a clean win"),
    ],
    "jesmon_gx": [
        ("health.activeEnergy", "stage", "atLeast", 34000, "Pour a superior spirit into the final form"),
        ("care.battleCount", "lifetime", "atLeast", 42, "And prove the crest over countless duels"),
    ],
    "jougamon": [
        ("health.flightsClimbed", "stage", "atLeast", 560, "Haul the stone body up every ridge"),
        ("care.trainingSessions", "stage", "atLeast", 28, "And harden the pilgrim in the training pit"),
    ],
    "jumbogamemon": [
        ("health.distanceSwimming", "stage", "atLeast", 42000, "Cross the deep the giant turtle rules"),
        ("care.overfeeds", "stage", "atLeast", 7, "And pile the shell high past every meal"),
    ],
    "justimon_x": [
        ("health.exerciseMinutes", "stage", "atLeast", 1600, "Keep the cyborg fighter in constant motion"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And let the justice kick end every bout"),
    ],
    "kuzuhamon": [
        ("health.mindfulMinutes", "stage", "atLeast", 900, "Sit the fox priestess in a long meditation"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And never break the shrine's quiet rest"),
    ],
    "leviamon_x": [
        ("health.distanceSwimming", "stage", "atLeast", 48000, "Dive past the abyss the leviathan claims"),
        ("care.battleCount", "lifetime", "atLeast", 40, "And drag every challenger under the tide"),
    ],
    "lilithmon": [
        ("health.daylight", "stage", "atMost", 150, "Keep the demon lord well out of the sun"),
        ("care.battleCount", "lifetime", "atLeast", 34, "And build her dread one duel at a time"),
    ],
    "lilithmon_x": [
        ("health.sleep", "stage", "atMost", 5400, "Let the seductress keep the long night awake"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And leave every rival to her golden claw"),
    ],
    "lordknightmon_x": [
        ("health.flightsClimbed", "stage", "atLeast", 620, "Carry the rose knight up every stair"),
        ("care.trainingSessions", "stage", "atLeast", 30, "And rehearse the spiral masquerade daily"),
    ],
    "lotusmon": [
        ("health.steps", "stage", "atLeast", 100000, "Walk the whole garden the lotus tends"),
        ("care.overfeeds", "stage", "atMost", 1, "And keep the flower's temperance at the table"),
    ],
    "lucemon_satan": [
        ("health.activeEnergy", "stage", "atLeast", 36000, "Loose the fallen angel's whole hellfire"),
        ("care.battleCount", "lifetime", "atLeast", 44, "And judge the living over endless war"),
    ],
    "lucemon_x": [
        ("health.daylight", "stage", "atMost", 120, "Keep the antibody devil far from daylight"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.9, "And let dead-or-alive spare no challenger"),
    ],
    "magnamon_x": [
        ("health.flightsClimbed", "stage", "atLeast", 600, "Lift the golden armour above every peak"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And let the miracle metal turn each blow"),
    ],
    "marinangemon": [
        ("health.distanceSwimming", "stage", "atLeast", 40000, "Swim the whole reef the sea cherub blesses"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And never trouble its gentle tidal rest"),
    ],
    "mastemon": [
        ("health.mindfulMinutes", "stage", "atLeast", 1000, "Balance light and dark in a long stillness"),
        ("care.trainingSessions", "stage", "atLeast", 30, "And temper both halves in the training ring"),
    ],
    "megidramon": [
        ("health.activeEnergy", "stage", "atLeast", 32000, "Stoke the doom dragon until the ground shakes"),
        ("care.overfeeds", "stage", "atLeast", 8, "And gorge its endless hunger far past full"),
    ],
    "megidramon_x": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 240000, "Range the ruin the reworked dragon leaves"),
        ("care.battleCount", "lifetime", "atLeast", 40, "And answer the hazard with unending war"),
    ],
    "metalgarurumon_black": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 220000, "Run the black wolf across the frozen waste"),
        ("care.battleCount", "lifetime", "atLeast", 38, "And let the metal fangs meet every foe"),
    ],
    "metalgarurumon_x": [
        ("health.exerciseMinutes", "stage", "atLeast", 1600, "Keep the reforged wolf on the endless hunt"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And let its ice cannon finish every chase"),
    ],
    "minervamon_x": [
        ("health.exerciseMinutes", "stage", "atLeast", 1500, "Keep the little sword goddess ever moving"),
        ("care.trainingSessions", "stage", "atLeast", 30, "And whet the strike sword in daily drill"),
    ],
    "mitamamon": [
        ("health.mindfulMinutes", "stage", "atLeast", 900, "Sit the shrine guardian in a purifying calm"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And keep the sacred barrier's rest unbroken"),
    ],
}

COMMENTS = {
    "imperialdramon_fighter": (
        "Paildramon is a BOLDED `Evolves From` on Wikimon and is `penc-wg`'s — the V-mon-and-Wormmon "
        "DNA line the whole Imperialdramon thread belongs to, so the Fighter Mode lands on an existing "
        "line for nothing. Its other Wikimon parents are Imperialdramon: Dragon Mode (a Mode Change, "
        "an Ultimate) and card-game placeholders. **THIS EDIT MAKES PAILDRAMON A FOUR-EDGE PERFECT** — "
        "Fighter (stamina), Fighter Black (spirit), Paladin (vitality) and its own UlforceV-dramon "
        "climb (strength) — every energy spent, closed. Stamina."),
    "imperialdramon_fighter_black": (
        "SITS ON ITS BASE FORM'S OWN PERFECT, the strong variant rule. Wikimon bolds Imperialdramon: "
        "Dragon Mode (Black), a Mode-Change Ultimate `invalidStageTransition` refuses, so the black "
        "dragon hangs where the plain Fighter Mode hangs: Paildramon on `penc-wg`. Spirit; Paildramon "
        "spends stamina on the Fighter Mode and vitality on the Paladin in this same edit."),
    "imperialdramon_paladin": (
        "Wikimon bolds Imperialdramon: Fighter Mode for the Paladin Mode, an Ultimate that "
        "`invalidStageTransition` refuses, so the Royal Knight paladin hangs where the Fighter Mode "
        "itself hangs — Paildramon on `penc-wg`, the V-mon DNA line. Every other `Evolves From` on the "
        "long page is a two-parent Jogress (Omegamon, Gran Kuwagamon) the file cannot draw. Vitality."),
    "jesmon": (
        "SaviorHackmon is the cited `Evolves From` on Wikimon for the Hackmon Royal Knight (Digimon "
        "Story: Cyber Sleuth, the Hackmon -> BaoHackmon -> SaviorHackmon -> Jesmon thread) and is "
        "`penc-nso`'s, so the three-tailed knight lands on its own line for nothing. **THIS EDIT MAKES "
        "SAVIORHACKMON A FOUR-EDGE PERFECT** — Jesmon (strength), Jesmon X (stamina), Jesmon GX "
        "(vitality) and its own Boltmon climb (spirit). Strength."),
    "jesmon_x": (
        "SITS ON ITS BASE FORM'S OWN PERFECT, the strong variant rule. Wikimon has no `Evolves From` "
        "section for Jesmon (X-Antibody) at all, so the antibody hangs where the plain Jesmon hangs — "
        "SaviorHackmon on `penc-nso`. Stamina; SaviorHackmon spends strength on Jesmon and vitality on "
        "Jesmon GX in this same edit."),
    "jesmon_gx": (
        "Jesmon GX is Jesmon's superior form, an Ultimate `invalidStageTransition` refuses to draw "
        "from Jesmon itself (Wikimon lists no Perfect parent for it), so it hangs where Jesmon hangs — "
        "SaviorHackmon on `penc-nso`, the Hackmon knight line. Vitality; the third of SaviorHackmon's "
        "three Jesmon branches, and every energy on it is now distinct."),
    "jougamon": (
        "Cho·Hakkaimon is a cited `Evolves From` on Wikimon (Pendulum COLOR 6 Saiyu Warriors, as a "
        "Jogress) and is `penc-sw`'s, the Journey-to-the-West line the pig-warrior and its fellows "
        "sit on, so the earth pilgrim lands beside its Saiyu Warriors cast. Its other citations "
        "(Andiramon Deva, Dianamon, Cherubimon Vice) are Devas, Ultimates or off this line. Strength."),
    "jumbogamemon": (
        "Shawujinmon is a BOLDED `Evolves From` on Wikimon (a Jogress with Whamon Perfect and the "
        "Chessmon) and is `penc-sw`'s, the Saiyu Warriors line Sha Wujing anchors, so the giant "
        "turtle lands on an existing line for nothing. Its other bolded and cited parents (Whamon "
        "Perfect, Big Mamemon, Mega Seadramon) are off this line or two-parent Jogresses. Stamina."),
    "justimon_x": (
        "**ITS BASE FORM IS IDLE-ONLY, SO A CITATION HAS TO CARRY IT** — the Dynasmon X shape "
        "(US-164). Wikimon bolds only the Justimon Arm modes (Ultimates), and the roster marks the "
        "plain Justimon `dexOnly`, so `edgeToDexOnlyNode` and the Ultimate rung would refuse that "
        "arrow twice over. Cyberdramon (X-Antibody) is a cited `Evolves From` and is `penc-me`'s, so "
        "an antibody rises from an antibody on the cyborg dragon line. Strength."),
    "kaguyamon": (
        "Karakurumon is a BOLDED `Evolves From` on Wikimon (Digimon Liberator, Digimon Pendulum "
        "COLOR) and had been a PERFECT DEAD END on `wanyamon` — so the arrow clears a leaf AND "
        "follows a bolded citation, the leaf-climb shape every Ultimate sweep uses. Hanimon, the "
        "other bolded parent, is a Champion `invalidStageTransition` refuses. Strength, and it is "
        "Karakurumon's FIRST edge, so it is the `isDefault` climb and carries no criteria."),
    "kuzuhamon": (
        "Karatenmon is a cited `Evolves From` on Wikimon (a Jogress with Taomon) and is `wanyamon`'s, "
        "so the fox priestess lands on an existing line for nothing. Its bolded parent Doumon is "
        "marked `dexOnly` in this pack (no animated sheet) and Taomon and Sakuyamon are not nodes at "
        "all, so the crow-tengu Karatenmon is the drawable citation. Strength."),
    "leviamon_x": (
        "SITS ON ITS BASE FORM'S OWN PERFECT, the strong variant rule. Wikimon bolds only Leviamon "
        "for Leviamon (X-Antibody), an Ultimate `invalidStageTransition` refuses, so the antibody "
        "hangs where the plain Leviamon hangs — MarinDevimon on `penc-ds` climbs into Leviamon, and "
        "the leviathan belongs to its Deep Savers sea-demon line. Strength."),
    "lilithmon": (
        "LadyDevimon is a BOLDED `Evolves From` on Wikimon (Pendulum Progress 2.0, Digimon World "
        "Re:Digitize and many more, as the canonical single parent) and is `tamers`'. **THIS EDIT "
        "MAKES LADYDEVIMON A FOUR-EDGE PERFECT** — Apocalymon (vitality), Beelzebumon (spirit), "
        "Lilithmon (strength) and Lilithmon X (stamina) in this same edit — every energy spent, and "
        "the Sin of Lust joins the Seven Great Demon Lords already scattered across the file. Strength."),
    "lilithmon_x": (
        "SITS ON ITS BASE FORM'S OWN PERFECT, the strong variant rule. Wikimon bolds only Lilithmon "
        "for Lilithmon (X-Antibody), an Ultimate `invalidStageTransition` refuses, so the antibody "
        "hangs where the plain Lilithmon hangs — LadyDevimon on `tamers`. Stamina; the fourth and "
        "last energy on LadyDevimon, taken beside the plain Lilithmon in this same edit."),
    "lordknightmon_x": (
        "**ITS BASE FORM IS IDLE-ONLY, SO A CITATION HAS TO CARRY IT** — the Dynasmon X shape. "
        "Wikimon bolds only Lord Knightmon for Lord Knightmon (X-Antibody), and the roster marks the "
        "plain LordKnightmon `dexOnly`, so `edgeToDexOnlyNode` refuses the base-form arrow. Knightmon "
        "is the Royal Knight's canonical Perfect parent and is `penc-me`'s. **THIS EDIT MAKES "
        "KNIGHTMON A FOUR-EDGE PERFECT** — Duftmon (spirit), Duftmon X (vitality), Craniummon "
        "(strength) and LordKnightmon X (stamina). Stamina."),
    "lotusmon": (
        "Lilamon is a BOLDED `Evolves From` on Wikimon (Digimon Story: Cyber Sleuth, Digimon RPG, "
        "Digimon New Century) and is `palmon`'s, the plant line the flower fairies climb, so the "
        "thousand-armed lotus lands on an existing line for nothing. Its other bolded parent Floramon "
        "is a Child `invalidStageTransition` refuses; Blossomon and Lady Devimon are Jogress parents. "
        "Strength; Lilamon spends spirit on BanchoLilimon and vitality on its Rosemon climb."),
    "lucemon_satan": (
        "Lucemon: Falldown Mode is a BOLDED `Evolves From` on Wikimon (Digimon Story: Cyber Sleuth, "
        "the Lucemon -> Falldown -> Satan ladder) and is `penc-nso`'s, so the final demon lord form "
        "lands on its own line for nothing. Its plain Lucemon parent is a Child `invalidStageTransition` "
        "refuses; the Ancient and Demon Lord names are Jogress parents. Strength; Lucemon Falldown "
        "spends stamina on Venom Vamdemon and spirit on Lucemon X in this same edit."),
    "lucemon_x": (
        "Wikimon bolds Lucemon: Falldown Mode (X-Antibody route, Digimon Chronicle X) for Lucemon "
        "(X-Antibody), so the antibody hangs where Lucemon Satan hangs — Lucemon: Falldown Mode on "
        "`penc-nso`, an antibody rising from the fallen angel. Its other citations (Barbamon, Leviamon "
        "Jogress, Lucemon: Larva) are Ultimates or off this line. Spirit."),
    "magnamon_x": (
        "**ITS BASE FORM IS IDLE-ONLY, SO A CITATION HAS TO CARRY IT** — the Dynasmon X shape. "
        "Wikimon bolds only Magnamon for Magnamon (X-Antibody), and the roster marks the plain "
        "Magnamon `dexOnly` (an Armor-Hybrid with no animated sheet), so `edgeToDexOnlyNode` refuses "
        "the base-form arrow. Aero V-dramon is a cited `Evolves From` for the base Magnamon (a Jogress) "
        "and is `penc-wg`'s, the V-mon Wind Guardians line the golden armour belongs to. Stamina."),
    "marinangemon": (
        "Whamon Perfect is a BOLDED `Evolves From` on Wikimon (a Jogress, D-Ark and Digimon World 2) "
        "and `pencds_whamon` is `penc-ds`'s, the Deep Savers line the sea angel belongs to, so the "
        "tiny holy Digimon lands on an existing line for nothing. Its bolded Child and Baby parents "
        "(Pitchmon, Shakomon) cannot be drawn at this rung; Crescemon, Holy Angemon and Digitamamon "
        "are off this line. Strength; MarinAngemon is itself a Jogress parent of Mitamamon below."),
    "mastemon": (
        "Mastemon is a Jogress result on Wikimon — Angewomon and LadyDevimon, both BOLDED, both "
        "Perfects — and the file cannot draw a two-parent Jogress. Because both parents ARE Perfects "
        "(unlike the Cernumon shape, whose parents are Ultimates), the light-and-dark androgyne hangs "
        "directly off one of them as a legal Perfect -> Ultimate edge: Angewomon on `penc-nsp`, the "
        "holy half of the fusion. `jogress.json` still reserves the recipe, exactly as it does for "
        "Cernumon, which was wired the same way in US-164. Strength."),
    "megidramon": (
        "Megalo Growmon is a BOLDED `Evolves From` on Wikimon (Digimon Story: Cyber Sleuth Hacker's "
        "Memory, Digimon ReArise, the Guilmon dark thread) and is `tamers`', so the dragon of "
        "destruction lands on the Guilmon line it belongs to. Its bolded Growmon parent is a Champion "
        "`invalidStageTransition` refuses; the rest of the long page is Jogress and off-line names. "
        "Stamina; Megalo Growmon spends strength on its Breakdramon climb."),
    "megidramon_x": (
        "SITS ON ITS BASE FORM'S OWN PERFECT, the strong variant rule. Wikimon bolds only Megidramon "
        "for Megidramon (X-Antibody), an Ultimate `invalidStageTransition` refuses, so the antibody "
        "hangs where the plain Megidramon hangs — Megalo Growmon on `tamers`. Spirit; Megalo Growmon "
        "spends strength on its climb and stamina on the plain Megidramon in this same edit."),
    "metalgarurumon_black": (
        "WereGarurumon (Black) is a BOLDED `Evolves From` on Wikimon (Digimon Story: Cyber Sleuth, "
        "Digimon New Century) and is `dmc-v2`'s, the black-wolf line, so the black metal wolf lands "
        "on its own line for nothing. Its bolded Garurumon (Black) parent is a Champion "
        "`invalidStageTransition` refuses; Vamdemon and the Mammon names are off this line. Stamina; "
        "WereGarurumon Black spends strength on its CresGarurumon climb."),
    "metalgarurumon_x": (
        "WereGarurumon (X-Antibody) is a BOLDED `Evolves From` on Wikimon (Digital Monster X) and is "
        "`penc-nso`'s, so an antibody rises from an antibody — the X wolf on the Nightmare Soldiers "
        "WereGarurumon X line. Its other bolded parent, the plain Metal Garurumon, is an Ultimate "
        "`invalidStageTransition` refuses (and lives on `dmc-v2` besides). Strength; WereGarurumon X "
        "spends stamina on its own climb."),
    "minervamon_x": (
        "**ITS BASE FORM IS IDLE-ONLY, SO A CITATION HAS TO CARRY IT** — the Dynasmon X shape. "
        "Wikimon bolds only Minervamon for Minervamon (X-Antibody), and the roster marks the plain "
        "Minervamon `dexOnly`, so `edgeToDexOnlyNode` and the Ultimate rung would refuse it twice. "
        "Digitamamon is the base Minervamon's bolded `Evolves From` (Digimon Story: Cyber Sleuth) and "
        "is `dmc-v4`'s. **THIS EDIT MAKES DIGITAMAMON A FOUR-EDGE PERFECT** — Gankoomon X (vitality), "
        "HolyDigitamamon (spirit), Gankoomon (strength) and Minervamon X (stamina). Stamina."),
    "mitamamon": (
        "**ITS `Evolves From` IS A JOGRESS OF TWO ULTIMATES**, the Cernumon shape: Wikimon draws "
        "Mitamamon from Hououmon and MarinAngemon (Pendulum COLOR 4 Wind Guardians), both Ultimates "
        "`invalidStageTransition` refuses, so the shrine guardian is drawn one rung below on the "
        "Perfect that climbs into a cited Ultimate. Garudamon climbs into Hououmon on `penc-wg`, the "
        "Wind Guardians line, so the sacred-treasure spirit lands there. Its bolded parents Tyilinmon "
        "(dexOnly) and Kudamon 2006 (a Child) cannot be drawn. `jogress.json` reserves the recipe, "
        "which is wired all the same. Strength."),
}

ELEMENTS = {
    "imperialdramon_fighter": ("light", "free"),
    "imperialdramon_fighter_black": ("dark", "virus"),
    "imperialdramon_paladin": ("light", "free"),
    "jesmon": ("light", "vaccine"),
    "jesmon_x": ("light", "vaccine"),
    "jesmon_gx": ("light", "vaccine"),
    "jougamon": ("earth", "virus"),
    "jumbogamemon": ("water", "data"),
    "justimon_x": ("electric", "vaccine"),
    "kaguyamon": ("light", "data"),
    "kuzuhamon": ("dark", "virus"),
    "leviamon_x": ("water", "virus"),
    "lilithmon": ("dark", "virus"),
    "lilithmon_x": ("dark", "virus"),
    "lordknightmon_x": ("steel", "vaccine"),
    "lotusmon": ("plant", "data"),
    "lucemon_satan": ("dark", "virus"),
    "lucemon_x": ("dark", "virus"),
    "magnamon_x": ("light", "vaccine"),
    "marinangemon": ("water", "vaccine"),
    "mastemon": ("light", "free"),
    "megidramon": ("dark", "virus"),
    "megidramon_x": ("dark", "virus"),
    "metalgarurumon_black": ("ice", "virus"),
    "metalgarurumon_x": ("ice", "vaccine"),
    "minervamon_x": ("steel", "data"),
    "mitamamon": ("light", "data"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
MOVES = {
    "imperialdramon_fighter": ("bolt.fill", "orange", "Positron Laser", "bolt.fill"),
    "imperialdramon_fighter_black": ("bolt.fill", "purple", "Black Positron Laser", "bolt.fill"),
    "imperialdramon_paladin": ("sparkles", "cyan", "Omega Blade", "sparkles"),
    "jesmon": ("shield.fill", "red", "Sanctuary Blade", "shield.fill"),
    "jesmon_x": ("shield.fill", "pink", "Judgement Testament", "shield.fill"),
    "jesmon_gx": ("shield.fill", "yellow", "Final Crest", "shield.fill"),
    "jougamon": ("flame.fill", "brown", "Rock Fist Barrage", "flame.fill"),
    "jumbogamemon": ("shield.fill", "green", "Jumbo Press", "shield.fill"),
    "justimon_x": ("bolt.fill", "gray", "Justice Kick Cross", "bolt.fill"),
    "kaguyamon": ("moon.fill", "white", "Lunar Rainbow", "moon.fill"),
    "kuzuhamon": ("flame.fill", "purple", "Fox Drop", "flame.fill"),
    "leviamon_x": ("bolt.fill", "red", "Rostrum Cross", "bolt.fill"),
    "lilithmon": ("sparkles", "purple", "Nazar Nail", "sparkles"),
    "lilithmon_x": ("sparkles", "blue", "Phantom Pain Cross", "sparkles"),
    "lordknightmon_x": ("shield.fill", "pink", "Spiral Masquerade Cross", "shield.fill"),
    "lotusmon": ("flame.fill", "green", "Thousand Arrows", "flame.fill"),
    "lucemon_satan": ("bolt.fill", "indigo", "Divine Atonement", "bolt.fill"),
    "lucemon_x": ("bolt.fill", "teal", "Dead or Alive Cross", "bolt.fill"),
    "magnamon_x": ("sparkles", "yellow", "Magna Blast Cross", "sparkles"),
    "marinangemon": ("heart.fill", "pink", "Ocean Love", "heart.fill"),
    "mastemon": ("sparkles", "white", "Dual Genesis", "sparkles"),
    "megidramon": ("drop.fill", "orange", "Megiddo Flame", "drop.fill"),
    "megidramon_x": ("drop.fill", "purple", "Hell Fire Cross", "drop.fill"),
    "metalgarurumon_black": ("bolt.fill", "white", "Cocytus Breath Black", "bolt.fill"),
    "metalgarurumon_x": ("bolt.fill", "cyan", "Metal Wolf Claw Cross", "bolt.fill"),
    "minervamon_x": ("triangle.fill", "orange", "Strike Sword Cross", "triangle.fill"),
    "mitamamon": ("sparkles", "mint", "Purifying Barrier", "sparkles"),
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

    # 2. the twenty-seven Ultimates, terminal and so with no `evolutions` key at all.
    for uid, name, sprite, line, _, _ in ULTIMATES:
        nodes.append({
            "id": uid, "displayName": name, "stage": "Ultimate-Super Ultimate", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[uid],
        })

    open(path, "w").write(json.dumps(doc, indent=2, ensure_ascii=False))

    # 3. elements.json and moves.json, one entry apiece for all twenty-seven.
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
