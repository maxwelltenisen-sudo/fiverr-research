# Roblox Studio story scene

Builds a small map and plays the story "The new player nobody wanted" by script,
so every take looks identical.

## Setup (Roblox Studio, free, PC/Mac)
1. Open Studio > New > **Baseplate**.
2. In the Explorer, add a **Script** to `ServerScriptService`. Paste `StoryBuilder.server.lua` into it.
3. Add a **LocalScript** to `StarterPlayer > StarterPlayerScripts`. Paste `CameraAndCaptions.client.lua` into it.
4. Press **Play** (F5). Watch the Output window: it prints `SCENE 0X: START RECORDING` / `STOP RECORDING`.

## Record
- Start your screen recorder when a scene starts, stop when it ends. Name the files
  `01_spawn.mp4`, `02_asking.mp4`, `03_tourney.mp4`, `04_win.mp4`, `05_end.mp4` and put them in
  `../roblox-video-pipeline/clips/`. Then run `build_video.py`.
- Replay a single scene by editing `SCENES_TO_PLAY` at the top (e.g. `{2}`).
- Keep the action in the centre of the frame: the video tool crops the wide recording to vertical.

## Limits
- Written and syntax-checked without access to Roblox, so it has not been run in Studio.
  If anything errors, paste the Output message to me.
- Characters are plain coloured R15 rigs. To use your own mascot, swap `makeNpc` for a model from your avatar.
- Animation ids are Roblox's standard R15 ones; if one doesn't play, replace it in the `ANIM` table.

## Combat scene (Gojo-style vs Toji-style)
`CombatScene.server.lua` is a second Script for a 4-scene fight: standoff, clash against a barrier,
a blade breaking through, then blue + red energy merging into a purple blast. It also needs
`CameraAndCaptions.client.lua` (updated with screen shake and zoom). Use it **instead of** StoryBuilder
(disable one of the two Scripts). If punches swing backwards, set `ARM_SIGN = -1` at the top.
Untested in Studio. The characters are built from simple parts (hair, blindfold, scar, knife), so no
asset ids are needed. These are fan-made versions of anime characters: fine for a fan channel, but
monetised videos can get copyright claims, so original characters are safer long term.

## Combat scene v2 (dark ruins, lightning, post-processing)
`CombatScene_v2.server.lua` replaces the first combat script (delete or disable the old one).
Adds fog, bloom, a purple moon, ruins, floating rocks, fighters with spiky hair / scarf / cloak /
glowing trim, speed trails, lightning, shockwaves and tilted fast camera cuts. It prints `DEBUG`
lines so problems are easy to diagnose. Untested in Studio.
