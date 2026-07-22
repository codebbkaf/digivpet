"""US-162 — Orphan sweep: Perfect S-Z, and the rung is finished.

Authors the twenty-two orphaned Perfect whose display name begins S-Z — every Perfect still
orphaned anywhere, so this story closes the rung — the three Ultimates they climb into that had no
node, and the two junk Perfect floors the two lines this story OPENS needed before their Champions
could branch at all. `adventure02` and `commandramon` were two of the three lines US-161 handed
over with no Perfect rung; `algomon` is the third and STAYS CLOSED, because the only Champion any
orphan cites on it (Siesamon) sits on a thread Ghost Digitama cannot reach, so opening the rung
there would have left an egg unraisable on a line that has one. Shishimamon went to `vital` under
Reppamon instead, with the cited Zanbamon already above it.

Run once; it refuses to run twice (every id it adds must be absent).

Kept in `scripts/` beside `us157_author.py` .. `us161_author.py` for the same reason: the JSON
round-trips byte-exactly through `json.dumps(indent=2, ensure_ascii=False)`, which is what makes
scripted authoring of twenty-seven nodes across three files safe.
"""
import collections
import json
import sys

ROOT = "/Users/red/Documents/SourceCode/ios_project/digi/"

# (id, displayName, spriteFile, line, parent, parentEnergy, ultimate, climbEnergy)
PERFECTS = [
    ("sagomon", "Sagomon", "Sagomon", "penc-sw",
     "lianpumon", "vitality", "shakamon", "vitality"),
    ("sanzomon", "Sanzomon", "Sanzomon", "penc-sw",
     "hakubamon", "vitality", "shakamon", "vitality"),
    ("saviorhackmon", "SaviorHackmon", "SaviorHackmon", "penc-nso",
     "firamon", "spirit", "pencnso_boltmon", "spirit"),
    ("scorpiomon", "Scorpiomon", "Scorpiomon", "penc-me",
     "kuwagamon_x", "stamina", "pencme_mugendramon", "stamina"),
    ("sekkamon", "Sekkamon", "Sekkamon", "dmc-v3",
     "shellmon", "spirit", "ryugumon", "spirit"),
    ("shawujinmon", "Shawujinmon", "Shawujinmon", "penc-sw",
     "tsuchidarumon", "strength", "shakamon", "strength"),
    ("shishimamon", "Shishimamon", "Shishimamon", "vital",
     "reppamon", "strength", "zanbamon", "strength"),
    ("shootmon", "Shootmon", "Shootmon", "penc-me",
     "minotaurmon", "vitality", "kazuchimon", "vitality"),
    ("sirenmon", "Sirenmon", "Sirenmon", "vital",
     "hookmon", "stamina", "regalecusmon", "stamina"),
    ("skullbaluchimon", "SkullBaluchimon", "SkullBaluchimon", "commandramon",
     "damemon", "stamina", "chaosdramon_x", "stamina"),
    ("superstarmon", "Superstarmon", "Superstarmon", "penc-me",
     "omekamon", "spirit", "princemamemon", "spirit"),
    ("tekkamon", "Tekkamon", "Tekkamon", "penc-me",
     "guardromon", "stamina", "pencme_hiandromon", "stamina"),
    ("triceramon", "Triceramon", "Triceramon", "dmc-v4",
     "monochromon", "strength", "darkdramon", "strength"),
    ("triceramon_x", "Triceramon X", "Triceramon_X", "commandramon",
     "ginryumon", "strength", "chaosdramon_x", "strength"),
    ("vamdemon_x", "Vamdemon X", "Vamdemon_X", "penc-nso",
     "musyamon", "spirit", "venomvamdemon", "spirit"),
    ("vermillimon", "Vermillimon", "Vermillimon", "adventure02",
     "nisedrimogemon", "strength", "blackwargreymon", "strength"),
    ("waruseadramon", "WaruSeadramon", "WaruSeadramon", "penc-ds",
     "pencds_seadramon", "spirit", "leviamon", "spirit"),
    ("weregarurumon_black", "WereGarurumon Black", "WereGarurumon_Black", "dmc-v2",
     "garurumon_black", "strength", "cresgarurumon", "strength"),
    ("weregarurumon_x", "WereGarurumon X", "WereGarurumon_X", "penc-nso",
     "pencnso_garurumon", "stamina", "pencnso_metalgarurumon", "stamina"),
    ("xingtianmon", "Xingtianmon", "Xingtianmon", "penc-sw",
     "ginkakumon", "vitality", "seitengokuwmon", "vitality"),
    ("yatagaramon", "Yatagaramon", "Yatagaramon", "penc-wg",
     "xv-mon_black", "spirit", "hououmon", "spirit"),
    ("yatagaramon_2006", "Yatagaramon 2006", "Yatagaramon_2006", "penc-wg",
     "pencwg_birdramon", "stamina", "griffomon", "stamina"),
]

# The Ultimates this story had to open, in the order they are appended. Two of the three are the
# Mega US-158's rule owes a line whose Perfect rung opens here; Regalecusmon is `vital`'s third and
# is here because Sirenmon has no cited climb with a node anywhere.
ULTIMATES = [
    ("chaosdramon_x", "Chaosdramon X", "Chaosdramon_X", "commandramon"),
    ("blackwargreymon", "BlackWarGreymon", "BlackWarGreymon", "adventure02"),
    ("regalecusmon", "Regalecusmon", "Regalecusmon", "vital"),
]

# The two junk PERFECTS this story had to invent, one for each line whose Perfect rung it opens.
# `EvolutionCriteriaTests` refuses a branching Champion with no `isDefault` edge onto a junk node
# of its own line, and not one of the twenty-two Perfect orphaned when this story ran is
# junk-flavoured — so both are line-scoped ALIASES, the `diablomon_gerbemon` pattern.
# (id, displayName, spriteFile, line).
JUNK_PERFECTS = [
    ("commandramon_karakurumon", "Karakurumon", "Karakurumon", "commandramon"),
    ("adventure02_jyagamon", "Jyagamon", "Jyagamon", "adventure02"),
]

# The eight Champions that were LEAVES before this story: giving one an out-edge means giving it
# its line's junk floor in the same edit. Six floors already existed; two are the nodes above.
JUNK_FLOORS = {
    "lianpumon": ("pandamon", "stamina"),
    "tsuchidarumon": ("pandamon", "stamina"),
    "reppamon": ("vital_darumamon", "vitality"),
    "hookmon": ("vital_darumamon", "strength"),
    "damemon": ("commandramon_karakurumon", "strength"),
    "ginryumon": ("commandramon_karakurumon", "stamina"),
    "nisedrimogemon": ("adventure02_jyagamon", "stamina"),
    "garurumon_black": ("gerbemon", "vitality"),
}

# The criteria on each new in-edge. Two apiece: one HealthKit, one care counter, so no edge is
# earned by walking alone and none by playing alone.
CONDITIONS = {
    "sagomon": [
        ("health.water", "stage", "atLeast", 5600, "Keep the head-dish brimming the whole way"),
        ("care.trainingSessions", "stage", "atLeast", 24, "And drill the crescent staff on the bank"),
    ],
    "sanzomon": [
        ("health.mindfulMinutes", "stage", "atLeast", 240, "Sit with the sutra until the words go quiet"),
        ("care.overfeeds", "stage", "atMost", 2, "And keep the pilgrim's bowl close to empty"),
    ],
    "saviorhackmon": [
        ("health.exerciseMinutes", "stage", "atLeast", 1120, "Work the little knight past every excuse"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.78, "And let the oath be kept in almost every fight"),
    ],
    "scorpiomon": [
        ("health.steps", "stage", "atLeast", 54000, "Walk the armoured tail across the whole desert"),
        ("care.battleCount", "lifetime", "atLeast", 27, "And let the sting settle every argument"),
    ],
    "sekkamon": [
        ("health.daylight", "stage", "atMost", 220, "Keep the snow fox out of the thawing sun"),
        ("care.trainingSessions", "stage", "atLeast", 21, "And teach it to dance before it fights"),
    ],
    "shawujinmon": [
        ("health.distanceSwimming", "stage", "atLeast", 5200, "Send it down to the river bed and back"),
        ("care.battleCount", "lifetime", "atLeast", 23, "And let the sand monk carry every quarrel"),
    ],
    "shishimamon": [
        ("health.activeEnergy", "stage", "atLeast", 10800, "Burn the guardian lion's whole reserve"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.72, "And leave the gate mostly unbroken"),
    ],
    "shootmon": [
        ("health.exerciseMinutes", "stage", "atLeast", 1180, "Work the fists until the guard never drops"),
        ("care.trainingSessions", "stage", "atLeast", 29, "And spar with it more than anything else"),
    ],
    "sirenmon": [
        ("health.distanceSwimming", "stage", "atLeast", 5800, "Take the song out past the shallows"),
        ("care.sleepDisturbances", "stage", "atMost", 1, "And let it sleep, because a siren sings rested"),
    ],
    "skullbaluchimon": [
        ("health.sleep", "stage", "atMost", 3200, "Keep the bones walking through the small hours"),
        ("care.overfeeds", "stage", "atMost", 1, "And let nothing at all stay on those ribs"),
    ],
    "superstarmon": [
        ("health.daylight", "stage", "atLeast", 900, "Put it under every light there is"),
        ("care.battleCount", "lifetime", "atLeast", 31, "And book the star a great many shows"),
    ],
    "tekkamon": [
        ("health.flightsClimbed", "stage", "atLeast", 270, "Carry the iron up every stair there is"),
        ("care.trainingSessions", "stage", "atLeast", 26, "And beat the blade out over and over"),
    ],
    "triceramon": [
        ("health.steps", "stage", "atLeast", 58000, "Walk the frill until the ground remembers it"),
        ("care.battleCount", "lifetime", "atLeast", 28, "And let all three horns be used"),
    ],
    "triceramon_x": [
        ("health.standHours", "stage", "atLeast", 230, "Keep the heavier plate off the ground"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.8, "And let the antibody lose almost nothing"),
    ],
    "vamdemon_x": [
        ("health.daylight", "stage", "atMost", 160, "Keep the coffin shut through every dawn"),
        ("care.battleCount", "lifetime", "atLeast", 25, "And let the count take what it wants by night"),
    ],
    "vermillimon": [
        ("health.activeEnergy", "stage", "atLeast", 11200, "Stoke the crimson hide until it glows"),
        ("care.overfeeds", "stage", "atLeast", 7, "And let the furnace be fed well past full"),
    ],
    "waruseadramon": [
        ("health.distanceSwimming", "stage", "atLeast", 6200, "Take the coils the length of the trench"),
        ("care.sleepDisturbances", "stage", "atLeast", 7, "And wake it often enough to sour it"),
    ],
    "weregarurumon_black": [
        ("health.sleep", "stage", "atLeast", 9600, "Let it dream through the whole of the dark moon"),
        ("care.battleWinRatio", "lifetime", "atMost", 0.45, "And let it lose more than it wins, which is what turns it"),
    ],
    "weregarurumon_x": [
        ("health.distanceWalkingRunning", "stage", "atLeast", 44000, "Run the wolf until the antibody takes"),
        ("care.trainingSessions", "stage", "atLeast", 25, "And drill the kick until it lands blind"),
    ],
    "xingtianmon": [
        ("health.standHours", "stage", "atLeast", 250, "Keep it upright, because it has no head to lift"),
        ("care.battleCount", "lifetime", "atLeast", 30, "And give the axe and shield plenty of work"),
    ],
    "yatagaramon": [
        ("health.flightsClimbed", "stage", "atLeast", 290, "Take the three-legged crow above the shrine"),
        ("care.trainingSessions", "stage", "atLeast", 27, "And teach it the road before it flies it"),
    ],
    "yatagaramon_2006": [
        ("health.steps", "stage", "atLeast", 60000, "Walk the whole pilgrim road beneath it"),
        ("care.battleWinRatio", "lifetime", "atLeast", 0.75, "And let the guide win far more than it loses"),
    ],
}

COMMENTS = {
    "sagomon": (
        "Lianpumon is a cited `Evolves From` on Wikimon — the page bolds only the Xros Wars fusion "
        "Xros Up Arresterdramon (Sagomon) and its two components, which are DigiXros arrows and not "
        "evolutions — and it had been a LEAF on `penc-sw` since US-157, so the arrow clears a dead "
        "end. Shakamon is on the same page's `Evolves To` and has been this line's Mega over "
        "Cho·Hakkaimon since US-157, so both ends are cited on the Saiyu Warriors line, which is "
        "where the whole Journey to the West cast belongs: Wikimon's own Virtual Pets section lists "
        "Sagomon in Pendulum COLOR 6 Saiyu Warriors, beside Gokuwmon and Cho·Hakkaimon. Gawappamon "
        "(`penc-ds`), Tortamon (`dmc-v3`) and Xiquemon (`dmc-v4`) are the drawable alternatives and "
        "each would have split the quartet. Vitality is what a river monk earns; Lianpumon's junk "
        "fall to Pandamon takes stamina."),
    "sanzomon": (
        "Hakubamon is a cited `Evolves From` on Wikimon and Shakamon is a BOLDED `Evolves To`, and "
        "both are on `penc-sw`, the Saiyu Warriors line — the cheapest shape there is. Hakubamon is the white horse Tang "
        "Sanzang rides, so the arrow is the story itself, and it already carried Cho·Hakkaimon "
        "(US-157) on stamina, leaving vitality free. Lianpumon and Xiquemon are the other cited "
        "parents; Tailmon and Turuiemon are cited too and are on `penc-nsp`, `penc-vb` and nowhere "
        "near the quartet. Erlangmon and Nezhamon are the flavour-perfect climbs and neither has a "
        "node — they are left for the Ultimate sweeps, which will find Sanzomon waiting."),
    "saviorhackmon": (
        "Firamon is a cited `Evolves From` on Wikimon and Boltmon is a cited `Evolves To` that has "
        "been `penc-nso`'s Mega since US-140, so US-152's rule of intersecting both ends closes on "
        "one line with no new node. **JESmon, the page's BOLDED climb, has no sheet in this pack at "
        "all** — it is a roster entry with no evolution anywhere and belongs to the Ultimate "
        "sweeps — and every other bolded name on the page is a device rather than a Digimon. "
        "Arresterdramon (`xros`) and Coredramon (Green) (`dmc-v1`) are the cited parents that are "
        "also leaves, and either would have cleared a dead end, but neither line holds a cited "
        "climb; Angemon on `dmc-v2` does (Metal Garurumon) and lost on flavour, since Firamon is a "
        "fire beast and Savior Huckmon is the fire knight. Spirit; Firamon spends vitality on "
        "Flaremon and strength on its junk fall to Darumamon."),
    "scorpiomon": (
        "Kuwagamon (X-Antibody) is a cited `Evolves From` on Wikimon and Mugendramon is a BOLDED "
        "`Evolves To`, and `penc-me` holds both — the only line anywhere that does. The page's "
        "other bolded climb, Hi Mugendramon, has no sheet. Note that this is the JAPANESE "
        "Scorpiomon, the sand scorpion: Wikimon's own disambiguation line points the English dub's "
        "'Scorpiomon' at Anomalocarimon, which is already on `penc-ds`, so the two are not the same "
        "Digimon and neither displaces the other. Snimon is the sole bolded parent and has no sheet "
        "in this pack; Dobermon (`xros`), Gekomon (`vital`), Sangloupmon (`diablomon`) and Tortamon "
        "(`dmc-v3`) are cited leaves whose lines hold no cited climb. Stamina; Kuwagamon X spends "
        "strength on Okuwamon, vitality on Okuwamon X and spirit on its junk fall to Locomon."),
    "sekkamon": (
        "Shellmon is a cited `Evolves From` on Wikimon and Ryugumon is a cited `Evolves To` that "
        "has been `dmc-v3`'s Mega over MarinBullmon since US-160, so both ends are cited on one "
        "line at no cost. **TENKOMON, THE BOLDED PARENT, WAS DELIBERATELY NOT TAKEN.** It is a "
        "`tamers` leaf, so the arrow would have cleared a dead end — but the page's bolded climb, "
        "Yukinamon, has no node and `tamers` holds no cited climb at all, so honouring the bold "
        "would have cost an Ultimate for one Perfect. Manekimon (`wanyamon`) is the third cited "
        "parent and its line holds no cited climb either. Spirit; Shellmon spends stamina on "
        "Andromon and on its junk fall to Etemon, and vitality on MarinBullmon."),
    "shawujinmon": (
        "**NO CITED PARENT EXISTS ON THIS LINE, AND THE CLIMB IS WHY IT IS HERE ANYWAY.** Shakamon "
        "is a BOLDED `Evolves To` on Wikimon and exists only on `penc-sw`; so do Cho·Hakkaimon, "
        "Gokuwmon and Sanzomon, the other three bolded names in the same clause, because that "
        "clause is the Journey to the West party fusing. Shawujinmon is Sha Wujing under the "
        "Chinese spelling exactly as Sagomon is under the Japanese one, so the quartet is where it "
        "belongs and `penc-sw`, the Saiyu Warriors line, is the only one that can draw the bolded "
        "arrow at all. The price is "
        "an UNCITED parent: Gawappamon, the bolded `Evolves From`, is on `penc-ds`, and Bakemon, "
        "Dinohumon, Gaogamon, Geo Greymon, Hanumon, Hookmon, Ice Devimon, Numemon, Peckmon, "
        "Reppamon and Starmon are cited and spread across nine other lines, none of them this one. "
        "Tsuchidarumon is `penc-sw`'s JUNK Champion and takes the branch — the Scumon arrangement "
        "US-133 recorded, where a junk Adult carries an earned arrow as well as the fall — and the "
        "flavour is exact: a clay doll of the earth into the monk of the sands. Strength; the fall "
        "to Pandamon takes stamina."),
    "shishimamon": (
        "**NO CITED PARENT ON THIS LINE, AND `algomon` IS THE REASON — SAID HERE BECAUSE IT IS THE "
        "ONE PLACE THIS STORY COULD NOT FINISH THE JOB.** Wikimon gives Shishimamon three "
        "`Evolves From`: Peckmon and Tenkomon, both `tamers` leaves, and Siesamon, which is the "
        "only Champion any orphan in this band cites on `algomon` — the last line in the file with "
        "no Perfect rung. Taking Siesamon would have opened that rung and STRANDED Ghost Digitama, "
        "`algomon`'s only egg, which descends through Algomon and Ghostmon to Algomon (Adult), "
        "Mimicmon and Witchmon and never reaches Labramon or Siesamon at all; `paomon`, the Baby I "
        "that thread starts at, is one of the thirteen no Digitama can reach (US-145 spent all "
        "fifty-seven). US-159's rule refuses exactly that — an unraisable egg on a line that HAS a "
        "Perfect rung — so `algomon` stays closed and is handed on. `tamers` holds no cited climb "
        "either, while Zanbamon is on this page's own `Evolves To` and has been `vital`'s Mega "
        "since US-161, so the CLIMB decides the line: Reppamon, a `vital` LEAF since US-153, takes "
        "the branch on flavour, a bladed Japanese weasel under a shrine lion with a mounted samurai "
        "above them. Darumamon, the page's other cited target, is this line's own junk floor, so "
        "both of Shishimamon's drawable `Evolves To` are on `vital`. Strength."),
    "shootmon": (
        "**NO DRAWABLE CITED PARENT EXISTS ANYWHERE, AND THIS SAYS SO.** Wikimon gives Shootmon "
        "three `Evolves From` — Exermon, Namakemon and Runnermon — and not one has a sheet in this "
        "pack, which is one worse than US-160's Mephismon X, whose parents at least existed as "
        "Digimon the file knows. Kazuchimon is a cited `Evolves To` and has been `penc-me`'s Mega "
        "since US-142, so the CLIMB decides the line, and `penc-me` is where Shootmon belongs on "
        "its own account: Wikimon's reference-book entry pairs it with Boutmon, which US-142 put on "
        "this very line under Thunderballmon. Minotaurmon takes the branch on flavour, a brawler "
        "under a brawler, with the Achillesmon and Shroudmon readings left for the Ultimate sweeps "
        "since neither has a node. Vitality; Minotaurmon spends stamina on Rebellimon and strength "
        "on its junk fall to Locomon."),
    "sirenmon": (
        "Hookmon is a cited `Evolves From` on Wikimon and had been a LEAF on `vital` since US-153, "
        "so the arrow clears a dead end. **KIWIMON, THE BOLDED PARENT, LOST ON A TIEBREAK RATHER "
        "THAN ON A RULE**: it is on `penc-wg`, and `penc-wg` holds no cited climb for Sirenmon "
        "either — not one of Ancient Megatheriumon, Ancient Mermaimon, Marin Angemon, Regalecusmon "
        "or the bolded Ceresmon has a node anywhere — so a new Ultimate had to be authored whichever "
        "parent was taken, and once that was true the flavour decided it. Regalecusmon is the "
        "deep-sea oarfish and `vital` is the water-heavy line (Gekomon, Hookmon, Mantaraymon X, "
        "Seadramon X), so the siren and her Mega both sit where they belong. Ebidramon on `penc-ds` "
        "is cited too and is FULL — four earned branches since US-139 — which is what took the "
        "Deep Savers reading off the table before flavour was reached. Stamina; the fall to "
        "Darumamon takes strength."),
    "skullbaluchimon": (
        "Damemon is a cited `Evolves From` on Wikimon and had been a LEAF on `commandramon` since "
        "US-151, so the arrow clears a dead end AND opens the last-but-one line with no Perfect "
        "rung. Baluchimon, the sole BOLDED parent, has no sheet in this pack at all. Chaosdramon "
        "(X-Antibody) is a cited `Evolves To` here and on Triceramon (X-Antibody)'s page as well, "
        "which is why one Mega serves both and `commandramon` pays for one rather than two: a "
        "chaos-red machine dragon over the line of mechanised soldiers is the flavour this line was "
        "always going to want. Titamon, the page's bolded climb, is on `tamers`, and every other "
        "cited climb — Dinorexmon, Dinotigermon, Griffomon, Ouryumon, Platinum Numemon, Skull "
        "Mammon, Zanbamon — is on a line that is not this one. Stamina; the fall to Karakurumon "
        "takes strength."),
    "superstarmon": (
        "Omekamon is a cited `Evolves From` on Wikimon and Prince Mamemon is a cited `Evolves To` "
        "that has been `penc-me`'s since US-142, so both ends are cited on one line. **STARMON, THE "
        "BOLDED PARENT, WAS NOT TAKEN AND THE REASON IS A WHOLE RUNG.** It is a `tamers` Adult and "
        "`tamers` holds no cited climb for Superstarmon at all — Mametyramon is a Perfect — so the "
        "bolded arrow would have cost an Ultimate; and the two other `penc-me` parents Wikimon "
        "cites, Revolmon and Thunderballmon, are both FULL at three earned branches apiece, which "
        "is what left Omekamon carrying it. Vademon and Nanimon are cited and are junk, Numemon and "
        "Scumon likewise; Superstarmon really is the Digimon a gag Digimon becomes when it makes "
        "it. Spirit; Omekamon spends strength on Hisyaryumon, vitality on RizeGreymon X and "
        "strength again on its junk fall to Locomon."),
    "tekkamon": (
        "Guardromon is a cited `Evolves From` on Wikimon and Hi Andromon is a cited `Evolves To` "
        "that has been `penc-me`'s Mega over Andromon since US-142 — both ends cited on the Metal "
        "Empire line, which is where an iron-masked swordsman belongs. The page bolds NOTHING at "
        "all in either direction, so there is no bolded reading to reject: Hyougamon (`penc-nsp`, "
        "with Herakle Kabuterimon above it), Kuwagamon (`dmc-v4`, with Boltmon) and V-dramon "
        "(`penc-wg`, with Pinochimon) each close on both ends too and each lost on flavour alone. "
        "Stamina; Guardromon spends vitality on Andromon and strength on its junk fall to Locomon."),
    "triceramon": (
        "Monochromon is a BOLDED `Evolves From` on Wikimon and Darkdramon is a cited `Evolves To` "
        "that has been `dmc-v4`'s Mega since US-136, so the bolded arrow and a cited climb close on "
        "one line for nothing. The page's other bolded parents are Agumon — a CHILD, which "
        "`GraphValidationError.invalidStageTransition` refuses exactly as it refused Lucemon under "
        "Lucemon Falldown in US-159 — and Mori Shellmon on `penc-ds`, whose line holds cited climbs "
        "but not the pairing this one has. **Astamon and Triceramon (X-Antibody) are the page's two "
        "bolded `Evolves To`: the first is a PERFECT and so can never be a climb, and the second is "
        "the variant, which cannot be reached from its own base form.** Strength; Monochromon "
        "spends vitality on Megadramon and on its junk fall to GreatKingScumon."),
    "triceramon_x": (
        "FOLLOWS A CITED PARENT RATHER THAN ITS BASE FORM, AND BOUGHT A LINE WITH IT. Triceramon "
        "itself is the BOLDED `Evolves From` and is a PERFECT, so it can never be an in-edge; of "
        "the fourteen drawable parents Wikimon does cite, Ginryumon on `commandramon` is the one "
        "that was a LEAF and the one whose line holds a cited climb — Chaosdramon (X-Antibody), "
        "which SkullBaluchimon cites too, so the two X-Antibody Perfects share one Mega and "
        "`commandramon` opens for four nodes rather than six. `dmc-v4`, where the plain Triceramon "
        "goes, offers this variant a cited parent (Monochromon) and NO cited climb whatever, which "
        "is the limit US-160 recorded on the variant rule and the escape hatch "
        "`ChildSweepMToZTests.testEveryVariantSitsWithItsBaseFormOrFollowsACitedParent` opened. "
        "Strength; the fall to Karakurumon takes stamina."),
    "vamdemon_x": (
        "**PLACED BY THE VARIANT RULE WITH NO CITED PARENT AND NO CITED CLIMB ON THIS LINE, AND THE "
        "COMMENT SAYS SO.** Wikimon gives Vamdemon (X-Antibody) exactly three `Evolves From`: the "
        "bolded Vamdemon, which is a PERFECT and so can never be an in-edge, Filmon on `penc-vb` "
        "and Numemon (X-Antibody) on `tamers` — and neither of those lines holds one of its cited "
        "climbs either (Belial Vamdemon and Prince Mamemon X have no node, Dark Knightmon X is "
        "`penc-nsp`, Metal Piranimon `penc-ds`). So the variant hangs off Musyamon, one of the two "
        "Champions its base form hangs off, and converges on the base form's own Mega, "
        "VenomVamdemon — the Monzaemon X and Mamemon X arrangement US-160 recorded. Belial "
        "Vamdemon is the flavour-perfect climb and is left for the Ultimate sweeps, which will find "
        "Vamdemon X waiting under it. Spirit; Musyamon spends strength on Vamdemon and on its junk "
        "fall to Darumamon."),
    "vermillimon": (
        "Nise Drimogemon is a cited `Evolves From` on Wikimon — three times over, across three "
        "device readings — and had been a LEAF on `adventure02` since US-151, so the arrow clears a "
        "dead end and opens the LAST line in the file with no Perfect rung. **AND IT IS THE ONLY "
        "CHAMPION ON THAT LINE THAT COULD HAVE OPENED IT**, which is the whole reason this node is "
        "here rather than on one of the five lines that hold both its ends for free (`dmc-v5` under "
        "Cyclomon with Gaioumon above, `wanyamon` under Geo Greymon with Ancient Volcamon, `dmc-v1`, "
        "`tamers`, `penc-me`). US-161 left `adventure02` closed because XV-mon carries only ONE of "
        "the line's two Digitama and opening the rung there would have left Worm Digitama "
        "unraisable; Nise Drimogemon is the line's JUNK Champion and takes the `isDefault` fall of "
        "V-mon, Wormmon AND Tinkermon, so branching it promotes BOTH eggs at once. Monochromon is "
        "the sole bolded parent and is on `dmc-v4` carrying Triceramon. BlackWarGreymon, a cited "
        "`Evolves To`, is the Mega: an Adventure 02 Digimon over the Adventure 02 line. Strength; "
        "the fall to Jyagamon takes stamina."),
    "waruseadramon": (
        "Seadramon is the BOLDED `Evolves From` on Wikimon and `penc-ds` has its own — "
        "`pencds_seadramon`, since US-139 — and Leviamon is a cited `Evolves To` that has been this "
        "line's Mega since US-139 too, so the bolded arrow and a cited climb close on one line at "
        "no cost. Aegisdramon, Metal Seadramon, Plesiomon and Pukumon are cited climbs on this same "
        "line and any would have served; Leviamon is the one that is a demon lord of the sea, which "
        "is what an evil Seadramon becomes. Coelamon, Ebidramon, Gawappamon, Gesomon and Tesla "
        "Jellymon are all cited `penc-ds` parents as well — this Digimon has no argument anywhere "
        "else. Spirit; `pencds_seadramon` spends stamina on Anomalocarimon and strength on its junk "
        "fall to Piranimon."),
    "weregarurumon_black": (
        "Garurumon (Black) is the SOLE bolded `Evolves From` on Wikimon and CresGarurumon is a "
        "cited `Evolves To` that has been `dmc-v2`'s Mega since US-134 — and Garurumon (Black) had "
        "been a LEAF since US-134 as well, so the bolded arrow clears a dead end and costs nothing. "
        "Metal Garurumon (Black), the page's bolded climb, has no node anywhere and is left for the "
        "Ultimate sweeps; Were Garurumon (X-Antibody), the other name on that list, is a PERFECT "
        "and is authored on `penc-nso` by this same story, which is the one place the two black "
        "wolves part company. Siesamon (`algomon`) and Sangloupmon (`diablomon`) are cited parents "
        "and each would have opened or leaned on another line for no gain. **The criteria are "
        "inverted on purpose**: this is the Digimon a WereGarurumon becomes when it loses, so the "
        "care gate asks for a losing record rather than a winning one — the Lucemon Falldown shape "
        "US-159 recorded. Strength; the fall to Gerbemon takes vitality."),
    "weregarurumon_x": (
        "PLACED BY THE VARIANT RULE IN ITS STRONGEST FORM — SAME PARENT — AND WITH BOTH ENDS CITED. "
        "Garurumon is on Were Garurumon (X-Antibody)'s Wikimon `Evolves From` and `penc-nso` has "
        "its own, `pencnso_garurumon`, which is the very Champion the plain Were Garurumon hangs "
        "off on this line; Metal Garurumon is on the page's `Evolves To` and has been this line's "
        "Mega over that Were Garurumon since US-140. So the variant runs beside its base form under "
        "one Champion and into one Mega, which is the six-of-nine shape US-160 recorded. Were "
        "Garurumon itself is the page's BOLDED parent and is a Perfect, so it can never be an "
        "in-edge, and Metal Garurumon (X-Antibody), the bolded climb, has no node anywhere. Four "
        "lines carry a Were Garurumon and all four cite Metal Garurumon; `penc-nso` was taken "
        "because its Garurumon had one earned branch and three free energies while `penc-nsp`'s and "
        "`penc-vb`'s spend strength on theirs. Stamina."),
    "xingtianmon": (
        "Ginkakumon is a cited `Evolves From` on Wikimon and Seiten Gokuwmon is a cited "
        "`Evolves To` that has been `penc-sw`'s Mega over Gokuwmon since US-158 — both ends cited "
        "on the Saiyu Warriors line, which is where a Chinese myth headless giant belongs. The page "
        "cites only three parents in total and TWO of them are on this line (Lianpumon is the "
        "other, and it carries Sagomon here); Gawappamon on `penc-ds` is the third. Dijiangmon and "
        "Takutoumon are the cited climbs with no node and are left for the Ultimate sweeps. "
        "Vitality; Ginkakumon spends strength on Gokuwmon and stamina on its junk fall to "
        "Pandamon."),
    "yatagaramon": (
        "XV-mon (Black) is a cited `Evolves From` on Wikimon and Hououmon is a cited `Evolves To` "
        "that has been `penc-wg`'s Mega since US-141, so both ends are cited on the Wind Guardians "
        "line — a three-legged crow under the phoenix, which is the pairing this line exists for. "
        "**FALCOMON, THE SOLE BOLDED PARENT, IS IDLE-ONLY IN THIS PACK** (`Idle Frame Only/`, "
        "dexOnly, and `edgeToDexOnlyNode` forbids the edge), which is the MachGaogamon shape US-160 "
        "recorded and the fourth time this series has met it. The plain XV-mon on `adventure02` is "
        "cited too and was not taken because Vermillimon needed that line's junk Champion instead — "
        "see that node's comment — and Birdramon, the remaining cited parent, carries this "
        "Digimon's 2006 variant on this same line. Spirit; XV-mon Black spends stamina on Aero "
        "V-dramon and on its junk fall to TonosamaGekomon, and strength on Paildramon."),
    "yatagaramon_2006": (
        "SITS WITH ITS BASE FORM AND ON A CITED PARENT OF ITS OWN. Birdramon is a cited "
        "`Evolves From` on Wikimon and `penc-wg` has its own, `pencwg_birdramon`, and Griffomon is "
        "a cited `Evolves To` that has been this line's Mega since US-141 — so both ends are cited "
        "and the 2006 design lands on the same line as the plain Yatagaramon above, one Champion "
        "over. **Peckmon, the bolded parent, is a `tamers` leaf and would have split the pair**; "
        "Ravmon and Karatenmon, the two bolded climbs, are both on `wanyamon`, and Cyberdramon, the "
        "third, is a `penc-me` PERFECT — so no line anywhere holds a bolded parent and a bolded "
        "climb together, and the cited pair on `penc-wg` wins outright. Falcomon (2006 Anime "
        "Version), its canonical Child, is idle-only in this pack exactly as the plain Falcomon is. "
        "Stamina; Birdramon spends vitality on Garudamon, spirit on Garudamon X and strength on its "
        "junk fall to TonosamaGekomon."),
    # The three Ultimates.
    "chaosdramon_x": (
        "Cited on BOTH SkullBaluchimon's and Triceramon (X-Antibody)'s Wikimon `Evolves To`, which "
        "is exactly why `commandramon` cost four nodes rather than six: one Mega serves both "
        "Perfects. It is the first Ultimate that line has ever had, paid under US-158's rule, and a "
        "chaos-red machine dragon is what the line of mechanised soldiers — Commandramon, "
        "Sealsdramon, Hi-Commandramon — was always climbing towards. A leaf, as every Ultimate in "
        "this file is."),
    "blackwargreymon": (
        "Vermillimon's cited `Evolves To` on Wikimon, and the first Ultimate `adventure02` has ever "
        "had — the last of the three lines US-161 handed over with no Perfect rung. It belongs here "
        "twice over: BlackWarGreymon is an Adventure 02 character, and this is the Adventure 02 "
        "line. A leaf, as every Ultimate in this file is."),
    "regalecusmon": (
        "Sirenmon's cited `Evolves To` on Wikimon and `vital`'s third Ultimate. Unlike the other "
        "three here it does not open a rung — `vital` gained Zanbamon and Bryweludramon in "
        "US-161 — it exists because Sirenmon has no cited climb with a node ANYWHERE, on this line "
        "or any other, so one had to be authored whichever parent was taken. A deep-sea oarfish "
        "over a siren, on the line that already carries Gekomon, Hookmon, Mantaraymon X and "
        "Seadramon X. A leaf, as every Ultimate in this file is."),
    # The two junk Perfects, both line-scoped aliases.
    "commandramon_karakurumon": (
        "FLAVOUR, AND AN UNCITED ONE — SAID PLAINLY BECAUSE IT IS THE FIRST JUNK FLOOR IN THIS "
        "SERIES THAT WIKIMON DOES NOT DRAW. Neither Damemon nor Ginryumon, the two Champions this "
        "story branches, cites a junk Perfect at all: Damemon's `Evolves To` is Andromon, Cerberumon "
        "X, Cho·Hakkaimon, Lilimon X and MegaloGrowmon X, and Ginryumon's twenty names hold none "
        "either. So the argument is shape rather than citation — Karakurumon is a wind-up automaton "
        "and this is the line of mechanised soldiers, so a soldier that stops drilling seizes into "
        "a clockwork puppet. An ALIAS on the Karakurumon sheet, which `wanyamon` already owns under "
        "the plain id, for the same reason as `vital_darumamon`; it removes no orphan."),
    "adventure02_jyagamon": (
        "FLAVOUR, AND UNCITED LIKE `commandramon_karakurumon` above. Nise Drimogemon's Wikimon "
        "`Evolves To` runs Atlur Kabuterimon (Blue), Digitamamon, DORUguremon, Drimogemon, "
        "Insekimon, Tortamon and Vermillimon, and not one of them is a junk Perfect — but the "
        "moment Nise Drimogemon branches, `EvolutionCriteriaTests` requires a fall onto one of its "
        "OWN line, and `adventure02` had no Perfect rung at all. Jyagamon is the argument shape "
        "makes: a fake mole that keeps digging turns up a potato and nothing else. An ALIAS on the "
        "Jyagamon sheet, which `dmc-v3` already owns under the plain id; it removes no orphan."),
}

ELEMENTS = {
    "sagomon": ("water", "data"),
    "sanzomon": ("light", "vaccine"),
    "saviorhackmon": ("fire", "vaccine"),
    "scorpiomon": ("earth", "virus"),
    "sekkamon": ("ice", "data"),
    "shawujinmon": ("water", "data"),
    "shishimamon": ("fire", "data"),
    "shootmon": ("fire", "data"),
    "sirenmon": ("water", "data"),
    "skullbaluchimon": ("dark", "virus"),
    "superstarmon": ("light", "data"),
    "tekkamon": ("steel", "data"),
    "triceramon": ("earth", "data"),
    "triceramon_x": ("earth", "data"),
    "vamdemon_x": ("dark", "virus"),
    "vermillimon": ("fire", "data"),
    "waruseadramon": ("water", "virus"),
    "weregarurumon_black": ("dark", "virus"),
    "weregarurumon_x": ("ice", "vaccine"),
    "xingtianmon": ("earth", "virus"),
    "yatagaramon": ("dark", "data"),
    "yatagaramon_2006": ("wind", "vaccine"),
    "chaosdramon_x": ("machine", "virus"),
    "blackwargreymon": ("dark", "virus"),
    "regalecusmon": ("water", "data"),
    "commandramon_karakurumon": ("machine", "virus"),
    "adventure02_jyagamon": ("plant", "virus"),
}

# id -> (projectileSymbol, tint, signatureName, signatureSymbol)
# `projectileSymbol|tint` must be unique WITHIN a line and `signatureName` GLOBALLY; `check()`
# below proves both against the real files before anything is written.
MOVES = {
    "sagomon": ("drop.fill", "teal", "River Sand Crush", "drop.fill"),
    "sanzomon": ("sparkles", "white", "Sutra Seal", "sparkles"),
    "saviorhackmon": ("shield.fill", "white", "Savior Fang", "shield.fill"),
    "scorpiomon": ("scissors", "yellow", "Scorpion Tail Blade", "scissors"),
    "sekkamon": ("snowflake", "white", "Snowflake Dance", "snowflake"),
    "shawujinmon": ("hand.raised.fill", "red", "Crescent Spade", "hand.raised.fill"),
    "shishimamon": ("flame.fill", "orange", "Shrine Lion Wave", "flame.fill"),
    "shootmon": ("flame.fill", "red", "Shooting Knuckle", "flame.fill"),
    "sirenmon": ("music.note", "blue", "Siren Song", "music.note"),
    "skullbaluchimon": ("hammer.fill", "brown", "Bone Trample", "hammer.fill"),
    "superstarmon": ("star.fill", "yellow", "Hollywood Meteor", "star.fill"),
    "tekkamon": ("hammer.fill", "gray", "Iron Fire Blade", "hammer.fill"),
    "triceramon": ("hammer.fill", "gray", "Tri Horn Attack", "hammer.fill"),
    "triceramon_x": ("shield.fill", "brown", "Wild Horn Cross", "shield.fill"),
    "vamdemon_x": ("moon.fill", "gray", "Crimson Bat Cross", "moon.fill"),
    "vermillimon": ("flame.fill", "red", "Vermillion Flare", "flame.fill"),
    "waruseadramon": ("drop.fill", "red", "Evil Icicle", "drop.fill"),
    "weregarurumon_black": ("hand.raised.fill", "gray", "Black Moon Kick", "hand.raised.fill"),
    "weregarurumon_x": ("snowflake", "indigo", "Garuru Kick Cross", "snowflake"),
    "xingtianmon": ("hammer.fill", "red", "Headless Axe", "hammer.fill"),
    "yatagaramon": ("wind", "white", "Three Legged Raven", "wind"),
    "yatagaramon_2006": ("wind", "yellow", "Mikafutsu no Kami", "wind"),
    "chaosdramon_x": ("bolt.fill", "red", "Chaos Cannon Cross", "bolt.fill"),
    "blackwargreymon": ("flame.fill", "gray", "Terra Destroyer", "flame.fill"),
    "regalecusmon": ("drop.fill", "indigo", "Deep Sea Ribbon", "drop.fill"),
    "commandramon_karakurumon": ("gearshape.fill", "brown", "Clockwork Seize", "gearshape.fill"),
    "adventure02_jyagamon": ("leaf.fill", "yellow", "Potato Barrage", "leaf.fill"),
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

    # Every climb target must already exist, on the Perfect's own line and at the top rung.
    for pid, _, _, new_line, _, _, ultimate, _ in PERFECTS:
        if ultimate in by_id:
            if by_id[ultimate]["line"] != new_line:
                sys.exit("%s climbs off its line into %s" % (pid, ultimate))
        elif ultimate not in [u[0] for u in ULTIMATES]:
            sys.exit("%s climbs into %s, which does not exist" % (pid, ultimate))


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

    # 2. the twenty-two Perfects, each a single isDefault climb, the shape every Perfect in the
    #    file has carried since US-134.
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

    # 4. the three Ultimates, terminal and so with no `evolutions` key at all.
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
