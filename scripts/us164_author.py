"""US-164 — Orphan sweep: Ultimate-Super Ultimate C-D, the second sweep at the top rung.

Authors the twenty orphaned Ultimate whose display name begins C-D. The rung is TERMINAL, so this is
an IN-EDGE sweep and nothing else — twenty orphans, twenty nodes, no junk floor and no new line,
exactly the shape US-163 recorded.

**TWO C-D ULTIMATES ARE NOT ORPHANS AND ARE LEFT ALONE: Chaosdramon and Chaosmon.** Both are
Jogress results — the DMC Ver.5 and Ver.4 documents draw them as the Jogress Ultra row, and
`jogress.json` spends them — so they are OBTAINABLE and `DMCVersion5TreeTests`,
`DMCVersion4TreeTests` and `PendulumMetalEmpireTreeTests` each assert they are NOT evolution nodes.
Wiring them would break those tests and duplicate a route the player already has. (Cernumon is also
a Jogress result but no device tree reserves it, exactly as `aegisdramon` and `millenniumon` are
both Jogress results AND evolution nodes wired by earlier sweeps — so it is wired here.)

Two shapes of in-edge, and the parent decides which:

  * TWO leaf Perfects gain their single `isDefault` climb. Both were parked for this rung IN AS MANY
    WORDS: `metalgreymon_x` (US-160) and `huankunmon` (US-159) each end their node comment with "A
    leaf until the Ultimate sweeps", and each is a CITED parent of the Digimon it now carries. Two
    entries off the dead-end ledger in `ChildSweepAToFTests`.
  * The other eighteen hang an EARNED branch beside the climb their Perfect already has: `minEnergy`
    150, `maxCareMistakes` 2, two conditions (one HealthKit metric, one care counter) and a
    `requiredEnergy` distinct from every other edge on that node. `EvolutionEngine.qualifies` matches
    on the DOMINANT type, so a shared energy would leave one edge unreachable for good.

THIS STORY'S ONE FIRST: `holyangemon` becomes the FIRST PERFECT IN THE FILE WITH FOUR EDGES, and
Dominimon spends its last free energy. Four other Perfects go to three.

Run once; it refuses to run twice (every id it adds must be absent).

Kept in `scripts/` beside `us157_author.py` .. `us163_author.py` for the same reason: the JSON
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
    ("callismon", "Callismon", "Callismon", "penc-nso",
     "soloogarmon", "vitality"),
    ("cernumon", "Cernumon", "Cernumon", "penc-wg",
     "jyureimon", "spirit"),
    ("chaosdukemon_core", "ChaosDukemon Core", "ChaosDukemon_Core", "tamers",
     "blackmegalogrowmon", "vitality"),
    ("chaosdramon_v2", "Chaosdramon V2", "Chaosdramon_V2", "dmc-v3",
     "metalgreymon_x", "strength"),
    ("cherubimon_vice_x", "Cherubimon Vice X", "Cherubimon_Vice_X", "penc-vb",
     "andiramon_virus", "vitality"),
    ("cherubimon_virtue_x", "Cherubimon Virtue X", "Cherubimon_Virtue_X", "penc-vb",
     "entmon", "spirit"),
    ("craniummon_x", "Craniummon X", "Craniummon_X", "penc-me",
     "pencme_andromon", "stamina"),
    ("cthyllamon", "Cthyllamon", "Cthyllamon", "penc-ds",
     "dagomon", "vitality"),
    ("darknessbagramon", "DarknessBagramon", "DarknessBagramon", "penc-nsp",
     "darkknightmon", "strength"),
    ("deathmon_black", "Deathmon Black", "Deathmon_Black", "penc-nso",
     "darumamon", "vitality"),
    ("demon", "Demon", "Demon", "penc-nso",
     "deathmeramon", "spirit"),
    ("demon_x", "Demon X", "Demon_X", "penc-nso",
     "deathmeramon", "vitality"),
    ("diablomon", "Diablomon", "Diablomon", "diablomon",
     "meicrackmon", "strength"),
    ("diablomon_x", "Diablomon X", "Diablomon_X", "diablomon",
     "meicrackmon", "spirit"),
    ("dijiangmon", "Dijiangmon", "Dijiangmon", "dmc-v4",
     "huankunmon", "spirit"),
    ("dominimon", "Dominimon", "Dominimon", "penc-vb",
     "holyangemon", "stamina"),
    ("duftmon", "Duftmon", "Duftmon", "penc-me",
     "knightmon", "spirit"),
    ("duftmon_x", "Duftmon X", "Duftmon_X", "penc-me",
     "knightmon", "vitality"),
    ("dukemon_x", "Dukemon X", "Dukemon_X", "tamers",
     "megalogrowmon_orange", "spirit"),
    ("dynasmon_x", "Dynasmon X", "Dynasmon_X", "tamers",
     "doruguremon", "vitality"),
]

# The two Perfects that were LEAVES before this story. Each gains its single `isDefault` climb,
# which is also two entries off the dead-end ledger in `ChildSweepAToFTests`. Both were parked for
# this rung by the sweep that authored them, in the words "A leaf until the Ultimate sweeps".
LEAF_PARENTS = {"metalgreymon_x", "huankunmon"}

# Two criteria on every EARNED in-edge: one HealthKit metric, one care counter, so no Mega is
# earned by walking alone and none by playing alone. `care.battleCount` and `care.battleWinRatio`
# are answerable only over `lifetime` and every other `care.*` only over `stage` — US-150's rule.
CONDITIONS = {
    "callismon": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 180000, "Run the hunting ground end to end"),
        ("care.battleCount", "lifetime", "atLeast", 28, "And come back from every hunt with a fight behind you"),
    ],
    "cernumon": [
        ("health.flightsClimbed", "stage", "atLeast", 520, "Climb until the forest canopy is below you"),
        ("care.trainingSessions", "stage", "atLeast", 26, "And drill the antlers into a weapon"),
    ],
    "chaosdukemon_core": [
        ("health.activeEnergy", "stage", "atLeast", 26000, "Burn through everything it has, because a core is what is left"),
        ("care.battleWinRatio", "lifetime", "atMost", 0.4, "And let the knight lose itself"),
    ],
    "cherubimon_vice_x": [
        ("health.sleep", "stage", "atMost", 5400, "Keep the beast up through the vigil the antibody wants"),
        ("care.overfeeds", "stage", "atLeast", 6, "And feed the rabbit far past full, until its temper turns"),
    ],
    "cherubimon_virtue_x": [
        ("health.mindfulMinutes", "stage", "atLeast", 900, "Sit still with it until the light answers"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And never break its rest"),
    ],
    "craniummon_x": [
        ("health.flightsClimbed", "stage", "atLeast", 640, "Carry the shield up every stair you find"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.85, "And let almost nothing through it"),
    ],
    "cthyllamon": [
        ("health.distanceSwimming", "stage", "atLeast", 42000, "Swim down to where the light stops"),
        ("care.sleepDisturbances", "stage", "atLeast", 9, "And wake it again and again in the dark"),
    ],
    "darknessbagramon": [
        ("health.daylight", "stage", "atMost", 150, "Keep it out of the sun entirely"),
        ("care.battleCount", "lifetime", "atLeast", 36, "And build the army one fight at a time"),
    ],
    "deathmon_black": [
        ("health.activeEnergy", "stage", "atLeast", 30000, "Spend everything, because the black one takes what is left"),
        ("care.overfeeds", "stage", "atLeast", 8, "And keep feeding it long after it has had enough"),
    ],
    "demon": [
        ("health.steps", "stage", "atLeast", 96000, "Walk the whole circle of it"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.9, "And win with a wrath nothing answers"),
    ],
    "demon_x": [
        ("health.exerciseMinutes", "stage", "atLeast", 1680, "Push it past where the base form stopped"),
        ("care.trainingSessions", "stage", "atLeast", 34, "And temper the antibody in the training pit"),
    ],
    "diablomon": [
        ("health.steps", "stage", "atLeast", 120000, "Let it multiply across every step you take"),
        ("care.battleCount", "lifetime", "atLeast", 40, "And swarm one fight after another"),
    ],
    "diablomon_x": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 210000, "Outrun the copy of itself"),
        ("care.trainingSessions", "stage", "atLeast", 32, "And drill until the swarm moves as one"),
    ],
    "dominimon": [
        ("health.mindfulMinutes", "stage", "atLeast", 1200, "Keep the long silence a dominion asks for"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.8, "And hold the order you were given"),
    ],
    "duftmon": [
        ("health.exerciseMinutes", "stage", "atLeast", 1520, "Move like something that never stops moving"),
        ("care.trainingSessions", "stage", "atLeast", 28, "And drill the strategy until it is instinct"),
    ],
    "duftmon_x": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 240000, "Range further than the leopard ever did"),
        ("care.battleCount", "lifetime", "atLeast", 44, "And take the field again and again"),
    ],
    "dukemon_x": [
        ("health.flightsClimbed", "stage", "atLeast", 700, "Climb with the lance still raised"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.88, "And keep the Royal Knight's record clean"),
    ],
    "dynasmon_x": [
        ("health.activeEnergy", "stage", "atLeast", 34000, "Pour everything into the dragon's roar"),
        ("care.sleepDisturbances", "stage", "atMost", 2, "And still let it rest between them"),
    ],
}

COMMENTS = {
    "callismon": (
        "Soloogarmon is a cited `Evolves From` on Wikimon, cited to Pendulum COLOR 3 Nightmare "
        "Soldiers — the device `penc-nso` IS — so the arrow and the line come from the same page. "
        "**THE BOLDED PARENT IS AT THE WRONG RUNG**: Gryzmon is an ADULT here and "
        "`GraphValidationError.invalidStageTransition` refuses an Adult -> Ultimate edge, and the "
        "other bolded name, Arkadimon (V-Tamer), is idle-only at every level above Child. Fantomon "
        "and Vamdemon are the other Nightmare Soldiers citations and each already carries a climb; "
        "Great Gryzmon and Grappu Leomon have no sheet in this pack; Monzaemon (`dmc-v1`), Zudomon "
        "(`penc-ds`) and the three WereGarurumon are off this line. Vitality; Soloogarmon spends "
        "stamina on Fenriloogamon."),
    "cernumon": (
        "**EVERY `Evolves From` Wikimon GIVES IT IS AN ULTIMATE.** Griffomon, Hydramon and "
        "Pinochimon are the whole list, all three cited to Pendulum COLOR 4 Wind Guardians, and "
        "`invalidStageTransition` refuses an Ultimate -> Ultimate edge — so the arrow is drawn one "
        "rung below where the page draws it, on the Perfect that climbs into the cited Digimon. "
        "Jyureimon is Pinochimon's only parent in this file and is `penc-wg`'s, which is the Wind "
        "Guardians line the citation names, so the placement follows the device even though no "
        "single arrow could be copied. The page bolds nothing. Spirit; Jyureimon spends vitality on "
        "Pinochimon."),
    "chaosdukemon_core": (
        "The ONE bolded `Evolves From` on Wikimon is Chaos Dukemon itself, an ULTIMATE — "
        "`invalidStageTransition` — and the page's only other name is the Chrono Core, an ITEM and "
        "not a Digimon, the Code Key trap US-163 recorded on Barbamon. So the Core lands on the "
        "Perfect that carries the form it is the core of: BlackMegaloGrowmon climbs to ChaosDukemon "
        "on `tamers`, and MegaloGrowmon X, the other parent of that Mega, is left free for a later "
        "sweep. Vitality; BlackMegaloGrowmon spends strength on ChaosDukemon. **THE CRITERIA ARE "
        "THE DIGIMON**: a core is what is left when a knight burns out, so it asks for everything "
        "spent and for a record that fell apart."),
    "chaosdramon_v2": (
        "**THE BASE FORM IS A JOGRESS RESULT, NOT AN EVOLUTION NODE, SO THE VARIANT FOLLOWS A CITED "
        "PARENT ON THE SAME LINE** — the shape Dynasmon X takes below, and the reason this story "
        "wires the V2 while leaving the plain Chaosdramon alone. Chaosdramon is drawn as the Digital "
        "Monster Ver.5 Jogress Ultra and `jogress.json` spends it twice (Darkdramon+Mugendramon, "
        "Mugendramon+HiAndromon), so `DMCVersion5TreeTests` and `PendulumMetalEmpireTreeTests` both "
        "pin it to NO node; it is obtainable and so not an orphan. **Wikimon HAS NO PAGE FOR A "
        "'Chaosdramon V2' AT ALL** — `action=opensearch` returns an empty list, not a redirect — so "
        "this is the sprite pack's second Chaosdramon design, the MetalTyranomon V2 shape on "
        "`dmc-v5`. Chaosdramon cites Metal Greymon (X-Antibody) as an `Evolves From`, and that node "
        "had been a LEAF on `dmc-v3` since US-160 ('A leaf until the Ultimate sweeps'), so the V2 "
        "clears that dead end and follows the base form's own cited parent. Strength, and it is "
        "MetalGreymon X's FIRST edge, so it is the `isDefault` climb."),
    "cherubimon_vice_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT, the strong variant rule US-160 recorded, and it is "
        "the only reading: both bolded `Evolves From` on Wikimon — Cherubimon (Vice) and Cherubimon "
        "(Virtue) (X-Antibody) — are ULTIMATES. Andiramon Virus is one of the two Perfects that "
        "carry the plain Cherubimon Vice on `penc-vb`, so the antibody hangs where the beast does. "
        "Kaiser Leomon is Armor-Hybrid and off the ladder; Mammon X, Mephismon X and Vamdemon X are "
        "cited and all three are on `penc-nso`, which would have split this variant from its base "
        "form. Vitality; Andiramon Virus spends strength on Cherubimon Vice."),
    "cherubimon_virtue_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT, exactly as its opposite number above does, and for the "
        "same reason: Wikimon bolds only Cherubimon (Virtue) and Cherubimon (Vice) (X-Antibody), "
        "both ULTIMATES. The plain Cherubimon Virtue has two Perfects on `penc-vb` and Entmon is "
        "the one still free — HolyAngemon, the other, spends its last energy on Dominimon in this "
        "same edit. Anomalocarimon X (`penc-ds`), Jazarichmon (`tamers`), Monzaemon X (`dmc-v1`) "
        "and Pumpmon (`penc-nsp`) are the cited alternatives and every one is off this line. "
        "Spirit; Entmon spends vitality on Cherubimon Virtue."),
    "craniummon_x": (
        "FOLLOWS A CITED PARENT ON ITS BASE FORM'S OWN LINE. Andromon is a cited `Evolves From` on "
        "Wikimon, cited to Digimon ReArise, and is `penc-me`'s since US-142 — the same line as the "
        "plain Craniummon, so the variant rule holds at the line even though the parent differs. "
        "The bolded name is Craniummon itself, an ULTIMATE. Knightmon, the base form's own Perfect, "
        "is cited too and would have been the strong reading, but this same edit spends both of its "
        "free energies on Duftmon and Duftmon X, and a fourth edge there for a variant when a cited "
        "parent sits one node away is a worse trade than the one US-160 priced. Stamina; Andromon "
        "spends strength on HiAndromon and vitality on Tekkamon's thread."),
    "cthyllamon": (
        "Dagomon is a cited `Evolves From` on Wikimon, cited to Pendulum COLOR 2 Deep Savers — the "
        "device `penc-ds` is — and it is the flavour besides: a god of the drowned under the deep-"
        "sea line. The page bolds NOTHING, so the citations are the whole of the argument. "
        "Anomalocarimon, Anomalocarimon X, Hangyomon, MarinDevimon and Thetismon are the other Deep "
        "Savers names and each already climbs; BlackKingNumemon (`dmc-v1`) is off this line and "
        "Majiramon is idle-only in this pack. Vitality; Dagomon spends spirit on Pukumon."),
    "darknessbagramon": (
        "**A BOLDED PARENT THAT IS ACTUALLY A PERFECT, WHICH AT THIS RUNG IS RARE ENOUGH TO SAY OUT "
        "LOUD.** Wikimon bolds three `Evolves From` for DarknessBagramon: Bagramon, an ULTIMATE on "
        "`tamers`; DarknessBagramon (Dark Knightmon), which has no sheet in this pack; and "
        "DarkKnightmon, which US-153 wired as a PERFECT on `penc-nsp` under Tailmon. So the page's "
        "own arrow can be drawn exactly as drawn, which almost nothing else in this story could "
        "manage. Dark Knightmon (X-Antibody) is cited too and is this node's parent's own climb. "
        "Strength; DarkKnightmon spends spirit on DarkKnightmon X."),
    "deathmon_black": (
        "SITS ON ITS BASE FORM'S OWN PARENT. Deathmon is the one bolded `Evolves From` on Wikimon and "
        "is an ULTIMATE, so the strong variant rule is again the only reading; Darumamon is one of "
        "the two Perfects that carry the plain Deathmon on `penc-nso` and is the one still free, "
        "because Mummymon already carries three edges after US-163. Chimairamon, Nanomon, "
        "Piccolomon, Digitamamon, Etemon, Fantomon, LadyDevimon, Manticoremon, Cyberdramon and "
        "RaijiLudomon are cited and each is on another line; Ponchomon and Rare Raremon have no "
        "sheet. Vitality; Darumamon spends strength on Deathmon."),
    "demon": (
        "DeathMeramon is a cited `Evolves From` on Wikimon, cited to Pendulum COLOR 3 Nightmare "
        "Soldiers — and Demon is the Demon Lord that line is built around, so the device and the "
        "flavour point at the same node. **ALL THREE BOLDED NAMES ARE UNDRAWABLE**: Seraphimon and "
        "BlackSeraphimon are ULTIMATES, and the Code Key of Wrath is an ITEM. The page lists more "
        "`penc-nso` Perfects than any other in this story — Fantomon, LadyDevimon, Vamdemon, "
        "BlueMeramon, Mephismon, Archnemon, Mummymon, Lucemon Falldown — and the one chosen is the "
        "one whose own device is cited beside it. Spirit; DeathMeramon spends strength on Boltmon."),
    "demon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT, and no other reading exists: Wikimon gives Demon "
        "(X-Antibody) four `Evolves From` and every one is an ULTIMATE — Demon itself, bolded and "
        "authored in this same edit, plus BlackWarGreymon X, Chaosdramon X and PrinceMamemon X. So "
        "the antibody hangs where the wrath does. Vitality; DeathMeramon spends strength on Boltmon "
        "and spirit on Demon, three edges on three energies, which is what keeps both Demon "
        "reachable — `EvolutionEngine.qualifies` matches on the dominant type and a shared energy "
        "would have hidden one of them for good."),
    "diablomon": (
        "**THE LINE IS NAMED FOR IT AND EVERY CITED ROUTE ONTO IT IS SHUT — SO THE JOB WAS TO GET "
        "IT ONTO ITS OWN LINE ANYWAY.** All four bolded `Evolves From` on Wikimon live on "
        "`diablomon` and not one can be drawn: Chrysalimon and Infermon are idle-only, which "
        "`GraphValidationError.edgeToDexOnlyNode` forbids, and Keramon is a CHILD and Kuramon a "
        "BABY I, which `invalidStageTransition` forbids. That is the exact wall US-163 hit with "
        "Armagemon, which had to leave the line entirely — but Meicrackmon, wired by US-160 over "
        "Meicoomon, is a drawable Perfect on this line that already climbs, so the eponym stays "
        "home. Digitamamon (`dmc-v4`), Okuwamon (`penc-me`), Nanomon (`dmc-v5`), LadyDevimon "
        "(`tamers`) and Vamdemon (`penc-nso`) are the cited parents off the line, and each would "
        "have left `diablomon` without a Diablomon. Strength; Meicrackmon spends vitality on "
        "Rasielmon."),
    "diablomon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT and meets the same two walls the base form did: its "
        "bolded `Evolves From` are Diablomon, an ULTIMATE authored in this same edit, and Keramon "
        "(X-Antibody), which is a CHILD on this very line — `invalidStageTransition` again. Every "
        "other citation on the page (BeelStarmon X, Beelzebumon X, BelialVamdemon, Chaosdramon X, "
        "PrinceMamemon X, Rasenmon Fury Mode) is an Ultimate. So Meicrackmon carries both "
        "Diablomon, which also keeps the pair on the line Wikimon draws them on. Spirit; "
        "Meicrackmon spends vitality on Rasielmon and strength on Diablomon."),
    "dijiangmon": (
        "Huankunmon is a cited `Evolves From` on Wikimon, cited to Pendulum COLOR 6 Saiyu Warriors, "
        "and had been a LEAF on `dmc-v4` since US-159, whose node comment ends 'A leaf until the "
        "Ultimate sweeps' — this is that sweep, so the arrow clears a dead end AND follows a "
        "citation, the same trade Chaosdramon makes above. **THE BOLDED NAME IS Digitama, WHICH IS "
        "A THING AND NOT A DIGIMON**, the Chrono Core trap this story met twice. ChoHakkaimon, "
        "Gokuwmon and Xingtianmon on `penc-sw` — the Saiyu Warriors line proper — are the cited "
        "alternatives and every one already climbs to Shakamon or Seitengokuwmon; Huankunmon's own "
        "node records that the Journey to the West cast sits on `dmc-v4` only because Xiquemon "
        "does, and this arrow inherits that rather than re-arguing it. Spirit, and it is this "
        "Perfect's FIRST edge, so it is the `isDefault` climb."),
    "dominimon": (
        "HolyAngemon is the one BOLDED `Evolves From` on Wikimon, cited to Pendulum COLOR ZERO Virus "
        "Busters, and is `penc-vb`'s since US-143 — so the bolded arrow lands on an existing line "
        "for nothing. **THIS MAKES HOLYANGEMON THE FIRST PERFECT IN THE FILE WITH FOUR EDGES, AND "
        "IT SPENDS THE NODE'S LAST FREE ENERGY**: vitality goes to Cherubimon Virtue, strength to "
        "BlackSeraphimon, spirit to Seraphimon, and stamina is what was left — the node is CLOSED "
        "after this, and a later sweep that wants it must take a different Perfect. Angewomon, "
        "Asuramon and WereGarurumon are the other Virus Busters citations, all on this line and all "
        "free; the bolded one wins, as it has at every rung."),
    "duftmon": (
        "Knightmon is a BOLDED `Evolves From` on Wikimon and is `penc-me`'s since US-142 — a knight "
        "under a knight-commander, on the line this file builds its Royal Knights on. The other "
        "bolded name, Duftmon: Leopard Mode, is IDLE-ONLY in this pack, so `edgeToDexOnlyNode` "
        "would refuse it and it could not be a parent even if it were at the right rung. Grademon "
        "(`tamers`), Panjyamon (`penc-nsp`), Mammon (`penc-nso`), RizeGreymon and WereGarurumon are "
        "the cited alternatives and each is off this line; Grappu Leomon has no sheet and "
        "SlashAngemon is an Ultimate. Spirit; Knightmon spends strength on Craniummon."),
    "duftmon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT. Its bolded `Evolves From` on Wikimon is Duftmon, an ULTIMATE "
        "authored in this same edit, and the rest of the page is Ultimates (Hexeblaumon, "
        "NoblePumpmon, Ofanimon X) or forms with no sheet. Panjyamon and Panjyamon X on `penc-nsp` "
        "and the three MegaloGrowmon on `tamers` are the drawable citations and each would have "
        "split the variant from its base form, which is what US-160's rule exists to stop. "
        "Vitality; Knightmon spends strength on Craniummon and spirit on Duftmon — three edges, "
        "three energies, so the fork holds in every direction."),
    "dukemon_x": (
        "SITS ON ITS BASE FORM'S OWN PARENT. Both bolded `Evolves From` on Wikimon are undrawable: "
        "Dukemon itself is an ULTIMATE and Medieval Dukemon has no sheet in this pack. MegaloGrowmon "
        "(Orange) is one of the two Perfects that carry the plain Dukemon on `tamers`; Manticoremon, "
        "the other, was spent on Dukemon by US-160 for the argument recorded on that node, so the "
        "Orange form is where the antibody goes. Grademon, BlackMegaloGrowmon and MegaloGrowmon X "
        "are the other `tamers` citations and Knightmon, Hisyaryumon and Ouryumon the `penc-me` "
        "ones. Spirit; MegaloGrowmon Orange spends strength on Dukemon."),
    "dynasmon_x": (
        "**ITS BASE FORM IS IDLE-ONLY, SO THE VARIANT RULE HAS NOTHING TO HANG ON AND A CITATION "
        "HAS TO CARRY IT** — the first time in this series that a variant's base form is refused by "
        "ART at its own rung rather than by stage. Dynasmon is the page's one bolded `Evolves From` "
        "on Wikimon, is an ULTIMATE, and the roster marks it `dexOnly`, so `edgeToDexOnlyNode` "
        "would refuse the arrow twice over. DORUguremon is a cited `Evolves From` and is `tamers`', "
        "the line the whole DORUmon thread lives on. Angewomon and HolyAngemon are cited and on "
        "`penc-vb`, where this same edit closes HolyAngemon's last energy; Metallicdramon, "
        "MetalPiranimon and Silphymon are Ultimates or idle-only. Vitality; DORUguremon spends "
        "strength on Dorugoramon and spirit on Alphamon Ouryuken."),
}

ELEMENTS = {
    "callismon": ("dark", "virus"),
    "cernumon": ("wind", "data"),
    "chaosdukemon_core": ("dark", "virus"),
    "chaosdramon_v2": ("machine", "virus"),
    "cherubimon_vice_x": ("dark", "virus"),
    "cherubimon_virtue_x": ("light", "vaccine"),
    "craniummon_x": ("steel", "vaccine"),
    "cthyllamon": ("water", "virus"),
    "darknessbagramon": ("dark", "virus"),
    "deathmon_black": ("dark", "virus"),
    "demon": ("dark", "virus"),
    "demon_x": ("dark", "virus"),
    "diablomon": ("dark", "virus"),
    "diablomon_x": ("dark", "virus"),
    "dijiangmon": ("wind", "free"),
    "dominimon": ("light", "vaccine"),
    "duftmon": ("light", "data"),
    "duftmon_x": ("light", "data"),
    "dukemon_x": ("light", "vaccine"),
    "dynasmon_x": ("fire", "vaccine"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
# `projectileSymbol|tint` must be unique WITHIN a line and `signatureName` GLOBALLY; `check()`
# proves both against the real files before anything is written.
MOVES = {
    "callismon": ("hand.raised.fill", "mint", "Beast Slayer", "hand.raised.fill"),
    "cernumon": ("leaf.fill", "blue", "Antler Gale", "leaf.fill"),
    "chaosdukemon_core": ("shield.fill", "indigo", "Chrono Breaker", "shield.fill"),
    "chaosdramon_v2": ("gearshape.fill", "orange", "Twin Chaos Cannon", "gearshape.fill"),
    "cherubimon_vice_x": ("moon.fill", "brown", "Lightning Spear Cross", "moon.fill"),
    "cherubimon_virtue_x": ("sparkles", "blue", "Storm of Judgement Cross", "sparkles"),
    "craniummon_x": ("shield.fill", "teal", "Final Elysion Cross", "shield.fill"),
    "cthyllamon": ("drop.fill", "brown", "Abyssal Chant", "drop.fill"),
    "darknessbagramon": ("moon.fill", "red", "Death Crush", "moon.fill"),
    "deathmon_black": ("moon.fill", "teal", "Vampire Wave Black", "moon.fill"),
    "demon": ("flame.fill", "white", "Flame Inferno of Wrath", "flame.fill"),
    "demon_x": ("sparkles", "indigo", "Chaos Flare Cross", "sparkles"),
    "diablomon": ("circle.fill", "teal", "Catastrophe Day", "circle.fill"),
    "diablomon_x": ("circle.fill", "cyan", "Catastrophe Cannon Cross", "circle.fill"),
    "dijiangmon": ("wind", "mint", "Faceless Gale", "wind"),
    "dominimon": ("sparkles", "teal", "Holy Dominion", "sparkles"),
    "duftmon": ("scissors", "mint", "Black Aura Blast", "scissors"),
    "duftmon_x": ("scissors", "cyan", "Leopard Cross Slash", "scissors"),
    "dukemon_x": ("shield.fill", "white", "Royal Saber Cross", "shield.fill"),
    "dynasmon_x": ("bolt.fill", "white", "Dragon Thrower Cross", "bolt.fill"),
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

    # A leaf's FIRST in-edge is its `isDefault` climb and carries no criteria; every other in-edge
    # is earned and must. The leaf that gains a SECOND node in this same edit (MetalGreymon X) owes
    # criteria on that one, so the rule is per-edge rather than per-parent.
    climbed = set()
    for uid, _, _, _, parent, _ in ULTIMATES:
        is_climb = parent in LEAF_PARENTS and parent not in climbed
        if is_climb:
            climbed.add(parent)
        if is_climb and uid in CONDITIONS:
            sys.exit("%s is a leaf's isDefault climb and must not carry criteria" % uid)
        if not is_climb and uid not in CONDITIONS:
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

    # 1. the in-edges. A leaf Perfect gains its single `isDefault` climb first; every other new
    #    arrow is an EARNED branch beside the climb, and the climb stays last.
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

    # 2. the twenty-two Ultimates, terminal and so with no `evolutions` key at all.
    for uid, name, sprite, line, _, _ in ULTIMATES:
        nodes.append({
            "id": uid, "displayName": name, "stage": "Ultimate-Super Ultimate", "line": line,
            "spriteFile": sprite, "comment": COMMENTS[uid],
        })

    open(path, "w").write(json.dumps(doc, indent=2, ensure_ascii=False))

    # 3. elements.json and moves.json, one entry apiece for all twenty-two.
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
