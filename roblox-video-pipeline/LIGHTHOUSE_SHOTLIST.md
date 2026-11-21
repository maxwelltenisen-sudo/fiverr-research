# "The Light Nobody Could Turn On": cinematic Roblox-style Short (original story)

Target: about 48 s, 10 shots of ~4.5 s each, 9:16 vertical, Pixar-style 3D with Roblox-blocky characters.
Original characters and story. Do not reuse another creator's characters, footage or watermark.

## Character sheet (paste the matching line into EVERY prompt for consistency)
- **MILO**: small blocky Roblox-style boy, messy orange hair, teal jacket with a yellow star patch, white sneakers, big curious eyes.
- **ZARA**: blocky Roblox-style girl, two curly black hair buns, yellow raincoat, round blue-framed glasses, red boots.
- **MR. BOLT**: tall blocky Roblox-style lighthouse keeper, grey beard, navy captain's cap, orange scarf, brown work boots.
- **WORLD**: Brickport, a toy-like blocky harbour town, pastel buildings, red-and-white striped lighthouse on a hill, lantern festival banners.

## Style block (add to every prompt)
`cinematic 3D animation, Roblox-style blocky characters, soft global illumination, warm volumetric light, shallow depth of field, rich saturated colours, smooth fluid motion, high detail, no text, no watermark, no logos`

## Best workflow for consistent characters
1. In an AI image tool, generate a **reference image per character** and one **town establishing image** from the lines above. Keep the best ones.
2. For each shot, use **image-to-video** (start from a reference or a generated key frame) with the shot prompt below. Generate 3 versions, keep the best.
3. Pick **9:16** in the tool, or generate 16:9 and let `build_video.py` crop to centre (keep action centred).
4. Save the clips as `clips/lh_01.mp4` ... `lh_10.mp4`, then run `python3 build_video.py lighthouse.json -o lighthouse.mp4 --tts`.

## Shots (voiceover is what `lighthouse.json` captions and speaks)

| # | Time of day | Voiceover | Video prompt (add character lines + style block) |
|---|---|---|---|
| 1 | Golden hour | "Everyone in Brickport loved the old lighthouse." | Wide establishing shot of Brickport harbour at golden hour, red-and-white lighthouse on a hill, lantern banners swaying, slow drone push-in, Milo skateboards into frame in foreground |
| 2 | Dusk | "But tonight, its great lamp would not turn on." | Mr. Bolt at the base of the lighthouse looking up worried, scratches his head, dark lamp room above, pink dusk sky, camera tilts up to the dark lamp |
| 3 | Blue hour | "And a thick fog was rolling in." | Fog rolls across the harbour, boats with small lights, a foghorn sounds, Zara on the dock raises binoculars, anxious, camera slow pan |
| 4 | Blue hour | "Milo knew he had to help." | Milo sprints up a spiral staircase inside the lighthouse, determined face, handheld-style dynamic follow shot, dust motes in warm window light |
| 5 | Night | "The glass lens was cracked. There was no time to fix it." | Close-up of a cracked giant lighthouse lens, Milo reaches the lamp room and gasps, moonlight through the cracks, camera pushes in |
| 6 | Night | "So he ran back down and asked everyone for their festival lanterns." | Milo shouts from the balcony, town kids run up the hill in a line carrying glowing paper lanterns, magical warm glow trail, wide shot |
| 7 | Night | "One lantern at a time, the lamp room began to glow." | Zara and Milo arrange glowing lanterns in the lamp room, Mr. Bolt wires them with a smile, warm golden light fills the room, medium shot orbiting |
| 8 | Night | "And then... a beam of light cut through the fog." | Epic shot from the sea: the lighthouse beam sweeping through thick fog, lanterns glowing in the windows, dramatic light rays, slow camera rise |
| 9 | Night | "The lost boats followed the light safely home." | Boats gliding into harbour guided by the beam, crowd cheering on the dock, Mr. Bolt tips his cap toward Milo, emotional wide shot |
| 10 | Night | "Part 2? Comment a star." | Milo on the lighthouse balcony under a starry sky with fireworks and lantern glow, Zara waves, camera pulls back and up, heart-warming ending |

## Voice and sound
- Warm storyteller voice (an AI voice or your own). Music: soft cinematic piano from the YouTube Audio Library.
- Add a foghorn and cheering crowd sound effect from a free library if you like.
- Disclose AI-generated visuals/voice where YouTube asks.

## Upload
Title: `The Light Nobody Could Turn On 💡 #roblox #robloxstory #shorts`
Description: `Everyone helped Milo save the boats of Brickport. Comment ⭐ for Part 2!`
