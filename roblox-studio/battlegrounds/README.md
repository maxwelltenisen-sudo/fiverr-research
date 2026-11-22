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
   **Or paste:** copy all of `Install_Battlegrounds.lua`, paste it into **View > Command Bar** (or the Output window's command line), press Enter. It prints `created ...` 11 times.
   **Or Rojo:** `rojo serve` in this folder (uses `default.project.json`).
   **Or by hand:** create the 11 scripts in the table below and paste each file.
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
| ReplicatedStorage | ModuleScript | BGCinematicData | BGCinematicData.lua (EDITABLE cinematic keyframes, contacts, cameras, markers) |
| ServerScriptService | Script | BGBuilder | BGBuilder.server.lua (arena + the two rigs and costumes) |
| ServerScriptService | Script | BGServer | BGServer.server.lua (runs BGCore, validates input) |
| StarterPlayer > StarterPlayerScripts | LocalScript | BGClient | BGClient.client.lua (playable mode: input, posing, VFX, forms, camera, UI) |
| StarterPlayer > StarterPlayerScripts | LocalScript | BGDirector | BGDirector.client.lua (cinematic replay) |

Older story/showcase Scripts and LocalScripts are disabled by the installer, not deleted.

## Controls
Playable: **WASD** move (W = toward the opponent) | **LMB** combo | **Q E R C** skills | **hold F** guard | **G** counter / riposte | **X** first form (50%) | **Z** final form (100%) | **T** ultimate | **Tab** playable <-> cinematic.
Cinematic: **R** replay | **B** slow motion | **V** VFX on/off | **Space** pause | **, .** step | **C** contact inspector (side camera, then top camera, prints the measured gap). The same buttons are in the left panel.

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
