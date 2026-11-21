# Roblox Short builder

Turns your recorded Roblox clips + a script into a finished vertical Short
(1080x1920) with big word-by-word captions and optional voiceover and music.

## Install
- Python 3.9+ and FFmpeg (with libass), on PC/Mac/Linux.
- Optional voiceover: `pip install edge-tts` (needs internet).

## Use
1. Put your clips in `clips/` (any size or orientation; they get cropped to 9:16).
2. Copy `story.example.json` to `my_story.json` and edit the `text` for each scene.
3. Run:
   `python3 build_video.py my_story.json -o short.mp4`          (captions only)
   `python3 build_video.py my_story.json -o short.mp4 --tts`    (adds a computer voice)
4. Upload `short.mp4` to YouTube.

Scene length comes from the voice audio if you have it, else `duration`, else the word count.
Missing clips become coloured placeholders so you can preview timing first.

Own voice: record each scene, save as `voice/01.mp3` etc., and set `"voice"` per scene.
Music: set `"music": "song.mp3"`. Use copyright-safe tracks only (YouTube Audio Library).
Caption look: edit `caption` in the JSON (font, size, colors, words per chunk).
Disclose AI/computer voices when YouTube asks.
