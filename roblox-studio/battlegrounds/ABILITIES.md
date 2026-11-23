# Anime ability checklist (scope: released TV anime + Jujutsu Kaisen 0; manga-only material excluded)

**Source-audit status: NOT DONE.** This environment cannot play or read the episodes, so the "reference" column is the best-known location and **must be checked against the episodes**.
Nothing marked "pending" has been seen on screen. "Offline" means only the pose solver / rule tests ran (`verify/run.py`). **No row is visually verified.** Timestamps are in this build (`mm:ss`, 30 fps frames).

Types: **I** = innate trait, **T** = technique, **E** = equipment, **X** = effect caused by another character.

| # | Who | Ability | Type | Era / reference (to verify) | Build time (frames) | What the audience should see | Status |
|---|---|---|---|---|---|---|---|
| 1 | Gojo | Six Eyes / cursed-energy perception | I | Hidden Inventory (teen) | 0:01 (30-50), 0:02 (58) | Eyes move to Toji before the head turns (eye keys), Toji reflected in the glasses | Offline-tested (eye keys exist); the subjective Six-Eyes POV shot is **pending** (only a POV shot of the empty stair exists, 1:29) |
| 2 | Gojo | Cursed-energy reinforcement, close combat | T | Hidden Inventory / Shibuya | 2:20-2:55 (4200-5250, chapter 6 exchange) | evasive micro-movements | Offline-tested; the requested single uninterrupted full-body exchange with distinct footwork/impacts is **pending** (chapter 6 is sparse) |
| 3 | Gojo | Neutral Limitless / Infinity | T | Hidden Inventory | 0:20 pebble (612-700), 0:30 fist stop (906-1020) | pebble stops at the cheek, fist hangs a 0.5-stud gap, dust suspended while the courtyard keeps moving | Offline-tested (0.5 stud gap measured); on-screen **pending** |
| 4 | Gojo (adult) | Infinity selective filtering (two objects) | T | Shibuya | 4:00 on (7200-7500) | a leaf passes through, a stone stops | Written; **pending** visual check |
| 5 | Gojo | Blue | T | Hidden Inventory / S1 | 0:50 (1500-1740) | grit, tiles tilt, slab slides toward a point | Written; **pending** |
| 6 | Gojo (adult) | Maximum Output Blue | T | Shibuya | 4:12 (7560-7900) | wide shot, tiles within 26 studs pulled and lifted | Written; **pending** |
| 7 | Gojo | Reverse cursed technique | T | Hidden Inventory | 1:55 (3450-4200) | breathing steadies, posture and movement recover in sequence, soft sparkles | Written (breathing keys, rise keys, small particles); **pending** |
| 8 | Gojo | Red | T | Hidden Inventory | 2:25 (4342) | red core, dust running outward, Toji thrown back | Written; **pending** |
| 9 | Gojo | Hollow Purple | T | Hidden Inventory | 3:35-4:00 (6450-7200) | blue + red converge, violet core, beam along a lane, tiles cleared | Written; **pending** |
| 10 | Gojo | Spatial movement (short reposition, long transport) | T | Shibuya (verify) | 4:28 (8040 short), 4:41 (8203 long) | three studs in four frames, then gate to walkway | Written; **pending**; anime reference **unverified** |
| 11 | Gojo | Barriers / curtains | T | S1 (verify) | 4:35 (8240-8399) | translucent dark dome | Placeholder only; application **unverified in the anime**, **pending** |
| 12 | Gojo (adult) | Domain Expansion: Unlimited Void | T | S1/Shibuya (verify) | 4:40-5:10 (8400-9300) | barrier closes (wide), interior with distant light and layered streams, opponent stalls, release | Written; **pending** (never seen on screen) |
| 13 | Gojo | Unlimited Void, 0.2 s application | T | Shibuya (verify) | 5:10-5:18 (9300-9540; domain frames 9420-9425) | six frames of the void, anticipation and aftermath | Written; **pending** |
| 14 | Toji | Heavenly Restriction (zero cursed energy; strength, speed, senses) | I | Hidden Inventory | 0:05 (150-166), 2:20 (4290-4340) | gate-to-pillar burst, hard to track | Offline-tested; the "heightened senses" beat is **pending** |
| 15 | Toji | Inventory curse (storage, retrieval, equipment change) | E | Hidden Inventory | 1:21 (2440-2494) | jaw opens, spear drawn out of the mouth | Written; mid-scene equipment change **pending** |
| 16 | Toji | Fly Heads | E | Hidden Inventory | 1:27 (2600-2760) | swarm around Gojo, Gojo's POV, empty stair, wide reveal | Written; **pending** |
| 17 | Toji | Inverted Spear of Heaven | E | Hidden Inventory | 1:30 (2716) | Infinity first, then folds inward at contact | Offline-tested (contact solved); **pending** visual |
| 18 | Toji | Chain of a Thousand Miles | E | Hidden Inventory | 2:58-3:35 (5340-6449) | sweep, return, airborne crossing | Written; far end in the curse is approximate; **pending** |
| 19 | Toji | Split Soul Katana vs a curse construct | E | Hidden Inventory (verify) | - | - | **NOT BUILT** |
| 20 | Toji | Ordinary blade / handgun (non-graphic) | E | Hidden Inventory (verify) | - | - | **NOT BUILT** |
| 21 | Toji | Shibuya séance manifestation + Playful Cloud over water | X + E | Shibuya (**verify that the anime shows this**) | 5:18 (9540-10289) | slack body, eyes snap open, three-section staff, water rings, construct knocked back | Written first pass; **pending**; scope **unverified** |
| 22 | - | Chapter-start states (glasses, spear, chain, tiles) | - | - | all chapters | direct selection starts correctly | Offline: states are pure functions of the frame; **pending** in Studio |

Open scope questions: confirm in the episodes whether the barrier/curtain demo, the Shibuya séance Toji and the spatial-transport application appear in the anime as described; drop any that do not.
