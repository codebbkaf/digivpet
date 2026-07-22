"""US-157 — Orphan sweep: Perfect A-C.

Authors the nineteen orphaned Perfect whose display name begins A-C, the nine Ultimates they
climb into that had no node, and the junk Perfect the `penc-sw` line needed before any of its
Champions could branch at all. Run once; it is idempotent only in the sense that it refuses to
run twice (every id it adds must be absent).

Kept in `scripts/` rather than thrown away because the JSON round-trips byte-exactly through
`json.dumps(indent=2)`, which is what makes scripted authoring of 29 nodes safe at all.
"""
import json
import sys

ROOT = "/Users/red/Documents/SourceCode/ios_project/digi/"

# (id, displayName, spriteFile, line, parent, parentEnergy, ultimate, climbEnergy)
PERFECTS = [
    ("andiramon_data", "Andiramon Data", "Andiramon_Data", "penc-vb",
     "turuiemon", "vitality", "cherubimon_vice", "vitality"),
    ("angewomon_x", "Angewomon X", "Angewomon_X", "penc-vb",
     "tailmon_x", "spirit", "ophanimon_x", "spirit"),
    ("anomalocarimon_x", "Anomalocarimon X", "Anomalocarimon_X", "penc-ds",
     "ebidramon", "stamina", "aegisdramon", "stamina"),
    ("archnemon", "Archnemon", "Archnemon", "penc-nso",
     "dokugumon", "spirit", "piemon", "spirit"),
    ("astamon", "Astamon", "Astamon", "penc-me",
     "porcupamon", "strength", "pencme_venomvamdemon", "strength"),
    ("atlurkabuterimon_red", "AtlurKabuterimon Red", "AtlurKabuterimon_Red", "penc-nsp",
     "pencnsp_kabuterimon", "strength", "heraklekabuterimon", "strength"),
    ("baalmon", "Baalmon", "Baalmon", "tamers",
     "icedevimon", "spirit", "beelzebumon", "spirit"),
    ("blackmegalogrowmon", "BlackMegaloGrowmon", "BlackMegaloGrowmon", "tamers",
     "blackgrowmon", "strength", "chaosdukemon", "strength"),
    ("bluemeramon", "BlueMeramon", "BlueMeramon", "penc-nso",
     "pencnso_meramon", "vitality", "pencnso_boltmon", "vitality"),
    ("boutmon", "Boutmon", "Boutmon", "penc-me",
     "thunderballmon", "strength", "kazuchimon", "strength"),
    ("cannonbeemon", "Cannonbeemon", "Cannonbeemon", "palmon",
     "waspmon", "strength", "tigervespamon", "stamina"),
    ("cargodramon", "Cargodramon", "Cargodramon", "penc-me",
     "tankmon", "stamina", "pencme_mugendramon", "stamina"),
    ("caturamon", "Caturamon", "Caturamon", "penc-vb",
     "pencvb_leomon", "vitality", "pencvb_saberleomon", "vitality"),
    ("cerberumon_x", "Cerberumon X", "Cerberumon_X", "penc-me",
     "raptordramon", "strength", "pencme_wargreymon", "strength"),
    ("chimairamon", "Chimairamon", "Chimairamon", "dmc-v1",
     "airdramon", "strength", "millenniumon", "strength"),
    ("chohakkaimon", "ChoHakkaimon", "ChoHakkaimon", "penc-sw",
     "hakubamon", "stamina", "shakamon", "stamina"),
    ("crescemon", "Crescemon", "Crescemon", "tamers",
     "lekismon", "spirit", "dianamon", "spirit"),
    ("cryspaledramon", "CrysPaledramon", "CrysPaledramon", "tamers",
     "paledramon", "vitality", "hexeblaumon", "vitality"),
    ("cyberdramon_x", "Cyberdramon X", "Cyberdramon_X", "penc-me",
     "revolmon", "stamina", "pencme_mugendramon", "stamina"),
]

# The Ultimates this story had to open, in the order they are appended.
ULTIMATES = [
    ("ophanimon_x", "Ophanimon X", "Ophanimon_X", "penc-vb"),
    ("beelzebumon", "Beelzebumon", "Beelzebumon", "tamers"),
    ("chaosdukemon", "ChaosDukemon", "ChaosDukemon", "tamers"),
    ("kazuchimon", "Kazuchimon", "Kazuchimon", "penc-me"),
    ("tigervespamon", "TigerVespamon", "TigerVespamon", "palmon"),
    ("millenniumon", "Millenniumon", "Millenniumon", "dmc-v1"),
    ("shakamon", "Shakamon", "Shakamon", "penc-sw"),
    ("dianamon", "Dianamon", "Dianamon", "tamers"),
    ("hexeblaumon", "Hexeblaumon", "Hexeblaumon", "tamers"),
]

# The Champions that were LEAVES before this story: giving one an out-edge means giving it its
# line's junk floor too, or `EvolutionCriteriaTests` fails. Every floor here already existed
# except Pandamon, which this story authors for `penc-sw`.
JUNK_FLOORS = {
    "tailmon_x": ("andiramon_virus", "strength"),
    "porcupamon": ("locomon", "strength"),
    "icedevimon": ("catchmamemon", "strength"),
    "blackgrowmon": ("catchmamemon", "strength"),
    "waspmon": ("jyagamon", "spirit"),
    "raptordramon": ("locomon", "strength"),
    "hakubamon": ("pandamon", "stamina"),
    "lekismon": ("catchmamemon", "strength"),
    "paledramon": ("catchmamemon", "strength"),
}

# The criteria on each new in-edge. Two apiece: one HealthKit, one care counter, so no edge is
# earned by walking alone and none by playing alone.
CONDITIONS = {
    "andiramon_data": [
        ("health.exerciseMinutes", "stage", "atLeast", 900,
         "Work the rabbit's arms until they cut"),
        ("care.trainingSessions", "stage", "atLeast", 18,
         "And drill the forms over and over"),
    ],
    "angewomon_x": [
        ("health.sleep", "stage", "atLeast", 9000, "Let it rest in a long clean light"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And never wake it in the dark"),
    ],
    "anomalocarimon_x": [
        ("health.steps", "stage", "atLeast", 42000, "Walk it along the deep shelf"),
        ("care.battleCount", "lifetime", "atLeast", 20, "And let the old shell learn to fight"),
    ],
    "archnemon": [
        ("health.steps", "stage", "atLeast", 38000, "Let it spin thread across a long walk"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.7, "And win far more often than not"),
    ],
    "astamon": [
        ("health.activeEnergy", "stage", "atLeast", 8000, "Burn hard enough to earn the coat"),
        ("care.battleCount", "lifetime", "atLeast", 26, "And carry the gun into fight after fight"),
    ],
    "atlurkabuterimon_red": [
        ("health.flightsClimbed", "stage", "atLeast", 220, "Climb until the red horn is level"),
        ("care.trainingSessions", "stage", "atLeast", 22, "And build the shoulders to swing it"),
    ],
    "baalmon": [
        ("health.sleep", "stage", "atMost", 5400, "Keep the long vigil, and do not sleep it off"),
        ("care.battleCount", "lifetime", "atLeast", 24, "And hunt through fight after fight"),
    ],
    "blackmegalogrowmon": [
        ("health.activeEnergy", "stage", "atLeast", 9000, "Let the black engine run hot"),
        ("care.overfeeds", "stage", "atMost", 1, "And keep it lean while it does"),
    ],
    "bluemeramon": [
        ("health.exerciseMinutes", "stage", "atLeast", 800, "Push the flame past red into blue"),
        ("care.trainingSessions", "stage", "atLeast", 20, "And hold it there, session after session"),
    ],
    "boutmon": [
        ("health.exerciseMinutes", "stage", "atLeast", 1000, "Put the rounds in"),
        ("care.trainingSessions", "stage", "atLeast", 26, "And spar until the guard never drops"),
    ],
    "cannonbeemon": [
        ("health.flightsClimbed", "stage", "atLeast", 260, "Take the hive up, floor after floor"),
        ("care.trainingSessions", "stage", "atLeast", 20, "And drill the swarm into one gun"),
    ],
    "cargodramon": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 30000,
         "Fly the freight the whole long haul"),
        ("care.overfeeds", "stage", "atMost", 2, "And keep the hold under its weight limit"),
    ],
    "caturamon": [
        ("health.standHours", "stage", "atLeast", 160, "Stand the watch a Deva stands"),
        ("care.battleCount", "lifetime", "atLeast", 22, "And answer for it in the ring"),
    ],
    "cerberumon_x": [
        ("health.steps", "stage", "atLeast", 46000, "Run the gate's boundary until it knows it"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.75, "And lose almost nothing that comes"),
    ],
    "chimairamon": [
        ("health.activeEnergy", "stage", "atLeast", 8500, "Feed every borrowed part at once"),
        ("care.battleCount", "lifetime", "atLeast", 28, "And bolt them together in battle"),
    ],
    "chohakkaimon": [
        ("health.steps", "stage", "atLeast", 44000, "Walk the pilgrim road west"),
        ("care.overfeeds", "stage", "atMost", 1, "And do not let the appetite win"),
    ],
    "crescemon": [
        ("health.sleep", "stage", "atLeast", 10000, "Give it the whole of the night"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And leave the moon undisturbed"),
    ],
    "cryspaledramon": [
        ("health.flightsClimbed", "stage", "atLeast", 240, "Take it up where the air freezes"),
        ("care.trainingSessions", "stage", "atLeast", 24, "And temper the armour there"),
    ],
    "cyberdramon_x": [
        ("health.exerciseMinutes", "stage", "atLeast", 950, "Run the hunter until it cannot stop"),
        ("care.battleCount", "lifetime", "atLeast", 30, "And give it something to hunt"),
    ],
}

COMMENTS = {
    "andiramon_data": (
        "Wikimon draws Andiramon out of Turuiemon - bolded, and cited both with and without a Virus "
        "Adult from the Vital Bracelet Digital Monster - and into Cherubimon (Vice), also bolded. "
        "BOTH ENDS WERE ALREADY ON `penc-vb`: Turuiemon has been this line's junk Champion since "
        "US-143 and Cherubimon (Vice) the Ultimate over Andiramon (Virus), so US-152's rule of "
        "intersecting `Evolves From` against `Evolves To` closes with no new node at all. Wendimon "
        "is the page's other bolded parent and has no sheet in this pack, which is why the arrow "
        "rests on Turuiemon. The Data and Virus Andiramon are now siblings on one line, the earned "
        "one and the junk one, which is exactly the shape their attributes describe. Vitality is "
        "the energy Turuiemon had free after Asuramon took strength."),
    "angewomon_x": (
        "Wikimon's bolded `Evolves From` for Angewomon (X-Antibody) is Tailmon (X-Antibody), and "
        "Tailmon X has sat on `penc-vb` as a LEAF since US-150 - so this arrow costs nothing below "
        "and clears a dead end at the same time. The climb is Ofanimon (X-Antibody), also on the "
        "page, which had no node: the X counterpart of the Ophanimon this line already puts over "
        "the plain Angewomon, so the pair reads as one family rather than two. Jazardmon and "
        "Pegasmon X are the page's other parents; both are `tamers`, which has no Angel rung, and "
        "the criteria's own rule puts a variant on its BASE FORM's line in any case. Spirit is what "
        "a holy cat earns and Tailmon X had every energy free."),
    "anomalocarimon_x": (
        "NO CITATION FOR EITHER ARROW, AND THIS SAYS SO RATHER THAN DRESSING A LINE ARGUMENT AS "
        "ONE. Wikimon gives Anomalocarimon (X-Antibody) exactly one `Evolves From` - Anomalocarimon "
        "itself, with the X-Antibody - which is a Perfect and cannot be an in-edge here, and one "
        "`Evolves To`, Cherubimon (Virtue) (X-Antibody) [Digital Monster X Ver.3], which has no "
        "sheet in this pack. Both ends are therefore LINE arguments off the base form: Ebidramon is "
        "one of the three Champions that already reach the plain Anomalocarimon on `penc-ds`, and "
        "Aegisdramon is the Ultimate that Anomalocarimon already climbs into. The day a Cherubimon "
        "(Virtue) X sheet appears, the out-edge is the first thing to revisit. Stamina is the "
        "energy Ebidramon had free after vitality went to the base form."),
    "archnemon": (
        "Both arrows are Wikimon's and both land on `penc-nso`, which is what chose the line: "
        "Dokugumon is Archnemon's most heavily cited parent by a distance (Digimon Story, Sunburst "
        "& Moonlight, RPG, Masters, Lost Evolution and more) and has been this line's spider "
        "Champion since US-140, and Piemon - cited as 'Piemon (with Infermon or Fantomon)' - is "
        "already the Ultimate over Phantomon here. Parasimon is the arrow the page leads with and "
        "has no sheet in this pack, so it could not be drawn; Gokimon, this line's own junk "
        "Champion, is a cited parent too, which is a second reason the placement is `penc-nso` "
        "rather than convenience. Spirit is the energy Dokugumon had free after Phantomon took "
        "stamina."),
    "astamon": (
        "Wikimon bolds Porcupamon in Astamon's `Evolves From` [Bo-1145, Da-275, Da-399, Digimon "
        "Crusader, Digimon Pendulum Ver.20th, Digimon New Century], and Porcupamon has been a LEAF "
        "on `penc-me` since US-150 - so the in-edge costs nothing and clears a dead end. The climb "
        "is Venom Vamdemon, which the same `Evolves To` names and which this line already carries "
        "over WaruMonzaemon. Belphemon: Rage Mode and Quartzmon are the page's bolded Ultimates and "
        "NEITHER has a sheet in this pack, which is the only reason the bolded arrow is not the one "
        "drawn - said out loud so a later story with a Belphemon sheet knows what to replace. "
        "Psychemon, the other bolded parent, is a Child rather than a Champion."),
    "atlurkabuterimon_red": (
        "The cheapest placement in the story and both halves are bolded on Wikimon: Kabuterimon is "
        "AtlurKabuterimon (Red)'s bolded `Evolves From` and Herakle Kabuterimon its bolded "
        "`Evolves To`, and `penc-nsp` already holds both - Kabuterimon as a Champion since US-138 "
        "and Herakle Kabuterimon as the Ultimate over the BLUE AtlurKabuterimon. So the two "
        "AtlurKabuterimon now hang off one Kabuterimon and climb into one Herakle Kabuterimon, "
        "which is the criteria's variant rule drawn exactly. Gran Kuwagamon, the page's other "
        "bolded climb, has a sheet but no node and would have cost one; it is left to the Ultimate "
        "sweeps. Strength is the energy Kabuterimon had free after the Blue took stamina."),
    "baalmon": (
        "Wikimon draws Baalmon out of Ice Devimon and into Beelzebumon (2010 Anime Version), and "
        "`tamers` is where both belong: Ice Devimon has been a LEAF on it since US-149, and "
        "Beelzebumon is Impmon's Ultimate - Impmon and Impmon X are both Children of this line - so "
        "the new Ultimate lands on a line with a claim on it far beyond the single arrow. THIS "
        "OPENS THE `tamers` ULTIMATE RUNG, which has been empty since the line was created: three "
        "more of this story's Perfects climb into it. Devimon, Mad Leomon, Porcupamon and Wizarmon "
        "are the page's other parents and each is on a line whose Ultimates the page does not name. "
        "Spirit is a devil's energy and Ice Devimon had every one free."),
    "blackmegalogrowmon": (
        "One line, two bolded arrows, and both cite a card: Wikimon gives BlackMegaloGrowmon "
        "Black Growmon as its bolded `Evolves From` [St-731] and Chaos Dukemon as its bolded "
        "`Evolves To` [Bo-550]. Black Growmon has been a LEAF on `tamers` since the Champion "
        "sweeps, and Chaos Dukemon is the black counterpart of the Dukemon this line's Guilmon "
        "thread points at, so the Ultimate belongs here as squarely as the Champion does. It cost "
        "one node rather than two because US-151 put CatchMamemon under this line as its junk "
        "floor. Strength is what a black Growmon has and nothing else."),
    "bluemeramon": (
        "The one placement in this story where both cited ends were on the SAME line already, with "
        "no argument needed at all: Wikimon draws BlueMeramon out of Meramon [St-96, Digimon World "
        "Re:Digitize, Digimon World 2, Digimon Championship, Digimon Crusader, Cyber Sleuth, "
        "-next 0rder-, Survive, Super Rumble, Time Stranger] and into Boltmon [Digimon World 2, "
        "Re:Digitize Decode, Cyber Sleuth, -next 0rder-], and `penc-nso` carries Meramon as a "
        "Champion and Boltmon as the Ultimate over DeathMeramon. Zero new nodes. Vitality is the "
        "energy Meramon had free after DeathMeramon took strength, and a flame that burns cold "
        "rather than hot earns the quiet one."),
    "boutmon": (
        "Wikimon's bolded `Evolves From` for Boutmon are Bulkmon, which is idle-only in this pack "
        "and cannot take an edge, and Pulsemon, which is a CHILD and would be a two-rung jump the "
        "validator forbids. Thunderballmon [Vital Bracelet BE] is the cited parent that is a "
        "Champion with a node, and it is on `penc-me`; the bolded climb, Kazuchimon [Vital Bracelet "
        "Digital Monster, Digimon Card Game], had no node and is opened here. The `vital` line is "
        "where the theme points - Boutmon is a Vital Bracelet Digimon and Pulsemon is on it - and "
        "it lost on cost exactly as US-153's Kinkakumon did: `vital` has NO Perfect rung, so that "
        "reading is this Perfect plus a junk floor plus the Ultimate, and Pulsemon could not have "
        "carried the in-edge in any case. Strength is what a boxer earns."),
    "cannonbeemon": (
        "Wikimon bolds Waspmon in Cannonbeemon's `Evolves From` and Tiger Vespamon in its "
        "`Evolves To`, each with a dozen citations [Sx-97, Bx-114, Digimon Pendulum X Ver.3, "
        "Digimon Next, Cyber Sleuth, Super Rumble, Vital Bracelet BE, Time Stranger and more], and "
        "Waspmon has been a LEAF on `palmon` since the Champion sweeps - so the in-edge clears a "
        "dead end and the whole hive thread now sits on one line. Tiger Vespamon is opened here "
        "because `palmon` had only Rosemon and ShinMonzaemon above it and neither is anything a bee "
        "climbs into. Strength for the in-edge, stamina for the climb: the Champion is a gunner "
        "and the Ultimate is a swarm that does not stop."),
    "cargodramon": (
        "US-152's rule paid twice here: Wikimon gives Cargodramon Tankmon as an `Evolves From` and "
        "Mugendramon as an `Evolves To`, and `penc-me` - the Metal Empire line - already carries "
        "both, so a Virus Machine troop transport lands on the machine line for nothing. THE "
        "REJECTED READING IS THE BETTER THEME AND IS WRITTEN DOWN ON PURPOSE, as US-153's "
        "Kinkakumon and US-156's Xiquemon were: Cargodramon is D-Brigade, its profile carries five "
        "Commandramon and one Hi-Commandramon, and BOTH of those are cited parents on the "
        "`commandramon` line. It lost on cost - that line has no Perfect rung and no Ultimate rung, "
        "so the reading is this Perfect plus a junk floor plus Brigadramon and a new "
        "`EvolutionCriteriaTests.junkIds` entry, against nothing here. Sealsdramon, the third "
        "D-Brigade parent, is idle-only. When a later story opens `commandramon`'s Perfect rung, "
        "Cargodramon is the first rehome candidate on it. Stamina is the energy Tankmon had free "
        "after Knightmon took strength."),
    "caturamon": (
        "Wikimon cites Leomon in Caturamon's `Evolves From` [9] and Saber Leomon - 'with Vajramon' - "
        "in its `Evolves To` [26], and `penc-vb` holds both: Leomon as a Champion since US-143 and "
        "Saber Leomon as the Ultimate over Asuramon. Vajramon is idle-only so the partner half of "
        "that citation cannot be drawn, but the arrow itself is the source's. The line is also "
        "where the Devas are: Turuiemon is this line's junk Champion, Andiramon (Virus) its junk "
        "Perfect and Andiramon Data joins them in this same story, so the dog Deva stands beside "
        "the rabbit ones. Baihumon, the page's SOLE bolded climb, has no sheet in this pack and "
        "could not be drawn - the reason a cited-but-unbolded arrow is the one taken. Vitality is "
        "the energy Leomon had free after Asuramon took stamina."),
    "cerberumon_x": (
        "Wikimon draws Cerberumon (X-Antibody) out of Raptordramon [2] and into 'War Greymon (with "
        "Cyberdramon)' [13], and `penc-me` is the one line that holds all THREE names: Raptordramon "
        "has been a LEAF on it since US-150, War Greymon is the Ultimate over this line's Metal "
        "Greymon, and Cyberdramon - the partner the citation names - is a Perfect on it too. The "
        "plain Cerberumon has no sheet in this pack at all, so the base-form rule could not be "
        "applied and the cited Champion chose the line instead, which is US-155's Tyranomon X "
        "reading again. Anubimon is the page's leading climb and would have cost a node; Platinum "
        "Numemon, the other drawable one, is dmc-v1's junk Ultimate and no fit for a guardian of "
        "the gate. Strength for a three-headed hound, and Raptordramon had every energy free."),
    "chimairamon": (
        "Wikimon bolds Airdramon in Chimairamon's `Evolves From` and Millenniumon in its "
        "`Evolves To`, and both belong on `dmc-v1`: the Digimon is stitched together out of "
        "Version 1's own cast - Airdramon's wings, Greymon's head, Kabuterimon's shell, Devimon's "
        "arms - and every one of those is a Champion on this line. Millenniumon is opened here "
        "because Mugendramon, the page's other bolded climb, sits on `dmc-v5` and `penc-me` and "
        "NEITHER has a cited parent for this Digimon, so taking it would have moved the Champion "
        "onto a line with no claim on it. The other bolded parents - Garurumon, Kabuterimon, "
        "Kuwagamon, Monochromon, Skull Greymon - are spread across four lines, none of which "
        "carries a cited climb. Strength is the energy Airdramon had free after Metal Greymon "
        "(Virus) took vitality."),
    "chohakkaimon": (
        "THIS OPENS `penc-sw`'s PERFECT RUNG, which US-153 and US-156 both deferred and US-156 "
        "handed to the Perfect sweeps by name. Wikimon cites 'Hakubamon (with any Virus Adult "
        "Digimon from Digimon Pendulum COLOR)' in Cho-Hakkaimon's `Evolves From`, and Hakubamon is "
        "the white horse of Journey to the West sitting on the Saiyu Warriors line since US-150; "
        "Shakamon is the page's SOLE bolded `Evolves To` and is opened above it. Opossummon, the "
        "bolded parent, has no sheet in this pack. The bill is three nodes - this Perfect, Shakamon "
        "and the junk floor Pandamon that every branching Champion of the line now needs - which is "
        "exactly the price US-156 quoted, and it is paid here rather than deferred again because "
        "Sagomon, Sanzomon, Gokuwmon and Shawujinmon are all orphaned Perfects waiting on this rung "
        "and Xiquemon is waiting to be rehomed onto it. The whole line remains STRANDED - `penc-sw` "
        "has no Digitama and cannot be reached from the top of the ladder down - which US-148 "
        "recorded and no story at this rung can fix. Stamina for a pilgrim's long road."),
    "crescemon": (
        "Wikimon bolds Lekismon in Crescemon's `Evolves From` and Dianamon in its `Evolves To`, and "
        "Lekismon has been a LEAF on `tamers` since US-149 - so the in-edge clears a dead end and "
        "the moon-rabbit thread runs Lunamon to Lekismon to Crescemon to Dianamon on one line, "
        "unbroken, which is the tidiest thread this sweep drew. Dianamon is opened here because "
        "nothing above `tamers` existed when this story started; Beelzebumon, authored in this same "
        "story, is its neighbour. It cost one node rather than two because US-151 put CatchMamemon "
        "under this line as its junk floor. Spirit is a moon's energy and Lekismon had every one "
        "free."),
    "cryspaledramon": (
        "Wikimon bolds Paledramon in Crys Paledramon's `Evolves From` and Hexeblaumon in its "
        "`Evolves To` - the Freezing Knight's own thread, Paledramon to Crys Paledramon to "
        "Hexeblaumon, drawn in one story - and Paledramon has been a LEAF on `tamers` since the "
        "Champion sweeps. Hyougamon (`penc-nsp`) and Omekamon (`penc-me`) are the page's other "
        "drawable parents and neither line carries a cited climb, so the intersection picked "
        "`tamers` on its own. It cost one node rather than two because US-151 put CatchMamemon "
        "under this line as its junk floor. Vitality is the energy that keeps something alive "
        "inside ice."),
    "cyberdramon_x": (
        "NO CITATION FOR EITHER ARROW, AND THIS SAYS SO. Wikimon gives Cyberdramon (X-Antibody) "
        "exactly one `Evolves From` - Cyberdramon itself, with or without the X-Antibody, a Perfect "
        "that cannot be an in-edge - and no bolded `Evolves To` at all, only Digimon Card Game "
        "colour categories. Both ends are therefore LINE arguments off the base form, the shape "
        "US-156's V-dramon Black established: Revolmon is the Champion that already reaches the "
        "plain Cyberdramon on `penc-me`, and Mugendramon is the Ultimate the plain Cyberdramon "
        "already climbs into. Monodramon, Cyberdramon's Tamers-canon parent, is a Child and could "
        "not have carried the edge. Stamina is the last energy Revolmon had, after Andromon took "
        "vitality and the plain Cyberdramon strength - and this fills the node."),
    # The junk floor and the nine Ultimates.
    "pandamon": (
        "FLAVOUR. The Saiyu Warriors line had no junk PERFECT and every branching Champion needs "
        "one (`EvolutionCriteriaTests`), so opening this line's Perfect rung for Cho-Hakkaimon "
        "meant authoring a floor under it in the same story - the same bill US-151 paid when it "
        "gave `wanyamon` Karakurumon and `tamers` CatchMamemon. Pandamon is a stuffed-panda puppet "
        "off an unused sheet: a Chinese toy beside a Journey to the West line, following "
        "Tsuchidarumon the mud daruma, which US-148 chose as this line's junk CHAMPION for the same "
        "reason. `grep -rn Pandamon` finds it in no tree markdown - the check US-140 insists on. A "
        "leaf until the Ultimate sweeps, and stranded with the rest of `penc-sw`."),
    "ophanimon_x": (
        "Cited in Angewomon (X-Antibody)'s `Evolves To` on Wikimon as Ofanimon (X-Antibody), and "
        "opened for exactly one Perfect. It is the X counterpart of the Ophanimon this line already "
        "puts over the plain Angewomon, so `penc-vb` carries the pair the way it carries the two "
        "Angewomon and the two Tailmon. A leaf, as every Ultimate in this file is."),
    "beelzebumon": (
        "THE FIRST ULTIMATE `tamers` HAS EVER HAD. Cited in Baalmon's `Evolves To` on Wikimon as "
        "Beelzebumon (2010 Anime Version) and opened for exactly one Perfect - but the line has a "
        "claim on it well beyond that arrow, because Beelzebumon is Impmon's Ultimate and both "
        "Impmon and Impmon X are Children here. Three more of US-157's Perfects climb into this "
        "rung beside it. A leaf, as every Ultimate in this file is."),
    "chaosdukemon": (
        "BlackMegaloGrowmon's bolded `Evolves To` on Wikimon [Bo-550], opened for exactly one "
        "Perfect. The black counterpart of the Dukemon that the Guilmon thread of `tamers` points "
        "at, which is a second reason it belongs on this line rather than only the arrow. A leaf, "
        "as every Ultimate in this file is."),
    "kazuchimon": (
        "Boutmon's bolded `Evolves To` on Wikimon [Vital Bracelet Digital Monster, Digimon Card "
        "Game, Digimon Seekers, BT17-040, BT20-035], opened for exactly one Perfect. It sits on "
        "`penc-me` because its only parent here does - Thunderballmon is the cited Champion - and "
        "not because a thunder god belongs to the Metal Empire; the `vital` reading is argued in "
        "full on the Boutmon node. A leaf, as every Ultimate in this file is."),
    "tigervespamon": (
        "Cannonbeemon's bolded `Evolves To` on Wikimon [Digimon Pendulum X Ver.3, Da-109, Digimon "
        "World Digital Card Arena, Cyber Sleuth, Digital Monster X Ver.3, Vital Bracelet BE and "
        "more], opened for exactly one Perfect. It is only the THIRD Ultimate `palmon` has - the "
        "line had Rosemon and ShinMonzaemon and nothing a hive could climb into. A leaf, as every "
        "Ultimate in this file is."),
    "millenniumon": (
        "Chimairamon's bolded `Evolves To` on Wikimon, drawn with or without Mugendramon, and "
        "opened for exactly one Perfect. Mugendramon was the alternative and is why this node "
        "exists: it has nodes on `dmc-v5` and `penc-me` and neither line holds a cited parent for "
        "Chimairamon, so taking it would have moved the Perfect off the line its own parts come "
        "from. A leaf, as every Ultimate in this file is."),
    "shakamon": (
        "THE FIRST ULTIMATE `penc-sw` HAS EVER HAD, and the second of the three nodes that opening "
        "the Saiyu Warriors Perfect rung cost. Cho-Hakkaimon's SOLE bolded `Evolves To` on Wikimon, "
        "drawn with or without Gokuwmon, Sanzomon and Shawujinmon - all three of which have sheets "
        "in this pack and no node, and are the obvious company for it once a later sweep reaches "
        "them. Opened for exactly one Perfect. Stranded with the rest of the line, which has no "
        "Digitama. A leaf, as every Ultimate in this file is."),
    "dianamon": (
        "Crescemon's bolded `Evolves To` on Wikimon, opened for exactly one Perfect, and the top of "
        "the tidiest thread this sweep drew: Lunamon, Lekismon, Crescemon, Dianamon, every rung on "
        "`tamers` and every arrow bolded. A leaf, as every Ultimate in this file is."),
    "hexeblaumon": (
        "Crys Paledramon's bolded `Evolves To` on Wikimon - the Freezing Knight evolved its "
        "Paledramon this far in 'Out of Control' - opened for exactly one Perfect. A leaf, as every "
        "Ultimate in this file is."),
}

ELEMENTS = {
    "andiramon_data": ("plant", "data"),
    "angewomon_x": ("light", "vaccine"),
    "anomalocarimon_x": ("water", "virus"),
    "archnemon": ("dark", "virus"),
    "astamon": ("dark", "virus"),
    "atlurkabuterimon_red": ("electric", "free"),
    "baalmon": ("dark", "virus"),
    "blackmegalogrowmon": ("machine", "virus"),
    "bluemeramon": ("ice", "virus"),
    "boutmon": ("earth", "vaccine"),
    "cannonbeemon": ("machine", "data"),
    "cargodramon": ("machine", "virus"),
    "caturamon": ("earth", "data"),
    "cerberumon_x": ("dark", "virus"),
    "chimairamon": ("dark", "virus"),
    "chohakkaimon": ("earth", "data"),
    "crescemon": ("ice", "data"),
    "cryspaledramon": ("ice", "vaccine"),
    "cyberdramon_x": ("machine", "virus"),
    "pandamon": ("machine", "virus"),
    "ophanimon_x": ("light", "vaccine"),
    "beelzebumon": ("dark", "virus"),
    "chaosdukemon": ("dark", "virus"),
    "kazuchimon": ("electric", "vaccine"),
    "tigervespamon": ("steel", "data"),
    "millenniumon": ("dark", "virus"),
    "shakamon": ("light", "vaccine"),
    "dianamon": ("ice", "data"),
    "hexeblaumon": ("ice", "vaccine"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
MOVES = {
    "andiramon_data": ("leaf.fill", "green", "Arm Bomber", "scissors"),
    "angewomon_x": ("sparkles", "mint", "Holy Arrow Cross", "sparkles"),
    "anomalocarimon_x": ("scissors", "gray", "Cutter Shrimp", "scissors"),
    "archnemon": ("circle.fill", "green", "Spider Thread", "circle.fill"),
    "astamon": ("bolt.fill", "purple", "Hellfire Volley", "bolt.fill"),
    "atlurkabuterimon_red": ("bolt.fill", "red", "Crimson Mega Blaster", "bolt.fill"),
    "baalmon": ("moon.fill", "orange", "Death Slinger", "moon.fill"),
    "blackmegalogrowmon": ("gearshape.fill", "purple", "Double Edge Cannon", "flame.fill"),
    "bluemeramon": ("flame.fill", "cyan", "Cold Flame", "snowflake"),
    "boutmon": ("hand.raised.fill", "yellow", "Blazing Knuckle", "hand.raised.fill"),
    "cannonbeemon": ("bolt.fill", "yellow", "Nitrogen Bomb", "bolt.fill"),
    "cargodramon": ("gearshape.fill", "green", "Suppression Strike", "gearshape.fill"),
    "caturamon": ("hammer.fill", "brown", "Thunder Drum", "hammer.fill"),
    "cerberumon_x": ("flame.fill", "green", "Portals of Hell", "flame.fill"),
    "chimairamon": ("wind", "purple", "Heat Viper", "wind"),
    "chohakkaimon": ("hammer.fill", "pink", "Nine-Tooth Rake", "hammer.fill"),
    "crescemon": ("moon.fill", "mint", "Lunatic Dance", "moon.fill"),
    "cryspaledramon": ("snowflake", "blue", "Glacier Lance", "snowflake"),
    "cyberdramon_x": ("scissors", "purple", "Erase Claw", "scissors"),
    "pandamon": ("circle.fill", "white", "Bamboo Bomber", "circle.fill"),
    "ophanimon_x": ("star.fill", "mint", "Sefirot Crystal", "star.fill"),
    "beelzebumon": ("bolt.fill", "yellow", "Double Impact", "bolt.fill"),
    "chaosdukemon": ("shield.fill", "purple", "Demon's Disaster", "shield.fill"),
    "kazuchimon": ("bolt.fill", "pink", "Thunder Cleave", "bolt.fill"),
    "tigervespamon": ("bolt.fill", "orange", "Mach Stinger", "bolt.fill"),
    "millenniumon": ("eye.fill", "red", "Dimension Destroyer", "eye.fill"),
    "shakamon": ("sparkles", "yellow", "Lotus Repose", "sparkles"),
    "dianamon": ("snowflake", "indigo", "Crescent Harken", "snowflake"),
    "hexeblaumon": ("shield.fill", "blue", "Blaue Sturm", "shield.fill"),
}


def condition(metric, window, comparison, value, hint):
    return {"metric": metric, "window": window, "comparison": comparison,
            "value": value, "hint": hint}


def main():
    path = ROOT + "Resources/evolutions.json"
    doc = json.loads(open(path).read())
    nodes = doc["nodes"]
    by_id = {n["id"]: n for n in nodes}

    new_ids = [p[0] for p in PERFECTS] + ["pandamon"] + [u[0] for u in ULTIMATES]
    for i in new_ids:
        if i in by_id:
            sys.exit("already authored: " + i)

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

    # 2. the nineteen Perfects, each a single isDefault climb, the shape every Perfect in the
    #    file has carried since US-134.
    for pid, name, sprite, line, _, _, ultimate, climb in PERFECTS:
        nodes.append({
            "id": pid, "displayName": name, "stage": "Perfect", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[pid],
            "evolutions": [{"to": ultimate, "requiredEnergy": climb, "minEnergy": 150,
                            "maxCareMistakes": 2, "isDefault": True}],
        })

    # 3. `penc-sw`'s junk floor, a leaf.
    nodes.append({
        "id": "pandamon", "displayName": "Pandamon", "stage": "Perfect", "line": "penc-sw",
        "spriteFile": "Pandamon", "comment": COMMENTS["pandamon"], "evolutions": [],
    })

    # 4. the nine Ultimates, terminal and so with no `evolutions` key at all.
    for uid, name, sprite, line in ULTIMATES:
        nodes.append({
            "id": uid, "displayName": name, "stage": "Ultimate-Super Ultimate", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[uid],
        })

    open(path, "w").write(json.dumps(doc, indent=2, ensure_ascii=False))

    # 5. elements.json and moves.json, one entry apiece for all twenty-nine.
    epath = ROOT + "Resources/elements.json"
    edoc = json.loads(open(epath).read())
    for i in new_ids:
        element, attribute = ELEMENTS[i]
        edoc["types"][i] = {"element": element, "attribute": attribute}
    open(epath, "w").write(json.dumps(edoc, indent=2, ensure_ascii=False))

    mpath = ROOT + "Resources/moves.json"
    mdoc = json.loads(open(mpath).read())
    for i in new_ids:
        symbol, tint, signature, sig_symbol = MOVES[i]
        mdoc["moves"][i] = {"projectileSymbol": symbol, "tint": tint,
                            "signatureName": signature, "signatureSymbol": sig_symbol}
    open(mpath, "w").write(json.dumps(mdoc, indent=2, ensure_ascii=False))

    print("authored", len(new_ids), "nodes; graph is now", len(nodes))


if __name__ == "__main__":
    main()
