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
