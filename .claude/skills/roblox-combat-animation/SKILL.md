---
name: roblox-combat-animation
description: Build realistic, readable Roblox (R15) combat and anime-style cinematic fight animation in code - keyframed poses with two-bone IK, planted feet, verified contacts, frame-based timelines with chapters, cameras, VFX and sound cues. Use when the user wants fight scenes, character close-ups, power effects (Infinity, Blue, Red, Purple, domains), or says "make the animation realistic / feel like combat".
---

# Roblox realistic combat animation (what actually worked in this repo)

Reference implementation: `roblox-studio/battlegrounds/` (BGEngine, BGClips, BGDuel, BGDuelPlayer, BGBuilder, verify/). Read BGEngine.lua and BGDuel.lua before writing new animation.


## PRIORITY A: anime hits that feel real (do this for every strike)
Anatomy of one hit, at 30 fps (authored), in order:
1. **Anticipation 4-6 frames**: weight drops (crouch +0.3..0.5), torso twists AWAY (twist/pyaw -20..-35), striking hand pulled back, head slightly down. The defender's tell comes here (eyes/head turn first).
2. **Travel 2-4 frames**: ease in3/in2 (slow start, fast arrival), body leans into the line (lean 14-30), rear heel lifts (foot pitch 25-35), root moves forward 1-2 studs, hand reaches full extension ON the contact frame (solve it with a contact, do not eyeball).
3. **Impact accent 1-2 frames**: hold the contact pose (both bodies) for 2 frames, then hit-stop: freeze BOTH fighters 3-6 frames (3 for light, 6 for big). Add the burst on the first accent frame: shards + one or two thin crossing ring slashes + a white flash 0.05-0.08 s (strength 0.3-0.5). Camera: cut to a tighter side angle or FOV punch (-6 deg) with a 2-4 degree roll; shake only 0.1-0.3 for normal hits, 0.5+ for finishers.
4. **Reaction on the SAME frame**: the defender's head snaps back (headPitch -14..-18), spine arches (lean -20..-26), arms fling out, then a staggered slide away (push 4-7 studs over 0.25 s) with feet sliding, not teleporting. Loose cloth/hair lags 2-4 frames behind.
5. **Recovery 8-20 frames**: attacker overshoots and settles (crouch up, hand returns slowly), the winner's weight visibly lands; the loser's recovery is longer. Never snap back to idle: cross-fade 0.05-0.12 s.
Rules: vary timings between hits so rhythm is not metronomic; one hit gets slow motion at most; a blocked/stopped hit shows the gap (Infinity) instead of contact; hits must connect from two camera angles (measure with the contact check); heavier character = longer anticipation + longer recovery; faster character = shorter anticipation + longer travel distance.
Combo of 4: jab (short, fast), cross (twist), hook (arc, hand sweeps), finisher (long anticipation, hit-stop longer, only this one pushes the opponent back).
Sound/silence: a thin impact sound on the accent frame, low thud 2 frames later; cut music for the biggest hit.

## PRIORITY B: correct Roblox character style
- Keep the R15 block look: SQUARE head, blocky torso, simple broad hands (no fingers modelling), rigid limbs. Do NOT scale limbs or add realistic anatomy; get personality from hair, face, collar, sleeves, trousers, footwear and posture.
- Proportions: same skeleton scale for both rigs (the IK solver needs it). Show "tall/slender" with narrow torso accessories + tall hair; show "broad" with wide shoulder/yoke parts (2.6-3.0 studs), tapered LowerTorso (1.6-1.8), thicker forearms.
- Faces from small parts on the front of the head (z about -0.61): eyes (white + coloured iris + dark pupil, iris movable on a Motor6D so eyes lead the head), tilted brows (tilt 6-16 deg for expression), tiny mouth, scar/glasses as separate removable parts. Keep irises slightly emissive (Neon, tiny) so they survive dusk lighting.
- Hair = one continuous mass cap + darker underside + locks made of 3 stacked, narrowing, bent segments; fringe as separate locks with an irregular lower edge. Never a single box.
- Clothes: Fabric/SmoothPlastic matte; add lighter thin strips at elbows/knees/shoulder seams so dark clothes keep their folds; collars low enough to show the jaw; trousers as wider parts with a narrow ankle gather.
- Accessories (scarf, coat tails, creature tails) as Motor6D chains animated with delay so they lag the body.
- Verify like this: neutral light, VFX off, front / three-quarter / profile / fight-camera waist-up; silhouettes must be distinguishable in solid black; faces readable at the actual fight camera distance.

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
