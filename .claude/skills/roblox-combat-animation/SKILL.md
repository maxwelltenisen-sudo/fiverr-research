---
name: roblox-combat-animation
description: Build realistic, readable Roblox (R15) combat and anime-style cinematic fight animation in code - keyframed poses with two-bone IK, planted feet, verified contacts, frame-based timelines with chapters, cameras, VFX and sound cues. Use when the user wants fight scenes, character close-ups, power effects (Infinity, Blue, Red, Purple, domains), or says "make the animation realistic / feel like combat".
---

# Roblox realistic combat animation (what actually worked in this repo)

Reference implementation: `roblox-studio/battlegrounds/` (BGEngine, BGClips, BGDuel, BGDuelPlayer, BGBuilder, verify/). Read BGEngine.lua and BGDuel.lua before writing new animation.

## 0. Be honest about verification
Claude cannot see Studio unless a Studio connector (Roblox_Studio MCP in the user's local Claude Code) is attached. Label every item **visually verified / offline-tested only / pending**. Never claim a shot looks good without seeing it. Never claim an ability exists in the anime without a source; mark references "to verify".

## 1. Rigs and posing (R15)
- New Roblox rigs use AnimationConstraints, not Motor6D. Convert each constraint to a Motor6D (same parts, C0/C1) before posing; drive `Motor6D.Transform` on the client every frame. Find joints by the part they move (Part1), not by name.
- Do not use `Motor6D.C0` (read-only in some Studios). Anchor HumanoidRootPart; set its CFrame from the solver.
- Pose engine: body root + pelvis/torso yaw, lean, crouch, head yaw/pitch; hands and feet as TARGETS; two-bone IK for arms and legs with an elbow/knee pole vector; planted feet stay planted (world-baked) until a key moves them; add a ground height `gy` for stairs.
- Keep fists at least ~0.9 studs from their own shoulder (blend the direction toward body-forward) or the elbow flips 180 degrees.
- Keyframe format: keys inherit the previous key; list only what changes; named eases (in2/in3/out2/inout). Author in FRAMES at 30 fps, play by ELAPSED time (never frame counts), unclamped dt.

## 2. Make combat feel real
- Per exchange: 4-6 frames anticipation, 2-4 frames travel, 1-2 frame impact accent, recovery that shows where weight lands. Vary timings. Hit-stop (3-6 frames both fighters freeze) on contact. Longer lunges so combos keep pressure.
- Speed shown by distance covered between poses, trailing feet, cloth lag, delayed dust. Auto-generate footwork (a step every ~0.9 studs, dash trails, plants) and hand-key only contacts, reversals, reveals, finishing poses.
- Close-ups for decisions, wide shots for impossible speed, silence before the biggest release, slow motion only where the story needs it.
- Signature acting beats per character (eyes move before the head; shoulders loose until the instant of movement).

## 3. Contacts must meet
Solve contacts instead of eyeballing: fist-to-forearm (guard), fist stops a gap short of a face/palm (hover), hand to torso (chest), hand to a point. Measure gaps on the actual parts in Studio from two cameras. Check: IK reach miss, foot below ground, wrist inside a torso, per-frame joint step (flips).

## 4. Timeline architecture
One shared timeline file: chapters (each a dramatic question), fighter keys, camera shots (cut vs blend, positions relative to a fighter's head for close-ups), effects as pure functions of the frame, costume states (glasses/weapon/chain), sound cues, music envelope, slow-motion windows. Because every state is a function of the frame, any chapter starts correctly when selected. Provide: chapter select, full replay, slow motion, VFX toggle, neutral-light toggle, HUD hidden by default.

## 5. Characters that read in close-up
Square R15 head kept. Spend geometry on hair (continuous mass + tapered locks, darker underside), faces (brows, irises, scar), collars (leave the jaw visible), sleeves, trousers volume. Matte materials everywhere; glow only on small effect parts. Light faces separately (soft camera-following fill, small face light). Put white hair against a darker background. Preview front / three-quarter / profile / fight-camera under neutral light with effects off. No custom mesh => say which mesh/texture would improve the likeness.

## 6. Visual bugs found the hard way
- White blown-out head/floor: Bloom threshold too low, ExposureCompensation, Reflectance, Neon on hair/skin/large parts. Keep bloom high-threshold; raise it only inside a void/special scene.
- A stray white rectangle with a dark graphic: the place's default SpawnLocation pad. Also audit ForceField/Glass parts, Decals, SurfaceGuis, wide ParticleEmitters (a "shot audit" key that hides one category at a time finds the owner).
- Atmosphere has no Enabled property: change Density. Default Baseplate/sky leak into "black void" scenes: hide them.
- Instance Streaming can show only sky when no character exists: set `Player.ReplicationFocus`.
- Controls/HUD must be hidden during normal playback.

## 7. Power effects (user preference: big and punchy)
Infinity: object slows, a visible gap, unrelated motion continues. Blue pulls (grit first, tiles tilt, slab slides); Red repels (dust outward, fabric away, readable landing); Purple: converge, compact core, cleared lane, aftermath, glasses settle. Domain: wide shot closing, black interior, distant bright centre, layered streams at different speeds that keep accumulating, opponent's stall, strong flash/ink frame/shockwave on release, restore the location. Keep manga-only material out of an "anime" cut; keep injuries stylized.

## 8. Workflow
1. Inspect the project, reuse rigs/controls. 2. Characters in neutral light. 3. Block the whole timeline with effects off. 4. Run offline tests (lupa + mock rig: reach, floors, penetration, contacts). 5. Add cameras, debris, effects, sound. 6. Install through the Studio connector, run Full Replay, jump to each chapter, capture stills. 7. Report actual running time and what is verified vs pending.
