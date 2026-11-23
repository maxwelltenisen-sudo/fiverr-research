# Kael vs Ren: Roblox battlegrounds showcase

Two original blocky fighters (Kael = blue, Ren = purple), a playable practice mode with a server-authoritative combat core,
power forms and ultimates, and an 8-12 s cinematic replay of the fist-to-forearm clash. R15 rigs, built from code, no Marketplace assets.

> **Status.** The rules (combat, meter, forms, ultimates, resets), every clip's pose solve and the cinematic clash were checked
> offline on a mock rig (`verify/`). **Nothing in this folder has been run inside Roblox Studio yet.** The Studio checklist at the bottom lists what to confirm.
> I could not see the attached reference image in this session: the look follows your written brief (blocky proportions, electric blue vs violet, dark layered outfits, fist-to-forearm clash).

## Launch in Studio (exact steps)
1. Open your place. Stop any running Play session.
2. **Easiest:** the Roblox Studio connector in your local Claude Code can install it for you. In the repo folder run `claude` and say:
   *"Install roblox-studio/battlegrounds into my open Studio place from the source files (see README), press Play, read the Output and fix errors."*
   **Or paste:** copy all of `Install_Battlegrounds.lua`, paste it into **View > Command Bar** (or the Output window's command line), press Enter. It prints `created ...` 14 times.
   **Or Rojo:** `rojo serve` in this folder (uses `default.project.json`).
   **Or by hand:** create the 14 scripts in the table below and paste each file.
3. **Test > Play** (not Run). The cinematic replay starts: pass 1 with VFX off, pass 2 with VFX on, then it loops.
4. Press **Tab** (or the *Playable* button) to fight. The left panel picks the fighter (Kael / Ren), dummy behaviour (Idle / Guard / Attack) and, in Studio only, jumps to Base / First form / Final form.

| Put it in | Class | Name | File |
|---|---|---|---|
| ReplicatedStorage | ModuleScript | BGEngine | BGEngine.lua (pose solver: FK, two-bone IK, planted feet) |
| ReplicatedStorage | ModuleScript | BGConfig | BGConfig.lua (every number: damage, ranges, cooldowns, thresholds, timers) |
| ReplicatedStorage | ModuleScript | BGClips | BGClips.lua (EDITABLE ANIMATIONS: keyframes + markers for every clip) |
| ReplicatedStorage | ModuleScript | BGCore | BGCore.lua (server rules, no instances) |
| ReplicatedStorage | ModuleScript | BGCloth | BGCloth.lua (scarf / coat lag) |
| ReplicatedStorage | ModuleScript | BGRig | BGRig.lua (reads R15 joints) |
| ReplicatedStorage | ModuleScript | BGStyle | BGStyle.lua (shards, ring slashes, floor cracks, speed lines, flashes, ink frame) |
| ReplicatedStorage | ModuleScript | BGDuel | BGDuel.lua (**THE 4-minute timeline: poses, chapters, camera, effects, costume states, sound, slow motion, by frame**) |
| ReplicatedStorage | ModuleScript | BGLook | BGLook.lua (night / neutral lighting presets + the light audit) |
| ReplicatedStorage | ModuleScript | BGCinematicData | BGCinematicData.lua (colour palette only; the old cinematic data is no longer played) |
| ServerScriptService | Script | BGBuilder | BGBuilder.server.lua (arena + the two rigs and costumes) |
| ServerScriptService | Script | BGServer | BGServer.server.lua (runs BGCore, validates input) |
| StarterPlayer > StarterPlayerScripts | LocalScript | BGClient | BGClient.client.lua (playable mode: input, posing, VFX, forms, camera, UI) |
| StarterPlayer > StarterPlayerScripts | LocalScript | BGDuelPlayer | BGDuelPlayer.client.lua (plays BGDuel by elapsed time; chapters, preview) |

Older story/showcase Scripts and LocalScripts are disabled by the installer, not deleted.

## Controls
Playable: **WASD** move (W = toward the opponent) | **LMB** combo | **Q E R C** skills | **hold F** guard | **G** counter / riposte | **X** first form (50%) | **Z** final form (100%) | **T** ultimate | **Tab** playable <-> cinematic.
Cinematic: see "Controls (cinematic)" in the duel section.

## The Gojo vs Toji duel (teen Gojo, Hidden Inventory look; original choreography, models, animation)
**Status: written and checked offline only. Nothing here has run in Studio yet. Read "Not verified" below.**
One timeline, `BGDuel.lua`: 30 fps, frames 0-7199 = the 4:00 duel in 8 chapters, 7200-7799 = the optional 0:20 epilogue. Poses are macros and footwork is generated
(a footstep every ~0.9 studs, dash trails, plants). Chapters, camera shots, effects, costume states (glasses / spear / chain / tiles), sound cues, the music envelope and
slow motion are all frame numbers in that file. Every state is a function of the frame, so every chapter starts correctly when selected.

| # | Time | Chapter | Question |
|---|---|---|---|
| 1 | 0:00 | Who moved first? | glasses close-up, Toji's reflection, wide (stair / broken pillar / gate), gate-to-pillar burst, both faces in the first 10 s |
| 2 | 0:20 | Infinity | pebble slows at the cheek; ordinary strike stops a visible gap short (slow motion); feint, then Toji studies him |
| 3 | 0:50 | Blue | grit, tiles tilt, slab slides; Toji rides it over Gojo to the stair (one continuous shot); fight moves to the walkway |
| 4 | 1:20 | Toji takes control | curse uncoils, spear, Fly Heads, Gojo's POV, wide reveal, the Infinity fold, Gojo down (stylised) |
| 5 | 1:55 | Awakening | music drops; hand on a tile, breathing, uncovered eyes; footstep behind Toji; Gojo discovered standing |
| 6 | 2:20 | Red | opening angle repeated; red core repels Toji; fast exchange, Gojo evades with tiny movements |
| 7 | 2:55 | Toji's full arsenal | chain of a thousand miles: sweep, return, airborne crossing |
| 8 | 3:35 | Hollow Purple | blue + red converge, violet core, wide release with the pillar, cleared lane, glasses settle on a broken step |
| 9 | 4:00 | Years later - Unlimited Void (epilogue) | adult outfit, blindfold, one eye revealed, abstract field, suspended dummy |

**Characters (`BGBuilder.server.lua`)** Gojo ("Blue" rig): tall slender, layered irregular white hair clumps with grey roots and gaps over the forehead, small round dark glasses (removable: a loose prop takes over when they leave his face),
pale brows, bright blue irises, dark high-collar uniform; the adult outfit and blindfold are hidden parts used in the epilogue. His eyes find Toji before his head turns (`D.eyes`).
Toji ("Purple" rig): broad shoulders, tapered waist, bare strong forearms, straight black hair over the forehead, narrow green eyes, scar at the right corner of the mouth, fitted black short-sleeve shirt, loose pale trousers gathered at the ankles, dark shoes, no glow.
The inventory curse is a muted purple band around his torso plus a head (eyes, teeth) and a tail on cloth chains that lag the body. Spear and chain are parts the timeline shows and hides.
Both rigs share one skeleton scale (the solver needs it), so "tall" and "broad" come from the clothing and hair volume. No custom mesh or texture was used: the places a mesh or texture would raise the likeness most are Gojo's hair silhouette (a sculpted mesh), the uniform collar, and Toji's face and shirt texture.

**Controls (cinematic)** `1-9` jump to a chapter | `[` `]` previous / next | `R` full replay | `Space` pause | `, .` step a frame | `B` slow motion | `V` effects | `F` fixed wide camera | `N` neutral light | `H` HUD and panel (hidden by default) | `C` measured checks | `P` character preview | `Tab` playable.
**Character preview (`P`)**: neutral flat light, both characters standing side by side; `Left`/`Right` cycles front Gojo, profile Gojo, front Toji, profile Toji, the fight camera at medium distance, a Gojo close-up and a Toji close-up; `G` toggles the glasses; `N` neutral / dusk.
Slow motion is automatic only on the first Infinity stop (frames 906-960) and the beat before Purple (6860-6900). Playback uses elapsed time; the first full playthrough prints its measured real running time.

**Checked offline on the mock rig (`python3 verify/run.py`)**: 7800 frames = 260.0 s (240.0 duel + 20.0 epilogue); Infinity stop leaves a 0.5-stud gap; spear contact hand miss 0.000; limbs reach their targets (worst per chapter 0.00-0.59 studs, the 0.59 is the leap in chapter 3);
no foot sinks more than 0.31 studs (worst on Gojo's seated pose), no more than 21 frames per chapter with a wrist inside a torso (chapters 2 and 7), joint-speed peaks of 105-123 degrees per frame in the fastest strikes.
**Not verified (needs Studio):** every visual: both faces and the scar / glasses at medium distance, hair profiles, front / profile / fight-camera stills, whether the effects read, the camera cuts, the audio (built-in `rbxasset://sounds` files, unconfirmed), real running time, floor and hair exposure, the chapter-start states on the real rig, the contact checks (`C`), and the Gojo POV shot.
Chapters 4-7 are blocked in at a first-pass level (the choreography keys are sparse: long holds and few intermediate poses), so expect to polish timing and add keys. Capture was not available to me.

## Lighting and the "white head / white floor" audit
`BGLook.audit()` runs when the player starts and prints bloom, exposure, colour correction, large Neon parts, reflective parts, Highlights and lights (`[LOOK]` lines). Dusk look: bloom only above threshold 2.0 (white hair keeps detail),
exposure 0, no reflectance, matte stone (mid-grey, never white) and clothing, glow only on small effect parts. `N` gives flat neutral light with all post effects off.

## Visual style (reference: anime-cinematic VFX reel)
Blue and violet stay the only colours on a high-contrast, desaturated, dark glossy arena with a dark vignette and drifting motes.
Effects are shaped, short and tied to the action: sharp shards and crossing ring slashes with a white flash on hard hits, radiating speed lines,
cracked-glass lines racing over the floor on slams, a white "ink" frame with black speed lines on Thunderfall, close-up and top-down camera cuts with a FOV punch and tilt on big hits.
Ren has two long cloth hair tails. All of it lives in `BGStyle.lua` (+ the event handlers in `BGClient`); in the cinematic it only fires when VFX is on, so the VFX-off review stays clean.

## Combat feel (tuning)
* **Speed:** `BGClips.lua` is authored at 1.0 and played at `Clips.DEFAULT_SPEED = 0.78` (22% shorter). Lower = faster. Walk speeds are in `BGConfig.char`.
* **Hit-stop:** `BGConfig.hitstop` (light 0.05 s, big 0.095 s, block 0.03 s): both fighters freeze on contact. Longer = heavier.
* **Forms:** `BGConfig.form`: Charged/Rift Mode +15% damage, +15% swing speed, +12% move speed; Final form +40% / +30% / +25%. Power forms also get a body aura, a torso glow and speed afterimages.
* **M1 lunges** travel 1.1-2.2 studs per hit so the combo keeps pressure; the final palm / palm knock back 6-7 studs. M1 presses up to 0.45 s early still chain.

## Moves
| | Kael | Ren |
|---|---|---|
| M1 (4 hits, each with its own contact marker) | Quick Jab > Cross > Body Hook > Rising Palm (only the palm pushes back) | Guard Jab > Short Elbow > Turning Backfist > Heavy Palm (long anticipation, heavy recovery) |
| Q | Flash Step: dash, zero damage, one blue afterimage (Charged: 2 charges) | Anchor Step: planted stance, armour (resists stagger / knockback), cannot move, release push |
| E | Arc Breaker: wind-up lunge; hit = stagger, block = absorbed, miss = Kael "open" (Charged: longer stagger). Final: **Storm Pierce** | Gravity Pulse: palm to the floor, violet ring pushes nearby opponents out (Rift Mode: more range) |
| R | Sky Current: rising strike lifts the opponent; press R again in the window for the slam | |
| C | Static Slip: evasive step; a timed dodge unlocks one counter (G) | |
| F (hold) | Guard (absorbs 85%) | Rift Guard: block; press F **just before** the hit (0.25 s) for a timed block: attacker staggered, riposte window opens. Final: **Eclipse Guard** stores energy |
| G | Counter (after a dodge, 1.1 s) | Void Counter (after a timed block, 1.0 s; stored Eclipse energy empowers it) |
| X | Charged Mode: seams light, longer scarf, hand sparks, 2nd Flash charge, longer Arc stagger | Rift Mode: bracer lines + coat lining glow, shield ripples on blocks, Gravity Pulse range up |
| Z | Thunder Ascension (12 s): blue-white eyes, bright guards, electric outline | Eclipse Form (12 s): rim-lit silver hair, violet eyes, translucent bracer layers, orbiting fragments |
| T | **Thunderfall**: launch, leap, slam, one expanding ground ring | **Event Horizon**: telegraphed floor field, inward pull, one outward blast |

Meter: landed hits and successful defence (block, timed block, dodge, landed counters) build it; whiffs give nothing. 50% enables the first form
(activation lifts the meter to 75% so it does not end at once; it then drains 4/s and returns to Base at 50%). 100% enables the final form directly from Base or the first form.
The final form lasts 12 s, the ultimate is single-use, and when the form ends (after the ultimate's recovery, or at timeout) the meter resets to 0.
No actions during transformations (they are invulnerable); `BGCore:reset()` clears forms, timers, cooldowns and effects.

## Animations: what is editable and what is not
* All motion lives in `BGClips.lua` (Kael and Ren) and `BGCinematicData.lua` (the cinematic) as readable keyframes: body shift, crouch, lean, twist, hand targets, foot placement, elbow poles, with eases and named markers
  (`contact_*`, `windup_charge`, `pulse_*`, `anchor_*`, `redirect_arc`, `afterimage`, `timed_ripple`). Feet stay planted unless a key moves them; hands are solved with two-bone IK.
* These are **procedural keyframes played by the client**, not Roblox Animation assets: **there are no animation asset IDs** and nothing was published. Roblox animation IDs are created by uploading from the Animation Editor under your account.
  To get real IDs: re-key a clip in the Animation Editor (Plugins > Animation Editor) on a rig from `BGBuilder`, publish it, and play it with an `Animator`. I did not do that because I cannot upload to your account.
* R15 only. R6 would need its own clips.
* Combat gameplay already in the project was not touched: the old Gojo/Toji scene scripts are disabled by the installer.

## Verification done here (mock R15 rig, `verify/`, `pip install lupa && python3 verify/run.py`)
* 70 rule checks (`core_test.lua`): combo order / damage / push, whiffs build no meter, Arc Breaker hit / block / miss, timed Rift Guard and late counter refusal, Static Slip and counter,
  Sky Current + follow-up, 50% / 100% thresholds, drain, final timer, ultimates once, reset, repeated replays, no overlaps, dummy AI.
* 44 clips (`clips_test.lua`): every pose solves, no reach misses over 0.12 stud, no elbow flips (a solver guard keeps fists out of the shoulder).
* Cinematic (`cin_*.lua`): clash gap -0.005 stud, counter miss 0.03, return-to-guard error 0, no pops.

## Still to check in Studio
1. Both fighters appear, face each other, costumes read clearly with VFX off (key V in cinematic, or Studio's effects).
2. Cinematic: `[SHOWCASE CHECK]` lines in Output; press **C** and compare the side and top views of the clash; confirm both bodies react on the contact frame.
3. Playable: every move above against the dummy (set it to Attack to test Static Slip and timed Rift Guard); meter ticks at 50 / 100; forms, ultimates, reset (Reset fight button).
4. Foot sliding while walking / dashing (the walk cycle is matched to the move speed, dashes slide by design), body clipping in the heavy poses, scarf / coat lag.
5. Face and hair proportions at gameplay distance. Costume parts are plain Parts, easy to resize in `BGBuilder.server.lua`.
6. Instance Streaming: `BGBuilder` sets `ReplicationFocus` on the arena; if the arena is missing in a place with streaming enabled, untick Workspace > StreamingEnabled.
