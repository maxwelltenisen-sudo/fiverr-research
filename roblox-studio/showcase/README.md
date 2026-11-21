# Blue vs Purple combat showcase (Roblox Studio, R15)

A replayable ~10 s exchange: guard stances, Blue's step-in + jab, committed rear-hand strike,
Purple's raised-forearm block, clash hold, Purple's pivoting counter, Blue's hit reaction + recovery step,
both back in guard. Authored as **editable keyframe data**, solved with FK + two-bone IK so feet stay
planted and the fist lands exactly on the forearm.

## Files
| File | Where it goes in Studio | What it does |
|---|---|---|
| `ShowcaseData.lua` | ModuleScript `ShowcaseData` in ReplicatedStorage | **The editable animation source** (keys, contacts, markers, VFX windows, cameras) |
| `ShowcaseEngine.lua` | ModuleScript `ShowcaseEngine` in ReplicatedStorage | Pose solver: FK/IK, keyframe expansion, contact baking |
| `ShowcaseBuilder.server.lua` | Script in ServerScriptService | Stage, lighting, both R15 rigs and costumes (hair, scarf chain, collar, bracers, trims) |
| `ShowcaseDirector.client.lua` | LocalScript in StarterPlayer > StarterPlayerScripts | Playback, camera, markers, VFX, scarf lag, on-screen checks |
| `Install_Showcase.lua` | paste into the Command Bar | Creates the four scripts above and disables (does not delete) older story scripts |
| `verify/` | not used in Studio | Re-runs my solver checks on a mock rig: `pip install lupa && python3 verify/run.py` |

## Replay it
1. View > Command Bar, paste `Install_Showcase.lua`, press Enter (or create the four scripts by hand using the table above).
2. Test > Play. Pass 1 plays with **VFX OFF**, pass 2 with **VFX ON**, then it loops with VFX on.
3. Keys: `R` replay, `V` VFX on/off, `B` slow motion (0.25x), `Space` pause, `,` `.` step a frame while paused,
   `C` contact inspector (freezes at the clash, cycles side camera A and top camera B, prints measurements).
4. Output window lines starting `[SHOWCASE CHECK]` report clash gap, counter miss, foot slide, lowest foot height and return-to-guard error.

## Editing the animation
Open `ShowcaseData`. Every key inherits the previous key; list only what changes. Names map to the brief:
`guard`, `stepIn_*` (step-in), `jab`, `rear_load`/`rear_drive`/`CONTACT` (heavy strike), `block_set`/`block_absorb` (block),
`counter_load`/`COUNTER_HIT` (counter), `HIT_REACT`, `recover_step_*`, `return_*`. A foot only moves when its key lists `rf`/`lf`
(otherwise it stays planted at the exact same world point). `CONTACT` hand targets are baked from the defender's forearm,
so do not hand-edit those; move the forearm pose instead.

## Honest limits
* Written without Studio access; verified on a mock R15 rig, not in Studio. Expect small first-run fixes.
* No Animation asset IDs are used or invented: the motion is procedural keyframe data, played client-side (Motor6D.Transform).
  To get Animation Editor / publishable assets you would have to re-key it there by hand and publish under your account.
* There is no gameplay in this project, so there is no hit detection; if you add combat later keep hit detection on the server.
