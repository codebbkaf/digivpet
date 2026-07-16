# Ralph Loop — Digimon Health V-Pet (watchOS)

You are one iteration of an autonomous loop. You have NO memory of previous iterations.
Everything you need is in this file, `prd.json`, `progress.txt`, and `tasks/prd-digimon-health-vpet.md`.

**Do exactly ONE user story this iteration, then stop.**

---

## Environment (verified — do not re-derive)

- Xcode 26.4.1 lives at `/Applications/Xcode_26_4_1.app`.
- **`xcode-select` may still point at CommandLineTools.** Always export this before ANY xcodebuild/xcrun call:
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode_26_4_1.app/Contents/Developer
  ```
- watchOS SDK: `watchos26.4` / `watchsimulator26.4`.
- Simulators available:
  - watchOS 26.4 — Apple Watch Series 11 (42mm), Series 11 (46mm)
  - watchOS 10.4 — Apple Watch Series 9 (41mm), Series 9 (45mm), Apple Watch Ultra 2 (49mm)
- `xcodegen` 2.46.0 is installed. The Xcode project is generated from `project.yml` — **never hand-edit `.xcodeproj`**; edit `project.yml` and re-run `xcodegen generate`.
- Sprites live in `16x16 Digimon Sprites/` (bundle as a folder reference, NOT an asset catalog).
- Git repo, branch `ralph/digimon-health-vpet`.

## Build and test commands

```bash
export DEVELOPER_DIR=/Applications/Xcode_26_4_1.app/Contents/Developer
xcodegen generate

# Build — this is what "Typecheck passes" means
xcodebuild build \
  -project DigiVPet.xcodeproj -scheme DigiVPet \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'

# Test
xcodebuild test \
  -project DigiVPet.xcodeproj -scheme DigiVPet \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

---

## Your procedure this iteration

1. **Read `progress.txt`** to see what previous iterations did. Do not redo their work.
2. **Read `prd.json`.** Find the FIRST story with `"passes": false`, ordered by `priority`. That is your story. Only that one.
3. **Read `tasks/prd-digimon-health-vpet.md`** for context — it holds the verified sprite layout, energy model, and asset facts. Trust it over your own assumptions.
4. **Implement the story.** Small, focused change. Match the style of surrounding code.
5. **Verify EVERY acceptance criterion literally.** Run the build. Run the tests. A criterion is met only if you actually observed it pass — never because the code looks right.
6. **If and only if all criteria pass**, set that story's `"passes": true` in `prd.json` and put a one-line summary in its `"notes"`.
7. **If you could not finish**, leave `"passes": false` and write what you tried and what blocked you into `"notes"`. This is a success — an honest note is worth more than a false pass. The next iteration depends on it.
8. **Append to `progress.txt`**: date, story id, what you did, what passed, what remains.
9. **Commit**: `git add -A && git commit -m "US-XXX: <title>"`.
10. **If every story in `prd.json` now has `"passes": true`**, output exactly: `<promise>COMPLETE</promise>`

---

## Rules

- **One story per iteration.** Do not start the next one, even with context to spare.
- **Never mark `passes: true` without running the build and observing it succeed.** A false pass poisons every later iteration, because they trust it and build on top of it.
- **Never fake, stub, or skip a test to make it green.** If a test is wrong, say so in `notes`.
- **Never hand-edit `.xcodeproj`** — edit `project.yml`, re-run `xcodegen generate`.
- **Sprite rendering must use `.interpolation(.none)`.** Smoothed pixel art is a bug.
- **Sprite sheets are 48×64 = a 3×4 grid of 16×16 frames**, row-major, indices 0–11: walk1, walk2, eat1, eat2, sleep1, sleep2, refuse, happy, angry, hurt1, hurt2, attack. Digitama are 48×16 = 3 frames. Slice with `x = (i % 3) * 16`, `y = (i / 3) * 16`.
- **Do not invent Digimon names or sprite paths.** Every `spriteFile` must exist on disk — verify with `ls` before referencing it. 157 Digimon exist ONLY in `Idle Frame Only/` with no animated sheet (e.g. Poyomon, Ankylomon, Aquilamon); those are `dexOnly` and must never be playable or appear in an evolution edge.
- **The clock must be injectable** for anything time-based (hunger, sickness, death, stage gating). Tests must never wait real time.
- **HealthKit has no data in the Simulator by default.** Test energy/health logic against injected fixture samples, not live queries.
- If a story is genuinely too big for one iteration, do the coherent first part, note precisely where you stopped, and leave `passes: false`.

## Definition of done

- Every acceptance criterion observed to pass, build green.
- Work committed.
- `prd.json` and `progress.txt` reflect reality — including failures.
